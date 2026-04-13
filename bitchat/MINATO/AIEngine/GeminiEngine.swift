import Foundation
import GoogleGenerativeAI

// MARK: - Once Flag (thread-safe single-fire guard)

private final class OnceFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()
    func tryFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return false }
        fired = true
        return true
    }
}

// MARK: - Gemini Engine

/// AI engine implementation using Google Gemini API.
final class GeminiEngine: AIEngine, @unchecked Sendable {
    let engineId = "gemini"

    private let model: GenerativeModel
    private var chatSessions: [String: Chat] = [:]  // peerID → Chat session
    private let sessionsLock = NSLock()

    init(apiKey: String, modelName: String = "gemini-2.5-flash") {
        self.model = GenerativeModel(name: modelName, apiKey: apiKey)
    }

    func generateResponse(to message: String, context: AIContext) async throws -> String {
        let chat = getOrCreateChat(for: context)

        // Race API call vs 10s timeout.
        // Can't use withThrowingTaskGroup because Google SDK ignores cancellation,
        // which would cause the group to hang forever.
        let flag = OnceFlag()
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if flag.tryFire() {
                    continuation.resume(throwing: AIEngineError.timeout)
                }
            }

            // API call
            Task {
                do {
                    let response = try await chat.sendMessage(message)
                    if flag.tryFire() {
                        timeoutTask.cancel()
                        continuation.resume(returning: response.text ?? "")
                    }
                } catch {
                    if flag.tryFire() {
                        timeoutTask.cancel()
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func getOrCreateChat(for context: AIContext) -> Chat {
        let sessionKey = context.peerDisplayName
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        if let existing = chatSessions[sessionKey] {
            return existing
        }
        let chat = model.startChat(history: [
            ModelContent(role: "user", parts: context.systemPrompt),
            ModelContent(role: "model", parts: "Understood. I'm ready to assist as a MINATO agent.")
        ])
        chatSessions[sessionKey] = chat
        return chat
    }

    func translateMessage(_ text: String, from sourceLocale: String, to targetLocale: String) async throws -> String {
        let prompt = """
        Translate the following message from \(sourceLocale) to \(targetLocale).
        Output ONLY the translated text — no explanations, no quotes, no prefixes.

        Message: \(text)
        """

        let flag = OnceFlag()
        return try await withCheckedThrowingContinuation { continuation in
            let workTask = Task {
                let response = try await model.generateContent(prompt)
                return response.text ?? ""
            }

            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if flag.tryFire() {
                    workTask.cancel()
                    continuation.resume(throwing: AIEngineError.timeout)
                }
            }

            Task {
                do {
                    let result = try await workTask.value
                    if flag.tryFire() { continuation.resume(returning: result) }
                } catch {
                    if flag.tryFire() { continuation.resume(throwing: error) }
                }
            }
        }
    }

    func extractScheduleProposal(from message: String, locale: String, busySlots: [(start: Date, end: Date)], areaHint: String?) async throws -> (isSchedule: Bool, event: ProposedEvent?, displayMessage: String?) {
        let now = ISO8601DateFormatter().string(from: Date())

        let busyInfo: String
        if busySlots.isEmpty {
            busyInfo = "No calendar data available."
        } else {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let slots = busySlots.prefix(20).map { "  - \(formatter.string(from: $0.start)) to \(formatter.string(from: $0.end))" }
            busyInfo = "Busy times (avoid these):\n\(slots.joined(separator: "\n"))"
        }

        let areaInfo = areaHint.map { "User's approximate area: \($0)" } ?? "User's area: unknown"

        let prompt = """
        You are a schedule intent classifier + extractor. The current date/time is: \(now)
        The user's locale is: \(locale)
        \(areaInfo)

        \(busyInfo)

        STEP 1: Determine if this message is a REAL scheduling request (inviting someone to meet at a specific time/place, or asking about availability for a future event).

        NOT a scheduling request:
        - General questions or statements ("How are you?", "I love free software")
        - Past tense or reminiscing ("yesterday was fun")
        - Casual mentions without invitation intent ("I had dinner", "let's meet someday")
        - Idioms like "feel free", "free software", "let's hang in there"

        IS a scheduling request:
        - Explicit invitations ("let's grab drinks Friday", "今夜飲みに行こう")
        - Availability checks with intent ("are you free Friday evening?", "金曜の夜空いてる？")
        - Time+activity combinations ("lunch tomorrow?", "明日ランチ行かない？")

        STEP 2: If IS a scheduling request, extract the event. Otherwise return isSchedule=false.

        Respond in EXACTLY this JSON format, nothing else:
        {"isSchedule":true,"title":"event title","start":"ISO8601","end":"ISO8601","location":"specific venue name and area","message":"polite proposal text in \(locale)"}
        OR
        {"isSchedule":false}

        Rules when isSchedule=true:
        - Use ISO 8601 format with timezone for start/end (e.g., 2026-04-18T19:00:00+09:00)
        - If no specific time, use reasonable defaults (evening=19:00, lunch=12:00, morning=10:00)
        - If no duration specified, default to 2 hours
        - ALWAYS suggest a specific venue/restaurant/place name based on the activity and area
        - If the area is unknown, suggest a well-known popular spot
        - Avoid proposing times that overlap with busy times listed above
        - The "message" field should be a friendly proposal in the user's language, mentioning the specific venue
        - Output ONLY the JSON — no markdown, no explanation

        User message: \(message)
        """

        let flag = OnceFlag()
        let raw: String = try await withCheckedThrowingContinuation { continuation in
            let workTask = Task {
                let response = try await model.generateContent(prompt)
                return response.text ?? ""
            }
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if flag.tryFire() {
                    workTask.cancel()
                    continuation.resume(throwing: AIEngineError.timeout)
                }
            }
            Task {
                do {
                    let result = try await workTask.value
                    if flag.tryFire() { continuation.resume(returning: result) }
                } catch {
                    if flag.tryFire() { continuation.resume(throwing: error) }
                }
            }
        }

        // Parse the JSON response
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AIEngineError.noResponse
        }

        struct ScheduleExtraction: Decodable {
            let isSchedule: Bool
            let title: String?
            let start: String?
            let end: String?
            let location: String?
            let message: String?
        }

        let extraction = try JSONDecoder().decode(ScheduleExtraction.self, from: data)
        guard extraction.isSchedule,
              let title = extraction.title,
              let start = extraction.start,
              let end = extraction.end else {
            return (isSchedule: false, event: nil, displayMessage: nil)
        }
        let event = ProposedEvent(
            title: title,
            start: start,
            end: end,
            location: extraction.location
        )
        return (isSchedule: true, event: event, displayMessage: extraction.message)
    }

    /// Clears the chat session for a peer (e.g., on disconnect).
    func clearSession(for peerDisplayName: String) {
        sessionsLock.lock()
        defer { sessionsLock.unlock() }
        chatSessions.removeValue(forKey: peerDisplayName)
    }
}

// MARK: - API Key Management

enum GeminiAPIKey {
    /// Reads the Gemini API key from GenerativeAI-Info.plist.
    static var `default`: String? {
        guard let path = Bundle.main.path(forResource: "GenerativeAI-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["API_KEY"] as? String,
              !key.isEmpty,
              key != "YOUR_API_KEY_HERE"
        else {
            return nil
        }
        return key
    }
}
