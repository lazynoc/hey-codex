import Testing
@testable import HeyCodex

@Suite("Wake sensitivity")
struct WakeSensitivityTests {
    @Test func strictOnlyAcceptsTheExactPhrase() {
        #expect(PhraseParser.containsWakePhrase(
            "hey codex", wakePhrase: "hey codex", sensitivity: .strict
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "hey codec", wakePhrase: "hey codex", sensitivity: .strict
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "hey kodak", wakePhrase: "hey codex", sensitivity: .strict
        ))
    }

    @Test func normalMatchesCurrentAliasBehavior() {
        #expect(PhraseParser.containsWakePhrase(
            "hey codec", wakePhrase: "hey codex", sensitivity: .normal
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "okay codex please", wakePhrase: "hey codex", sensitivity: .normal
        ))
    }

    @Test func looseAcceptsHeyLikeGreetingsBeforeCodex() {
        #expect(PhraseParser.containsWakePhrase(
            "hi codex", wakePhrase: "hey codex", sensitivity: .loose
        ))
        #expect(PhraseParser.containsWakePhrase(
            "hy codex", wakePhrase: "hey codex", sensitivity: .loose
        ))
        #expect(PhraseParser.containsWakePhrase(
            "hi codec", wakePhrase: "hey codex", sensitivity: .loose
        ))
    }

    @Test func looseRejectsGreetingsThatDoNotSoundLikeHey() {
        #expect(!PhraseParser.containsWakePhrase(
            "okay codex please", wakePhrase: "hey codex", sensitivity: .loose
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "ok codex", wakePhrase: "hey codex", sensitivity: .loose
        ))
    }

    @Test func looseStillRequiresAGreetingBeforeCodex() {
        #expect(!PhraseParser.containsWakePhrase(
            "codex", wakePhrase: "hey codex", sensitivity: .loose
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "codec start", wakePhrase: "hey codex", sensitivity: .loose
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "I was talking about codex yesterday", wakePhrase: "hey codex", sensitivity: .loose
        ))
        #expect(!PhraseParser.containsWakePhrase(
            "completely unrelated words", wakePhrase: "hey codex", sensitivity: .loose
        ))
    }

    @Test func customPhrasesStayExactInEveryMode() {
        for sensitivity in [WakeSensitivity.strict, .normal, .loose] {
            #expect(PhraseParser.containsWakePhrase(
                "computer wake up now", wakePhrase: "computer wake up", sensitivity: sensitivity
            ))
            #expect(!PhraseParser.containsWakePhrase(
                "computer wake", wakePhrase: "computer wake up", sensitivity: sensitivity
            ))
        }
    }
}

@Suite("Wake phrase parsing")
struct PhraseParserTests {
    @Test func findsWakePhraseIgnoringCaseAndPunctuation() {
        #expect(PhraseParser.containsWakePhrase("Okay, HEY CODEX!", wakePhrase: "hey codex"))
    }

    @Test(arguments: ["Hey codec", "Hey codecs", "Hey code X", "Hey Kodak"])
    func acceptsCommonCodexTranscriptions(_ transcript: String) {
        #expect(PhraseParser.containsWakePhrase(transcript, wakePhrase: "hey codex"))
    }

    @Test func rejectsUnrelatedSpeech() {
        #expect(!PhraseParser.containsWakePhrase("hello codec", wakePhrase: "hey codex"))
    }

    @Test func rejectsIncompletePartialWakePhrase() {
        #expect(!PhraseParser.containsWakePhrase("Hey code", wakePhrase: "hey codex"))
    }

    @Test func supportsAnExactCustomWakePhraseWithoutCodexAliases() {
        #expect(PhraseParser.containsWakePhrase("Okay, hello zebra!", wakePhrase: "hello zebra"))
        #expect(!PhraseParser.containsWakePhrase("hello zebras", wakePhrase: "hello zebra"))
    }
}

@Suite("Multiple wake phrases")
struct MatchedActionTests {
    private let bindings = [
        WakePhraseBinding(phrase: "hey codex", action: WakeAction.dictation),
        WakePhraseBinding(phrase: "hey jarvis", action: .voiceChat),
    ]

    @Test func reportsWhichPhraseWasHeard() {
        #expect(PhraseParser.matchedAction("okay hey codex", bindings: bindings) == .dictation)
        #expect(PhraseParser.matchedAction("Hey Jarvis!", bindings: bindings) == .voiceChat)
        #expect(PhraseParser.matchedAction("hello there", bindings: bindings) == nil)
    }

    @Test(arguments: ["hey jarvis", "hey jervis", "hey jarves", "hey jarvus"])
    func acceptsCommonJarvisTranscriptions(_ transcript: String) {
        #expect(PhraseParser.matchedAction(transcript, bindings: bindings) == .voiceChat)
    }

    @Test func phrasesDoNotCrossMatch() {
        #expect(PhraseParser.matchedAction("hey codec", bindings: bindings) == .dictation)
        #expect(PhraseParser.matchedAction("hey jervis", bindings: bindings) == .voiceChat)
    }

    @Test func strictOnlyAcceptsTheExactJarvisPhrase() {
        #expect(PhraseParser.matchedAction(
            "hey jarvis", bindings: bindings, sensitivity: .strict
        ) == .voiceChat)
        #expect(PhraseParser.matchedAction(
            "hey jervis", bindings: bindings, sensitivity: .strict
        ) == nil)
    }
}
