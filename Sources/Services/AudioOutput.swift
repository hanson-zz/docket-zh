import CoreAudio
import AudioToolbox
import Foundation
import Observation

/// The default output device: its name and its volume, and every output the
/// Mac could switch to.
///
/// Read through Core Audio's public property API. The volume is the
/// device's "virtual main" volume, the same one the menu bar slider moves;
/// some outputs (HDMI and most digital ones) have none, and the widget says
/// so rather than drawing a slider that cannot move anything.
///
/// 音量卡片上一排输出设备：列表从 `kAudioHardwarePropertyDevices` 读，只留有
/// 输出流、没隐藏的；点一下就把它设成系统的默认输出，和控制中心里选一样，
/// 不用再去系统设置。码头自己为应用音量建的私有聚合设备不列出来。
@MainActor @Observable
final class AudioOutput {
    static let shared = AudioOutput()

    private(set) var deviceName = ""
    /// 0...1, or nil when the device has no adjustable volume.
    private(set) var volume: Double?
    private(set) var muted = false
    /// Every output that can be chosen, in no particular order; the tile sorts.
    private(set) var devices: [OutputDevice] = []
    /// The default output's object ID, matching one of `devices`.
    private(set) var currentID: UInt32?

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
        let listed = Self.outputDevices()
        if listed != devices { devices = listed }
        guard let device = Self.defaultOutput() else {
            deviceName = ""
            volume = nil
            currentID = nil
            return
        }
        if currentID != device { currentID = device }
        deviceName = Self.name(of: device) ?? tr("输出设备")
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

    /// Makes `device` the default output, as choosing it in Control Centre
    /// does. Sound already playing follows it; the app-volume taps rebuild on
    /// the new output by themselves.
    @discardableResult
    func select(_ device: OutputDevice) -> Bool {
        var id = AudioObjectID(device.id)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice,
                                   scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        holdUntil = .distantPast
        read()
        return status == noErr
    }

    // MARK: Core Audio

    /// Outputs a person would pick: at least one output stream, not hidden,
    /// and not one of our own private aggregates.
    private static func outputDevices() -> [OutputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutput(id) else { return nil }
            if (globalUInt(id, kAudioDevicePropertyIsHidden) ?? 0) != 0 { return nil }
            let uid = globalString(id, kAudioDevicePropertyDeviceUID) ?? ""
            if uid.hasPrefix("com.docket-zh.") { return nil }
            let transport = OutputTransport(fourCC: globalUInt(id, kAudioDevicePropertyTransportType) ?? 0)
            return OutputDevice(id: id, uid: uid, name: name(of: id) ?? tr("输出设备"), transport: transport)
        }
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams)
        var size = UInt32(0)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func globalUInt(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func globalString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

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
