import AppKit

/// Briefly makes Hey Codex frontmost without showing a window.
///
/// Codex routes its global dictation shortcut to the composer while Codex is
/// frontmost. This invisible key window gives the shortcut a neutral desktop
/// route without flashing Finder or another user-facing application.
@MainActor
final class InvisibleFocusRouter {
    private let window: NSWindow

    init() {
        let window = InvisibleKeyWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        window.isExcludedFromWindowsMenu = true
        window.sharingType = .none
        self.window = window
    }

    func takeFocus() async -> Bool {
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()

        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
            {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        releaseFocus()
        return false
    }

    func releaseFocus() {
        window.resignKey()
        window.orderOut(nil)
    }
}

private final class InvisibleKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
