import Foundation
import Testing
@testable import HeyCodex

@MainActor
@Suite("Voice controller state machine")
struct VoiceControllerTests {
    @Test func voiceChatWakePhraseTogglesChatAndResumesListening() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey codex", action: .dictation),
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])

        harness.listener.onWakePhrase?(.voiceChat)
        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 1 })
        #expect(harness.trigger.startCount == 0)

        // Listening resumes on its own so the same phrase can end the chat.
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.listener.isListening)

        harness.listener.onWakePhrase?(.voiceChat)
        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 2 })
        #expect(await waitUntil { harness.controller.phase == .listening })
    }

    @Test func wakePhraseTogglesApplyLiveWhileListening() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.dictationWakeEnabled = false
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
        #expect(harness.listener.isListening)

        harness.controller.voiceChatWakeEnabled = false
        #expect(harness.listener.bindings.isEmpty)
        #expect(harness.controller.phase == .listening)

        harness.controller.dictationWakeEnabled = true
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey codex", action: .dictation),
        ])
    }

    @Test func dictationWakeToggleIsPersisted() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.dictationWakeEnabled = false
        #expect(harness.defaults.bool(forKey: "dictationWakeEnabled") == false)
        #expect(harness.defaults.object(forKey: "dictationWakeEnabled") != nil)

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
    }

    @Test func refreshWakeBindingsAppliesEditedPhraseWhileListening() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.wakePhrase = "hey buddy"
        harness.controller.refreshWakeBindings()
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey buddy", action: .dictation),
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
    }

    @Test func onboardingVoiceChatCompletesOnOpenAndStaysOpenUntilHeardAgain() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.controller.beginOnboardingTest(.voiceChat)

        harness.listener.onWakePhrase?(.voiceChat)

        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 1 })
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.controller.onboardingVoiceChatIsOpen)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(harness.voiceChatTrigger.toggleCount == 1)
        #expect(harness.controller.completedOnboardingTest == .voiceChat)

        harness.listener.onWakePhrase?(.voiceChat)

        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 2 })
        #expect(await waitUntil {
            harness.controller.completedOnboardingTest == .voiceChat
        })
        #expect(!harness.controller.onboardingVoiceChatIsOpen)
        #expect(harness.controller.phase == .listening)
    }

    @Test func finishingOnboardingKeepsVoiceChatOpenAndRestoresBothPhrases() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.controller.beginOnboardingTest(.voiceChat)
        harness.listener.onWakePhrase?(.voiceChat)
        #expect(await waitUntil {
            harness.controller.completedOnboardingTest == .voiceChat
        })
        #expect(harness.controller.onboardingVoiceChatIsOpen)

        harness.controller.finishOnboardingTest()

        #expect(harness.voiceChatTrigger.toggleCount == 1)
        #expect(!harness.controller.onboardingVoiceChatIsOpen)
        #expect(harness.controller.completedOnboardingTest == nil)
        #expect(harness.controller.phase == .listening)
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey codex", action: .dictation),
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
    }

    @Test func onboardingDictationTestClosesItselfAndReportsSuccess() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.controller.beginOnboardingTest(.dictation)

        harness.listener.onWakePhrase?(.dictation)

        #expect(await waitUntil { harness.trigger.startCount == 1 })
        #expect(await waitUntil { harness.trigger.stopCount == 1 })
        #expect(await waitUntil {
            harness.controller.completedOnboardingTest == .dictation
        })
        #expect(harness.controller.phase == .listening)
        #expect(harness.store.snapshot == nil)
    }

    @Test func onboardingTestListensOnlyForThePhraseShownThenRestoresBoth() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.beginOnboardingTest(.voiceChat)
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])

        harness.controller.endOnboardingTest()
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey codex", action: .dictation),
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
    }

    @Test func endingOnboardingClosesVoiceChatAndRestoresBothPhrases() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.controller.beginOnboardingTest(.voiceChat)
        harness.listener.onWakePhrase?(.voiceChat)
        #expect(await waitUntil { harness.controller.onboardingVoiceChatIsOpen })
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.endOnboardingTest()

        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 2 })
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(!harness.controller.onboardingVoiceChatIsOpen)
        #expect(harness.controller.completedOnboardingTest == nil)
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey codex", action: .dictation),
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
    }

    @Test func disablingDuringOnboardingVoiceChatStillClosesTheDemo() async {
        let harness = VoiceControllerHarness.make()

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.controller.beginOnboardingTest(.voiceChat)
        harness.listener.onWakePhrase?(.voiceChat)
        #expect(await waitUntil { harness.controller.onboardingVoiceChatIsOpen })
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.setEnabled(false)

        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 2 })
        #expect(harness.controller.phase == .off)
    }

    @Test func cancellingOnboardingVoiceChatClosesItAndReturnsToTheTest() async {
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.timings.completionSettle = .seconds(30)
        }

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.controller.beginOnboardingTest(.voiceChat)
        harness.listener.onWakePhrase?(.voiceChat)
        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 1 })

        harness.controller.cancelPendingDictation()

        #expect(await waitUntil { harness.voiceChatTrigger.toggleCount == 2 })
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.controller.completedOnboardingTest == nil)
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
        ])
    }

    @Test func disabledVoiceChatWakeKeepsOnlyTheDictationBinding() async {
        let harness = VoiceControllerHarness.make()
        harness.controller.voiceChatWakeEnabled = false

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.listener.bindings == [
            WakePhraseBinding(phrase: "hey codex", action: .dictation),
        ])
    }

    @Test func voiceChatTriggerFailureSurfacesAnError() async {
        let harness = VoiceControllerHarness.make()
        harness.voiceChatTrigger.toggleError = CodexShortcutConfigurationError.missingRealtimeVoice

        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })
        harness.listener.onWakePhrase?(.voiceChat)

        #expect(await waitUntil {
            if case .error = harness.controller.phase { return true }
            return false
        })
    }

    @Test func disablingWhileDictatingStopsNativeDictationAndClearsSession() async {
        let harness = VoiceControllerHarness.make()
        #expect(await harness.startDictating())
        #expect(harness.store.snapshot != nil)

        harness.controller.setEnabled(false)

        #expect(await waitUntil { harness.trigger.stopCount == 1 })
        #expect(harness.store.snapshot == nil)
        #expect(harness.controller.phase == .off)
        #expect(!harness.monitor.isArmed)
    }

    @Test func historyChangeCompletesDictationAndResumesListening() async {
        let harness = VoiceControllerHarness.make()
        #expect(await harness.startDictating())

        harness.historySignature.value = "changed"
        harness.historyStream.tick()

        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.store.snapshot == nil)
        #expect(!harness.monitor.isArmed)
        #expect(harness.listener.isListening)
    }

    @Test func stopShortcutStopsDictationAndResumesListening() async {
        let harness = VoiceControllerHarness.make()
        #expect(await harness.startDictating())

        harness.controller.stopNativeDictation()

        #expect(await waitUntil { harness.trigger.stopCount == 1 })
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.store.snapshot == nil)
        #expect(!harness.monitor.isArmed)
    }

    @Test func invalidStoredStopShortcutFallsBackToTheDefault() async {
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.defaults.set("Left Option", forKey: StopShortcut.defaultsKey)
        }

        #expect(harness.controller.stopShortcutDisplay == "Control+Option+D")
        // Dictation must still work: the monitor arms with the default keys.
        #expect(await harness.startDictating())
        #expect(harness.monitor.isArmed)
    }

    @Test func pausingAutoResumesAfterTheDuration() async {
        let harness = VoiceControllerHarness.make()
        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.pauseListening(for: 0.05)

        #expect(harness.controller.phase == .paused)
        #expect(!harness.listener.isListening)
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.listener.isListening)
    }

    @Test func resumeEndsAPauseEarly() async {
        let harness = VoiceControllerHarness.make()
        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.pauseListening(for: 60)
        #expect(harness.controller.phase == .paused)

        harness.controller.resumeListening()
        #expect(await waitUntil { harness.controller.phase == .listening })
    }

    @Test func disablingWhilePausedCancelsThePendingResume() async {
        let harness = VoiceControllerHarness.make()
        harness.controller.setEnabled(true)
        #expect(await waitUntil { harness.controller.phase == .listening })

        harness.controller.pauseListening(for: 0.05)
        harness.controller.setEnabled(false)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(harness.controller.phase == .off)
        #expect(!harness.listener.isListening)
    }

    @Test func playsSoundCuesOnWakeAndCompletion() async {
        let played = PlayedSounds()
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.playSound = { played.cues.append($0) }
        }
        #expect(await harness.startDictating())
        #expect(played.cues == [.wakeHeard])

        harness.historySignature.value = "changed"
        harness.historyStream.tick()

        #expect(await waitUntil { played.cues == [.wakeHeard, .dictationStopped] })
    }

    @Test func staysSilentWhenSoundCuesAreDisabled() async {
        let played = PlayedSounds()
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.defaults.set(false, forKey: SoundCue.enabledKey)
            dependencies.playSound = { played.cues.append($0) }
        }
        #expect(await harness.startDictating())
        #expect(played.cues.isEmpty)
    }

    @Test func configuredSafetyTimeoutStopsARunawayDictation() async {
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.defaults.set(0.05, forKey: VoiceController.safetyTimeoutKey)
        }
        #expect(await harness.startDictating())

        // No stop action and no history change: the safety timeout must fire.
        #expect(await waitUntil { harness.trigger.stopCount == 1 })
        #expect(await waitUntil { harness.controller.phase == .listening })
        #expect(harness.store.snapshot == nil)
    }

    @Test func silenceStopIsOffByDefault() async {
        let harness = VoiceControllerHarness.make()
        #expect(await harness.startDictating())

        let feeder = feedLevels(0.0, into: harness.levelStream)
        try? await Task.sleep(for: .milliseconds(150))
        feeder.cancel()

        #expect(harness.trigger.stopCount == 0)
        #expect(harness.controller.phase == .dictating)
    }

    @Test func silenceStopsDictationAfterConfiguredSilence() async {
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.defaults.set(0.05, forKey: VoiceController.silenceStopKey)
        }
        #expect(await harness.startDictating())

        let feeder = feedLevels(0.0, into: harness.levelStream)
        #expect(await waitUntil { harness.trigger.stopCount == 1 })
        #expect(await waitUntil { harness.controller.phase == .listening })
        feeder.cancel()
        #expect(harness.store.snapshot == nil)
    }

    @Test func speechKeepsSilenceStopFromFiring() async {
        let harness = VoiceControllerHarness.make { dependencies in
            dependencies.defaults.set(0.05, forKey: VoiceController.silenceStopKey)
        }
        #expect(await harness.startDictating())

        let feeder = feedLevels(0.5, into: harness.levelStream)
        try? await Task.sleep(for: .milliseconds(150))
        feeder.cancel()

        #expect(harness.trigger.stopCount == 0)
        #expect(harness.controller.phase == .dictating)
    }

    private func feedLevels(
        _ level: Float, into stream: LevelStreamBox
    ) -> Task<Void, Never> {
        Task.detached {
            while !Task.isCancelled {
                stream.yield(level)
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    @Test func recoversPersistedSessionOnLaunchWhenHistoryUnchanged() async {
        let harness = VoiceControllerHarness.make { dependencies in
            let store = InMemorySessionStore()
            store.snapshot = NativeSessionSnapshot(
                historyBaseline: "baseline",
                startedAt: Date().timeIntervalSince1970 - 60,
                nativeShortcutRawValue: "Ctrl+Shift+D"
            )
            dependencies.sessionStore = store
        }

        harness.controller.setEnabled(true)

        #expect(await waitUntil { harness.controller.phase == .dictating })
        #expect(harness.monitor.isArmed)
    }
}
