import AppKit
import SwiftUI

/// The full dictation history — every entry from Codex's history file,
/// newest first, searchable, with per-entry copy.
struct HistoryWindowView: View {
    let stats: DictationStatsModel

    @AppStorage(InterfaceSize.defaultsKey) private var interfaceSize = InterfaceSize.medium
    @AppStorage(AppTheme.defaultsKey) private var appTheme = AppTheme.system
    @State private var entries: [DictationEntry] = []
    @State private var searchText = ""
    @State private var copiedEntryID: String?
    @State private var watchTask: Task<Void, Never>?

    private var filteredEntries: [DictationEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filteredEntries) { entry in
                VStack(alignment: .leading, spacing: interfaceSize.historyRowSpacing) {
                    HStack {
                        if let createdAt = entry.createdAt {
                            Text(createdAt, format: .dateTime.day().month().year().hour().minute())
                                .font(interfaceSize.secondaryFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(copiedEntryID == entry.id ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.text, forType: .string)
                            copiedEntryID = entry.id
                        }
                    }
                    Text(entry.text)
                        .font(interfaceSize.historyBodyFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, interfaceSize.historyRowPadding)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Dictations Yet",
                        systemImage: "waveform",
                        description: Text("Finished dictations appear here.")
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Dictation History")
            .navigationSubtitle(subtitle)
        }
        .searchable(text: $searchText, prompt: "Search dictations")
        .controlSize(interfaceSize.controlSize)
        .preferredColorScheme(appTheme.colorScheme)
        .frame(minWidth: 520, minHeight: 400)
        .onAppear {
            reload()
            watchWhileOpen()
        }
        .onDisappear {
            watchTask?.cancel()
            watchTask = nil
        }
    }

    private var subtitle: String {
        stats.summary
    }

    private func reload() {
        entries = TranscriptionHistory.all(at: VoiceDependencies.dictationHistoryURL)
    }

    private func watchWhileOpen() {
        watchTask?.cancel()
        let changes = FileChangeWatcher.changes(at: VoiceDependencies.dictationHistoryURL)
        watchTask = Task { @MainActor in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                reload()
            }
        }
    }
}
