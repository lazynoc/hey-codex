import AppKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case permissions
    case shortcut
    case tryDictation
    case tryVoiceChat

    var number: Int { rawValue + 1 }

    var testAction: WakeAction? {
        switch self {
        case .tryVoiceChat:
            .voiceChat
        case .tryDictation:
            .dictation
        case .permissions, .shortcut:
            nil
        }
    }
}

private struct OnboardingTestContent {
    let action: WakeAction
    let phrase: String
    let featureName: String
    let successTitle: String
    let readyDetail: String
    let busyDetail: String

    init(action: WakeAction, voiceChatPhrase: String, dictationPhrase: String) {
        self.action = action
        switch action {
        case .voiceChat:
            phrase = voiceChatPhrase.capitalized
            featureName = "Voice Chat"
            successTitle = "Nice — Voice Chat works"
            readyDetail = "Voice Chat stays open so you can try it. Say the phrase again when you’re done."
            busyDetail = "Codex Voice is responding…"
        case .dictation:
            phrase = dictationPhrase.capitalized
            featureName = "Dictation"
            successTitle = "Nice — Dictation works"
            readyDetail = "This quick test starts dictation briefly, then stops automatically."
            busyDetail = "Starting and stopping dictation…"
        }
    }
}

struct FirstRunOnboardingView: View {
    @Bindable var controller: VoiceController
    @Bindable var model: OnboardingModel

    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                Color.clear
                    .frame(width: 1, height: 1)
                    .task {
                        dismissWindow(id: "first-run")
                    }
            } else {
                OnboardingView(
                    controller: controller,
                    model: model,
                    windowID: "first-run",
                    isFirstRun: true
                )
            }
        }
    }
}

struct OnboardingView: View {
    @Bindable var controller: VoiceController
    @Bindable var model: OnboardingModel
    let windowID: String
    let isFirstRun: Bool

    @AppStorage(OnboardingModel.completedKey) private var hasCompletedOnboarding = false
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var step = OnboardingStep.permissions
    @State private var pendingPermission: SetupPermissionKind?
    @State private var isWaitingForCodexShortcut = false
    @State private var windowPresenter = OnboardingWindowPresenter()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch step {
                case .permissions:
                    permissionsStep
                case .shortcut:
                    shortcutStep
                case .tryVoiceChat:
                    wakePhraseTestStep(action: .voiceChat)
                case .tryDictation:
                    wakePhraseTestStep(action: .dictation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.vertical, 22)

            Divider()

            footer
        }
        .frame(width: 620, height: 520)
        .preferredColorScheme(appTheme.colorScheme)
        .background {
            OnboardingWindowReader(
                presenter: windowPresenter,
                isFirstRun: isFirstRun
            )
            .frame(width: 0, height: 0)
        }
        .task {
            await refreshWhileVisible()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            Task { await model.refresh() }
        }
        .onChange(of: model.permissions) {
            restoreAfterPermissionHandoffIfReady()
        }
        .onChange(of: model.isShortcutConfigured) {
            guard isWaitingForCodexShortcut, model.isShortcutConfigured else { return }
            isWaitingForCodexShortcut = false
            windowPresenter.present()
        }
        .onChange(of: controller.completedOnboardingTest) {
            guard controller.completedOnboardingTest == step.testAction else { return }
            windowPresenter.present()
        }
        .onDisappear {
            controller.endOnboardingTest()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Hey Codex", systemImage: "ear")
                    .font(.headline)

                Spacer()

                Text("Step \(step.number) of \(OnboardingStep.allCases.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(step.number),
                total: Double(OnboardingStep.allCases.count)
            )
            .accessibilityLabel("Setup progress")
            .accessibilityValue(
                "Step \(step.number) of \(OnboardingStep.allCases.count)"
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private var permissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stepHeading(
                    title: "Allow Hey Codex",
                    detail: "Permissions let Hey Codex hear the wake phrase and pass dictation to Codex. Nothing leaves your Mac."
                )

                VStack(spacing: 0) {
                    ForEach(Array(model.permissions.enumerated()), id: \.element.id) {
                        index, permission in
                        PermissionRow(permission: permission) {
                            requestPermission(permission)
                        }

                        if index < model.permissions.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(
                    .quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 12)
                )

                if !model.allPermissionsGranted {
                    Label(
                        "Previously denied access? Open System Settings. This page updates automatically.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepHeading(
                title: "Connect Codex",
                detail: "Hey Codex follows the global dictation shortcut you choose in Codex."
            )

            VStack(alignment: .leading, spacing: 16) {
                if let shortcutDisplay = model.shortcutDisplay {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(shortcutDisplay) detected")
                                .font(.headline)
                            Text("Your shortcut is ready.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    }
                } else {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Shortcut not configured")
                                .font(.headline)
                            Text(model.shortcutError ?? "Set a global dictation shortcut in Codex.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                    }
                }

                Divider()

                if let voiceChatDisplay = model.voiceChatShortcutDisplay {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Voice chat: \(voiceChatDisplay)")
                                .font(.headline)
                            Text("“Hey Jarvis” will toggle Codex voice chat.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    }

                    Divider()
                }

                if model.isShortcutConfigured {
                    Text("Hey Codex will use this shortcut automatically. You can change it anytime in Codex Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Codex will open directly to Voice. Set Toggle dictation hotkey, then return here.")
                        .font(.callout)

                    HStack {
                        Button("Open Codex Voice Settings") {
                            isWaitingForCodexShortcut = true
                            model.openCodex()
                        }

                        Button("Check Again") {
                            Task {
                                await model.refresh()
                                windowPresenter.present()
                            }
                        }
                    }
                }
            }
            .padding(18)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
    }

    private func wakePhraseTestStep(action: WakeAction) -> some View {
        let content = OnboardingTestContent(
            action: action,
            voiceChatPhrase: controller.voiceChatPhrase,
            dictationPhrase: controller.wakePhrase
        )
        let isComplete = controller.completedOnboardingTest == action
        let isBusy = controller.pendingWakeAction == action
            && (controller.phase == .triggering
                || controller.phase == .dictating
                || controller.phase == .finishing)

        return VStack(spacing: 22) {
            Spacer()

            Image(systemName: testSymbol(action: action, isComplete: isComplete))
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(testColor(isComplete: isComplete))
                .symbolEffect(
                    .pulse,
                    isActive: controller.phase == .listening && !isComplete
                )
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(testTitle(
                    content: content,
                    isComplete: isComplete,
                    isBusy: isBusy
                ))
                    .font(.title.bold())

                Text(testDetail(content: content, isComplete: isComplete, isBusy: isBusy))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if action == .voiceChat && controller.onboardingVoiceChatIsOpen {
                Button("Close Voice Chat") {
                    controller.closeOnboardingVoiceChatTest()
                }
            }

            if case let .error(message) = controller.phase {
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Try Again") {
                        controller.beginOnboardingTest(action)
                    }
                }
            } else if controller.phase == .paused {
                Button("Resume Listening") {
                    controller.resumeListening()
                    controller.beginOnboardingTest(action)
                }
            } else if controller.phase == .off {
                Button("Start Listening") {
                    controller.beginOnboardingTest(action)
                    controller.setEnabled(true)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func testSymbol(action: WakeAction, isComplete: Bool) -> String {
        if isComplete {
            return "checkmark.circle.fill"
        }
        if case .error = controller.phase {
            return "exclamationmark.circle.fill"
        }
        if controller.phase == .triggering
            || controller.phase == .dictating
            || controller.phase == .finishing {
            return controller.phase.symbolName
        }
        if action == .voiceChat && controller.onboardingVoiceChatIsOpen {
            return "bubble.left.and.bubble.right.fill"
        }
        return controller.phase.symbolName
    }

    private func testColor(isComplete: Bool) -> Color {
        if isComplete {
            return .green
        }
        if case .error = controller.phase {
            return .orange
        }
        return controller.phase == .listening ? .green : .secondary
    }

    private func testTitle(
        content: OnboardingTestContent,
        isComplete: Bool,
        isBusy: Bool
    ) -> String {
        if content.action == .voiceChat && controller.onboardingVoiceChatIsOpen {
            return "Voice Chat is open"
        }

        if isComplete {
            return content.successTitle
        }

        if isBusy {
            return "Testing \(content.featureName)…"
        }

        switch controller.phase {
        case .listening:
            return "Say “\(content.phrase)”"
        case .requestingPermission:
            return "Checking permissions"
        case .paused:
            return "Listening is paused"
        case .off:
            return "Start listening"
        case .triggering, .dictating, .finishing:
            return "Testing \(content.featureName)…"
        case .error:
            return "Setup needs attention"
        }
    }

    private func testDetail(
        content: OnboardingTestContent,
        isComplete: Bool,
        isBusy: Bool
    ) -> String {
        if content.action == .voiceChat && controller.onboardingVoiceChatIsOpen {
            return "Finish setup to keep talking, or say “\(content.phrase)” again to close Voice Chat."
        }

        if isComplete {
            return content.action == .voiceChat
                ? "Voice Chat is closed. You’re ready."
                : "The quick test stopped automatically."
        }
        if isBusy {
            return content.busyDetail
        }

        switch controller.phase {
        case .requestingPermission:
            return "This should take only a moment."
        case .paused:
            return "Resume listening, then say the phrase."
        case .off:
            return "Turn on the wake listener, then say the phrase."
        case .error:
            return "Resolve the issue below or skip this test."
        default:
            return content.readyDetail
        }
    }

    private var footer: some View {
        HStack {
            if step != .permissions {
                Button("Back") {
                    moveBack()
                }
                .disabled(isTestBusy)
            }

            Spacer()

            if step.testAction != nil {
                Button("Skip Test") {
                    skipCurrentTest()
                }
                .buttonStyle(.borderless)
                .disabled(isTestBusy)

                Button(testPrimaryActionTitle) {
                    if step == .tryVoiceChat {
                        finish()
                    } else {
                        moveForward()
                    }
                }
                .disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") {
                    moveForward()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    private func stepHeading(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.title.bold())
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var testPrimaryActionTitle: String {
        step == .tryVoiceChat
            ? (isFirstRun ? "Finish Setup" : "Done")
            : "Continue"
    }

    private var isTestBusy: Bool {
        guard step.testAction != nil else { return false }
        if step == .tryVoiceChat && controller.onboardingVoiceChatIsOpen {
            return true
        }
        return switch controller.phase {
        case .triggering, .dictating, .finishing:
            true
        default:
            false
        }
    }

    private var canContinue: Bool {
        switch step {
        case .permissions:
            model.allPermissionsGranted
        case .shortcut:
            model.isShortcutConfigured
        case .tryVoiceChat:
            controller.completedOnboardingTest == .voiceChat
        case .tryDictation:
            controller.completedOnboardingTest == .dictation
        }
    }

    private func moveForward() {
        switch step {
        case .permissions:
            step = .shortcut
        case .shortcut:
            showTestStep(.tryDictation, action: .dictation)
        case .tryDictation:
            showTestStep(.tryVoiceChat, action: .voiceChat)
        case .tryVoiceChat:
            finish()
        }
    }

    private func moveBack() {
        switch step {
        case .permissions:
            break
        case .shortcut:
            step = .permissions
        case .tryDictation:
            controller.endOnboardingTest()
            step = .shortcut
        case .tryVoiceChat:
            showTestStep(.tryDictation, action: .dictation)
        }
    }

    private func showTestStep(_ destination: OnboardingStep, action: WakeAction) {
        step = destination

        if controller.phase == .paused {
            controller.resumeListening()
        }

        controller.beginOnboardingTest(action)
        if !controller.isEnabled {
            controller.setEnabled(true)
        }
    }

    private func skipCurrentTest() {
        switch step {
        case .tryDictation:
            showTestStep(.tryVoiceChat, action: .voiceChat)
        case .tryVoiceChat:
            finish()
        case .permissions, .shortcut:
            break
        }
    }

    private func requestPermission(_ permission: SetupPermissionItem) {
        pendingPermission = permission.kind
        Task {
            await model.request(permission.kind)
        }
    }

    private func restoreAfterPermissionHandoffIfReady() {
        guard let pendingPermission else { return }
        switch model.permissionState(for: pendingPermission) {
        case .granted, .denied, .unavailable:
            self.pendingPermission = nil
            windowPresenter.presentAfterPermissionHandoff()
        case .checking, .needsPermission:
            break
        }
    }

    private func finish() {
        controller.finishOnboardingTest()
        hasCompletedOnboarding = true
        dismissWindow(id: windowID)
    }

    private func refreshWhileVisible() async {
        await model.refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
    }
}

private struct PermissionRow: View {
    let permission: SetupPermissionItem
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.kind.title)
                    .font(.body.weight(.medium))
                Text(permission.kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if permission.state == .granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .frame(width: 178, alignment: .trailing)
            } else if permission.state == .checking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking \(permission.kind.title)")
                    .frame(width: 178, alignment: .trailing)
            } else {
                HStack(spacing: 8) {
                    Text(permission.state.statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .frame(width: 72, alignment: .trailing)

                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .frame(width: 98)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var actionTitle: String {
        switch permission.state {
        case .denied:
            "Open Settings"
        case .unavailable:
            "Try Again"
        default:
            "Allow"
        }
    }

    private var statusColor: Color {
        switch permission.state {
        case .denied, .unavailable:
            .orange
        default:
            .secondary
        }
    }
}
