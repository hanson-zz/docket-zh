import AppKit
import CoreAudio
import CoreMediaIO
import Darwin
import Foundation
import Observation
@preconcurrency import UserNotifications

/// 麦克风与摄像头：谁在用麦克风、摄像头开没开、输入设备、输入音量和全局静音。
///
/// 全部读 Core Audio 和 CoreMediaIO 的公开属性，读属性不录音，不需要麦克风权限：
/// - 默认输入设备有没有人在用：`kAudioDevicePropertyDeviceIsRunningSomewhere`。
/// - 哪些 App 在用麦克风：`kAudioHardwarePropertyProcessObjectList` 里每个进程的
///   `kAudioProcessPropertyIsRunningInput`（macOS 14 起），按 PID 找到 App 的名字和
///   图标；辅助进程（`com.google.Chrome.helper` 这种）并进 bundle id 是它前缀的 App。
/// - 摄像头：CoreMediaIO 每个视频设备的 `kCMIODevicePropertyDeviceIsRunningSomewhere`。
///   系统不说是哪个 App 打开的，只显示「摄像头开着」，不猜。
/// - 输入音量：默认输入设备输入方向的 `kAudioDevicePropertyVolumeScalar`。
///
/// 全局静音是把输入音量拉到 0，记下原值（存在 `quick.micLevel`，快速开关的
/// 「麦克风静音」和这里是同一份），解除时恢复。设备没有可调的输入音量时退回
/// 设备自己的静音开关；两样都没有就做不了，面板照实写。
///
/// 使用记录只存在本机（Application Support/Docket/microphone-log.json），逻辑在
/// Core 的 `MicUsageLog`。每秒读一次，一个计时器给所有麦克风卡片、面板和按条件
/// 显示共用。
@MainActor @Observable
final class MicrophoneMonitor {
    static let shared = MicrophoneMonitor()

    struct AppUse: Identifiable, Hashable {
        var id: String
        var name: String
        var pid: pid_t
        var bundleURL: URL?
        var since: Date
    }

    struct InputDevice: Identifiable, Hashable {
        var id: AudioObjectID
        var uid: String
        var name: String
    }

    private(set) var hasDevice = false
    private(set) var deviceName = ""
    private(set) var deviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private(set) var inUse = false
    /// 设备自己的输入静音；nil 是设备没有。
    private(set) var muted: Bool?
    private(set) var canMute = false

    /// 现在在用麦克风的 App，开始得早的在前。
    private(set) var apps: [AppUse] = []
    /// 摄像头开着。
    private(set) var cameraOn = false
    private(set) var cameraSince: Date?
    /// 输入音量 0 到 1；nil 是这个设备没有可调的输入音量。
    private(set) var volume: Double?
    /// 全局静音（码头拉到 0 的，或设备静音开关打开）。
    private(set) var globalMuted = UserDefaults.standard.bool(forKey: MicrophoneMonitor.mutedKey)
    /// 有输入流的设备，面板开着时才读。
    private(set) var devices: [InputDevice] = []
    /// 使用记录，面板读它写「今天谁用过」。
    private(set) var log = MicUsageLog()
    /// 每秒加一，面板的已用时长跟着走。
    private(set) var tick = 0

    /// 第一个麦克风小组件的设置，由 DocketApp 接上；没有麦克风小组件时是 nil。
    @ObservationIgnored var settings: @MainActor () -> MicPrivacySettings? = { nil }
    /// 电平表开着时不把码头自己算进「谁在用」。
    @ObservationIgnored var excludeSelf = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panels = 0
    @ObservationIgnored private var tracker = MicAlertTracker()
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private var asked = false
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    nonisolated static let mutedKey = "quick.micMuted"
    /// 静音前的音量，0 到 100 的整数（和以前快速开关存的一样）。
    nonisolated static let levelKey = "quick.micLevel"

    private init() {
        log = Self.loadLog()
        log.closeDangling()
        log.prune(now: .now)
    }

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
        if terminationObserver == nil {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { MicrophoneMonitor.shared.saveLog() }
            }
        }
    }

    /// 面板打开、关上。开着时每秒多读设备列表。
    func panelAppeared() {
        panels += 1
        start()
        readDevices()
    }

    func panelDisappeared() {
        panels = max(0, panels - 1)
    }

    /// Writes only what changed: an observed property that is merely
    /// reassigned still redraws everything that reads it.
    func read() {
        tick &+= 1
        let now = Date.now
        readDefaultDevice()
        readApps(now: now)
        readCamera(now: now)
        if panels > 0, tick % 2 == 0 { readDevices() }
        reconcileMute()
        let current = settings()
        recordUsage(now: now, settings: current)
        applyHotKey(current?.muteKey)
    }

    // MARK: 默认输入设备

    private func readDefaultDevice() {
        guard let device = Self.defaultInput() else {
            if hasDevice { hasDevice = false }
            if !deviceName.isEmpty { deviceName = "" }
            if deviceID != AudioObjectID(kAudioObjectUnknown) { deviceID = AudioObjectID(kAudioObjectUnknown) }
            if inUse { inUse = false }
            if muted != nil { muted = nil }
            if canMute { canMute = false }
            if volume != nil { volume = nil }
            return
        }
        if !hasDevice { hasDevice = true }
        if device != deviceID { deviceID = device }
        let name = Self.name(of: device) ?? tr("输入设备")
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
        let level = Self.inputVolume(device)
        if let level, let old = volume, abs(level - old) < 0.001 {
            // 没变
        } else if level != volume {
            volume = level
        }
    }

    /// 设备自己的静音钮（卡片上那个小钮，只在设备有静音时出现）。
    func setMuted(_ on: Bool) {
        guard canMute, let device = Self.defaultInput() else { return }
        var value = UInt32(on ? 1 : 0)
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
        if AudioObjectSetPropertyData(device, &address, 0, nil,
                                      UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
            muted = on
        }
    }

    // MARK: 输入音量和全局静音

    /// 全局静音能不能做：有可调的输入音量，或者设备有静音开关。
    var canGlobalMute: Bool { hasDevice && (volumeSettable || canMute) }

    var volumeSettable: Bool {
        guard hasDevice, volume != nil else { return false }
        return Self.isVolumeSettable(deviceID)
    }

    /// 拖音量滑杆。静音中往上拖就算解除静音。
    func setVolume(_ value: Double) {
        guard hasDevice else { return }
        let clamped = min(1, max(0, value))
        if Self.setInputVolume(deviceID, clamped) { volume = clamped }
        if globalMuted, clamped > MicMute.silent { setGlobalMuted(false, restore: false) }
    }

    func toggleGlobalMute() {
        setGlobalMuted(!globalMuted)
    }

    /// 静音：记下原音量再拉到 0；解除：恢复记下的音量。没有可调音量时用设备静音开关。
    func setGlobalMuted(_ on: Bool, restore: Bool = true) {
        let defaults = UserDefaults.standard
        if on {
            guard hasDevice else { return }
            let previous = defaults.object(forKey: Self.levelKey) == nil
                ? nil : Double(defaults.integer(forKey: Self.levelKey)) / 100
            let keep = MicMute.remembered(current: volume, previous: previous)
            defaults.set(Int((keep * 100).rounded()), forKey: Self.levelKey)
            var done = false
            if volumeSettable, Self.setInputVolume(deviceID, 0) {
                volume = 0
                done = true
            }
            if !done, canMute {
                setMuted(true)
                done = true
            }
            guard done else { return }
        } else if restore {
            let saved = defaults.object(forKey: Self.levelKey) == nil
                ? nil : Double(defaults.integer(forKey: Self.levelKey)) / 100
            let level = MicMute.restored(saved)
            if volumeSettable, Self.setInputVolume(deviceID, level) { volume = level }
            if muted == true, canMute { setMuted(false) }
        }
        globalMuted = on
        defaults.set(on, forKey: Self.mutedKey)
        QuickActions.shared.noteChange()
    }

    /// 别处把音量调上去了，静音就不算了。
    private func reconcileMute() {
        guard globalMuted, hasDevice else { return }
        let deviceMuted = muted == true
        let stillMuted = MicMute.stillMuted(flag: true, volume: volumeSettable ? volume : nil) || deviceMuted
        if !stillMuted {
            globalMuted = false
            UserDefaults.standard.set(false, forKey: Self.mutedKey)
            QuickActions.shared.noteChange()
        }
    }

    // MARK: 谁在用

    private func readApps(now: Date) {
        let me = ProcessInfo.processInfo.processIdentifier
        var found: [String: AppUse] = [:]
        for process in Self.processObjects() {
            guard (Self.uint(process, kAudioProcessPropertyIsRunningInput,
                             scope: kAudioObjectPropertyScopeGlobal) ?? 0) != 0 else { continue }
            guard let pid = Self.pid(of: process) else { continue }
            if pid == me, excludeSelf { continue }
            let bundle = Self.string(process, kAudioProcessPropertyBundleID)
            let who = Self.identify(pid: pid, bundleID: bundle)
            if found[who.id] == nil {
                let since = apps.first { $0.id == who.id }?.since
                    ?? log.startOfOpen(app: who.id, source: .microphone) ?? now
                found[who.id] = AppUse(id: who.id, name: who.name, pid: who.pid, bundleURL: who.url, since: since)
            }
        }
        let next = found.values.sorted { $0.since == $1.since ? $0.name < $1.name : $0.since < $1.since }
        if next != apps { apps = next }
    }

    private func readCamera(now: Date) {
        let on = Self.cameraRunning()
        if on != cameraOn { cameraOn = on }
        if on {
            if cameraSince == nil {
                cameraSince = log.startOfOpen(app: MicActiveUse.cameraID, source: .camera) ?? now
            }
        } else if cameraSince != nil {
            cameraSince = nil
        }
    }

    /// 没有麦克风小组件时不记（开着的段收尾），也不提醒。
    private func recordUsage(now: Date, settings: MicPrivacySettings?) {
        var active = apps.map { MicActiveUse(app: $0.id, name: $0.name, source: .microphone) }
        if cameraOn { active.append(.camera) }
        if settings == nil { active = [] }
        // 改副本，真有变化才写回，免得每秒把读记录的面板全部重画。
        var next = log
        let started = next.update(active: active, now: now)
        if next != log { log = next }
        // 有段开始或结束就存；开着的段每分钟存一次，崩了也只差一分钟。
        let openCount = log.open.count
        if !started.isEmpty || openCount != lastOpenCount
            || (openCount > 0 && now.timeIntervalSince(lastSave) >= 60) {
            saveLog()
        }
        guard let settings else {
            tracker = MicAlertTracker()
            return
        }
        let alerts = tracker.alerts(started: started, notifyMic: settings.notifyMic,
                                    notifyCamera: settings.notifyCamera, now: now)
        for alert in alerts {
            Task { await post(alert) }
        }
    }

    @ObservationIgnored private var lastOpenCount = 0

    func saveLog() {
        lastOpenCount = log.open.count
        lastSave = .now
        var next = log
        next.prune(now: .now)
        next.savedAt = .now
        if next.sessions != log.sessions { log = next }
        Self.storeLog(next)
    }

    private func post(_ alert: MicAlert) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = BannerPresenter.shared }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
    }

    // MARK: 快捷键

    @ObservationIgnored private var appliedKey: KeyCombo?? = .none

    private func applyHotKey(_ wanted: KeyCombo?) {
        if case .some(let current) = appliedKey, current == wanted { return }
        appliedKey = .some(wanted)
        MicMuteHotKey.shared.onPress = { MicrophoneMonitor.shared.toggleGlobalMute() }
        MicMuteHotKey.shared.update(wanted)
    }

    // MARK: 输入设备

    func readDevices() {
        let next = Self.inputDevices()
        if next != devices { devices = next }
    }

    func selectDevice(_ device: InputDevice) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                UInt32(MemoryLayout<AudioObjectID>.size), &id)
        guard status == noErr else { return }
        // 换了设备：新设备静音中的音量不是我们拉的，静音状态照新设备重新算。
        read()
    }

    // MARK: 存盘

    nonisolated private static var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Docket", isDirectory: true)
            .appendingPathComponent("microphone-log.json")
    }

    nonisolated private static func loadLog() -> MicUsageLog {
        guard let data = try? Data(contentsOf: logURL),
              let log = try? JSONDecoder().decode(MicUsageLog.self, from: data) else { return MicUsageLog() }
        return log
    }

    nonisolated private static func storeLog(_ log: MicUsageLog) {
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(log) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
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

    private static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func processObjects() -> [AudioObjectID] {
        objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID, scope: kAudioObjectPropertyScopeGlobal)
        var pid = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr, pid > 0 else { return nil }
        return pid
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = address(selector, scope: scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }

    private static func name(of device: AudioObjectID) -> String? {
        string(device, kAudioObjectPropertyName)
    }

    private static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope,
                             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
        var address = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func isSettable(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope,
                                   element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = address(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    /// 输入音量所在的通道：主通道有就用主通道，没有就用 1、2 声道。
    private static func volumeElements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        var main = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput)
        if AudioObjectHasProperty(device, &main) { return [kAudioObjectPropertyElementMain] }
        let channels: [AudioObjectPropertyElement] = [1, 2]
        return channels.filter { element in
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput,
                                  element: element)
            return AudioObjectHasProperty(device, &address)
        }
    }

    private static func inputVolume(_ device: AudioObjectID) -> Double? {
        let elements = volumeElements(device)
        let values: [Double] = elements.compactMap { element in
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput,
                                  element: element)
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func isVolumeSettable(_ device: AudioObjectID) -> Bool {
        volumeElements(device).contains {
            isSettable(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput, element: $0)
        }
    }

    @discardableResult
    private static func setInputVolume(_ device: AudioObjectID, _ level: Double) -> Bool {
        var ok = false
        for element in volumeElements(device)
        where isSettable(device, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput, element: element) {
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput,
                                  element: element)
            var value = Float32(level)
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr {
                ok = true
            }
        }
        return ok
    }

    private static func inputDevices() -> [InputDevice] {
        objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap { device in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
            if (uint(device, kAudioDevicePropertyIsHidden, scope: kAudioObjectPropertyScopeGlobal) ?? 0) != 0 { return nil }
            guard let name = name(of: device) else { return nil }
            // 别的 App 临时建的聚合设备不列。
            if name.hasPrefix("CADefaultDeviceAggregate") { return nil }
            let uid = string(device, kAudioDevicePropertyDeviceUID) ?? "\(device)"
            return InputDevice(id: device, uid: uid, name: name)
        }
    }

    // MARK: App 名字

    private static func identify(pid: pid_t, bundleID: String?) -> (id: String, name: String, pid: pid_t, url: URL?) {
        let running = NSRunningApplication(processIdentifier: pid)
        if let running, running.activationPolicy == .regular {
            let id = running.bundleIdentifier ?? bundleID ?? "pid.\(pid)"
            return (id, running.localizedName ?? id, pid, running.bundleURL)
        }
        // 辅助进程并进主 App：bundle id 是它前缀、普通（有 Dock 图标）的那个。
        if let bundle = running?.bundleIdentifier ?? bundleID {
            let owner = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app -> (NSRunningApplication, String)? in
                    guard let id = app.bundleIdentifier, bundle.hasPrefix(id + ".") else { return nil }
                    return (app, id)
                }
                .max { $0.1.count < $1.1.count }
            if let owner {
                let app = owner.0, id = owner.1
                return (id, app.localizedName ?? id, app.processIdentifier, app.bundleURL)
            }
        }
        if let running, let name = running.localizedName {
            return (running.bundleIdentifier ?? bundleID ?? "pid.\(pid)", name, pid, running.bundleURL)
        }
        let name = processName(pid) ?? bundleID?.split(separator: ".").last.map(String.init) ?? "pid \(pid)"
        return (bundleID ?? "proc.\(name)", name, pid, nil)
    }

    private static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: 摄像头（CoreMediaIO）

    private static func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraRunning() -> Bool {
        var address = cmioAddress(Int(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }
        for device in devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size) {
            var running = cmioAddress(Int(kCMIODevicePropertyDeviceIsRunningSomewhere))
            guard CMIOObjectHasProperty(device, &running) else { continue }
            var value: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &value) == 0,
               value != 0 {
                return true
            }
        }
        return false
    }
}
