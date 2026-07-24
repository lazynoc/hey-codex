import Foundation

struct DictationEntry: Equatable, Identifiable {
    let id: String
    let text: String
    let createdAt: Date?
}

/// Tolerant reader for Codex's `transcription-history.jsonl`.
enum TranscriptionHistory {
    static func recent(in data: Data, limit: Int) -> [DictationEntry] {
        guard limit > 0, let content = String(data: data, encoding: .utf8) else { return [] }

        var entries: [DictationEntry] = []
        for line in content.split(separator: "\n").reversed() {
            guard entries.count < limit else { break }
            guard let lineData = line.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawEntry.self, from: lineData),
                  let text = raw.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }

            entries.append(DictationEntry(
                id: raw.id ?? String(entries.count),
                text: text,
                createdAt: raw.createdAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
            ))
        }
        return entries
    }

    /// Every entry in the data, newest first.
    static func all(in data: Data) -> [DictationEntry] {
        recent(in: data, limit: Int.max)
    }

    /// Every entry in the file, newest first. Reads the whole file — used
    /// by the history window and the stats catch-up, not the menu.
    static func all(at url: URL) -> [DictationEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return all(in: data)
    }

    /// Reads only the tail of the file so a large history stays cheap.
    static func recent(at url: URL, limit: Int, maxTailBytes: Int = 64 * 1_024) -> [DictationEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxTailBytes) ? size - UInt64(maxTailBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return [] }

        return recent(in: data, limit: limit)
    }

    private struct RawEntry: Decodable {
        let id: String?
        let createdAtMs: Double?
        let text: String?
    }
}
