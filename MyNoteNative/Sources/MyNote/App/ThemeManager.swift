import AppKit
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private static let modeKey = "Lume.themeMode"

    @Published var mode: ThemeMode {
        didSet {
            guard oldValue != mode else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            apply()
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.modeKey)
        mode = stored.flatMap(ThemeMode.init(rawValue:)) ?? .system
    }

    var isDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var toggleIcon: String {
        isDark ? "sun.max" : "moon"
    }

    func toggle() {
        mode = isDark ? .light : .dark
    }

    func apply() {
        NSApp?.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
