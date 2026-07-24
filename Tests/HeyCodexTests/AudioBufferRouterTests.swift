import AVFoundation
import Testing
@testable import HeyCodex

private final class RecordingConsumer: AudioBufferConsuming {
    private let lock = NSLock()
    private var count = 0

    var received: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class TapInvocation: @unchecked Sendable {
    let handler: AVAudioNodeTapBlock
    let buffer: AVAudioPCMBuffer
    let time: AVAudioTime

    init(
        handler: @escaping AVAudioNodeTapBlock,
        buffer: AVAudioPCMBuffer,
        time: AVAudioTime
    ) {
        self.handler = handler
        self.buffer = buffer
        self.time = time
    }

    func call() {
        handler(buffer, time)
    }
}

@Suite("Audio buffer router")
struct AudioBufferRouterTests {
    @Test func wakeAudioTapCanExecuteAwayFromTheMainActor() async throws {
        let router = AudioBufferRouter()
        let consumer = RecordingConsumer()
        router.attach(id: UUID(), consumer: consumer)
        let handler = WakeWordListener.makeAudioTapHandler(router: router)
        let invocation = TapInvocation(
            handler: handler,
            buffer: makeBuffer(),
            time: AVAudioTime(hostTime: 0)
        )

        await Task.detached {
            invocation.call()
        }.value

        #expect(consumer.received == 1)
    }

    private func makeBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
    }

    @Test func routesBuffersToTheAttachedConsumer() {
        let router = AudioBufferRouter()
        let consumer = RecordingConsumer()
        let id = UUID()

        router.attach(id: id, consumer: consumer)
        router.route(makeBuffer())

        #expect(consumer.received == 1)
    }

    @Test func routesToEveryConsumerDuringAnOverlap() {
        let router = AudioBufferRouter()
        let old = RecordingConsumer()
        let new = RecordingConsumer()

        router.attach(id: UUID(), consumer: old)
        router.attach(id: UUID(), consumer: new)
        router.route(makeBuffer())

        #expect(old.received == 1)
        #expect(new.received == 1)
    }

    @Test func stopsRoutingToADetachedConsumer() {
        let router = AudioBufferRouter()
        let old = RecordingConsumer()
        let new = RecordingConsumer()
        let oldID = UUID()

        router.attach(id: oldID, consumer: old)
        router.attach(id: UUID(), consumer: new)
        router.detach(id: oldID)
        router.route(makeBuffer())

        #expect(old.received == 0)
        #expect(new.received == 1)
    }

    @Test func detachAllStopsEverything() {
        let router = AudioBufferRouter()
        let consumer = RecordingConsumer()

        router.attach(id: UUID(), consumer: consumer)
        router.detachAll()
        router.route(makeBuffer())

        #expect(consumer.received == 0)
    }
}
