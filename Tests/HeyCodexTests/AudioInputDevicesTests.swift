import Testing
@testable import HeyCodex

@Suite("Audio input devices")
struct AudioInputDevicesTests {
    @Test func enumerationReturnsWellFormedDevices() {
        let devices = AudioInputDevices.all()

        // Hardware-dependent: the list may be empty on CI, but every
        // returned device must have a usable UID and name.
        for device in devices {
            #expect(!device.id.isEmpty)
            #expect(!device.name.isEmpty)
        }
        #expect(Set(devices.map(\.id)).count == devices.count)
    }

    @Test func unknownUIDResolvesToNoDevice() {
        #expect(AudioInputDevices.deviceID(forUID: "hey-codex-no-such-device") == nil)
    }
}
