import Foundation
import Testing
@testable import HeyCodex

@Suite("Native Codex dictation shortcut")
struct NativeDictationTriggerTests {
    @Test(
        "Live configured shortcut toggles Codex",
        .enabled(if: ProcessInfo.processInfo.environment["HEY_CODEX_LIVE_TEST"] == "1")
    )
    func liveConfiguredShortcutTogglesCodex() async throws {
        let shortcut = try NativeDictationTrigger.configuredShortcut()
        try await shortcut.send()
        try? await Task.sleep(for: .seconds(12))
        try? await shortcut.send()
    }

    @Test func safetyTimeoutIsTenMinutes() {
        #expect(VoiceController.safetyTimeoutSeconds == 600)
    }

    @Test func recoversNativeSessionWhenHistoryHasNotChanged() {
        let snapshot = NativeSessionSnapshot(
            historyBaseline: "100-1234",
            startedAt: 1_000,
            nativeShortcutRawValue: "LeftOption"
        )

        #expect(NativeSessionRecovery.shouldRecover(
            snapshot: snapshot,
            currentHistorySignature: "100-1234"
        ))
        #expect(!NativeSessionRecovery.shouldRecover(
            snapshot: snapshot,
            currentHistorySignature: "200-1235"
        ))
    }

    @Test func recoveredSessionKeepsOnlyRemainingSafetyTime() {
        let snapshot = NativeSessionSnapshot(
            historyBaseline: nil,
            startedAt: 1_000,
            nativeShortcutRawValue: "Ctrl+Shift+D"
        )

        #expect(NativeSessionRecovery.remainingSafetySeconds(
            snapshot: snapshot,
            now: 1_180,
            timeoutSeconds: 600
        ) == 420)
        #expect(NativeSessionRecovery.remainingSafetySeconds(
            snapshot: snapshot,
            now: 1_700,
            timeoutSeconds: 600
        ) == 0)
    }

    @Test func parsesConfiguredControlShiftDShortcut() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["command": "globalDictationToggle", "key": "Ctrl+Shift+D"],
        ])
        let shortcut = try NativeDictationTrigger.configuredShortcut(in: data)

        #expect(shortcut.keyCode == 2)
        #expect(shortcut.flags.contains(.maskControl))
        #expect(shortcut.flags.contains(.maskShift))
        #expect(shortcut.displayName == "Control+Shift+D")
    }

    @Test func acceptsConfiguredLeftOptionShortcut() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["command": "globalDictationToggle", "key": "LeftOption"],
        ])
        let shortcut = try NativeDictationTrigger.configuredShortcut(in: data)

        #expect(shortcut.keyCode == 58)
        #expect(shortcut.flags == .maskAlternate)
        #expect(shortcut.displayName == "Left Option")
        #expect(shortcut.isBareModifier)
    }

    @Test func parsesConfiguredRealtimeVoiceShortcut() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["command": "globalDictationToggle", "key": "LeftOption"],
            ["command": "realtimeVoice", "key": "Fn"],
        ])
        let shortcut = try CodexKeybindings.realtimeVoice(in: data)

        #expect(shortcut.rawValue == "Fn")
        #expect(shortcut.keyCode == 63)
        #expect(shortcut.flags == .maskSecondaryFn)
        #expect(shortcut.displayName == "Function")
        #expect(shortcut.isBareModifier)
    }

    @Test func holdsBareModifiersLongEnoughForCodexToRecognizeThem() throws {
        let bareModifier = try CodexShortcut.parse("Fn")
        let regularShortcut = try CodexShortcut.parse("Ctrl+Shift+D")

        #expect(bareModifier.pressDuration == .milliseconds(350))
        #expect(regularShortcut.pressDuration == .milliseconds(35))
    }

    @Test func parsesControlAltDAndFunctionKeys() throws {
        let combination = try CodexShortcut.parse("Ctrl+Alt+D")
        let reordered = try CodexShortcut.parse("Shift+Ctrl+D")
        let functionKey = try CodexShortcut.parse("F8")

        #expect(combination.keyCode == 2)
        #expect(combination.flags.contains(.maskControl))
        #expect(combination.flags.contains(.maskAlternate))
        #expect(reordered.flags.contains(.maskShift))
        #expect(reordered.flags.contains(.maskControl))
        #expect(functionKey.keyCode == 100)
        #expect(functionKey.flags.isEmpty)
    }

    @Test func duplicateBindingsUseLastEffectiveValue() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["command": "globalDictationToggle", "key": "Ctrl+Shift+D"],
            ["command": "globalDictationToggle", "key": "LeftOption"],
        ])

        #expect(try NativeDictationTrigger.configuredShortcut(in: data).rawValue == "LeftOption")
    }

    @Test func reportsInvalidAndMissingBindings() throws {
        #expect(throws: CodexShortcutConfigurationError.missingFile) {
            try NativeDictationTrigger.configuredShortcut(
                at: URL(fileURLWithPath: "/definitely/missing/hey-codex-keybindings.json")
            )
        }
        #expect(throws: CodexShortcutConfigurationError.invalidJSON) {
            try NativeDictationTrigger.configuredShortcut(in: Data("not-json".utf8))
        }
        #expect(throws: CodexShortcutConfigurationError.missingToggle) {
            try NativeDictationTrigger.configuredShortcut(in: Data("[]".utf8))
        }

        let noKey = try JSONSerialization.data(withJSONObject: [
            ["command": "globalDictationToggle"],
        ])
        #expect(throws: CodexShortcutConfigurationError.missingKey) {
            try NativeDictationTrigger.configuredShortcut(in: noKey)
        }
    }

    @Test func genericBareModifierNeedsASide() {
        #expect(throws: CodexShortcut.ParseError.modifierNeedsKey) {
            try CodexShortcut.parse("Option")
        }
    }

    @Test func rejectsUnsafeBareOrdinaryKey() {
        #expect(throws: CodexShortcut.ParseError.unsupportedBareKey("D")) {
            try CodexShortcut.parse("D")
        }
    }

    @Test func mapsAnInvalidConfiguredShortcutToConfigurationError() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            ["command": "globalDictationToggle", "key": "D"],
        ])

        #expect(throws: CodexShortcutConfigurationError.invalidShortcut(
            "Codex shortcut D needs a modifier"
        )) {
            try NativeDictationTrigger.configuredShortcut(in: data)
        }
    }

    @Test func detoursOnlyWhenCodexIsFrontmost() {
        #expect(NativeDictationTrigger.requiresDesktopRoutingDetour(
            frontmostBundleIdentifier: "com.openai.codex"
        ))
        #expect(!NativeDictationTrigger.requiresDesktopRoutingDetour(
            frontmostBundleIdentifier: "com.apple.TextEdit"
        ))
        #expect(!NativeDictationTrigger.requiresDesktopRoutingDetour(
            frontmostBundleIdentifier: nil
        ))
    }

    @Test func keepsTheInvisibleFocusHandoffBrief() {
        #expect(NativeDictationTrigger.startRoutingRestoreDelay == .milliseconds(60))
        #expect(NativeDictationTrigger.stopRoutingRestoreDelay == .milliseconds(20))
    }

    @Test func activatesTheTargetOnlyWhenFocusActuallyChanged() {
        #expect(!NativeDictationTrigger.shouldActivateTargetApplication(
            targetProcessIdentifier: 42,
            frontmostProcessIdentifier: 42
        ))
        #expect(NativeDictationTrigger.shouldActivateTargetApplication(
            targetProcessIdentifier: 42,
            frontmostProcessIdentifier: 84
        ))
        #expect(!NativeDictationTrigger.shouldActivateTargetApplication(
            targetProcessIdentifier: nil,
            frontmostProcessIdentifier: 84
        ))
    }
}
