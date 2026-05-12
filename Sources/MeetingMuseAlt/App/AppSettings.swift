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
    public static let openAIAPIKeyKey = "mm.alt.openAIAPIKey"
    public static let whisperModelKey = "mm.alt.whisperModel"

    public static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published public var themeMode: ThemeMode {
        didSet {
            guard themeMode != oldValue else { return }
            defaults.set(themeMode.rawValue, forKey: Self.themeModeKey)
        }
    }

    /// OpenAI API 키 (요약/번역/Ask AI 용). UserDefaults 평문 저장이지만
    /// 향후 Keychain 으로 옮길 수 있도록 단일 setter/getter 로 캡슐화.
    @Published public var openAIAPIKey: String {
        didSet {
            guard openAIAPIKey != oldValue else { return }
            defaults.set(openAIAPIKey, forKey: Self.openAIAPIKeyKey)
        }
    }

    /// WhisperKit 모델 이름 (tiny / base / small / medium / large).
    @Published public var whisperModel: String {
        didSet {
            guard whisperModel != oldValue else { return }
            defaults.set(whisperModel, forKey: Self.whisperModelKey)
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
        self.openAIAPIKey = defaults.string(forKey: Self.openAIAPIKeyKey) ?? ""
        self.whisperModel = defaults.string(forKey: Self.whisperModelKey) ?? "tiny"
    }

    /// Convenience pass-through to the current `themeMode`'s color scheme.
    public var preferredColorScheme: ColorScheme? {
        themeMode.preferredColorScheme
    }
}
