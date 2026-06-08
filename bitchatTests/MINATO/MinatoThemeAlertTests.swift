import Testing
import SwiftUI
@testable import bitchat

/// Verifies the disaster high-alert palette plumbing: the `alert:` flag on the
/// MinatoTheme accessors flips calm surfaces/ink to the high-alert variants, the
/// interactive `tint(alert:)` resolves teal vs danger, and the `\.minatoAlert`
/// environment flag defaults to off.
@Suite("MinatoTheme high-alert")
struct MinatoThemeAlertTests {

    @Test("background(alert:) flips to the alert background", arguments: [ColorScheme.dark, .light])
    func backgroundFlips(scheme: ColorScheme) {
        let alertMatchesAlertBackground = MinatoTheme.background(scheme, alert: true) == MinatoTheme.alertBackground(scheme)
        let calmMatchesCalm = MinatoTheme.background(scheme, alert: false) == MinatoTheme.background(scheme)
        let alertDiffersFromCalm = MinatoTheme.background(scheme, alert: true) != MinatoTheme.background(scheme, alert: false)
        #expect(alertMatchesAlertBackground)
        #expect(calmMatchesCalm)
        #expect(alertDiffersFromCalm)
    }

    @Test("background defaults to calm when alert is omitted", arguments: [ColorScheme.dark, .light])
    func backgroundDefaultIsCalm(scheme: ColorScheme) {
        let defaultEqualsExplicitCalm = MinatoTheme.background(scheme) == MinatoTheme.background(scheme, alert: false)
        #expect(defaultEqualsExplicitCalm)
    }

    @Test("ink stays distinct between calm and alert (and readable variants exist)", arguments: [ColorScheme.dark, .light])
    func inkFlips(scheme: ColorScheme) {
        let inkDiffers = MinatoTheme.ink(scheme, alert: true) != MinatoTheme.ink(scheme, alert: false)
        let secondaryDiffers = MinatoTheme.inkSecondary(scheme, alert: true) != MinatoTheme.inkSecondary(scheme, alert: false)
        #expect(inkDiffers)
        #expect(secondaryDiffers)
    }

    @Test("surface flips between calm and alert", arguments: [ColorScheme.dark, .light])
    func surfaceFlips(scheme: ColorScheme) {
        let surfaceDiffers = MinatoTheme.surface(scheme, alert: true) != MinatoTheme.surface(scheme, alert: false)
        #expect(surfaceDiffers)
    }

    @Test("tint resolves teal in peacetime and danger in high-alert")
    func tintResolves() {
        let calmIsAccent = MinatoTheme.tint(alert: false) == MinatoTheme.accent
        let alertIsAlertAccent = MinatoTheme.tint(alert: true) == MinatoTheme.alertAccent
        let defaultIsAccent = MinatoTheme.tint() == MinatoTheme.accent
        #expect(calmIsAccent)
        #expect(alertIsAlertAccent)
        #expect(defaultIsAccent)
    }

    @Test("alertAccent is the danger red")
    func alertAccentIsDanger() {
        let isDanger = MinatoTheme.alertAccent == MinatoTheme.danger
        #expect(isDanger)
    }

    @Test("minatoAlert environment value defaults to off")
    func environmentDefaultsOff() {
        let isOff = EnvironmentValues().minatoAlert == false
        #expect(isOff)
    }
}
