import AppKit
import ApplicationServices

@MainActor
enum CodexVoiceSettingsOpener {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let settingsURL = URL(string: "codex://settings")

    // Codex currently whitelists only a few settings deep links. Voice is the
    // fourth sidebar item after General, and focus enters the sidebar after
    // Back to app and Search.
    private static let tabsFromSettingsRootToVoice = 6

    static func open() {
        let wasRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: codexBundleIdentifier
        ).isEmpty

        guard let settingsURL, NSWorkspace.shared.open(settingsURL) else {
            activateCodex()
            return
        }

        Task { @MainActor in
            await selectVoiceSection(wasRunning: wasRunning)
        }
    }

    private static func selectVoiceSection(wasRunning: Bool) async {
        for _ in 0..<30 {
            if codexIsFrontmost {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard codexIsFrontmost else { return }

        let settleTime: Duration = wasRunning ? .milliseconds(800) : .milliseconds(1_500)
        try? await Task.sleep(for: settleTime)
        guard codexIsFrontmost else { return }

        for _ in 0..<tabsFromSettingsRootToVoice {
            guard codexIsFrontmost, postKey(48) else { return }
            try? await Task.sleep(for: .milliseconds(70))
        }

        guard codexIsFrontmost else { return }
        _ = postKey(36)
    }

    private static var codexIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == codexBundleIdentifier
    }

    private static func postKey(_ keyCode: CGKeyCode) -> Bool {
        guard
            let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: keyCode,
                keyDown: false
            )
        else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func activateCodex() {
        if let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: codexBundleIdentifier
        ).first {
            running.activate(options: .activateAllWindows)
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: codexBundleIdentifier
        ) else { return }

        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
