import SwiftUI

@main
struct HeyCodexApp: App {
    @State private var controller = VoiceController()
    @State private var stats = DictationStatsModel()
    @State private var onboarding = OnboardingModel()

    var body: some Scene {
        firstRunWindow

        MenuBarExtra {
            MenuBarView(controller: controller, stats: stats)
        } label: {
            Label {
                Text("Hey Codex")
            } icon: {
                VoiceStatusIcon(phase: controller.phase)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: controller)
        }

        Window("Dictation History", id: "history") {
            HistoryWindowView(stats: stats)
        }
        .defaultSize(width: 560, height: 480)

        Window("Hey Codex Setup", id: "setup") {
            OnboardingView(
                controller: controller,
                model: onboarding,
                windowID: "setup",
                isFirstRun: false
            )
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentSize)
    }

    private var firstRunWindow: some Scene {
        WindowGroup("Welcome to Hey Codex", id: "first-run") {
            FirstRunOnboardingView(
                controller: controller,
                model: onboarding
            )
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentSize)
    }
}
