import Foundation

/// Running dictation totals. Codex's history file is the source of truth
/// for the entries themselves; these aggregates survive even if Codex ever
/// trims that file. `lastProcessedAtMs` is the idempotency watermark.
struct DictationTotals: Codable, Equatable {
    var totalWords = 0
    var lastProcessedAtMs: Double = 0
}

enum DictationStats {
    nonisolated static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// Folds entries into the totals, counting only entries strictly newer
    /// than the watermark so repeated processing never double counts.
    /// Entries without a timestamp are skipped for the same reason.
    nonisolated static func updated(
        _ totals: DictationTotals,
        adding entries: [DictationEntry]
    ) -> DictationTotals {
        var result = totals

        for entry in entries {
            guard let createdAt = entry.createdAt else { continue }
            let atMs = createdAt.timeIntervalSince1970 * 1_000
            guard atMs > totals.lastProcessedAtMs else { continue }

            result.totalWords += wordCount(of: entry.text)
            result.lastProcessedAtMs = max(result.lastProcessedAtMs, atMs)
        }

        return result
    }
}

/// Persists `DictationTotals` as a small JSON file.
final class StatsStore {
    private let url: URL

    init(url: URL = StatsStore.defaultURL) {
        self.url = url
    }

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Hey Codex/stats.json")
    }

    func load() -> DictationTotals {
        guard let data = try? Data(contentsOf: url),
              let totals = try? JSONDecoder().decode(DictationTotals.self, from: data)
        else { return DictationTotals() }
        return totals
    }

    func save(_ totals: DictationTotals) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(totals)
        try data.write(to: url, options: .atomic)
    }
}
