import Foundation
import Testing
@testable import HeyCodex

@Suite("Sound cue volume")
struct SoundCueVolumeTests {
    @Test func providesThreeSystemRelativeLevels() {
        #expect(SoundCueVolume.low.level == 0.35)
        #expect(SoundCueVolume.medium.level == 0.65)
        #expect(SoundCueVolume.system.level == 1)
    }

    @Test func defaultsToSystemAndReadsAStoredChoice() {
        let suiteName = "SoundCueVolumeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(SoundCueVolume.selected(in: defaults) == .system)

        defaults.set(SoundCueVolume.medium.rawValue, forKey: SoundCueVolume.defaultsKey)
        #expect(SoundCueVolume.selected(in: defaults) == .medium)

        defaults.set("unknown", forKey: SoundCueVolume.defaultsKey)
        #expect(SoundCueVolume.selected(in: defaults) == .system)
    }
}
