import Foundation
import Observation

/// Keeps the running dictation totals current: catches up from Codex's
/// history file on launch, then folds in new entries as the file changes.
@MainActor
@Observable
final class DictationStatsModel {
    private(set) var totals: DictationTotals

    private let historyURL: URL
    private let store: StatsStore
    private var watchTask: Task<Void, Never>?

    init(
        historyURL: URL = VoiceDependencies.dictationHistoryURL,
        store: StatsStore = StatsStore()
    ) {
        self.historyURL = historyURL
        self.store = store
        totals = store.load()
        refresh()
        watch()
    }

    var summary: String {
        "\(totals.totalWords.formatted()) words"
    }

    func refresh() {
        let updated = DictationStats.updated(
            totals,
            adding: TranscriptionHistory.all(at: historyURL)
        )
        guard updated != totals else { return }
        totals = updated
        try? store.save(updated)
    }

    private func watch() {
        let changes = FileChangeWatcher.changes(at: historyURL)
        watchTask = Task { @MainActor [weak self] in
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }
}
