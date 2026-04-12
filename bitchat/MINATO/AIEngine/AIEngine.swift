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
}

/// Context passed to the AI engine for response generation.
struct AIContext {
    let peerDisplayName: String
    let peerLocale: String
    let localLocale: String
    let intent: String?
    let trustMode: TrustMode
    let capabilities: [String]

    /// Builds a system prompt from the context.
    var systemPrompt: String {
        """
        You are a MINATO agent — a personal AI assistant that communicates with other agents on behalf of your owner.

        Your owner's language: \(localLocale)
        Peer's name: \(peerDisplayName)
        Peer's language: \(peerLocale)
        Current trust mode: \(trustMode.displayName)
        Your capabilities: \(capabilities.joined(separator: ", "))

        Rules:
        - Respond in your owner's language (\(localLocale))
        - Be friendly, concise, and helpful
        - If the peer speaks a different language, include a translation in their language
        - For schedule-related requests, suggest concrete times
        - Respect the trust mode: \(trustMode.displayName) means \(trustModeDescription)
        - Keep responses under 200 characters for chat messages
        """
    }

    private var trustModeDescription: String {
        switch trustMode {
        case .plan: return "ask the owner before any action"
        case .suggest: return "confirm once before executing"
        case .auto: return "auto-execute low-risk actions, confirm high-risk ones"
        case .fullAuto: return "execute everything autonomously, notify after"
        }
    }
}
