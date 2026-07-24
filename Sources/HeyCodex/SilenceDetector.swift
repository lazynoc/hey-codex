import Foundation

/// Decides when a dictation session has been silent long enough to stop.
/// Levels are RMS amplitudes in 0...1; anything at or above `threshold`
/// counts as speech and restarts the window. Fires at most once.
final class SilenceDetector {
    static let defaultThreshold: Float = 0.015

    private let threshold: Float
    private let window: TimeInterval
    private var silenceStartedAt: TimeInterval?
    private var hasFired = false

    init(threshold: Float = SilenceDetector.defaultThreshold, window: TimeInterval) {
        self.threshold = threshold
        self.window = window
    }

    func process(level: Float, at time: TimeInterval) -> Bool {
        guard !hasFired else { return false }

        if level >= threshold {
            silenceStartedAt = nil
            return false
        }

        guard let start = silenceStartedAt else {
            silenceStartedAt = time
            return false
        }

        if time - start >= window {
            hasFired = true
            return true
        }
        return false
    }
}
