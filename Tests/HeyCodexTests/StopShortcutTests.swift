import Carbon
import Foundation
import Testing
@testable import HeyCodex

@Suite("Stop shortcut configuration")
struct StopShortcutTests {
    @Test func resolvesTheDefaultWhenNothingIsConfigured() throws {
        let shortcut = try StopShortcut.resolve(rawValue: nil)

        #expect(shortcut.keyCode == 2)
        #expect(shortcut.flags.contains(.maskControl))
        #expect(shortcut.flags.contains(.maskAlternate))
    }

    @Test func resolvesACustomShortcut() throws {
        let shortcut = try StopShortcut.resolve(rawValue: "Cmd+Shift+.")

        #expect(shortcut.keyCode == 47)
        #expect(shortcut.flags.contains(.maskCommand))
        #expect(shortcut.flags.contains(.maskShift))
    }

    @Test func rejectsBareModifierShortcuts() {
        #expect(throws: StopShortcutError.bareModifierUnsupported) {
            try StopShortcut.resolve(rawValue: "LeftOption")
        }
    }

    @Test func convertsEventFlagsToCarbonModifiers() {
        #expect(StopShortcut.carbonModifiers(from: [.maskControl, .maskAlternate])
            == UInt32(controlKey | optionKey))
        #expect(StopShortcut.carbonModifiers(from: [.maskShift, .maskCommand])
            == UInt32(shiftKey | cmdKey))
        #expect(StopShortcut.carbonModifiers(from: []) == 0)
    }

    @Test func detectsConflictWithTheCodexShortcut() throws {
        let stop = try CodexShortcut.parse("Ctrl+Option+D")
        let sameAsStop = try CodexShortcut.parse("Control+Alt+D")
        let different = try CodexShortcut.parse("Ctrl+Shift+D")

        #expect(StopShortcut.conflicts(stop, with: sameAsStop))
        #expect(!StopShortcut.conflicts(stop, with: different))
    }
}

@MainActor
@Suite("Stop shortcut in the voice controller")
struct VoiceControllerStopShortcutTests {
    @Test func refusesToDictateWhenStopShortcutEqualsCodexShortcut() async {
        let harness = VoiceControllerHarness.make { dependencies in
            // Codex toggle configured to the same keys as the stop shortcut.
            dependencies.configuredCodexShortcut = { try CodexShortcut.parse("Ctrl+Option+D") }
        }

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.listener.onWakePhrase?(.dictation)

        #expect(await waitUntil {
            if case .error = harness.controller.phase { return true }
            return false
        })
        #expect(harness.trigger.startCount == 0)
    }

    @Test func armsTheMonitorWithTheConfiguredStopShortcut() async {
        var received: CodexShortcut?
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.defaults.set("Cmd+Shift+.", forKey: StopShortcut.defaultsKey)
            let monitor = FakeHotKeyMonitor()
            dependencies.makeStopMonitor = { shortcut, _ in
                received = shortcut
                return monitor
            }
        }

        #expect(await harness.startDictating())
        #expect(received?.keyCode == 47)
    }
}
