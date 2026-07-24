import Foundation
import Testing
@testable import HeyCodex

private actor EventCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }

    func waitUntil(atLeast target: Int, timeout: Duration = .seconds(3)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if count >= target { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return count >= target
    }
}

@Suite("File change watcher")
struct FileChangeWatcherTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "hey-codex-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func consume(_ stream: AsyncStream<Void>, into counter: EventCounter) -> Task<Void, Never> {
        Task {
            for await _ in stream {
                await counter.increment()
            }
        }
    }

    @Test func emitsWhenAnExistingFileIsAppendedTo() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.jsonl")
        try Data("line-1\n".utf8).write(to: file)

        let counter = EventCounter()
        let consumer = consume(FileChangeWatcher.changes(at: file), into: counter)
        defer { consumer.cancel() }

        try await Task.sleep(for: .milliseconds(100))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("line-2\n".utf8))
        try handle.close()

        #expect(await counter.waitUntil(atLeast: 1))
    }

    @Test func emitsWhenTheFileIsCreatedAfterWatchingStarts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "appears-later.json")

        let counter = EventCounter()
        let consumer = consume(FileChangeWatcher.changes(at: file), into: counter)
        defer { consumer.cancel() }

        try await Task.sleep(for: .milliseconds(100))
        try Data("[]".utf8).write(to: file)

        #expect(await counter.waitUntil(atLeast: 1))
    }

    @Test func keepsEmittingAfterAnAtomicReplace() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "keybindings.json")
        try Data("[]".utf8).write(to: file)

        let counter = EventCounter()
        let consumer = consume(FileChangeWatcher.changes(at: file), into: counter)
        defer { consumer.cancel() }

        try await Task.sleep(for: .milliseconds(100))

        // Atomic replace: write to a temp name, rename over the original.
        let replacement = directory.appending(path: "keybindings.json.tmp")
        try Data("[{}]".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)

        #expect(await counter.waitUntil(atLeast: 1))
        let countAfterReplace = await counter.count

        // The watcher must survive the replace and see writes to the new file.
        try await Task.sleep(for: .milliseconds(700))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(", more".utf8))
        try handle.close()

        #expect(await counter.waitUntil(atLeast: countAfterReplace + 1))
    }
}
