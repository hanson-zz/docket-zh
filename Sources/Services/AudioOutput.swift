import CoreAudio
import AudioToolbox
import Foundation
import Observation

/// The default output device: its name and its volume.
///
/// Read through Core Audio's public property API. The volume is the
/// device's "virtual main" volume, the same one the menu bar slider moves;
/// some outputs (HDMI and most digital ones) have none, and the widget says
/// so rather than drawing a slider that cannot move anything.
@MainActor @Observable
final class AudioOutput {
    static let shared = AudioOutput()

    private(set) var deviceName = ""
    /// 0...1, or nil when the device has no adjustable volume.
    private(set) var volume: Double?
    private(set) var muted = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastRead: Date = .distantPast
    /// While dragging, readings would fight the slider.
    @ObservationIgnored private var holdUntil: Date = .distantPast

    private init() {}

    func start() {
        guard timer == nil else { return }
        read()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date.now
        guard PollGate.shouldStart(inFlight: false, blocked: now < holdUntil,
                                   sinceLastStart: now.timeIntervalSince(lastRead),
                                   interval: 1.5) else { return }
        read()
    }

    func read() {
        lastRead = .now
        guard let device = Self.defaultOutput() else {
            deviceName = ""
            volume = nil
            return
        }
        deviceName = Self.name(of: device) ?? "输出设备"
        volume = Self.float(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume).map(Double.init)
        muted = (Self.uint(device, kAudioDevicePropertyMute) ?? 0) != 0
    }

    func set(volume new: Double) {
        holdUntil = .now.addingTimeInterval(1)
        guard let device = Self.defaultOutput() else { return }
        var value = Float32(min(1, max(0, new)))
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<Float32>.size), &value)
        if status == noErr {
            volume = Double(value)
            if muted, value > 0 { setMuted(false) }
        }
    }

    func setMuted(_ on: Bool) {
        guard let device = Self.defaultOutput() else { return }
        var value = UInt32(on ? 1 : 0)
        var address = Self.address(kAudioDevicePropertyMute)
        if AudioObjectSetPropertyData(device, &address, 0, nil,
                                      UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
            muted = on
        }
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice,
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

    private static func float(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Float32? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
