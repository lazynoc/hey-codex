@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Runs continuous on-device speech recognition and fires `onWakePhrase`
/// when the configured wake phrase is heard.
///
/// The audio engine and microphone tap run without interruption; only the
/// recognition request/task pair rotates before Apple's ~1 minute session
/// limit. During a rotation the outgoing and incoming sessions overlap for
/// one second so the listener is never deaf.
@MainActor
final class WakeWordListener: WakeWordListening {
    var onWakePhrase: ((WakeAction) -> Void)?
    var onError: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let router = AudioBufferRouter()
    private let recognizer: SFSpeechRecognizer?
    private var sessions: [UUID: Session] = [:]
    private var currentSessionID: UUID?
    private var rotationTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var bindings: [WakePhraseBinding] = []
    private var sensitivity: WakeSensitivity = .normal
    private var isActive = false

    private struct Session {
        let request: SFSpeechAudioBufferRecognitionRequest
        let task: SFSpeechRecognitionTask
    }

    init(locale: Locale? = nil) {
        recognizer = Self.makeRecognizer(preferredLocale: locale)
    }

    func start(bindings: [WakePhraseBinding], sensitivity: WakeSensitivity) throws {
        self.bindings = bindings
        self.sensitivity = sensitivity
        isActive = true
        try startEngine()
        try startSession()
    }

    func stop() {
        isActive = false
        rotationTask?.cancel()
        rotationTask = nil
        restartTask?.cancel()
        restartTask = nil
        endAllSessions()
        stopEngine()
    }

    private static func makeRecognizer(preferredLocale: Locale?) -> SFSpeechRecognizer? {
        for locale in WakeLocaleSelector.candidates(
            preferred: preferredLocale,
            current: Locale.current
        ) {
            if let recognizer = SFSpeechRecognizer(locale: locale),
               recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }

    private func startEngine() throws {
        guard !audioEngine.isRunning else { return }

        AudioInputDevices.apply(
            uid: UserDefaults.standard.string(forKey: AudioInputDevices.defaultsKey),
            to: audioEngine
        )

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw WakeWordListenerError.microphoneUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeAudioTapHandler(router: router)
        )

        audioEngine.prepare()
        try audioEngine.start()
    }

    nonisolated static func makeAudioTapHandler(
        router: AudioBufferRouter
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            router.route(buffer)
        }
    }

    private func stopEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func startSession() throws {
        guard isActive, let recognizer, recognizer.isAvailable else {
            throw WakeWordListenerError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = bindings.map(\.phrase) + [
            "Hey codec",
            "Hey code X",
            "Hey Kodak",
            "Codex",
            "Hey Jarvis",
            "Jarvis",
        ]
        request.taskHint = .confirmation

        let sessionID = UUID()
        router.attach(id: sessionID, consumer: SpeechRequestConsumer(request))

        let task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeRecognitionHandler(
                listener: self,
                sessionID: sessionID
            )
        )

        sessions[sessionID] = Session(request: request, task: task)
        currentSessionID = sessionID
        scheduleSessionRotation(sessionID: sessionID)
    }

    private func startSessionIfActive() {
        guard isActive else { return }
        do {
            if !audioEngine.isRunning {
                try startEngine()
            }
            try startSession()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func scheduleSessionRotation(sessionID rotationSessionID: UUID) {
        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled,
                  let self,
                  self.isActive,
                  self.currentSessionID == rotationSessionID
            else { return }

            self.rotate(from: rotationSessionID)
        }
    }

    /// Starts the replacement session first, keeps both fed for one second,
    /// then retires the old one — the microphone tap never pauses.
    private func rotate(from oldSessionID: UUID) {
        startSessionIfActive()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.retireSession(oldSessionID)
        }
    }

    private func retireSession(_ sessionID: UUID) {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        router.detach(id: sessionID)
        session.request.endAudio()
        session.task.cancel()
        if currentSessionID == sessionID {
            currentSessionID = nil
        }
    }

    private func endAllSessions() {
        router.detachAll()
        for session in sessions.values {
            session.request.endAudio()
            session.task.cancel()
        }
        sessions.removeAll()
        currentSessionID = nil
    }

    private func consume(_ transcript: String) {
        guard isActive,
              let action = PhraseParser.matchedAction(
                  transcript,
                  bindings: bindings,
                  sensitivity: sensitivity
              )
        else { return }

        onWakePhrase?(action)
    }

    private func recognitionEnded(sessionID: UUID) {
        let wasCurrent = currentSessionID == sessionID
        retireSession(sessionID)
        guard wasCurrent, isActive else { return }

        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.startSessionIfActive()
        }
    }

    private nonisolated static func makeRecognitionHandler(
        listener: WakeWordListener,
        sessionID: UUID
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { [weak listener] result, error in
            let transcript = result?.bestTranscription.formattedString
            let recognitionEnded = error != nil || result?.isFinal == true

            Task { @MainActor [weak listener] in
                guard let listener, listener.sessions[sessionID] != nil else { return }

                if let transcript {
                    listener.consume(transcript)
                }

                if recognitionEnded {
                    listener.recognitionEnded(sessionID: sessionID)
                }
            }
        }
    }

    nonisolated static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        default:
            false
        }
    }
}

enum WakeLocaleSelector {
    /// Ordered, de-duplicated locale candidates for wake word recognition:
    /// an explicit preference first, then the user's current locale, then
    /// English fallbacks known to ship on-device recognition assets.
    nonisolated static func candidates(preferred: Locale?, current: Locale) -> [Locale] {
        var identifiers: [String] = []

        func append(_ identifier: String) {
            let normalized = identifier.replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty,
                  !identifiers.contains(where: {
                      $0.caseInsensitiveCompare(normalized) == .orderedSame
                  })
            else { return }
            identifiers.append(normalized)
        }

        if let preferred {
            append(preferred.identifier)
        }
        append(current.identifier)
        append("en-US")
        append("en-GB")

        return identifiers.map(Locale.init(identifier:))
    }
}

/// Feeds routed microphone buffers into one recognition request.
private final class SpeechRequestConsumer: AudioBufferConsuming {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }
}

enum WakeWordListenerError: LocalizedError {
    case recognizerUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "On-device speech recognition is unavailable"
        case .microphoneUnavailable:
            "The microphone is unavailable"
        }
    }
}
