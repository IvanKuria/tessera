import SwiftUI

/// The user's appearance preference, persisted under the `appAppearance`
/// `@AppStorage` key. `system` follows the macOS setting (and switches live);
/// `light`/`dark` force one. Read it in both `TesseraApp` (to drive
/// `preferredColorScheme`) and `RootView` (the sidebar picker).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// `nil` means "follow the system" — handed straight to `.preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
