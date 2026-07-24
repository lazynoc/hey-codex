import SwiftUI

struct SettingsView: View {
    @Bindable var controller: VoiceController
    @AppStorage(InterfaceSize.defaultsKey) private var interfaceSize = InterfaceSize.medium
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }

            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "mic") }

            UpdatesSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .controlSize(interfaceSize.controlSize)
        .preferredColorScheme(appTheme.colorScheme)
        .frame(width: 440, height: 470)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var controller: VoiceController
    @Environment(\.openWindow) private var openWindow
    @AppStorage(InterfaceSize.defaultsKey) private var interfaceSize = InterfaceSize.medium
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @FocusState private var focusedPhraseField: PhraseField?

    private enum PhraseField {
        case dictation
        case voiceChat
    }

    var body: some View {
        Form {
            Section {
                Toggle("Listen for wake phrases", isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.setEnabled($0) }
                ))
            } footer: {
                Text(
                    controller.isEnabled
                        ? "Hey Codex is listening. Changes below apply right away."
                        : "Listening is off — nothing wakes until you turn this on."
                )
            }

            Section {
                Toggle("Dictation wake phrase", isOn: $controller.dictationWakeEnabled)

                if controller.dictationWakeEnabled {
                    TextField("Dictation phrase", text: $controller.wakePhrase)
                        .focused($focusedPhraseField, equals: .dictation)
                        .onSubmit { controller.refreshWakeBindings() }
                }

                Toggle("Voice chat wake phrase", isOn: $controller.voiceChatWakeEnabled)

                if controller.voiceChatWakeEnabled {
                    TextField("Voice chat phrase", text: $controller.voiceChatPhrase)
                        .focused($focusedPhraseField, equals: .voiceChat)
                        .onSubmit { controller.refreshWakeBindings() }

                    LabeledContent(
                        "Codex voice chat hotkey",
                        value: controller.realtimeVoiceShortcutDisplay
                    )
                }

                Picker("Wake sensitivity", selection: $controller.wakeSensitivity) {
                    ForEach(WakeSensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.displayName).tag(sensitivity)
                    }
                }
            } header: {
                Text("Wake phrases")
            } footer: {
                Text(wakePhrasesFooter)
            }
            .onChange(of: focusedPhraseField) {
                // Apply phrase edits once the field loses focus.
                if focusedPhraseField == nil {
                    controller.refreshWakeBindings()
                }
            }

            Section {
                LabeledContent("Codex dictation shortcut", value: controller.nativeShortcutDisplay)

                Picker("Auto-stop dictation after", selection: Binding(
                    get: {
                        // Clamp older stored values (2/5 min) to the new minimum.
                        let minutes = Int(controller.safetyTimeout / 60)
                        return [10, 20, 30].contains(minutes) ? minutes : 10
                    },
                    set: { controller.setSafetyTimeout(TimeInterval($0 * 60)) }
                )) {
                    Text("10 minutes").tag(10)
                    Text("20 minutes").tag(20)
                    Text("30 minutes").tag(30)
                }

                Picker("Stop after silence", selection: Binding(
                    get: {
                        let seconds = Int(controller.silenceStopDuration)
                        return [10, 20, 30].contains(seconds) ? seconds : 0
                    },
                    set: { controller.setSilenceStop(TimeInterval($0)) }
                )) {
                    Text("Off").tag(0)
                    Text("10 seconds").tag(10)
                    Text("20 seconds").tag(20)
                    Text("30 seconds").tag(30)
                }
            } header: {
                Text("Dictation")
            } footer: {
                Text("To change the dictation hotkey, use Codex settings — Hey Codex follows it automatically. Stop after silence ends dictation hands-free once you stop talking.")
            }

            Section {
                Toggle("Start at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchAtLogin = newValue
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                    }
                ))

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.menu)

                Picker("Interface size", selection: $interfaceSize) {
                    ForEach(InterfaceSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System theme and Medium size are recommended.")
            }

            Section {
                Button("Run Setup Guide Again…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "setup")
                }
            } header: {
                Text("Help")
            } footer: {
                Text("Review permissions and the Codex dictation shortcut.")
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var wakePhrasesFooter: String {
        var parts: [String] = []
        if controller.dictationWakeEnabled {
            parts.append(
                "“\(controller.wakePhrase.capitalized)” starts dictation at your cursor."
            )
        }
        if controller.voiceChatWakeEnabled {
            parts.append(
                "“\(controller.voiceChatPhrase.capitalized)” toggles Codex voice chat — "
                    + "say it again to end the chat."
            )
        }
        if parts.isEmpty {
            parts.append(
                "Both wake phrases are off — start dictation or voice chat from the menu bar."
            )
        }
        return parts.joined(separator: " ")
    }
}

private struct AudioSettingsView: View {
    @AppStorage(SoundCue.enabledKey) private var soundCuesEnabled = true
    @AppStorage(SoundCueVolume.defaultsKey) private var soundCueVolume = SoundCueVolume.system
    @AppStorage(AudioInputDevices.defaultsKey) private var microphoneUID = ""
    @State private var inputDevices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section {
                Picker("Microphone", selection: $microphoneUID) {
                    Text("System Default").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            } footer: {
                Text("Applies the next time wake listening starts.")
            }

            Section {
                Toggle("Sound cues", isOn: $soundCuesEnabled)

                Picker("Cue volume", selection: $soundCueVolume) {
                    ForEach(SoundCueVolume.allCases) { volume in
                        Text(volume.title).tag(volume)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!soundCuesEnabled)
            } footer: {
                Text(
                    "A pop when the wake phrase is heard and a chime when dictation stops. "
                        + "Volume is relative to your Mac and never changes system settings."
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { inputDevices = AudioInputDevices.all() }
        .onChange(of: soundCueVolume) {
            guard soundCuesEnabled else { return }
            SoundCuePlayer.play(.dictationStopped, volume: soundCueVolume)
        }
    }
}

private struct UpdatesSettingsView: View {
    @State private var updateModel = UpdateModel()

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: updateModel.currentVersion)

                LabeledContent("Latest release") {
                    switch updateModel.status {
                    case .unknown:
                        Text("—")
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                    case .upToDate:
                        Text("Up to date")
                    case let .available(tag):
                        Link(
                            "\(tag) available",
                            destination: URL(
                                string: "https://github.com/lazynoc/hey-codex/releases/tag/\(tag)"
                            )!
                        )
                    case .failed:
                        Text("Could not reach GitHub")
                            .foregroundStyle(.orange)
                    }
                }

                Button("Check for Updates") {
                    Task { await updateModel.check() }
                }
                .disabled(updateModel.status == .checking)
            }
        }
        .formStyle(.grouped)
    }
}
