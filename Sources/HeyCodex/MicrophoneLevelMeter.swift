@preconcurrency import AVFoundation

/// Streams RMS microphone levels while native dictation runs, so the
/// controller can stop a session after a configured stretch of silence.
/// Level metering only — no recognition and no recording.
enum MicrophoneLevelMeter {
    nonisolated static func levels() -> AsyncStream<Float> {
        AsyncStream { continuation in
            let engine = AVAudioEngine()
            AudioInputDevices.apply(
                uid: UserDefaults.standard.string(forKey: AudioInputDevices.defaultsKey),
                to: engine
            )

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                continuation.finish()
                return
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                continuation.yield(Self.rmsLevel(of: buffer))
            }

            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                continuation.finish()
                return
            }

            let box = EngineBox(engine)
            continuation.onTermination = { _ in
                box.engine.stop()
                box.engine.inputNode.removeTap(onBus: 0)
            }
        }
    }

    nonisolated static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for frame in 0..<frames {
            sum += data[0][frame] * data[0][frame]
        }
        return sqrt(sum / Float(frames))
    }
}

private final class EngineBox: @unchecked Sendable {
    let engine: AVAudioEngine

    init(_ engine: AVAudioEngine) {
        self.engine = engine
    }
}
