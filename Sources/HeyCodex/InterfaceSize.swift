import SwiftUI

enum InterfaceSize: String, CaseIterable, Identifiable {
    nonisolated static let defaultsKey = "interfaceSize"

    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var controlSize: ControlSize {
        switch self {
        case .small:
            .small
        case .medium:
            .regular
        case .large:
            .large
        }
    }

    var menuWidth: CGFloat {
        switch self {
        case .small:
            310
        case .medium:
            340
        case .large:
            380
        }
    }

    var menuSpacing: CGFloat {
        switch self {
        case .small:
            10
        case .medium:
            12
        case .large:
            14
        }
    }

    var menuPadding: CGFloat {
        switch self {
        case .small:
            12
        case .medium:
            16
        case .large:
            18
        }
    }

    var secondaryFont: Font {
        switch self {
        case .small:
            .caption
        case .medium:
            .callout
        case .large:
            .body
        }
    }

    var historyBodyFont: Font {
        switch self {
        case .small:
            .callout
        case .medium:
            .body
        case .large:
            .title3
        }
    }

    var historyRowSpacing: CGFloat {
        switch self {
        case .small:
            4
        case .medium:
            7
        case .large:
            10
        }
    }

    var historyRowPadding: CGFloat {
        switch self {
        case .small:
            4
        case .medium:
            7
        case .large:
            10
        }
    }
}
