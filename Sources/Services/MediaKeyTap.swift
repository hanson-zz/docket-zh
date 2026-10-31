import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics

// 替代系统音量和亮度提示：拦下音量、亮度键，由码头自己改，系统的提示就不出现。
// 什么该拦、改成多少都在 Core 的 IslandMediaKeys.swift，这里只管事件和设备。

// MARK: - The event tap

/// 会话级键盘事件拦截，只看 NX_SYSDEFINED（媒体键）。
///
/// 回调跑在主线程的 run loop 上，交给 `handler` 决定拦不拦：返回 true 吞掉，
/// false 原样交给系统。需要辅助功能权限，没有时 `install` 返回 false。
/// 写法同 QuickActions.swift 的 KeyboardBlocker / CleanModeTap。
@MainActor
final class MediaKeyTap {
    typealias Handler = @MainActor (_ press: IslandMediaKeyPress, _ modifiers: IslandMediaModifiers,
                                    _ pointer: CGPoint) -> Bool

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { tap != nil }

    /// 装上时 macOS 也可能因为回调太慢把它停掉，回调里会重新启用；
    /// 这里再看一眼它还开着没有。
    var isEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// 已经装着时只换 handler。
    func install(_ handler: @escaping Handler) -> Bool {
        MediaKeyTapBridge.handler = handler
        if tap != nil { return true }
        let mask = CGEventMask(1) << CGEventMask(IslandMediaKeyPress.systemDefinedType)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: MediaKeyTapBridge.callback, userInfo: nil) else {
            MediaKeyTapBridge.handler = nil
            return false
        }
        MediaKeyTapBridge.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.tap = port
        self.source = source
        return true
    }

    func remove() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        MediaKeyTapBridge.port = nil
        MediaKeyTapBridge.handler = nil
    }
}

/// The C callback can capture nothing, so what it needs lives here.
enum MediaKeyTapBridge {
    nonisolated(unsafe) static var port: CFMachPort?
    @MainActor static var handler: MediaKeyTap.Handler?

    nonisolated(unsafe) static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = MediaKeyTapBridge.port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == IslandMediaKeyPress.systemDefinedType else {
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        let pointer = event.location
        let modifiers = IslandMediaModifiers(option: flags.contains(.maskAlternate),
                                             shift: flags.contains(.maskShift))
        // 源加在主线程的 run loop 上，回调就在主线程；事件只在这一次调用里用。
        nonisolated(unsafe) let current = event
        let swallow: Bool = MainActor.assumeIsolated {
            guard let handler = MediaKeyTapBridge.handler,
                  let ns = NSEvent(cgEvent: current),
                  let press = IslandMediaKeyPress.parse(eventType: IslandMediaKeyPress.systemDefinedType,
                                                        subtype: ns.subtype.rawValue, data1: ns.data1)
            else { return false }
            return handler(press, modifiers, pointer)
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}

// MARK: - Writing the volume

/// 默认输出设备的音量和静音，读和写。
///
/// 音量先用虚拟主音量（系统音量键走的就是它），没有时改各声道；
/// 都改不了（HDMI、多数数字输出）时 `volumeWritable` 是 false，按键放行给系统。
enum SystemVolumeControl {
    static func read(_ device: AudioObjectID) -> (level: Double, muted: Bool)? {
        let level = float(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            ?? float(device, kAudioDevicePropertyVolumeScalar)
            ?? channels(device).lazy.compactMap { float(device, kAudioDevicePropertyVolumeScalar, element: $0) }.first
        guard let level else { return nil }
        let muted = (uint(device, kAudioDevicePropertyMute)
                     ?? channels(device).lazy.compactMap { uint(device, kAudioDevicePropertyMute, element: $0) }.first
                     ?? 0) != 0
        return (Double(min(1, max(0, level))), muted)
    }

    static func volumeWritable(_ device: AudioObjectID) -> Bool {
        settable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            || settable(device, kAudioDevicePropertyVolumeScalar)
            || channels(device).contains { settable(device, kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    static func muteWritable(_ device: AudioObjectID) -> Bool {
        settable(device, kAudioDevicePropertyMute)
            || channels(device).contains { settable(device, kAudioDevicePropertyMute, element: $0) }
    }

    static func setVolume(_ level: Double, on device: AudioObjectID) -> Bool {
        let value = Float32(min(1, max(0, level)))
        if settable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) {
            return set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, value)
        }
        if settable(device, kAudioDevicePropertyVolumeScalar) {
            return set(device, kAudioDevicePropertyVolumeScalar, value)
        }
        var any = false
        for channel in channels(device) where settable(device, kAudioDevicePropertyVolumeScalar, element: channel) {
            any = set(device, kAudioDevicePropertyVolumeScalar, value, element: channel) || any
        }
        return any
    }

    static func setMute(_ muted: Bool, on device: AudioObjectID) -> Bool {
        let value = UInt32(muted ? 1 : 0)
        if settable(device, kAudioDevicePropertyMute) {
            return set(device, kAudioDevicePropertyMute, value)
        }
        var any = false
        for channel in channels(device) where settable(device, kAudioDevicePropertyMute, element: channel) {
            any = set(device, kAudioDevicePropertyMute, value, element: channel) || any
        }
        return any
    }

    // MARK: Core Audio plumbing

    /// 立体声的两个声道，读不到时按 1、2。
    private static func channels(_ device: AudioObjectID) -> [UInt32] {
        var address = address(kAudioDevicePropertyPreferredChannelsForStereo)
        var pair: [UInt32] = [1, 2]
        guard AudioObjectHasProperty(device, &address) else { return pair }
        var size = UInt32(MemoryLayout<UInt32>.size * 2)
        let status = pair.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr ? pair : [1, 2]
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func settable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                 element: UInt32 = kAudioObjectPropertyElementMain) -> Bool {
        var address = address(selector, element: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func float(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              element: UInt32 = kAudioObjectPropertyElementMain) -> Float32? {
        var address = address(selector, element: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             element: UInt32 = kAudioObjectPropertyElementMain) -> UInt32? {
        var address = address(selector, element: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func set(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: Float32,
                            element: UInt32 = kAudioObjectPropertyElementMain) -> Bool {
        var address = address(selector, element: element)
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    private static func set(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: UInt32,
                            element: UInt32 = kAudioObjectPropertyElementMain) -> Bool {
        var address = address(selector, element: element)
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

// MARK: - Volume feedback

/// 系统设置里“更改音量时播放反馈”开着时，系统在松开音量键时“嘀”一声；
/// 键被码头拦下后系统不会响，码头照着补一声。按着 Shift 时反过来，和系统一样。
/// 找不到那段声音（以后的系统挪了位置）就不响。
@MainActor
enum VolumeFeedback {
    private static let sound: NSSound? = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true)

    private static var enabled: Bool {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (global?["com.apple.sound.beep.feedback"] as? Int ?? 0) != 0
    }

    static func play(shift: Bool) {
        guard enabled != shift, let sound else { return }
        sound.stop()
        sound.play()
    }
}
