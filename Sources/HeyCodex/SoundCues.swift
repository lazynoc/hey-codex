import AppKit

enum SoundCue: String, Sendable, Equatable {
    case wakeHeard
    case dictationStopped

    static let enabledKey = "soundCuesEnabled"
}

enum SoundCueVolume: String, CaseIterable, Identifiable {
    nonisolated static let defaultsKey = "soundCueVolume"

    case low
    case medium
    case system

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var level: Float {
        switch self {
        case .low:
            0.35
        case .medium:
            0.65
        case .system:
            1
        }
    }

    static func selected(in defaults: UserDefaults = .standard) -> SoundCueVolume {
        guard let rawValue = defaults.string(forKey: defaultsKey) else {
            return .system
        }
        return SoundCueVolume(rawValue: rawValue) ?? .system
    }
}

@MainActor
enum SoundCuePlayer {
    static func play(_ cue: SoundCue, volume: SoundCueVolume? = nil) {
        let name: NSSound.Name = switch cue {
        case .wakeHeard: "Pop"
        case .dictationStopped: "Glass"
        }
        guard let sound = NSSound(named: name) else { return }
        sound.volume = (volume ?? SoundCueVolume.selected()).level
        sound.play()
    }
}
