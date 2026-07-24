import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    nonisolated static let defaultsKey = "appTheme"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
