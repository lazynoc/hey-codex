import Foundation
import Testing
@testable import HeyCodex

@Suite("Wake locale selection")
struct WakeLocaleSelectorTests {
    @Test func triesTheCurrentLocaleBeforeEnglishFallbacks() {
        let candidates = WakeLocaleSelector.candidates(
            preferred: nil,
            current: Locale(identifier: "de-DE")
        )

        #expect(candidates.map(\.identifier) == ["de-DE", "en-US", "en-GB"])
    }

    @Test func putsAnExplicitPreferenceFirst() {
        let candidates = WakeLocaleSelector.candidates(
            preferred: Locale(identifier: "en-IN"),
            current: Locale(identifier: "de-DE")
        )

        #expect(candidates.first?.identifier == "en-IN")
    }

    @Test func deduplicatesAcrossUnderscoreAndCaseVariants() {
        let candidates = WakeLocaleSelector.candidates(
            preferred: nil,
            current: Locale(identifier: "en_GB")
        )

        #expect(candidates.map(\.identifier) == ["en-GB", "en-US"])
    }
}
