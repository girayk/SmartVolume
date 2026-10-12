import CoreAudio
import Foundation

/// Tracks the system's default output device.
public final class CoreAudioOutputWatcher: OutputWatching {
    public private(set) var current: AudioOutput?
    public var onChange: ((AudioOutput?) -> Void)?
    private var started = false

    public init() {}

    public func start() {
        guard !started else { return }
        started = true
        current = Self.readDefaultOutput()
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main) { [weak self] _, _ in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let output = Self.readDefaultOutput()
        guard output != current else { return }
        current = output
        onChange?(output)
    }

    static func readDefaultOutput() -> AudioOutput? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown,
              let uid = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
              let name = stringProperty(deviceID, kAudioObjectPropertyName)
        else { return nil }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = Self.address(kAudioDevicePropertyTransportType)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return AudioOutput(uid: uid, name: name, transport: Self.transport(from: transport))
    }

    public static func transport(from raw: UInt32) -> AudioTransport {
        switch raw {
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        default: return .other
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
