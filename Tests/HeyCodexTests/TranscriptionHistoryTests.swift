import Foundation
import Testing
@testable import HeyCodex

@Suite("Full history reading")
struct FullHistoryReadingTests {
    @Test func readsEveryEntryNewestFirst() {
        let lines = (1...300).map {
            #"{"id":"\#($0)","createdAtMs":\#($0 * 1_000),"text":"entry \#($0)"}"#
        }
        let data = Data(lines.joined(separator: "\n").utf8)

        let entries = TranscriptionHistory.all(in: data)

        #expect(entries.count == 300)
        #expect(entries.first?.text == "entry 300")
        #expect(entries.last?.text == "entry 1")
    }
}

@Suite("Transcription history")
struct TranscriptionHistoryTests {
    @Test func returnsNewestEntriesFirstUpToTheLimit() {
        let data = Data("""
        {"id":"a","createdAtMs":1000,"text":"first"}
        {"id":"b","createdAtMs":2000,"text":"second"}
        {"id":"c","createdAtMs":3000,"text":"third"}
        """.utf8)

        let entries = TranscriptionHistory.recent(in: data, limit: 2)

        #expect(entries.map(\.text) == ["third", "second"])
        #expect(entries.first?.id == "c")
        #expect(entries.first?.createdAt == Date(timeIntervalSince1970: 3))
    }

    @Test func skipsMalformedLinesAndBlankText() {
        let data = Data("""
        not json at all
        {"id":"a","createdAtMs":1000,"text":"kept"}
        {"id":"b","createdAtMs":2000}
        {"id":"c","createdAtMs":3000,"text":"   "}
        """.utf8)

        let entries = TranscriptionHistory.recent(in: data, limit: 5)

        #expect(entries.map(\.text) == ["kept"])
    }

    @Test func emptyDataYieldsNoEntries() {
        #expect(TranscriptionHistory.recent(in: Data(), limit: 3).isEmpty)
    }
}
