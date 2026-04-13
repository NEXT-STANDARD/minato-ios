import Foundation

// MARK: - AIEngine Errors

enum AIEngineError: Error {
    case timeout
    case noResponse
}

// MARK: - AIEngine Protocol

/// Protocol for AI engine integrations.
/// MINATO is AI-engine agnostic — any provider can be used.
protocol AIEngine {
    /// The engine identifier (e.g., "gemini", "claude", "gpt").
    var engineId: String { get }

    /// Generate a response to a user message with context.
    /// - Parameters:
    ///   - message: The incoming message content
    ///   - context: Additional context (peer info, intent, etc.)
    /// - Returns: The generated response text
    func generateResponse(to message: String, context: AIContext) async throws -> String

    /// Translate a message from one language to another.
    /// - Returns: The translated text, or nil if translation is not needed or fails
    func translateMessage(_ text: String, from sourceLocale: String, to targetLocale: String) async throws -> String

    /// Extract a schedule proposal from natural language input.
    /// - Parameters:
    ///   - message: The user's message (e.g., "Let's grab drinks Friday evening")
    ///   - locale: The user's locale for date/time interpretation
    ///   - busySlots: Existing calendar events to avoid conflicts
    ///   - areaHint: Approximate area (e.g., "Tokyo", geohash) for location suggestions
    /// - Returns: isSchedule=false if the message is not a scheduling request; otherwise a ProposedEvent + message.
    func extractScheduleProposal(from message: String, locale: String, busySlots: [(start: Date, end: Date)], areaHint: String?) async throws -> (isSchedule: Bool, event: ProposedEvent?, displayMessage: String?)
}

/// Context passed to the AI engine for response generation.
struct AIContext {
    let ownerDisplayName: String
    let peerDisplayName: String
    let peerLocale: String
    let localLocale: String
    let intent: String?
    let trustMode: TrustMode
    let capabilities: [String]

    /// Builds a system prompt from the context.
    var systemPrompt: String {
        """
        You are \(ownerDisplayName)'s MINATO agent — a personal AI assistant that communicates with \(peerDisplayName)'s agent on behalf of \(ownerDisplayName).

        Your owner: \(ownerDisplayName) (language: \(localLocale))
        Peer: \(peerDisplayName) (language: \(peerLocale))
        Current trust mode: \(trustMode.displayName)
        Your capabilities: \(capabilities.joined(separator: ", "))

        CRITICAL: Your output is sent DIRECTLY to \(peerDisplayName) as a chat message.
        Do NOT include internal notes, owner notifications, or meta-instructions in your response.
        Do NOT generate text like "[オーナーへの通知]" or "[Notification to owner]".
        Owner notifications are handled by the system, not by you.

        Rules:
        - Always refer to your owner as "\(ownerDisplayName)" (never "オーナー" or "my owner")
        - Always refer to the peer as "\(peerDisplayName)" (never "相手" or "the peer")
        - Respond in \(ownerDisplayName)'s language (\(localLocale))
        - Be friendly, concise, and helpful
        - For schedule-related requests, suggest concrete times
        - \(trustModeDescription)
        - Keep responses under 200 characters for chat messages
        - Output ONLY the reply text — nothing else
        - Do NOT include translations — translation is handled separately by the system
        """
    }

    private var trustModeDescription: String {
        switch trustMode {
        case .plan: return "You are in Apprentice mode: generate a helpful reply as if \(ownerDisplayName) wrote it. The system has already sent a 'checking with owner' message — do NOT repeat that. Just write the actual reply \(ownerDisplayName) would send."
        case .suggest: return "You are in Partner mode: generate a helpful reply as if \(ownerDisplayName) wrote it. \(ownerDisplayName) will review before sending."
        case .auto: return "You are in Lieutenant mode: respond naturally on behalf of \(ownerDisplayName) for casual messages. For important requests, note you will confirm with \(ownerDisplayName)."
        case .fullAuto: return "You are in Alter Ego mode: respond naturally and handle everything autonomously on behalf of \(ownerDisplayName)."
        }
    }
}
