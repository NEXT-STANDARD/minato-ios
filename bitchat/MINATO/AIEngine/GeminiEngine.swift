import Foundation
import GoogleGenerativeAI

// MARK: - Gemini Engine

/// AI engine implementation using Google Gemini API.
final class GeminiEngine: AIEngine {
    let engineId = "gemini"

    private let model: GenerativeModel
    private var chatSessions: [String: Chat] = [:]  // peerID → Chat session

    init(apiKey: String, modelName: String = "gemini-2.0-flash") {
        self.model = GenerativeModel(name: modelName, apiKey: apiKey)
    }

    func generateResponse(to message: String, context: AIContext) async throws -> String {
        // Get or create a chat session for this peer
        let sessionKey = context.peerDisplayName
        let chat: Chat
        if let existing = chatSessions[sessionKey] {
            chat = existing
        } else {
            chat = model.startChat(history: [
                ModelContent(role: "user", parts: context.systemPrompt),
                ModelContent(role: "model", parts: "Understood. I'm ready to assist as a MINATO agent.")
            ])
            chatSessions[sessionKey] = chat
        }

        let response = try await chat.sendMessage(message)
        return response.text ?? ""
    }

    /// Clears the chat session for a peer (e.g., on disconnect).
    func clearSession(for peerDisplayName: String) {
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
