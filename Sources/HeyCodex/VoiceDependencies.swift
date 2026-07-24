import Foundation

struct VoiceTimings: Sendable {
    var handoffDelay: Duration = .milliseconds(700)
    var stopFallback: Duration = .seconds(3)
    var completionSettle: Duration = .milliseconds(750)
    var onboardingDictationDemo: Duration = .seconds(2)

    static let live = VoiceTimings()

    static let test = VoiceTimings(
        handoffDelay: .milliseconds(1),
        stopFallback: .milliseconds(5),
        completionSettle: .milliseconds(1),
        onboardingDictationDemo: .milliseconds(1)
    )
}

@MainActor
protocol WakeWordListening: AnyObject {
    var onWakePhrase: ((WakeAction) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func start(bindings: [WakePhraseBinding], sensitivity: WakeSensitivity) throws
    func stop()
}

@MainActor
protocol DictationTriggering: AnyObject {
    var activeShortcutRawValue: String? { get }
    func start() async throws
    func stop() async throws
    func captureCurrentTarget()
    func restoreActiveShortcut(rawValue: String?)
}

protocol HotKeyMonitoring: AnyObject {
    func start() -> Bool
    func stop()
}

protocol NativeSessionStoring: AnyObject {
    func save(_ snapshot: NativeSessionSnapshot)
    func load() -> NativeSessionSnapshot?
    func clear()
}

final class UserDefaultsNativeSessionStore: NativeSessionStoring {
    private static let activeKey = "nativeSessionActive"
    private static let baselineKey = "nativeSessionBaseline"
    private static let startedAtKey = "nativeSessionStartedAt"
    private static let shortcutKey = "nativeSessionShortcut"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save(_ snapshot: NativeSessionSnapshot) {
        defaults.set(true, forKey: Self.activeKey)
        defaults.set(snapshot.startedAt, forKey: Self.startedAtKey)
        if let shortcut = snapshot.nativeShortcutRawValue {
            defaults.set(shortcut, forKey: Self.shortcutKey)
        } else {
            defaults.removeObject(forKey: Self.shortcutKey)
        }
        if let baseline = snapshot.historyBaseline {
            defaults.set(baseline, forKey: Self.baselineKey)
        } else {
            defaults.removeObject(forKey: Self.baselineKey)
        }
    }

    func load() -> NativeSessionSnapshot? {
        guard defaults.bool(forKey: Self.activeKey) else { return nil }

        return NativeSessionSnapshot(
            historyBaseline: defaults.string(forKey: Self.baselineKey),
            startedAt: defaults.double(forKey: Self.startedAtKey),
            nativeShortcutRawValue: defaults.string(forKey: Self.shortcutKey)
        )
    }

    func clear() {
        defaults.removeObject(forKey: Self.activeKey)
        defaults.removeObject(forKey: Self.baselineKey)
        defaults.removeObject(forKey: Self.startedAtKey)
        defaults.removeObject(forKey: Self.shortcutKey)
    }
}

@MainActor
struct VoiceDependencies {
    var requestSpeechPermission: @Sendable () async -> Bool
    var requestMicrophonePermission: @Sendable () async -> Bool
    var hasAccessibilityPermission: () -> Bool
    var requestAccessibilityPermission: () -> Void
    var listener: any WakeWordListening
    var trigger: any DictationTriggering
    var makeStopMonitor: (CodexShortcut, @escaping @Sendable () -> Void) -> any HotKeyMonitoring
    var configuredCodexShortcut: () throws -> CodexShortcut
    var configuredRealtimeVoiceShortcut: () throws -> CodexShortcut
    var toggleRealtimeVoice: () async throws -> Void
    var codexKeybindingsSignature: () -> String?
    var dictationHistorySignature: () -> String?
    var historyChanges: () -> AsyncStream<Void>
    var keybindingsChanges: () -> AsyncStream<Void>
    var dictationLevels: () -> AsyncStream<Float>
    var sessionStore: any NativeSessionStoring
    var defaults: UserDefaults
    var timings: VoiceTimings
    var playSound: (SoundCue) -> Void

    static func live() -> VoiceDependencies {
        let defaults = UserDefaults.standard
        return VoiceDependencies(
            requestSpeechPermission: { await WakeWordListener.requestSpeechPermission() },
            requestMicrophonePermission: { await WakeWordListener.requestMicrophonePermission() },
            hasAccessibilityPermission: { NativeDictationTrigger.hasAccessibilityPermission },
            requestAccessibilityPermission: { NativeDictationTrigger.requestAccessibilityPermission() },
            listener: WakeWordListener(),
            trigger: NativeDictationTrigger(),
            makeStopMonitor: { shortcut, onPressed in
                StopHotKeyMonitor(shortcut: shortcut, onPressed: onPressed)
            },
            configuredCodexShortcut: { try NativeDictationTrigger.configuredShortcut() },
            configuredRealtimeVoiceShortcut: {
                try NativeDictationTrigger.configuredRealtimeVoiceShortcut()
            },
            toggleRealtimeVoice: { try await NativeDictationTrigger.toggleRealtimeVoice() },
            codexKeybindingsSignature: { NativeDictationTrigger.keybindingsSignature },
            dictationHistorySignature: { Self.dictationHistorySignature() },
            historyChanges: { FileChangeWatcher.changes(at: Self.dictationHistoryURL) },
            keybindingsChanges: { FileChangeWatcher.changes(at: NativeDictationTrigger.keybindingsURL) },
            dictationLevels: { MicrophoneLevelMeter.levels() },
            sessionStore: UserDefaultsNativeSessionStore(defaults: defaults),
            defaults: defaults,
            timings: .live,
            playSound: { SoundCuePlayer.play($0) }
        )
    }

    nonisolated static var dictationHistoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/transcription-history.jsonl")
    }

    nonisolated static func dictationHistorySignature() -> String? {
        FileSignature.signature(atPath: dictationHistoryURL.path)
    }
}

enum FileSignature {
    nonisolated static func signature(atPath path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }

        return "\(size.int64Value)-\(modified.timeIntervalSince1970)"
    }
}
