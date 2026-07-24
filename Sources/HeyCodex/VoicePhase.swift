import Foundation

enum VoicePhase: Equatable {
    case off
    case requestingPermission
    case listening
    case paused
    case triggering
    case dictating
    case finishing
    case error(String)

    var title: String {
        switch self {
        case .off:
            "Off"
        case .requestingPermission:
            "Checking permissions"
        case .listening:
            "Say “Hey Codex”"
        case .paused:
            "Paused"
        case .triggering:
            "Starting…"
        case .dictating:
            "Dictating at your cursor"
        case .finishing:
            "Finishing dictation…"
        case let .error(message):
            message
        }
    }

    var symbolName: String {
        switch self {
        case .off, .error:
            "ear"
        case .paused:
            "pause.circle"
        case .requestingPermission, .triggering, .finishing:
            "waveform"
        case .dictating:
            "waveform.circle.fill"
        case .listening:
            "ear.fill"
        }
    }

    var showsListeningSlash: Bool {
        switch self {
        case .off, .error:
            true
        default:
            false
        }
    }
}

extension VoicePhase {
    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}
