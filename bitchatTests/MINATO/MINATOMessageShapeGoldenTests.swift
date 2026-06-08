import Foundation
import Testing
@testable import bitchat

@Suite("MINATO Message Shape Golden Tests")
struct MINATOMessageShapeGoldenTests {
    private static let expectedTypesByFixture: [String: String] = [
        "agent_handshake.json": MINATOMessageType.agentHandshake.description,
        "agent_message.json": MINATOMessageType.agentMessage.description,
        "agent_request.json": MINATOMessageType.agentRequest.description,
        "agent_response.json": MINATOMessageType.agentResponse.description,
        "agent_ack.json": MINATOMessageType.agentAck.description,
        "agent_revoke.json": MINATOMessageType.agentRevoke.description,
        "agent_ping.json": MINATOMessageType.agentPing.description,
        "agent_log.json": MINATOMessageType.agentLog.description
    ]

    @Test("docs examples decode and re-encode without canonical diffs")
    func docsExamplesRoundTripWithoutDiffs() throws {
        let examplesURL = try Self.examplesURL()
        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: examplesURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        let fixtureNames = Set(fixtureURLs.map(\.lastPathComponent))
        #expect(fixtureNames == Set(Self.expectedTypesByFixture.keys))

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for url in fixtureURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let fixtureName = url.lastPathComponent
            let expectedType = try #require(Self.expectedTypesByFixture[fixtureName])
            let fixture = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let payload = try decoder.decode(MINATOPayload.self, from: Data(fixture.utf8))
            #expect(payload.type == expectedType, "\(fixtureName) must declare \(expectedType)")

            let encoded = try encoder.encode(payload)
            let canonical = try #require(String(data: encoded, encoding: .utf8))
            #expect(canonical == fixture, "\(fixtureName) must match sorted-key canonical JSON")
        }
    }

    private static func examplesURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent() // MINATO
        url.deleteLastPathComponent() // bitchatTests
        url.deleteLastPathComponent() // repo root
        url.appendPathComponent("docs/examples/minato-ios", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        return url
    }
}
