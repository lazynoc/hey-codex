import Foundation
import Observation

@MainActor
@Observable
final class VoiceController {
    private(set) var phase: VoicePhase = .off
    private(set) var isEnabled: Bool
    private(set) var nativeShortcutDisplay = "Checking…"
    private(set) var realtimeVoiceShortcutDisplay = "Checking…"

    var wakePhrase: String {
        didSet {
            let cleaned = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                dependencies.defaults.set(cleaned, forKey: Self.wakePhraseKey)
            }
        }
    }

    var stopShortcutRawValue: String {
        didSet {
            let cleaned = stopShortcutRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                dependencies.defaults.set(cleaned, forKey: StopShortcut.defaultsKey)
            }
        }
    }

    var stopShortcutDisplay: String {
        (try? StopShortcut.resolve(rawValue: stopShortcutRawValue))?.displayName
            ?? "Invalid — use e.g. Ctrl+Option+D"
    }

    private(set) var safetyTimeout: TimeInterval
    private(set) var silenceStopDuration: TimeInterval

    var wakeSensitivity: WakeSensitivity {
        didSet {
            dependencies.defaults.set(wakeSensitivity.rawValue, forKey: WakeSensitivity.defaultsKey)
            refreshWakeBindings()
        }
    }

    var dictationWakeEnabled: Bool {
        didSet {
            dependencies.defaults.set(dictationWakeEnabled, forKey: Self.dictationWakeEnabledKey)
            refreshWakeBindings()
        }
    }

    var voiceChatPhrase: String {
        didSet {
            let cleaned = voiceChatPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                dependencies.defaults.set(cleaned, forKey: Self.voiceChatPhraseKey)
            }
        }
    }

    var voiceChatWakeEnabled: Bool {
        didSet {
            dependencies.defaults.set(voiceChatWakeEnabled, forKey: Self.voiceChatEnabledKey)
            refreshWakeBindings()
        }
    }

    /// The action currently being triggered, for menu-bar labels.
    private(set) var pendingWakeAction: WakeAction?
    private(set) var completedOnboardingTest: WakeAction?
    private(set) var onboardingVoiceChatIsOpen = false

    private let dependencies: VoiceDependencies
    private var onboardingTestAction: WakeAction?
    private var activeOnboardingDemo: WakeAction?
    private var handoffTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var stopFallbackTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var safetyStopTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var keybindingsWatchTask: Task<Void, Never>?
    private var stopKeyMonitor: (any HotKeyMonitoring)?
    private var keybindingsSignature: String?

    private static let wakePhraseKey = "wakePhrase"
    private static let dictationWakeEnabledKey = "dictationWakeEnabled"
    private static let voiceChatPhraseKey = "voiceChatWakePhrase"
    private static let voiceChatEnabledKey = "voiceChatWakeEnabled"
    private static let listeningEnabledKey = "listeningEnabled"
    nonisolated static let safetyTimeoutSeconds: TimeInterval = 10 * 60
    nonisolated static let safetyTimeoutKey = "safetyTimeoutSeconds"
    nonisolated static let silenceStopKey = "silenceStopSeconds"

    init(dependencies: VoiceDependencies = .live()) {
        self.dependencies = dependencies
        wakePhrase = dependencies.defaults.string(forKey: Self.wakePhraseKey) ?? "hey codex"
        let storedStopShortcut = dependencies.defaults.string(forKey: StopShortcut.defaultsKey)
        if let storedStopShortcut,
           (try? StopShortcut.resolve(rawValue: storedStopShortcut)) != nil {
            stopShortcutRawValue = storedStopShortcut
        } else {
            // Self-heal an unset or invalid stored value.
            stopShortcutRawValue = StopShortcut.defaultRawValue
            dependencies.defaults.removeObject(forKey: StopShortcut.defaultsKey)
        }
        let storedTimeout = dependencies.defaults.double(forKey: Self.safetyTimeoutKey)
        safetyTimeout = storedTimeout > 0 ? storedTimeout : Self.safetyTimeoutSeconds
        silenceStopDuration = dependencies.defaults.double(forKey: Self.silenceStopKey)
        wakeSensitivity = dependencies.defaults.string(forKey: WakeSensitivity.defaultsKey)
            .flatMap(WakeSensitivity.init(rawValue:)) ?? .normal
        voiceChatPhrase = dependencies.defaults.string(forKey: Self.voiceChatPhraseKey)
            ?? "hey jarvis"
        dictationWakeEnabled = dependencies.defaults.object(forKey: Self.dictationWakeEnabledKey)
            == nil || dependencies.defaults.bool(forKey: Self.dictationWakeEnabledKey)
        voiceChatWakeEnabled = dependencies.defaults.object(forKey: Self.voiceChatEnabledKey)
            == nil || dependencies.defaults.bool(forKey: Self.voiceChatEnabledKey)
        isEnabled = dependencies.defaults.bool(forKey: Self.listeningEnabledKey)

        dependencies.listener.onWakePhrase = { [weak self] action in
            self?.wakePhraseHeard(action)
        }
        dependencies.listener.onError = { [weak self] message in
            guard let self, self.isEnabled, self.phase == .listening else { return }
            self.phase = .error(message)
        }

        refreshNativeShortcut()
        watchCodexShortcut()
        if isEnabled {
            Task { @MainActor [weak self] in
                await self?.begin()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        dependencies.defaults.set(enabled, forKey: Self.listeningEnabledKey)

        if enabled {
            Task { await begin() }
        } else {
            let mustStopNativeDictation = phase == .dictating
            let activeOnboardingDemo = activeOnboardingDemo
            self.activeOnboardingDemo = nil
            onboardingVoiceChatIsOpen = false
            dependencies.listener.stop()
            cancelSessionTasks()
            stopKeyMonitor?.stop()
            stopKeyMonitor = nil
            if activeOnboardingDemo == .voiceChat {
                let toggleRealtimeVoice = dependencies.toggleRealtimeVoice
                Task { @MainActor in
                    try? await toggleRealtimeVoice()
                }
            } else if activeOnboardingDemo == .dictation || mustStopNativeDictation {
                let trigger = dependencies.trigger
                Task { @MainActor in
                    try? await trigger.stop()
                }
            }
            dependencies.sessionStore.clear()
            phase = .off
        }
    }

    /// Cancels every per-session task. The keybindings watcher is not a
    /// session task — it runs for the lifetime of the controller.
    private func cancelSessionTasks() {
        handoffTask?.cancel()
        handoffTask = nil
        completionTask?.cancel()
        completionTask = nil
        stopFallbackTask?.cancel()
        stopFallbackTask = nil
        resumeTask?.cancel()
        resumeTask = nil
        safetyStopTask?.cancel()
        safetyStopTask = nil
        pauseTask?.cancel()
        pauseTask = nil
        silenceTask?.cancel()
        silenceTask = nil
    }

    func pauseListening(for duration: TimeInterval) {
        guard isEnabled, phase == .listening else { return }
        dependencies.listener.stop()
        phase = .paused

        pauseTask?.cancel()
        pauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, duration)))
            guard !Task.isCancelled else { return }
            self?.resumeListening()
        }
    }

    func resumeListening() {
        guard isEnabled, phase == .paused else { return }
        pauseTask?.cancel()
        pauseTask = nil
        startListening()
    }

    func requestAccessibilityPermission() {
        dependencies.requestAccessibilityPermission()
    }

    func retry() {
        guard isEnabled else { return }
        dependencies.listener.stop()
        Task { await begin() }
    }

    func testNativeDictation() {
        guard phase != .triggering, phase != .dictating, phase != .finishing else { return }
        triggerNativeDictation()
    }

    func startVoiceChat() {
        guard phase != .triggering, phase != .dictating, phase != .finishing else { return }
        triggerRealtimeVoice()
    }

    func beginOnboardingTest(_ action: WakeAction) {
        onboardingTestAction = action
        completedOnboardingTest = nil

        guard isEnabled else { return }
        switch phase {
        case .listening, .error:
            break
        default:
            return
        }

        dependencies.listener.stop()
        startListening()
    }

    func endOnboardingTest() {
        let hadActiveTest = onboardingTestAction != nil
        let shouldCloseVoiceChat = onboardingVoiceChatIsOpen
        onboardingTestAction = nil
        completedOnboardingTest = nil

        if shouldCloseVoiceChat {
            triggerOnboardingVoiceChatTest()
            return
        }

        guard hadActiveTest else { return }
        guard isEnabled, phase == .listening else { return }
        dependencies.listener.stop()
        startListening()
    }

    /// Finishes setup without closing a voice chat the user has already started.
    /// The regular wake bindings are restored so "Hey Jarvis" can still close it.
    func finishOnboardingTest() {
        onboardingTestAction = nil
        completedOnboardingTest = nil
        activeOnboardingDemo = nil
        onboardingVoiceChatIsOpen = false

        guard isEnabled, phase == .listening else { return }
        dependencies.listener.stop()
        startListening()
    }

    func closeOnboardingVoiceChatTest() {
        guard onboardingTestAction == .voiceChat,
              onboardingVoiceChatIsOpen,
              phase == .listening || phase.isError
        else { return }

        triggerOnboardingVoiceChatTest()
    }

    func cancelPendingDictation() {
        guard isEnabled, phase == .triggering else { return }
        handoffTask?.cancel()
        handoffTask = nil
        resumeTask?.cancel()
        resumeTask = nil
        stopKeyMonitor?.stop()
        stopKeyMonitor = nil

        if let activeOnboardingDemo {
            completedOnboardingTest = nil
            phase = .finishing
            handoffTask = Task { @MainActor [weak self] in
                guard let self else { return }

                do {
                    switch activeOnboardingDemo {
                    case .voiceChat:
                        try await self.dependencies.toggleRealtimeVoice()
                    case .dictation:
                        try await self.dependencies.trigger.stop()
                        self.playCue(.dictationStopped)
                        self.dependencies.sessionStore.clear()
                    }
                } catch {
                    self.phase = .error(error.localizedDescription)
                    return
                }

                self.activeOnboardingDemo = nil
                self.onboardingVoiceChatIsOpen = false
                self.startListening()
            }
            return
        }

        startListening()
    }

    func stopNativeDictation() {
        nativeStopShortcutObserved()
    }

    private func begin() async {
        phase = .requestingPermission

        if wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wakePhrase = "hey codex"
        }
        if voiceChatPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            voiceChatPhrase = "hey jarvis"
        }

        let speechAuthorized = await dependencies.requestSpeechPermission()
        let microphoneAuthorized = await dependencies.requestMicrophonePermission()

        guard speechAuthorized, microphoneAuthorized else {
            isEnabled = false
            dependencies.defaults.set(false, forKey: Self.listeningEnabledKey)
            phase = .error("Microphone and Speech access are required")
            return
        }

        guard dependencies.hasAccessibilityPermission() else {
            dependencies.requestAccessibilityPermission()
            phase = .error("Allow Accessibility access, then try again")
            return
        }

        if recoverPersistedNativeSessionIfNeeded() {
            return
        }

        do {
            _ = try dependencies.configuredCodexShortcut()
        } catch {
            refreshNativeShortcut()
            phase = .error(error.localizedDescription)
            return
        }

        startListening()
    }

    private func startListening() {
        guard isEnabled else { return }

        do {
            try dependencies.listener.start(
                bindings: wakeBindings,
                sensitivity: wakeSensitivity
            )
            pendingWakeAction = nil
            phase = .listening
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private var wakeBindings: [WakePhraseBinding] {
        if let onboardingTestAction {
            let phrase = onboardingTestAction == .voiceChat ? voiceChatPhrase : wakePhrase
            return [WakePhraseBinding(phrase: phrase, action: onboardingTestAction)]
        }

        var bindings: [WakePhraseBinding] = []
        let dictationPhrase = wakePhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if dictationWakeEnabled, !dictationPhrase.isEmpty {
            bindings.append(WakePhraseBinding(phrase: dictationPhrase, action: .dictation))
        }
        let chatPhrase = voiceChatPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if voiceChatWakeEnabled, !chatPhrase.isEmpty {
            bindings.append(WakePhraseBinding(phrase: chatPhrase, action: .voiceChat))
        }
        return bindings
    }

    /// Restarts wake listening with the current phrases, toggles, and
    /// sensitivity. Safe to call any time — a no-op unless listening.
    func refreshWakeBindings() {
        guard isEnabled, phase == .listening else { return }
        dependencies.listener.stop()
        startListening()
    }

    private func wakePhraseHeard(_ action: WakeAction) {
        guard phase == .listening else { return }
        playCue(.wakeHeard)

        if onboardingTestAction == action {
            switch action {
            case .voiceChat:
                triggerOnboardingVoiceChatTest()
            case .dictation:
                triggerOnboardingDictationTest()
            }
            return
        }

        switch action {
        case .dictation:
            triggerNativeDictation()
        case .voiceChat:
            triggerRealtimeVoice()
        }
    }

    private func playCue(_ cue: SoundCue) {
        guard dependencies.defaults.object(forKey: SoundCue.enabledKey) == nil
            || dependencies.defaults.bool(forKey: SoundCue.enabledKey)
        else { return }
        dependencies.playSound(cue)
    }

    private func triggerNativeDictation() {
        dependencies.listener.stop()
        handoffTask?.cancel()
        completionTask?.cancel()
        pendingWakeAction = .dictation
        phase = .triggering

        let baseline = dependencies.dictationHistorySignature()
        let handoffDelay = dependencies.timings.handoffDelay

        handoffTask = Task { @MainActor [weak self] in
            // Give Apple Speech time to release the microphone so native
            // dictation does not capture the tail of the wake phrase.
            try? await Task.sleep(for: handoffDelay)
            guard !Task.isCancelled, let self else { return }

            do {
                guard self.installStopKeyMonitor() else { return }
                try await self.dependencies.trigger.start()
                guard let shortcutRawValue = self.dependencies.trigger.activeShortcutRawValue else {
                    throw CodexShortcutConfigurationError.missingToggle
                }
                self.dependencies.sessionStore.save(NativeSessionSnapshot(
                    historyBaseline: baseline,
                    startedAt: Date().timeIntervalSince1970,
                    nativeShortcutRawValue: shortcutRawValue
                ))
                self.phase = .dictating
                self.scheduleSafetyStop(after: self.safetyTimeout)
                self.watchForSilence()
                self.watchForNativeDictationCompletion(baseline: baseline)
            } catch {
                self.stopKeyMonitor?.stop()
                self.stopKeyMonitor = nil
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    private func triggerRealtimeVoice() {
        dependencies.listener.stop()
        handoffTask?.cancel()
        completionTask?.cancel()
        pendingWakeAction = .voiceChat
        phase = .triggering

        let handoffDelay = dependencies.timings.handoffDelay
        let settleDelay = dependencies.timings.completionSettle
        handoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: handoffDelay)
            guard !Task.isCancelled, let self else { return }

            do {
                try await self.dependencies.toggleRealtimeVoice()
            } catch {
                self.phase = .error(error.localizedDescription)
                return
            }

            guard self.isEnabled else {
                self.pendingWakeAction = nil
                self.phase = .off
                return
            }

            // Voice chat is a hands-free toggle: resume wake listening so
            // the same phrase can end the chat without touching the menu.
            self.resumeTask?.cancel()
            self.resumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: settleDelay)
                guard !Task.isCancelled else { return }
                self?.startListening()
            }
        }
    }

    private func triggerOnboardingVoiceChatTest() {
        let isClosing = onboardingVoiceChatIsOpen
        dependencies.listener.stop()
        handoffTask?.cancel()
        completionTask?.cancel()
        completedOnboardingTest = nil
        pendingWakeAction = .voiceChat
        phase = .triggering

        let handoffDelay = dependencies.timings.handoffDelay
        let settleDelay = dependencies.timings.completionSettle
        handoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: handoffDelay)
            guard !Task.isCancelled, let self else { return }
            guard isClosing || self.onboardingTestAction == .voiceChat else {
                self.startListening()
                return
            }

            do {
                try await self.dependencies.toggleRealtimeVoice()

                if isClosing {
                    self.activeOnboardingDemo = nil
                    self.onboardingVoiceChatIsOpen = false
                } else {
                    self.activeOnboardingDemo = .voiceChat
                    self.onboardingVoiceChatIsOpen = true
                }

                guard !Task.isCancelled, self.isEnabled else {
                    if !isClosing {
                        try? await self.dependencies.toggleRealtimeVoice()
                    }
                    self.activeOnboardingDemo = nil
                    self.onboardingVoiceChatIsOpen = false
                    if self.isEnabled {
                        self.startListening()
                    } else {
                        self.phase = .off
                    }
                    return
                }
            } catch {
                self.phase = .error(error.localizedDescription)
                return
            }

            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            guard self.isEnabled else {
                self.pendingWakeAction = nil
                self.phase = .off
                return
            }

            let shouldReportSuccess = self.onboardingTestAction == .voiceChat
            self.startListening()
            if shouldReportSuccess {
                self.completedOnboardingTest = .voiceChat
            }
        }
    }

    private func triggerOnboardingDictationTest() {
        dependencies.listener.stop()
        handoffTask?.cancel()
        completionTask?.cancel()
        completedOnboardingTest = nil
        pendingWakeAction = .dictation
        phase = .triggering

        let baseline = dependencies.dictationHistorySignature()
        let handoffDelay = dependencies.timings.handoffDelay
        let demoDuration = dependencies.timings.onboardingDictationDemo
        let settleDelay = dependencies.timings.completionSettle
        handoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: handoffDelay)
            guard !Task.isCancelled, let self else { return }

            do {
                try await self.dependencies.trigger.start()
                guard let shortcutRawValue = self.dependencies.trigger.activeShortcutRawValue else {
                    throw CodexShortcutConfigurationError.missingToggle
                }
                self.dependencies.sessionStore.save(NativeSessionSnapshot(
                    historyBaseline: baseline,
                    startedAt: Date().timeIntervalSince1970,
                    nativeShortcutRawValue: shortcutRawValue
                ))
                self.activeOnboardingDemo = .dictation
                guard !Task.isCancelled, self.isEnabled else {
                    try? await self.dependencies.trigger.stop()
                    self.activeOnboardingDemo = nil
                    self.dependencies.sessionStore.clear()
                    self.phase = self.isEnabled ? .listening : .off
                    return
                }

                self.phase = .dictating

                try? await Task.sleep(for: demoDuration)
                guard !Task.isCancelled else { return }
                self.phase = .finishing
                try await self.dependencies.trigger.stop()
                self.activeOnboardingDemo = nil
            } catch {
                self.phase = .error(error.localizedDescription)
                return
            }

            self.playCue(.dictationStopped)
            self.dependencies.sessionStore.clear()

            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            guard self.isEnabled else {
                self.pendingWakeAction = nil
                self.phase = .off
                return
            }

            let shouldReportSuccess = self.onboardingTestAction == .dictation
            self.startListening()
            if shouldReportSuccess {
                self.completedOnboardingTest = .dictation
            }
        }
    }

    private func watchForNativeDictationCompletion(baseline: String?) {
        completionTask?.cancel()
        let changes = dependencies.historyChanges()

        completionTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }

                if self.dependencies.dictationHistorySignature() != baseline {
                    self.nativeDictationCompleted()
                    return
                }
            }
        }
    }

    private func installStopKeyMonitor() -> Bool {
        let stopShortcut: CodexShortcut
        do {
            stopShortcut = try StopShortcut.resolve(rawValue: stopShortcutRawValue)
        } catch {
            phase = .error(error.localizedDescription)
            return false
        }

        if let codexShortcut = try? dependencies.configuredCodexShortcut(),
           StopShortcut.conflicts(stopShortcut, with: codexShortcut) {
            phase = .error(
                "The stop shortcut matches the Codex dictation shortcut — change one of them"
            )
            return false
        }

        let monitor = dependencies.makeStopMonitor(stopShortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.nativeStopShortcutObserved()
            }
        }
        if monitor.start() {
            stopKeyMonitor = monitor
            return true
        }
        phase = .error("The stop shortcut could not be registered")
        return false
    }

    private func nativeStopShortcutObserved() {
        guard phase == .dictating else { return }
        phase = .finishing
        safetyStopTask?.cancel()
        safetyStopTask = nil
        silenceTask?.cancel()
        silenceTask = nil

        let fallbackDelay = dependencies.timings.stopFallback
        stopFallbackTask?.cancel()
        stopFallbackTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.dependencies.trigger.stop()
            } catch {
                self.stopKeyMonitor?.stop()
                self.stopKeyMonitor = nil
                self.phase = .error(error.localizedDescription)
                return
            }

            try? await Task.sleep(for: fallbackDelay)
            guard !Task.isCancelled else { return }
            self.nativeDictationCompleted()
        }
    }

    private func nativeDictationCompleted() {
        guard phase == .dictating || phase == .finishing else { return }
        phase = .finishing
        playCue(.dictationStopped)
        dependencies.sessionStore.clear()
        completionTask?.cancel()
        completionTask = nil
        stopFallbackTask?.cancel()
        safetyStopTask?.cancel()
        safetyStopTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        stopKeyMonitor?.stop()
        stopKeyMonitor = nil

        let settleDelay = dependencies.timings.completionSettle
        resumeTask?.cancel()
        resumeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.startListening()
        }
    }

    func setSafetyTimeout(_ seconds: TimeInterval) {
        safetyTimeout = seconds
        dependencies.defaults.set(seconds, forKey: Self.safetyTimeoutKey)
    }

    func setSilenceStop(_ seconds: TimeInterval) {
        silenceStopDuration = seconds
        dependencies.defaults.set(seconds, forKey: Self.silenceStopKey)
    }

    private func watchForSilence() {
        silenceTask?.cancel()
        silenceTask = nil
        guard silenceStopDuration > 0 else { return }

        let levels = dependencies.dictationLevels()
        let detector = SilenceDetector(window: silenceStopDuration)

        silenceTask = Task { @MainActor [weak self] in
            for await level in levels {
                guard !Task.isCancelled, let self else { return }

                if detector.process(level: level, at: Date().timeIntervalSince1970) {
                    self.nativeStopShortcutObserved()
                    return
                }
            }
        }
    }

    private func scheduleSafetyStop(after seconds: TimeInterval) {
        safetyStopTask?.cancel()
        safetyStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            guard !Task.isCancelled else { return }
            self?.nativeStopShortcutObserved()
        }
    }

    private func recoverPersistedNativeSessionIfNeeded() -> Bool {
        guard let snapshot = dependencies.sessionStore.load() else { return false }

        let currentSignature = dependencies.dictationHistorySignature()
        guard NativeSessionRecovery.shouldRecover(
            snapshot: snapshot,
            currentHistorySignature: currentSignature
        ) else {
            dependencies.sessionStore.clear()
            return false
        }

        guard installStopKeyMonitor() else { return true }

        dependencies.trigger.restoreActiveShortcut(rawValue: snapshot.nativeShortcutRawValue)
        dependencies.trigger.captureCurrentTarget()
        dependencies.listener.stop()
        phase = .dictating
        watchForSilence()
        watchForNativeDictationCompletion(baseline: snapshot.historyBaseline)
        scheduleSafetyStop(after: NativeSessionRecovery.remainingSafetySeconds(
            snapshot: snapshot,
            now: Date().timeIntervalSince1970,
            timeoutSeconds: safetyTimeout
        ))
        return true
    }

    private func refreshNativeShortcut() {
        do {
            nativeShortcutDisplay = try dependencies.configuredCodexShortcut().displayName
        } catch {
            nativeShortcutDisplay = "Not configured"
        }
        do {
            realtimeVoiceShortcutDisplay =
                try dependencies.configuredRealtimeVoiceShortcut().displayName
        } catch {
            realtimeVoiceShortcutDisplay = "Not configured"
        }
        keybindingsSignature = dependencies.codexKeybindingsSignature()
    }

    private func watchCodexShortcut() {
        keybindingsWatchTask?.cancel()
        let changes = dependencies.keybindingsChanges()

        keybindingsWatchTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }

                if self.dependencies.codexKeybindingsSignature() != self.keybindingsSignature {
                    self.refreshNativeShortcut()
                }
            }
        }
    }
}

struct NativeSessionSnapshot: Equatable {
    let historyBaseline: String?
    let startedAt: TimeInterval
    let nativeShortcutRawValue: String?
}

enum NativeSessionRecovery {
    nonisolated static func shouldRecover(
        snapshot: NativeSessionSnapshot,
        currentHistorySignature: String?
    ) -> Bool {
        snapshot.historyBaseline == currentHistorySignature
    }

    nonisolated static func remainingSafetySeconds(
        snapshot: NativeSessionSnapshot,
        now: TimeInterval,
        timeoutSeconds: TimeInterval
    ) -> TimeInterval {
        max(0, timeoutSeconds - max(0, now - snapshot.startedAt))
    }
}
