import AVFoundation
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum AudioInputDevices {
    static let defaultsKey = "preferredMicrophoneUID"

    static func all() -> [AudioInputDevice] {
        allDeviceIDs().compactMap { deviceID in
            guard hasInputStreams(deviceID),
                  let uid: String = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
                  let name: String = stringProperty(deviceID, kAudioObjectPropertyName),
                  !uid.isEmpty, !name.isEmpty
            else { return nil }
            return AudioInputDevice(id: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { deviceID in
            stringProperty(deviceID, kAudioDevicePropertyDeviceUID) == uid
        }
    }

    /// Points the engine's input at the preferred device; leaves the
    /// system default in place when the UID is nil, empty, or missing.
    static func apply(uid: String?, to engine: AVAudioEngine) {
        guard let uid, !uid.isEmpty, var deviceID = deviceID(forUID: uid),
              let audioUnit = engine.inputNode.audioUnit
        else { return }

        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var devices = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }

        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr
        else { return false }

        let buffers = UnsafeMutableAudioBufferListPointer(
            bufferList.assumingMemoryBound(to: AudioBufferList.self)
        )
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(
        _ deviceID: AudioDeviceID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
