import Testing
@testable import HeyCodex

@Suite("Silence detector")
struct SilenceDetectorTests {
    @Test func firesAfterContinuousSilenceForTheWindow() {
        let detector = SilenceDetector(window: 4)

        #expect(!detector.process(level: 0.001, at: 0))
        #expect(!detector.process(level: 0.001, at: 3.9))
        #expect(detector.process(level: 0.001, at: 4.1))
    }

    @Test func speechResetsTheWindow() {
        let detector = SilenceDetector(window: 4)

        #expect(!detector.process(level: 0.001, at: 0))
        #expect(!detector.process(level: 0.5, at: 2))
        #expect(!detector.process(level: 0.001, at: 2.5))
        #expect(!detector.process(level: 0.001, at: 6.4))
        #expect(detector.process(level: 0.001, at: 6.6))
    }

    @Test func firesOnlyOnce() {
        let detector = SilenceDetector(window: 4)

        _ = detector.process(level: 0.001, at: 0)
        #expect(detector.process(level: 0.001, at: 4.1))
        #expect(!detector.process(level: 0.001, at: 10))
    }

    @Test func levelAtOrAboveThresholdCountsAsSpeech() {
        let detector = SilenceDetector(threshold: 0.015, window: 4)

        #expect(!detector.process(level: 0.015, at: 0))
        #expect(!detector.process(level: 0.014, at: 1))
        // Silence only started at t=1, so t=4.5 is 3.5s of silence.
        #expect(!detector.process(level: 0.014, at: 4.5))
        #expect(detector.process(level: 0.014, at: 5.1))
    }
}
