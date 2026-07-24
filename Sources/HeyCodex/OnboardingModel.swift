import AppKit
@preconcurrency import AVFoundation
import Observation
@preconcurrency import Speech

enum SetupPermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case speechRecognition
    case accessibility
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            "Microphone"
        case .speechRecognition:
            "Speech Recognition"
        case .accessibility:
            "Accessibility"
        case .automation:
            "Automation"
        }
    }

    var detail: String {
        switch self {
        case .microphone:
            "Listen only for your wake phrase"
        case .speechRecognition:
            "Recognise “Hey Codex” on this Mac"
        case .accessibility:
            "Use your Codex shortcut and restore the cursor"
        case .automation:
            "Return focus after dictation"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone:
            "mic"
        case .speechRecognition:
            "waveform"
        case .accessibility:
            "accessibility"
        case .automation:
            "gearshape.2"
        }
    }
}

enum SetupPermissionState: Equatable {
    case checking
    case needsPermission
    case granted
    case denied
    case unavailable

    var statusText: String {
        switch self {
        case .checking:
            "Checking"
        case .needsPermission:
            "Needs access"
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .unavailable:
            "Unavailable"
        }
    }
}

struct SetupPermissionItem: Identifiable, Equatable {
    let kind: SetupPermissionKind
    var state: SetupPermissionState

    var id: SetupPermissionKind { kind }
}

@MainActor
struct OnboardingDependencies {
    var speechStatus: () -> SetupPermissionState
    var microphoneStatus: () -> SetupPermissionState
    var accessibilityStatus: () -> SetupPermissionState
    var automationStatus: () async -> SetupPermissionState
    var requestSpeech: () async -> Void
    var requestMicrophone: () async -> Void
    var requestAccessibility: () -> Void
    var requestAutomation: () async -> Void
    var configuredShortcut: () throws -> CodexShortcut
    var configuredVoiceChatShortcut: () throws -> CodexShortcut
    var openPrivacySettings: (SetupPermissionKind) -> Void
    var openCodex: () -> Void

    static func live() -> OnboardingDependencies {
        OnboardingDependencies(
            speechStatus: {
                switch SFSpeechRecognizer.authorizationStatus() {
                case .authorized:
                    .granted
                case .notDetermined:
                    .needsPermission
                case .denied, .restricted:
                    .denied
                @unknown default:
                    .unavailable
                }
            },
            microphoneStatus: {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized:
                    .granted
                case .notDetermined:
                    .needsPermission
                case .denied, .restricted:
                    .denied
                @unknown default:
                    .unavailable
                }
            },
            accessibilityStatus: {
                NativeDictationTrigger.hasAccessibilityPermission
                    ? .granted
                    : .needsPermission
            },
            automationStatus: {
                await AutomationPermission.status()
            },
            requestSpeech: {
                _ = await WakeWordListener.requestSpeechPermission()
            },
            requestMicrophone: {
                _ = await WakeWordListener.requestMicrophonePermission()
            },
            requestAccessibility: {
                NativeDictationTrigger.requestAccessibilityPermission()
            },
            requestAutomation: {
                _ = await AutomationPermission.status(promptIfNeeded: true)
            },
            configuredShortcut: {
                try NativeDictationTrigger.configuredShortcut()
            },
            configuredVoiceChatShortcut: {
                try NativeDictationTrigger.configuredRealtimeVoiceShortcut()
            },
            openPrivacySettings: { kind in
                guard let url = Self.privacySettingsURL(for: kind) else { return }
                NSWorkspace.shared.open(url)
            },
            openCodex: {
                CodexVoiceSettingsOpener.open()
            }
        )
    }

    private static func privacySettingsURL(for kind: SetupPermissionKind) -> URL? {
        let anchor = switch kind {
        case .microphone:
            "Privacy_Microphone"
        case .speechRecognition:
            "Privacy_SpeechRecognition"
        case .accessibility:
            "Privacy_Accessibility"
        case .automation:
            "Privacy_Automation"
        }
        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        )
    }
}

@MainActor
@Observable
final class OnboardingModel {
    nonisolated static let completedKey = "hasCompletedOnboarding"

    private(set) var permissions = SetupPermissionKind.allCases.map {
        SetupPermissionItem(kind: $0, state: .checking)
    }
    private(set) var shortcutDisplay: String?
    private(set) var shortcutError: String?
    private(set) var voiceChatShortcutDisplay: String?
    private(set) var isRefreshing = false

    private let dependencies: OnboardingDependencies

    init(dependencies: OnboardingDependencies = .live()) {
        self.dependencies = dependencies
    }

    var allPermissionsGranted: Bool {
        permissions.allSatisfy { $0.state == .granted }
    }

    var isShortcutConfigured: Bool {
        shortcutDisplay != nil
    }

    func permissionState(for kind: SetupPermissionKind) -> SetupPermissionState {
        permissions.first(where: { $0.kind == kind })?.state ?? .unavailable
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        setPermission(.speechRecognition, to: dependencies.speechStatus())
        setPermission(.microphone, to: dependencies.microphoneStatus())
        setPermission(.accessibility, to: dependencies.accessibilityStatus())
        setPermission(.automation, to: await dependencies.automationStatus())
        refreshShortcut()

        isRefreshing = false
    }

    func request(_ kind: SetupPermissionKind) async {
        let currentState = permissionState(for: kind)
        if currentState == .denied {
            dependencies.openPrivacySettings(kind)
            return
        }

        setPermission(kind, to: .checking)

        switch kind {
        case .microphone:
            await dependencies.requestMicrophone()
        case .speechRecognition:
            await dependencies.requestSpeech()
        case .accessibility:
            dependencies.requestAccessibility()
        case .automation:
            await dependencies.requestAutomation()
        }

        await refresh()
    }

    func openPrivacySettings(for kind: SetupPermissionKind) {
        dependencies.openPrivacySettings(kind)
    }

    func openCodex() {
        dependencies.openCodex()
    }

    private func refreshShortcut() {
        do {
            shortcutDisplay = try dependencies.configuredShortcut().displayName
            shortcutError = nil
        } catch {
            shortcutDisplay = nil
            shortcutError = error.localizedDescription
        }
        voiceChatShortcutDisplay = try? dependencies.configuredVoiceChatShortcut().displayName
    }

    private func setPermission(
        _ kind: SetupPermissionKind,
        to state: SetupPermissionState
    ) {
        guard let index = permissions.firstIndex(where: { $0.kind == kind }) else {
            return
        }
        permissions[index].state = state
    }
}
