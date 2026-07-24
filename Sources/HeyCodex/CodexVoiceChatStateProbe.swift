import AppKit
import ApplicationServices

/// Reads only Codex's top-level Accessibility windows. Voice Chat adds one
/// dialogue to the app, so comparing this count with the pre-launch baseline
/// lets Hey Codex notice when a user closes Voice Chat directly in Codex.
enum CodexVoiceChatStateProbe {
    @MainActor
    static func dialogCount() -> Int? {
        guard AXIsProcessTrusted() else { return nil }

        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: NativeDictationTrigger.codexBundleIdentifier
        ).first else {
            return 0
        }

        let application = AXUIElementCreateApplication(codex.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let windows = value as? [AXUIElement]
        else {
            return nil
        }

        return windows.reduce(into: 0) { count, window in
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXSubroleAttribute as CFString,
                &subroleValue
            ) == .success,
            let subrole = subroleValue as? String,
            subrole == kAXDialogSubrole as String
            else {
                return
            }

            count += 1
        }
    }
}
