import Foundation
import SwiftUI

/// User-selectable color scheme preference.
public enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// Maps to SwiftUI's `ColorScheme`. `nil` means follow the system.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Localized display label for UI pickers.
    public var localizedLabel: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

/// Persists app-wide user preferences (theme, etc.) in `UserDefaults`.
///
/// Use `AppSettings.shared` for the live in-app instance. Tests should construct
/// their own instance with a dedicated `UserDefaults(suiteName:)` to avoid
/// polluting the standard suite.
@MainActor
public final class AppSettings: ObservableObject {
    public static let themeModeKey = "mm.alt.themeMode"

    public static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published public var themeMode: ThemeMode {
        didSet {
            guard themeMode != oldValue else { return }
            defaults.set(themeMode.rawValue, forKey: Self.themeModeKey)
        }
    }

    /// - Parameter defaults: backing store. Defaults to `.standard`; pass a
    ///   suite-scoped instance from tests to isolate state.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.themeModeKey),
           let stored = ThemeMode(rawValue: raw) {
            self.themeMode = stored
        } else {
            self.themeMode = .system
        }
    }

    /// Convenience pass-through to the current `themeMode`'s color scheme.
    public var preferredColorScheme: ColorScheme? {
        themeMode.preferredColorScheme
    }
}
