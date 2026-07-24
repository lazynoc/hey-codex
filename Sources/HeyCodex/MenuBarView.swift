import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var controller: VoiceController
    let stats: DictationStatsModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(InterfaceSize.defaultsKey) private var interfaceSize = InterfaceSize.medium
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @State private var recentDictations: [DictationEntry] = []
    @State private var copiedEntryID: String?
    @State private var expandedEntryIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: interfaceSize.menuSpacing) {
            header

            Divider()

            actions

            statsSummary

            if !recentDictations.isEmpty {
                Divider()
                recentSection
            }

            Divider()

            footer
        }
        .controlSize(interfaceSize.controlSize)
        .preferredColorScheme(appTheme.colorScheme)
        .padding(interfaceSize.menuPadding)
        .frame(width: interfaceSize.menuWidth)
        .onAppear { refreshRecentDictations() }
        .onChange(of: controller.phase) {
            if controller.phase == .listening {
                refreshRecentDictations()
            }
        }
    }

    private var statsSummary: some View {
        LabeledContent {
            Text(stats.summary)
                .monospacedDigit()
        } label: {
            Text("Total words dictated")
                .foregroundStyle(.secondary)
        }
        .font(interfaceSize.secondaryFont)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
            .help("Total dictated words")
    }

    private var header: some View {
        HStack(spacing: 10) {
            VoiceStatusIcon(phase: controller.phase)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hey Codex")
                    .font(.headline)
                Text(statusDetail)
                    .font(interfaceSize.secondaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle(
                "Listen for “\(controller.wakePhrase.capitalized)”",
                isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.setEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var statusDetail: String {
        switch controller.phase {
        case .listening:
            controller.dictationWakeEnabled || controller.voiceChatWakeEnabled
                ? "Listening"
                : "Wake phrases off — click a card to start"
        case .triggering:
            if controller.pendingWakeAction == .voiceChat {
                controller.voiceChatIsOpen ? "Ending voice chat…" : "Starting voice chat…"
            } else {
                "Starting dictation…"
            }
        case .voiceChatActive:
            "Voice chat — say “\(controller.voiceChatPhrase.capitalized)” to end"
        case .dictating:
            "Dictating — press \(controller.stopShortcutDisplay) to stop"
        default:
            controller.phase.title
        }
    }

    @ViewBuilder
    private var actions: some View {
        primaryAction

        pauseRow

        if !NativeDictationTrigger.hasAccessibilityPermission {
            Button("Allow Accessibility Access") {
                controller.requestAccessibilityPermission()
            }
        }

        if case .error = controller.phase, controller.isEnabled {
            Button("Try Again") {
                controller.retry()
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch controller.phase {
        case .triggering:
            Button {
                controller.cancelPendingDictation()
            } label: {
                Text(controller.pendingWakeAction == .voiceChat
                    ? "Cancel Voice Chat Start"
                    : "Cancel Dictation Start")
                    .frame(maxWidth: .infinity)
            }
        case .dictating:
            Button {
                controller.stopNativeDictation()
            } label: {
                Text("Stop Dictation")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .voiceChatActive:
            Button {
                controller.startVoiceChat()
            } label: {
                Text("End Voice Chat")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        default:
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    WakeActionCard(
                        symbolName: "mic.fill",
                        title: "Dictation",
                        phrase: controller.wakePhrase,
                        wakeEnabled: controller.dictationWakeEnabled
                    ) {
                        controller.testNativeDictation()
                    }
                    .disabled(controller.phase == .finishing)

                    wakePhraseToggle(
                        phrase: controller.wakePhrase,
                        isOn: $controller.dictationWakeEnabled
                    )
                }

                VStack(spacing: 4) {
                    WakeActionCard(
                        symbolName: "bubble.left.and.bubble.right.fill",
                        title: "Voice Chat",
                        phrase: controller.voiceChatPhrase,
                        wakeEnabled: controller.voiceChatWakeEnabled
                    ) {
                        controller.startVoiceChat()
                    }
                    .disabled(controller.phase == .finishing)

                    wakePhraseToggle(
                        phrase: controller.voiceChatPhrase,
                        isOn: $controller.voiceChatWakeEnabled
                    )
                }
            }
        }
    }

    /// A compact switch that turns one wake phrase on or off without
    /// touching the master listening toggle or the other phrase.
    private func wakePhraseToggle(phrase: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 5) {
            Toggle(isOn: isOn) {
                Text("Wake phrase")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .help(
            isOn.wrappedValue
                ? "Stop waking on “\(phrase.capitalized)” — you can still start it from here"
                : "Wake on “\(phrase.capitalized)” again"
        )
    }

    @ViewBuilder
    private var pauseRow: some View {
        if controller.phase == .listening {
            Menu {
                Button("For 30 Minutes") {
                    controller.pauseListening(for: 30 * 60)
                }
                Button("For 1 Hour") {
                    controller.pauseListening(for: 60 * 60)
                }
            } label: {
                Label("Pause Listening", systemImage: "pause.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .font(interfaceSize.secondaryFont)
            .foregroundStyle(.secondary)
        } else if controller.phase == .paused {
            Button {
                controller.resumeListening()
            } label: {
                Label("Resume Listening", systemImage: "play.circle")
            }
            .buttonStyle(.borderless)
            .font(interfaceSize.secondaryFont)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Dictations")
                    .font(interfaceSize.secondaryFont)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("View All") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                }
                .buttonStyle(.borderless)
            }

            ForEach(recentDictations) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            if expandedEntryIDs.contains(entry.id) {
                                expandedEntryIDs.remove(entry.id)
                            } else {
                                expandedEntryIDs.insert(entry.id)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(
                                    systemName: expandedEntryIDs.contains(entry.id)
                                        ? "chevron.down"
                                        : "chevron.right"
                                )
                                .frame(width: 10)

                                Text(entry.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(
                            expandedEntryIDs.contains(entry.id)
                                ? "Collapse dictation"
                                : "Expand dictation"
                        )

                        Button {
                            copy(entry)
                        } label: {
                            Text(copiedEntryID == entry.id ? "Copied" : "Copy")
                        }
                        .buttonStyle(.bordered)
                        .help("Copy dictation")
                    }

                    if expandedEntryIDs.contains(entry.id) {
                        Text(entry.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                    }
                }
                .font(interfaceSize.secondaryFont)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",")

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func refreshRecentDictations() {
        recentDictations = TranscriptionHistory.recent(
            at: VoiceDependencies.dictationHistoryURL,
            limit: 3
        )
    }

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedEntryID = entry.id
    }

    private var statusColor: Color {
        switch controller.phase {
        case .triggering, .dictating, .finishing, .voiceChatActive:
            .blue
        case .listening:
            .green
        case .paused:
            .yellow
        case .error:
            .orange
        default:
            .secondary
        }
    }
}

/// One wake action shown as a card: what happens, and the phrase that
/// starts it. Clicking performs the action without the wake phrase.
private struct WakeActionCard: View {
    let symbolName: String
    let title: String
    let phrase: String
    let wakeEnabled: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbolName)
                    .font(.body)
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                    .frame(height: 18)

                Text(title)
                    .font(.callout.weight(.medium))

                Text("“\(phrase.capitalized)”")
                    .font(.caption)
                    .strikethrough(!wakeEnabled)
                    .foregroundStyle(wakeEnabled ? .secondary : .tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                .quaternary.opacity(isHovered && isEnabled ? 0.9 : 0.5),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(
            wakeEnabled
                ? "Start \(title.lowercased()) now — or say “\(phrase.capitalized)”"
                : "Start \(title.lowercased()) now — wake phrase is off"
        )
        .accessibilityLabel("Start \(title)")
        .accessibilityHint(
            wakeEnabled ? "Wake phrase: \(phrase)" : "Wake phrase off"
        )
    }
}
