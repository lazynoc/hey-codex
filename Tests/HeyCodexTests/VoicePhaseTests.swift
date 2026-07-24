import Testing
@testable import HeyCodex

@Suite("Voice status icon")
struct VoicePhaseTests {
    @Test func offAndErrorKeepTheEarIdentityWithASlash() {
        for phase in [VoicePhase.off, .error("Unavailable")] {
            #expect(phase.symbolName == "ear")
            #expect(phase.showsListeningSlash)
        }
    }

    @Test func activeStatesDoNotShowTheListeningSlash() {
        for phase in [
            VoicePhase.requestingPermission,
            .listening,
            .paused,
            .triggering,
            .dictating,
            .finishing,
        ] {
            #expect(!phase.showsListeningSlash)
        }
    }
}
