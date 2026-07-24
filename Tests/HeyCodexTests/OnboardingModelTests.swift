import Foundation
import Testing
@testable import HeyCodex

@MainActor
@Suite("First-run onboarding")
struct OnboardingModelTests {
    @Test func refreshReportsPermissionsAndConfiguredShortcut() async throws {
        let model = OnboardingModel(dependencies: makeDependencies())

        await model.refresh()

        #expect(model.allPermissionsGranted)
        #expect(model.isShortcutConfigured)
        #expect(model.shortcutDisplay == "Control+Shift+D")
        #expect(model.shortcutError == nil)
    }

    @Test func oneMissingPermissionBlocksThePermissionsStep() async {
        let dependencies = makeDependencies(
            accessibilityStatus: { .needsPermission }
        )
        let model = OnboardingModel(dependencies: dependencies)

        await model.refresh()

        #expect(!model.allPermissionsGranted)
        #expect(model.permissionState(for: .accessibility) == .needsPermission)
    }

    @Test func missingShortcutKeepsAnActionableError() async {
        var dependencies = makeDependencies()
        dependencies.configuredShortcut = {
            throw CodexShortcutConfigurationError.missingToggle
        }
        let model = OnboardingModel(dependencies: dependencies)

        await model.refresh()

        #expect(!model.isShortcutConfigured)
        #expect(model.shortcutDisplay == nil)
        #expect(model.shortcutError == "Set a Toggle dictation hotkey in Codex Settings → Voice")
    }

    @Test func requestingPermissionRefreshesItsLiveState() async {
        let probe = PermissionProbe()
        var dependencies = makeDependencies(
            microphoneStatus: {
                probe.microphoneGranted ? .granted : .needsPermission
            }
        )
        dependencies.requestMicrophone = {
            probe.microphoneGranted = true
        }
        let model = OnboardingModel(dependencies: dependencies)

        await model.refresh()
        #expect(model.permissionState(for: .microphone) == .needsPermission)

        await model.request(.microphone)

        #expect(model.permissionState(for: .microphone) == .granted)
    }

    @Test func requestingPermissionShowsCheckingWhileTheSystemPromptIsOpen() async {
        let gate = PermissionRequestGate()
        var dependencies = makeDependencies(
            microphoneStatus: { .needsPermission }
        )
        dependencies.requestMicrophone = {
            await gate.wait()
        }
        let model = OnboardingModel(dependencies: dependencies)

        await model.refresh()
        let request = Task {
            await model.request(.microphone)
        }
        await gate.waitUntilStarted()

        #expect(model.permissionState(for: .microphone) == .checking)

        gate.release()
        await request.value
    }

    @Test func openingCodexSettingsUsesTheInjectedAction() {
        let probe = CodexOpenProbe()
        var dependencies = makeDependencies()
        dependencies.openCodex = {
            probe.wasOpened = true
        }
        let model = OnboardingModel(dependencies: dependencies)

        model.openCodex()

        #expect(probe.wasOpened)
    }

    private func makeDependencies(
        speechStatus: @escaping () -> SetupPermissionState = { .granted },
        microphoneStatus: @escaping () -> SetupPermissionState = { .granted },
        accessibilityStatus: @escaping () -> SetupPermissionState = { .granted },
        automationStatus: @escaping () async -> SetupPermissionState = { .granted }
    ) -> OnboardingDependencies {
        OnboardingDependencies(
            speechStatus: speechStatus,
            microphoneStatus: microphoneStatus,
            accessibilityStatus: accessibilityStatus,
            automationStatus: automationStatus,
            requestSpeech: {},
            requestMicrophone: {},
            requestAccessibility: {},
            requestAutomation: {},
            configuredShortcut: {
                try CodexShortcut.parse("Ctrl+Shift+D")
            },
            configuredVoiceChatShortcut: {
                try CodexShortcut.parse("Fn")
            },
            openPrivacySettings: { _ in },
            openCodex: {}
        )
    }
}

@MainActor
private final class PermissionProbe {
    var microphoneGranted = false
}

@MainActor
private final class PermissionRequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func wait() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class CodexOpenProbe {
    var wasOpened = false
}
