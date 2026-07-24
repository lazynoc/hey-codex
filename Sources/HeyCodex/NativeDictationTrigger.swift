import AppKit
import ApplicationServices
import Foundation

@MainActor
final class NativeDictationTrigger: DictationTriggering {
    nonisolated static let codexBundleIdentifier = "com.openai.codex"
    nonisolated static let startRoutingRestoreDelay: Duration = .milliseconds(60)
    nonisolated static let stopRoutingRestoreDelay: Duration = .milliseconds(20)

    enum TriggerError: LocalizedError {
        case accessibilityPermissionMissing
        case codexNotRunning
        case invisibleFocusFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                "Allow Accessibility access, then try again"
            case .codexNotRunning:
                "Open the Codex desktop app first"
            case .invisibleFocusFailed:
                "Could not prepare Codex dictation without changing windows"
            }
        }
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    nonisolated static func configuredShortcut() throws -> CodexShortcut {
        try configuredShortcut(at: keybindingsURL)
    }

    nonisolated static func configuredShortcut(at url: URL) throws -> CodexShortcut {
        guard let data = try? Data(contentsOf: url) else {
            throw CodexShortcutConfigurationError.missingFile
        }
        return try configuredShortcut(in: data)
    }

    nonisolated static func configuredShortcut(in data: Data) throws -> CodexShortcut {
        try CodexKeybindings.globalDictationToggle(in: data)
    }

    nonisolated static func configuredRealtimeVoiceShortcut() throws -> CodexShortcut {
        try configuredRealtimeVoiceShortcut(at: keybindingsURL)
    }

    nonisolated static func configuredRealtimeVoiceShortcut(at url: URL) throws -> CodexShortcut {
        guard let data = try? Data(contentsOf: url) else {
            throw CodexShortcutConfigurationError.missingFile
        }
        return try CodexKeybindings.realtimeVoice(in: data)
    }

    static func toggleRealtimeVoice() async throws {
        try validateReady()
        try await configuredRealtimeVoiceShortcut().send()
    }

    nonisolated static var keybindingsSignature: String? {
        FileSignature.signature(atPath: keybindingsURL.path)
    }

    static func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private var target: DictationTarget?
    private var activeShortcut: CodexShortcut?
    private let focusRouter = InvisibleFocusRouter()

    var activeShortcutRawValue: String? {
        activeShortcut?.rawValue
    }

    func start() async throws {
        try Self.validateReady()
        let shortcut = try Self.configuredShortcut()
        activeShortcut = shortcut

        captureCurrentTarget()
        let frontmostApplication = target?.application

        if Self.requiresDesktopRoutingDetour(
            frontmostBundleIdentifier: frontmostApplication?.bundleIdentifier
        ) {
            try await sendThroughInvisibleDesktopRoute(
                shortcut,
                restoreDelay: Self.startRoutingRestoreDelay
            )
        } else {
            try await shortcut.send()
        }
    }

    func captureCurrentTarget() {
        let application = NSWorkspace.shared.frontmostApplication
        target = DictationTarget(
            application: application,
            window: Self.focusedWindow(
                processIdentifier: application?.processIdentifier
            ),
            focusedElement: Self.focusedElement()
        )
    }

    func restoreActiveShortcut(rawValue: String?) {
        guard let rawValue else {
            activeShortcut = nil
            return
        }
        activeShortcut = try? CodexShortcut.parse(rawValue)
    }

    func stop() async throws {
        try Self.validateReady()
        let shortcut: CodexShortcut
        if let activeShortcut {
            shortcut = activeShortcut
        } else {
            shortcut = try Self.configuredShortcut()
        }

        let targetBundleIdentifier = target?.application?.bundleIdentifier
        let currentBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let needsDetour = Self.requiresDesktopRoutingDetour(
            frontmostBundleIdentifier: targetBundleIdentifier
        ) || Self.requiresDesktopRoutingDetour(
            frontmostBundleIdentifier: currentBundleIdentifier
        )

        if needsDetour {
            try await sendThroughInvisibleDesktopRoute(
                shortcut,
                restoreDelay: Self.stopRoutingRestoreDelay
            )
        } else {
            try await shortcut.send()
            restoreTarget()
        }
    }

    private static func validateReady() throws {
        guard Self.hasAccessibilityPermission else {
            Self.requestAccessibilityPermission()
            throw TriggerError.accessibilityPermissionMissing
        }

        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first != nil else {
            throw TriggerError.codexNotRunning
        }

    }

    private func sendThroughInvisibleDesktopRoute(
        _ shortcut: CodexShortcut,
        restoreDelay: Duration
    ) async throws {
        guard await focusRouter.takeFocus() else {
            restoreTarget()
            throw TriggerError.invisibleFocusFailed
        }

        do {
            try await shortcut.send()
            try? await Task.sleep(for: restoreDelay)
        } catch {
            focusRouter.releaseFocus()
            restoreTarget()
            throw error
        }

        focusRouter.releaseFocus()
        restoreTarget()
    }

    private func restoreTarget() {
        guard let target else { return }
        Self.applyFocus(target, allowAutomationFallback: false)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            Self.applyFocus(target, allowAutomationFallback: true)
        }
    }

    private nonisolated static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value
        else { return nil }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private nonisolated static func focusedWindow(
        processIdentifier: pid_t?
    ) -> AXUIElement? {
        guard let processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success,
        let value
        else { return nil }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func applyFocus(
        _ target: DictationTarget,
        allowAutomationFallback: Bool
    ) {
        let targetProcessIdentifier = target.application?.processIdentifier
        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        let needsApplicationActivation = shouldActivateTargetApplication(
            targetProcessIdentifier: targetProcessIdentifier,
            frontmostProcessIdentifier: frontmostProcessIdentifier
        )

        if needsApplicationActivation {
            if allowAutomationFallback,
               let bundleIdentifier = target.application?.bundleIdentifier {
                let source = """
                tell application "System Events"
                    set frontmost of first application process whose bundle identifier is "\(bundleIdentifier)" to true
                end tell
                """
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
            } else {
                _ = target.application?.activate(options: [])
            }
        }

        let currentWindow = focusedWindow(processIdentifier: targetProcessIdentifier)
        if let window = target.window, !sameElement(window, currentWindow) {
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        let currentElement = focusedElement()
        if let focusedElement = target.focusedElement,
           !sameElement(focusedElement, currentElement) {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }
    }

    nonisolated static func shouldActivateTargetApplication(
        targetProcessIdentifier: pid_t?,
        frontmostProcessIdentifier: pid_t?
    ) -> Bool {
        guard let targetProcessIdentifier else { return false }
        return targetProcessIdentifier != frontmostProcessIdentifier
    }

    private nonisolated static func sameElement(
        _ lhs: AXUIElement,
        _ rhs: AXUIElement?
    ) -> Bool {
        guard let rhs else { return false }
        return CFEqual(lhs, rhs)
    }

    nonisolated static func requiresDesktopRoutingDetour(
        frontmostBundleIdentifier: String?
    ) -> Bool {
        frontmostBundleIdentifier == codexBundleIdentifier
    }

    nonisolated static var keybindingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/keybindings.json")
    }
}

private struct DictationTarget {
    let application: NSRunningApplication?
    let window: AXUIElement?
    let focusedElement: AXUIElement?
}
