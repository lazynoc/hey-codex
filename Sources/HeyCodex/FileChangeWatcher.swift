import Foundation

/// Emits an event whenever the file at the given URL changes, appears,
/// or is atomically replaced. Uses kernel file events (DispatchSource)
/// instead of polling; falls back to a slow existence probe only while
/// the file does not exist yet.
enum FileChangeWatcher {
    static func changes(at url: URL) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task.detached {
                while !Task.isCancelled {
                    let descriptor = open(url.path, O_EVTONLY)
                    if descriptor < 0 {
                        // File missing (not created yet, or just replaced away).
                        try? await Task.sleep(for: .milliseconds(250))
                        if FileManager.default.fileExists(atPath: url.path) {
                            continuation.yield(())
                        }
                        continue
                    }

                    await watchUntilInvalidated(fileDescriptor: descriptor) {
                        continuation.yield(())
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Watches one open file descriptor until the underlying file is
    /// renamed or deleted (or the surrounding task is cancelled), calling
    /// `onChange` for every event. Closes the descriptor before returning.
    private static func watchUntilInvalidated(
        fileDescriptor: Int32,
        onChange: @escaping @Sendable () -> Void
    ) async {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link],
            queue: .global()
        )

        await withTaskCancellationHandler {
            await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
                source.setEventHandler {
                    let flags = source.data
                    onChange()
                    if !flags.intersection([.rename, .delete, .link]).isEmpty {
                        source.cancel()
                    }
                }
                source.setCancelHandler {
                    close(fileDescriptor)
                    finished.resume()
                }
                source.resume()
            }
        } onCancel: {
            source.cancel()
        }
    }
}
