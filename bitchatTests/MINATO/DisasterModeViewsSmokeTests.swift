import Testing
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import bitchat

@MainActor
@discardableResult
private func mount<V: View>(_ view: V) -> AnyObject {
    #if os(iOS)
    let host = UIHostingController(rootView: view)
    _ = host.view
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    return host
    #else
    let host = NSHostingView(rootView: view)
    host.layoutSubtreeIfNeeded()
    _ = host.fittingSize
    return host
    #endif
}

/// Battery monitor whose reading the test controls.
private final class MockBatteryMonitor: BatteryMonitoring {
    var snapshot: BatterySnapshot
    init(_ snapshot: BatterySnapshot = BatterySnapshot(pct: 50, state: .discharging)) {
        self.snapshot = snapshot
    }
    func currentBattery() -> BatterySnapshot { snapshot }
}

@MainActor
@Suite("Disaster Mode Views Smoke Tests")
struct DisasterModeViewsSmokeTests {

    // MARK: - SafetyHeaderView

    @Test("SafetyHeaderView renders the off-state banner")
    func safetyHeaderOffState() {
        let store = DisasterModeStore(batteryMonitor: MockBatteryMonitor())
        // Default: not active.

        let view = SafetyHeaderView(
            store: store,
            onRequestActivate: { },
            onOpenDashboard: { }
        )

        _ = view.body
        _ = mount(view)
        #expect(store.isActive == false)
    }

    @Test("SafetyHeaderView renders the on-state status row after activate")
    func safetyHeaderOnState() {
        let store = DisasterModeStore(batteryMonitor: MockBatteryMonitor())
        store.activate()
        store.setStatus(.ok)

        let view = SafetyHeaderView(
            store: store,
            onRequestActivate: { },
            onOpenDashboard: { }
        )

        _ = view.body
        _ = mount(view)
        #expect(store.isActive == true)
        #expect(store.myStatus == .ok)
    }

    // MARK: - DisasterModeView

    @Test("DisasterModeView renders for each owner status")
    func disasterModeRendersAllStatuses() {
        for status in DisasterStatus.allCases {
            let store = DisasterModeStore(
                batteryMonitor: MockBatteryMonitor(BatterySnapshot(pct: 73, state: .discharging))
            )
            store.activate()
            store.setStatus(status)
            store.updateLocationHint("テスト位置")

            let view = DisasterModeView(store: store, onDismiss: { })
            _ = view.body
            _ = mount(view)
            #expect(store.myStatus == status)
        }
    }

    @Test("DisasterModeView renders the low-battery warning branch")
    func disasterModeLowBatteryBranch() {
        let store = DisasterModeStore(
            batteryMonitor: MockBatteryMonitor(BatterySnapshot(pct: 8, state: .discharging))
        )
        store.activate()
        store.setStatus(.injured)

        let view = DisasterModeView(store: store, onDismiss: { })
        _ = view.body
        _ = mount(view)
        #expect(store.battery.pct == 8)
        #expect(store.battery.state == .discharging)
    }

    @Test("DisasterModeView renders the charging-full branch")
    func disasterModeChargingBranch() {
        let store = DisasterModeStore(
            batteryMonitor: MockBatteryMonitor(BatterySnapshot(pct: 100, state: .charging))
        )
        store.activate()

        let view = DisasterModeView(store: store, onDismiss: { })
        _ = view.body
        _ = mount(view)
        #expect(store.battery.state == .charging)
    }

    @Test("DisasterModeView renders the unknown-battery branch")
    func disasterModeUnknownBatteryBranch() {
        let store = DisasterModeStore(batteryMonitor: MockBatteryMonitor(.unknown))
        store.activate()

        let view = DisasterModeView(store: store, onDismiss: { })
        _ = view.body
        _ = mount(view)
        #expect(store.battery.state == .unknown)
    }
}
