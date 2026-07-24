import Foundation
@testable import HeyCodex

@MainActor
final class FakeListener: WakeWordListening {
    var onWakePhrase: ((WakeAction) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var isListening = false
    private(set) var bindings: [WakePhraseBinding] = []
    var startError: (any Error)?

    func start(bindings: [WakePhraseBinding], sensitivity: WakeSensitivity) throws {
        if let startError { throw startError }
        self.bindings = bindings
        isListening = true
    }

    func stop() {
        isListening = false
    }
}

@MainActor
final class FakeTrigger: DictationTriggering {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var activeShortcutRawValue: String? = "Ctrl+Shift+D"
    var startError: (any Error)?
    var stopError: (any Error)?

    func start() async throws {
        if let startError { throw startError }
        startCount += 1
    }

    func stop() async throws {
        if let stopError { throw stopError }
        stopCount += 1
    }

    func captureCurrentTarget() {}

    func restoreActiveShortcut(rawValue: String?) {}
}

@MainActor
final class FakeRealtimeVoiceTrigger {
    private(set) var toggleCount = 0
    var toggleError: (any Error)?

    func toggle() async throws {
        if let toggleError { throw toggleError }
        toggleCount += 1
    }
}

final class FakeHotKeyMonitor: HotKeyMonitoring {
    private(set) var isArmed = false
    var startSucceeds = true

    func start() -> Bool {
        guard startSucceeds else { return false }
        isArmed = true
        return true
    }

    func stop() {
        isArmed = false
    }
}

final class InMemorySessionStore: NativeSessionStoring {
    var snapshot: NativeSessionSnapshot?

    func save(_ snapshot: NativeSessionSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> NativeSessionSnapshot? {
        snapshot
    }

    func clear() {
        snapshot = nil
    }
}

@MainActor
final class PlayedSounds {
    var cues: [SoundCue] = []
}

final class SignatureBox: @unchecked Sendable {
    var value: String?

    init(_ value: String? = nil) {
        self.value = value
    }
}

final class IntBox: @unchecked Sendable {
    var value: Int?

    init(_ value: Int? = nil) {
        self.value = value
    }
}

final class StreamBox: @unchecked Sendable {
    private var continuation: AsyncStream<Void>.Continuation?

    func makeStream() -> AsyncStream<Void> {
        AsyncStream { self.continuation = $0 }
    }

    func tick() {
        continuation?.yield(())
    }
}

final class LevelStreamBox: @unchecked Sendable {
    private var continuation: AsyncStream<Float>.Continuation?

    func makeStream() -> AsyncStream<Float> {
        AsyncStream { self.continuation = $0 }
    }

    func yield(_ level: Float) {
        continuation?.yield(level)
    }
}

@MainActor
struct VoiceControllerHarness {
    let controller: VoiceController
    let listener: FakeListener
    let trigger: FakeTrigger
    let voiceChatTrigger: FakeRealtimeVoiceTrigger
    let monitor: FakeHotKeyMonitor
    let store: InMemorySessionStore
    let historySignature: SignatureBox
    let codexDialogCount: IntBox
    let historyStream: StreamBox
    let levelStream: LevelStreamBox
    let defaults: UserDefaults

    static func make(
        configure: (inout VoiceDependencies) -> Void = { _ in }
    ) -> VoiceControllerHarness {
        let suiteName = "hey-codex-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let listener = FakeListener()
        let trigger = FakeTrigger()
        let voiceChatTrigger = FakeRealtimeVoiceTrigger()
        let monitor = FakeHotKeyMonitor()
        let store = InMemorySessionStore()
        let historySignature = SignatureBox("baseline")
        let codexDialogCount = IntBox()
        let historyStream = StreamBox()
        let levelStream = LevelStreamBox()

        var dependencies = VoiceDependencies(
            requestSpeechPermission: { true },
            requestMicrophonePermission: { true },
            hasAccessibilityPermission: { true },
            requestAccessibilityPermission: {},
            listener: listener,
            trigger: trigger,
            makeStopMonitor: { _, _ in monitor },
            configuredCodexShortcut: { try CodexShortcut.parse("Ctrl+Shift+D") },
            configuredRealtimeVoiceShortcut: { try CodexShortcut.parse("Fn") },
            toggleRealtimeVoice: { try await voiceChatTrigger.toggle() },
            codexDialogCount: { codexDialogCount.value },
            codexKeybindingsSignature: { "keybindings" },
            dictationHistorySignature: { historySignature.value },
            historyChanges: { historyStream.makeStream() },
            keybindingsChanges: { AsyncStream { _ in } },
            dictationLevels: { levelStream.makeStream() },
            sessionStore: store,
            defaults: defaults,
            timings: .test,
            playSound: { _ in }
        )
        configure(&dependencies)

        return VoiceControllerHarness(
            controller: VoiceController(dependencies: dependencies),
            listener: listener,
            trigger: trigger,
            voiceChatTrigger: voiceChatTrigger,
            monitor: monitor,
            store: store,
            historySignature: historySignature,
            codexDialogCount: codexDialogCount,
            historyStream: historyStream,
            levelStream: levelStream,
            defaults: defaults
        )
    }

    /// Drives the controller from off to `.dictating` via the wake phrase.
    func startDictating() async -> Bool {
        controller.setEnabled(true)
        guard await waitUntil({ controller.phase == .listening }) else { return false }
        listener.onWakePhrase?(.dictation)
        return await waitUntil { controller.phase == .dictating }
    }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}
