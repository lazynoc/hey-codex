import Foundation
import Testing
@testable import HeyCodex

@Suite("Dictation stats")
struct DictationStatsTests {
    private func entry(_ text: String, atMs: Double?) -> DictationEntry {
        DictationEntry(
            id: UUID().uuidString,
            text: text,
            createdAt: atMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
        )
    }

    @Test func countsWordsAcrossWhitespaceAndNewlines() {
        #expect(DictationStats.wordCount(of: "fix the login bug") == 4)
        #expect(DictationStats.wordCount(of: "  one\ntwo\t three  ") == 3)
        #expect(DictationStats.wordCount(of: "") == 0)
    }

    @Test func addsOnlyEntriesNewerThanTheWatermark() {
        var totals = DictationTotals()
        totals = DictationStats.updated(totals, adding: [
            entry("one two", atMs: 1_000),
            entry("three four five", atMs: 2_000),
        ])
        #expect(totals.totalWords == 5)
        #expect(totals.lastProcessedAtMs == 2_000)

        // Re-processing the same entries must not double count.
        totals = DictationStats.updated(totals, adding: [
            entry("one two", atMs: 1_000),
            entry("three four five", atMs: 2_000),
            entry("six", atMs: 3_000),
        ])
        #expect(totals.totalWords == 6)
        #expect(totals.lastProcessedAtMs == 3_000)
    }

    @Test func skipsEntriesWithoutTimestampsSoTotalsStayIdempotent() {
        let totals = DictationStats.updated(DictationTotals(), adding: [
            entry("never counted", atMs: nil)
        ])
        #expect(totals.totalWords == 0)
    }
}

@Suite("Stats store")
struct StatsStoreTests {
    @Test func roundTripsTotalsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hey-codex-stats-\(UUID().uuidString)/stats.json")
        let store = StatsStore(url: url)

        #expect(store.load() == DictationTotals())

        var totals = DictationTotals()
        totals.totalWords = 42
        totals.lastProcessedAtMs = 7_000
        try store.save(totals)

        #expect(StatsStore(url: url).load() == totals)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
