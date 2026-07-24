import AppKit
import CoreServices
import Foundation

enum AutomationPermission {
    private static let systemEventsBundleIdentifier = "com.apple.systemevents"

    @MainActor
    static func status(promptIfNeeded: Bool = false) async -> SetupPermissionState {
        await ensureSystemEventsIsRunning()
        return await Task.detached(priority: .userInitiated) {
            determineStatus(promptIfNeeded: promptIfNeeded)
        }.value
    }

    @MainActor
    private static func ensureSystemEventsIsRunning() async {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: systemEventsBundleIdentifier
        ).isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: systemEventsBundleIdentifier
        ) else { return }

        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration
            ) { _, _ in
                continuation.resume()
            }
        }
    }

    private nonisolated static func determineStatus(
        promptIfNeeded: Bool
    ) -> SetupPermissionState {
        var target = AEAddressDesc()
        let identifier = Data(systemEventsBundleIdentifier.utf8)
        let descriptorStatus = identifier.withUnsafeBytes { bytes in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                bytes.baseAddress,
                identifier.count,
                &target
            )
        }

        guard descriptorStatus == noErr else { return .unavailable }
        defer { AEDisposeDesc(&target) }

        let permissionStatus = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            promptIfNeeded
        )

        switch permissionStatus {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .needsPermission
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable
        }
    }
}
