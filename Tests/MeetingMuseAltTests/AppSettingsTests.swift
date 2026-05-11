import Testing
import Foundation
import SwiftUI
@testable import MeetingMuseAlt

/// Build an isolated `UserDefaults` suite per test so we don't leak state into
/// the standard domain (which `AppSettings.shared` uses).
@MainActor
private func makeIsolatedDefaults(_ suite: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
@Test func appSettingsDefaultsToSystemWhenNothingStored() {
    let defaults = makeIsolatedDefaults()
    let settings = AppSettings(defaults: defaults)
    #expect(settings.themeMode == .system)
    #expect(settings.preferredColorScheme == nil)
}

@MainActor
@Test func appSettingsRoundTripsThemeThroughUserDefaults() {
    let suite = "mm.alt.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    // First instance: change the theme.
    let a = AppSettings(defaults: defaults)
    a.themeMode = .dark
    #expect(defaults.string(forKey: AppSettings.themeModeKey) == "dark")

    // Fresh instance reading the same store should see the persisted value.
    let b = AppSettings(defaults: defaults)
    #expect(b.themeMode == .dark)
    #expect(b.preferredColorScheme == .dark)
}

@MainActor
@Test func themeModeMapsToColorScheme() {
    #expect(ThemeMode.system.preferredColorScheme == nil)
    #expect(ThemeMode.light.preferredColorScheme == .light)
    #expect(ThemeMode.dark.preferredColorScheme == .dark)
}

@MainActor
@Test func themeModeCaseIterableCoversAllVariants() {
    let all = ThemeMode.allCases.map(\.rawValue).sorted()
    #expect(all == ["dark", "light", "system"])
}

@MainActor
@Test func appSettingsIgnoresGarbageStoredValue() {
    let suite = "mm.alt.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set("not-a-real-mode", forKey: AppSettings.themeModeKey)

    let settings = AppSettings(defaults: defaults)
    #expect(settings.themeMode == .system)
}
