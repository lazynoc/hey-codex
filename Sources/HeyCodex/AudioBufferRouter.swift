import AVFoundation

/// Receives microphone buffers from an audio tap.
protocol AudioBufferConsuming: AnyObject {
    func consume(_ buffer: AVAudioPCMBuffer)
}

/// Thread-safe fan-out from a single always-running microphone tap to the
/// active speech recognition request(s). During a session rotation both the
/// outgoing and the incoming request are attached, so no audio is dropped.
final class AudioBufferRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var consumers: [(id: UUID, consumer: any AudioBufferConsuming)] = []

    func attach(id: UUID, consumer: any AudioBufferConsuming) {
        lock.lock()
        consumers.append((id, consumer))
        lock.unlock()
    }

    func detach(id: UUID) {
        lock.lock()
        consumers.removeAll { $0.id == id }
        lock.unlock()
    }

    func detachAll() {
        lock.lock()
        consumers.removeAll()
        lock.unlock()
    }

    func route(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = consumers
        lock.unlock()

        for entry in current {
            entry.consumer.consume(buffer)
        }
    }
}
