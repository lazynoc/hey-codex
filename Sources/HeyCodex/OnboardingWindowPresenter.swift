import AppKit
import SwiftUI

/// Keeps the setup assistant reachable across macOS permission and app handoffs.
///
/// The window deliberately does not float above other apps while the user is
/// working in System Settings or Codex. Instead, it returns to the active Space
/// and becomes key once that external task is complete.
@MainActor
final class OnboardingWindowPresenter {
    private weak var window: NSWindow?
    private var didPresent = false
    private var permissionHandoffTask: Task<Void, Never>?

    func attach(_ window: NSWindow, isFirstRun: Bool) {
        self.window = window
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = !isFirstRun

        guard !didPresent else { return }
        didPresent = true
        window.center()
        present()
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// The microphone privacy callback can arrive while macOS is still
    /// dismissing its system prompt. Present once immediately, then retry after
    /// that handoff animation so the setup window reliably becomes key again.
    func presentAfterPermissionHandoff() {
        present()

        permissionHandoffTask?.cancel()
        permissionHandoffTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.present()
        }
    }
}

struct OnboardingWindowReader: NSViewRepresentable {
    let presenter: OnboardingWindowPresenter
    let isFirstRun: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            presenter.attach(window, isFirstRun: isFirstRun)
        }
    }
}
