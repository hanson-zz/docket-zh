import CoreAudio
import Foundation
import Observation

/// Whether anything is recording from the default input device.
///
/// Read through Core Audio's public property API:
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device
/// says whether any process has it running. Reading properties records no
/// audio, so this needs no microphone permission. The device's own input
/// mute is offered only when the device publishes a settable one; many
/// built-in microphones do not, and the widget says so instead.
@MainActor @Observable
final class MicrophoneMonitor {
    static let shared = MicrophoneMonitor()

    private(set) var hasDevice = false
    private(set) var deviceName = ""
    private(set) var inUse = false
    /// Nil when the device has no input mute to read.
    private(set) var muted: Bool?
    private(set) var canMute = false

    @ObservationIgnored private var timer: Timer?

    private init() {}

    /// Idempotent; every microphone tile and the visibility rules share one poll.
    func start() {
        guard timer == nil else { return }
        read()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Writes only what changed: an observed property that is merely
    /// reassigned still redraws everything that reads it.
    func read() {
        guard let device = Self.defaultInput() else {
            if hasDevice { hasDevice = false }
            if !deviceName.isEmpty { deviceName = "" }
            if inUse { inUse = false }
            if muted != nil { muted = nil }
            if canMute { canMute = false }
            return
        }
        if !hasDevice { hasDevice = true }
        let name = Self.name(of: device) ?? "输入设备"
        if name != deviceName { deviceName = name }
        let running = (Self.uint(device, kAudioDevicePropertyDeviceIsRunningSomewhere,
                                 scope: kAudioObjectPropertyScopeGlobal) ?? 0) != 0
        if running != inUse { inUse = running }
        let mute = Self.uint(device, kAudioDevicePropertyMute,
                             scope: kAudioDevicePropertyScopeInput).map { $0 != 0 }
        if mute != muted { muted = mute }
        let settable = mute != nil && Self.isSettable(device, kAudioDevicePropertyMute,
                                                      scope: kAudioDevicePropertyScopeInput)
        if settable != canMute { canMute = settable }
    }

    func setMuted(_ on: Bool) {
        guard canMute, let device = Self.defaultInput() else { return }
        var value = UInt32(on ? 1 : 0)
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
        if AudioObjectSetPropertyData(device, &address, 0, nil,
                                      UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
            muted = on
        }
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultInput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultInputDevice,
                              scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope) -> UInt32? {
        var address = address(selector, scope: scope)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope) -> Bool {
        var address = address(selector, scope: scope)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
}
