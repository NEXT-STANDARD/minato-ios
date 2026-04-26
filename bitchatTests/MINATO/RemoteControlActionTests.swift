import Foundation
import Testing
@testable import bitchat

// MARK: - Remote Control Action Tests

@Suite("Remote Control Action Tests")
struct RemoteControlActionTests {

    // MARK: - Parsing

    @Test("parse returns the matching case for every known action string",
          arguments: RemoteControlAction.allCases)
    func parseRecognisesAllCases(action: RemoteControlAction) {
        #expect(RemoteControlAction.parse(action.rawValue) == action)
    }

    @Test("parse returns nil for non-remote actions")
    func parseRejectsForeignActions() {
        #expect(RemoteControlAction.parse(nil) == nil)
        #expect(RemoteControlAction.parse("") == nil)
        #expect(RemoteControlAction.parse("schedule.write") == nil)
        #expect(RemoteControlAction.parse("remote.unknown") == nil)
        #expect(RemoteControlAction.parse("REMOTE.STATUS") == nil)  // case sensitive
    }

    // MARK: - Capability Mapping

    @Test("read-only commands require remote.control.read")
    func readCommandsMapToReadCapability() {
        #expect(RemoteControlAction.status.requiredCapability == .remoteControlRead)
        #expect(RemoteControlAction.ping.requiredCapability == .remoteControlRead)
    }

    @Test("state-changing commands require remote.control.write")
    func writeCommandsMapToWriteCapability() {
        #expect(RemoteControlAction.cancel.requiredCapability == .remoteControlWrite)
        #expect(RemoteControlAction.mute.requiredCapability == .remoteControlWrite)
        #expect(RemoteControlAction.unmute.requiredCapability == .remoteControlWrite)
    }

    @Test("mutatesState matches the read/write capability split")
    func mutatesStateMatchesCapability() {
        for action in RemoteControlAction.allCases {
            switch action.requiredCapability {
            case .remoteControlRead:
                #expect(action.mutatesState == false, "\(action) is read-only but reports mutatesState=true")
            case .remoteControlWrite:
                #expect(action.mutatesState == true, "\(action) is write but reports mutatesState=false")
            default:
                Issue.record("Unexpected capability \(action.requiredCapability) for \(action)")
            }
        }
    }

    // MARK: - Capability Risk Classification

    @Test("remote.control.write is high-risk; remote.control.read is not")
    func capabilityRiskClassification() {
        #expect(Capability.highRisk.contains(.remoteControlWrite))
        #expect(!Capability.highRisk.contains(.remoteControlRead))
        #expect(Capability.isHighRisk("remote.control.write"))
        #expect(!Capability.isHighRisk("remote.control.read"))
    }

    @Test("remote control capabilities are not granted by default")
    func remoteCapabilitiesAreOptIn() {
        #expect(!Capability.defaults.contains(.remoteControlRead))
        #expect(!Capability.defaults.contains(.remoteControlWrite))
    }

    // MARK: - Status

    @Test("RemoteControlStatus raw values match the wire contract")
    func statusRawValues() {
        #expect(RemoteControlStatus.ok.rawValue == "ok")
        #expect(RemoteControlStatus.denied.rawValue == "denied")
        #expect(RemoteControlStatus.notFound.rawValue == "not_found")
        #expect(RemoteControlStatus.unknown.rawValue == "unknown")
        #expect(RemoteControlStatus.error.rawValue == "error")
    }
}
