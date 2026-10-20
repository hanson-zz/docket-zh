import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import Observation
import Synchronization

/// Per-app volume, through Core Audio process taps (macOS 14.2 and later).
///
/// Listing which apps are playing reads the HAL's process objects and needs
/// no permission. Changing an app's volume does: the app is tapped with
/// `mutedWhenTapped`, which silences its normal output and hands its audio
/// to us, and a private aggregate device whose main sub-device is the
/// current output plays it back scaled. That needs the "system audio
/// recording" permission, which is why every path here can end in a plain
/// "需要录音权限" instead of a tap.
///
/// An app left at 100 percent and unmuted is never tapped. Its sound takes
/// the normal path, so a tap that fails, or a permission that was refused,
/// can only ever affect an app the user deliberately changed.
///
/// The tap and aggregate-device sequence follows Apple's documented API, with
/// insidegui/AudioCap (BSD 2-Clause) as the reference for the dictionary keys
/// and teardown order; see NOTICE.md.
@MainActor @Observable
final class AppVolumeService {
    static let shared = AppVolumeService()

    struct Row: Identifiable, Equatable {
        var bundleID: String
        var name: String
        var setting: AppVolumeSetting
        /// The tap for this app could not be built, in words.
        var problem: String?

        var id: String { bundleID }
    }

    enum Permission: Equatable {
        case granted, denied, unknown
    }

    /// Apps playing right now, by name. 开会模式下 `setting` 是生效的那份（降到 30% 的）。
    private(set) var rows: [Row] = []
    /// 「＋ 添加 App」加进来、这会儿没在出声的，按加入顺序（卡片不显示，面板列在下面）。
    private(set) var presets: [Row] = []
    /// 加进来的全部（含正在出声的），面板用来判断能不能「从列表移除」。
    private(set) var pinned: [String] = []
    /// 开会模式开着。
    private(set) var meeting = false
    /// 面板里右键改过的「算不算会议 App」。
    private(set) var meetingChoices: [String: Bool] = [:]
    private(set) var permission: Permission = .unknown
    /// A failure that is not one app's, such as no output device.
    private(set) var problem: String?

    @ObservationIgnored private var settings: [String: AppVolumeSetting]
    /// 开会时在面板上拖过的临时值，关掉开会模式时丢掉。
    @ObservationIgnored private var meetingOverrides: [String: AppVolumeSetting] = [:]
    @ObservationIgnored private var groups: [AudioAppGroup] = []
    @ObservationIgnored private var taps: [String: AppTap] = [:]
    @ObservationIgnored private var failures: [String: String] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var outputDevice: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var asked = false

    private static let defaultsKey = "appVolume.settings"

    private init() {
        let defaults = UserDefaults.standard
        settings = AppVolumeSetting.decode(defaults.data(forKey: Self.defaultsKey))
        pinned = AppVolumePresets.decode(defaults.data(forKey: AppVolumePresets.defaultsKey))
        meeting = defaults.bool(forKey: MeetingMode.activeKey)
        meetingOverrides = meeting ? MeetingMode.decodeOverrides(defaults.data(forKey: MeetingMode.overridesKey)) : [:]
        meetingChoices = MeetingMode.decodeCustom(defaults.data(forKey: MeetingMode.customKey))
    }

    // MARK: Lifecycle

    /// Idempotent; every tile and panel share one poll.
    func start() {
        guard timer == nil else { return }
        permission = AudioCapturePermission.status()
        outputDevice = CoreAudioReader.defaultOutput() ?? AudioObjectID(kAudioObjectUnknown)
        refresh()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-reads which apps play, and builds or tears down taps to match.
    func refresh() {
        let device = CoreAudioReader.defaultOutput() ?? AudioObjectID(kAudioObjectUnknown)
        if device != outputDevice {
            // Every aggregate is built on the old output; rebuild on the new.
            outputDevice = device
            removeAllTaps()
            failures = [:]
        }
        let access = AudioCapturePermission.status()
        if access != permission { permission = access }
        let processes = CoreAudioReader.processes()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        var owners: [UInt32: String] = [:]
        for process in processes where process.isRunningOutput {
            if let owner = Responsibility.ownerBundleID(of: process.pid), owner != process.bundleID {
                owners[process.objectID] = owner
            }
        }
        let own = Bundle.main.bundleIdentifier.map { Set([$0]) } ?? []
        let next = AudioAppList.groups(processes, apps: apps, owners: owners, excluding: own)
        if !AudioAppList.diff(old: groups, new: next).isEmpty { groups = next }
        let issue: String? = device == AudioObjectID(kAudioObjectUnknown) ? tr("没有可用的输出设备") : nil
        if issue != problem { problem = issue }
        applyTaps()
        publishRows()
    }

    // MARK: Changes from the panel

    func setPercent(_ percent: Double, for bundleID: String) {
        var setting = editedSetting(for: bundleID)
        setting.percent = AppVolume.snapped(percent)
        update(setting, for: bundleID)
    }

    /// 「正在播放」面板借这一路给网易云、QQ 音乐做音量条：读现在的设置。
    /// 开会模式下是降过的那份，和应用音量面板显示的一致。
    func setting(for bundleID: String) -> AppVolumeSetting {
        effective(for: bundleID)
    }

    /// 录音权限是否已经给过。只读，不弹权限：面板没权限就不显示音量条。
    static var recordingGranted: Bool { AudioCapturePermission.status() == .granted }

    func setMuted(_ muted: Bool, for bundleID: String) {
        var setting = editedSetting(for: bundleID)
        setting.muted = muted
        update(setting, for: bundleID)
    }

    /// Every app back to normal: every tap down. 开会模式一起关掉，加进来的预设留着（回到 100%）。
    func resetAll() {
        settings = [:]
        meeting = false
        meetingOverrides = [:]
        save()
        saveMeeting()
        removeAllTaps()
        failures = [:]
        publishRows()
    }

    // MARK: 预设和开会模式

    /// 「＋ 添加 App」：没在出声也先放进列表，满了或已经在了就不加。
    @discardableResult
    func addPreset(_ bundleID: String) -> Bool {
        let next = AppVolumePresets.adding(bundleID, to: pinned)
        guard next != pinned else { return false }
        pinned = next
        savePinned()
        publishRows()
        return true
    }

    /// 从列表移除。没在出声的连同预设的音量一起清掉，免得看不见的设置还在起作用；
    /// 正在出声的只是不再固定，音量照旧。
    func removePreset(_ bundleID: String) {
        pinned = AppVolumePresets.removing(bundleID, from: pinned)
        savePinned()
        if !groups.contains(where: { $0.bundleID == bundleID }) {
            settings[bundleID] = nil
            meetingOverrides[bundleID] = nil
            save()
            saveMeeting()
        }
        publishRows()
    }

    /// 一键开会 / 再点恢复。
    func toggleMeeting() {
        meeting.toggle()
        meetingOverrides = [:]
        saveMeeting()
        reapply()
    }

    func isMeetingApp(_ bundleID: String) -> Bool {
        MeetingMode.isMeetingApp(bundleID, custom: meetingChoices)
    }

    /// 右键「开会时不降低」/「开会时也降低」：和内置名单一样就不记。
    func setMeetingApp(_ isMeeting: Bool, for bundleID: String) {
        if MeetingMode.isMeetingApp(bundleID) == isMeeting {
            meetingChoices[bundleID] = nil
        } else {
            meetingChoices[bundleID] = isMeeting
        }
        meetingOverrides[bundleID] = nil
        UserDefaults.standard.set(MeetingMode.encodeCustom(meetingChoices), forKey: MeetingMode.customKey)
        saveMeeting()
        reapply()
    }

    /// 真正交给音频接入的设置：存着的那份，开会时叠上降到 30% 或这次开会的临时值。
    private func effective(for bundleID: String) -> AppVolumeSetting {
        MeetingMode.effective(settings[bundleID] ?? AppVolumeSetting(), active: meeting,
                              isMeetingApp: isMeetingApp(bundleID), override: meetingOverrides[bundleID])
    }

    /// 拖动或静音时从哪一份改起：开会时的非会议 App 从生效的那份改，记成临时值。
    private func editedSetting(for bundleID: String) -> AppVolumeSetting {
        MeetingMode.editsOverride(active: meeting, isMeetingApp: isMeetingApp(bundleID))
            ? effective(for: bundleID) : (settings[bundleID] ?? AppVolumeSetting())
    }

    private var effectiveSettings: [String: AppVolumeSetting] {
        var all: [String: AppVolumeSetting] = [:]
        for key in Set(settings.keys).union(groups.map(\.bundleID)).union(meetingOverrides.keys) {
            all[key] = effective(for: key)
        }
        return all
    }

    /// 开会模式或会议名单变了：已经接入的改音量，该接入、该撤的照新的来。
    private func reapply() {
        for (bundleID, tap) in taps {
            let setting = effective(for: bundleID)
            if AppVolume.needsTap(setting) {
                tap.gain.store(AppVolume.gain(percent: setting.percent, muted: setting.muted))
            }
        }
        failures = [:]
        applyTaps()
        publishRows()
    }

    private func savePinned() {
        UserDefaults.standard.set(AppVolumePresets.encode(pinned), forKey: AppVolumePresets.defaultsKey)
    }

    private func saveMeeting() {
        let defaults = UserDefaults.standard
        defaults.set(meeting, forKey: MeetingMode.activeKey)
        if meeting, !meetingOverrides.isEmpty {
            defaults.set(MeetingMode.encodeOverrides(meetingOverrides), forKey: MeetingMode.overridesKey)
        } else {
            defaults.removeObject(forKey: MeetingMode.overridesKey)
        }
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
        if let url { NSWorkspace.shared.open(url) }
    }

    private func update(_ edited: AppVolumeSetting, for bundleID: String) {
        if MeetingMode.editsOverride(active: meeting, isMeetingApp: isMeetingApp(bundleID)) {
            meetingOverrides[bundleID] = edited
            saveMeeting()
        } else {
            settings[bundleID] = edited
            save()
        }
        let setting = effective(for: bundleID)
        // A live tap only needs its gain moved; the audio thread reads it.
        if let tap = taps[bundleID], AppVolume.needsTap(setting) {
            tap.gain.store(AppVolume.gain(percent: setting.percent, muted: setting.muted))
        } else {
            failures[bundleID] = nil
            applyTaps()
        }
        publishRows()
    }

    private func save() {
        UserDefaults.standard.set(AppVolumeSetting.encode(settings), forKey: Self.defaultsKey)
    }

    // MARK: Taps

    private func applyTaps() {
        let wanted = effectiveSettings
        let plan = AppTapPlan.plan(playing: groups, settings: wanted,
                                   tapped: taps.mapValues { $0.objectIDs })
        for bundleID in plan.remove {
            taps.removeValue(forKey: bundleID)?.invalidate()
        }
        guard !plan.build.isEmpty else { return }
        guard outputDevice != AudioObjectID(kAudioObjectUnknown) else { return }

        switch permission {
        case .denied:
            // Never tap without the grant: a refused tap still mutes the app.
            return
        case .unknown where !asked:
            asked = true
            AudioCapturePermission.request { granted in
                Task { @MainActor in
                    let service = AppVolumeService.shared
                    service.permission = granted ? .granted : .denied
                    if granted { service.applyTaps() }
                    service.publishRows()
                }
            }
            // The prompt answers asynchronously. When the private preflight
            // is unavailable the request below is how the system asks, so
            // fall through only in that case.
            if AudioCapturePermission.canAsk { return }
        default:
            break
        }

        for group in plan.build where failures[group.bundleID] == nil {
            let setting = wanted[group.bundleID] ?? AppVolumeSetting()
            do {
                let tap = try AppTap(group: group, output: outputDevice,
                                     gain: AppVolume.gain(percent: setting.percent, muted: setting.muted))
                taps[group.bundleID] = tap
            } catch {
                failures[group.bundleID] = error.tapMessage
            }
        }
    }

    private func removeAllTaps() {
        for tap in taps.values { tap.invalidate() }
        taps = [:]
    }

    private func publishRows() {
        let next = groups.map { group in
            Row(bundleID: group.bundleID,
                name: AppIdentity.name(for: group.bundleID),
                setting: effective(for: group.bundleID),
                problem: failures[group.bundleID])
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if next != rows { rows = next }
        let idle = AppVolumePresets.idle(pinned: pinned, playing: Set(groups.map(\.bundleID))).map { id in
            Row(bundleID: id, name: AppIdentity.name(for: id), setting: effective(for: id), problem: nil)
        }
        if idle != presets { presets = idle }
    }
}

// MARK: - Names and icons

@MainActor
enum AppIdentity {
    private static var icons: [String: NSImage] = [:]

    static func name(for bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    static func icon(for bundleID: String) -> NSImage {
        if let cached = icons[bundleID] { return cached }
        let image: NSImage
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = app.icon {
            image = icon
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        icons[bundleID] = image
        return image
    }
}

// MARK: - One tap

struct TapError: Error {
    var message: String
}

private extension Error {
    var tapMessage: String { (self as? TapError)?.message ?? tr("无法调节此应用的音量") }
}

/// The gain the audio thread reads, as the bits of a Float so it can be one
/// lock-free atomic.
final class TapGain: Sendable {
    private let bits: Atomic<UInt32>

    init(_ gain: Float) { bits = Atomic(gain.bitPattern) }

    func store(_ gain: Float) { bits.store(gain.bitPattern, ordering: .relaxed) }

    func load() -> Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
}

/// A process tap over one app, an aggregate device around it, and the I/O
/// callback that plays the tapped audio back at the chosen gain.
@MainActor
final class AppTap {
    let objectIDs: [UInt32]
    let gain: TapGain

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "app-volume.tap", qos: .userInteractive)

    init(group: AudioAppGroup, output: AudioObjectID, gain initial: Float) throws {
        objectIDs = group.objectIDs
        gain = TapGain(initial)

        let description = CATapDescription(stereoMixdownOfProcesses: group.objectIDs.map { AudioObjectID($0) })
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != AudioObjectID(kAudioObjectUnknown) else {
            throw TapError(message: tr("无法创建音频接入（\(status)）"))
        }
        tapID = tap

        guard let outputUID = CoreAudioReader.uid(of: output) else {
            invalidate()
            throw TapError(message: tr("读不到输出设备"))
        }
        let tapChannels = Int(CoreAudioReader.tapFormat(tap)?.mChannelsPerFrame ?? 2)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: tr("码头应用音量"),
            kAudioAggregateDeviceUIDKey: "com.docket-zh.app-volume.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else {
            invalidate()
            throw TapError(message: tr("无法创建聚合设备（\(status)）"))
        }
        aggregateID = device

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue,
                                                    Self.renderBlock(gain: gain, tapChannels: tapChannels))
        guard status == noErr, let proc else {
            invalidate()
            throw TapError(message: tr("无法启动音频回调（\(status)）"))
        }
        procID = proc
        status = AudioDeviceStart(device, proc)
        guard status == noErr else {
            invalidate()
            throw TapError(message: tr("无法启动聚合设备（\(status)）"))
        }
    }

    /// Stop, then destroy in reverse order of creation. Safe to call twice.
    func invalidate() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Built outside the main actor on purpose: a closure formed in a
    /// main-actor method is inferred main-actor isolated, and Swift 6 traps
    /// when the HAL then calls it on its own real-time thread.
    nonisolated private static func renderBlock(gain: TapGain, tapChannels: Int) -> AudioDeviceIOBlock {
        { @Sendable _, inputData, _, outputData, _ in
            let level = gain.load()
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            let outputs = UnsafeMutableAudioBufferListPointer(outputData)
            TapRender.render(inputs: inputs, outputs: outputs, tapChannels: tapChannels, gain: level)
        }
    }
}

/// The I/O callback's body. No allocation, no locks, no Swift arrays.
enum TapRender {
    /// The tap's streams are the last `tapChannels` input channels: an output
    /// with inputs of its own (a USB headset) puts those first, and they must
    /// never be played back into the speaker.
    static func render(inputs: UnsafeMutableAudioBufferListPointer,
                       outputs: UnsafeMutableAudioBufferListPointer,
                       tapChannels: Int, gain: Float) {
        var totalIn = 0
        for buffer in inputs { totalIn += Int(buffer.mNumberChannels) }
        let skip = max(0, totalIn - max(1, tapChannels))
        let available = totalIn - skip

        var outChannel = 0
        for out in outputs {
            let channels = Int(out.mNumberChannels)
            guard channels > 0, let raw = out.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let frames = Int(out.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for c in 0..<channels {
                let destination = samples + c
                guard let source = SampleGain.sourceChannel(for: outChannel + c, inputChannels: available),
                      let found = channel(skip + source, in: inputs) else {
                    SampleGain.silence(destination, stride: channels, frames: frames)
                    continue
                }
                let (pointer, stride, inFrames) = found
                let n = min(frames, inFrames)
                SampleGain.copy(from: pointer, sourceStride: stride, to: destination,
                                destinationStride: channels, frames: n, gain: gain)
                if n < frames {
                    SampleGain.silence(destination + n * channels, stride: channels, frames: frames - n)
                }
            }
            outChannel += channels
        }
    }

    /// The start of one logical input channel, its stride and its length.
    private static func channel(_ index: Int, in inputs: UnsafeMutableAudioBufferListPointer)
        -> (UnsafePointer<Float>, Int, Int)? {
        var first = 0
        for buffer in inputs {
            let channels = Int(buffer.mNumberChannels)
            if index < first + channels {
                guard channels > 0, let raw = buffer.mData else { return nil }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                let base = UnsafePointer(raw.assumingMemoryBound(to: Float.self))
                return (base + (index - first), channels, frames)
            }
            first += channels
        }
        return nil
    }
}

// MARK: - Reading the HAL

enum CoreAudioReader {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutput() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func uid(of device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func pid(_ object: AudioObjectID) -> Int32? {
        var address = address(kAudioProcessPropertyPID)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = address(kAudioTapPropertyFormat)
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// Every process the HAL knows about, with whether it is playing.
    static func processes() -> [AudioProcessInfo] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let processID = pid(id) else { return nil }
            let bundleID = string(id, kAudioProcessPropertyBundleID) ?? ""
            let running = (uint(id, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0
            return AudioProcessInfo(objectID: id, pid: processID, bundleID: bundleID, isRunningOutput: running)
        }
    }
}

// MARK: - Who a helper plays for

/// The app responsible for a process, from the system's own bookkeeping.
///
/// Safari plays web audio from `com.apple.WebKit.GPU`, whose bundle
/// identifier says nothing about Safari, so the prefix guess in
/// `AudioAppList.owner` cannot place it. The responsibility lookup can. It
/// is not public API, so it is looked up at run time and its absence simply
/// leaves the prefix guess in charge.
enum Responsibility {
    private typealias Lookup = @convention(c) (pid_t) -> pid_t

    private static let lookup: Lookup? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: Lookup.self)
    }()

    @MainActor
    static func ownerBundleID(of pid: Int32) -> String? {
        guard let lookup else { return nil }
        let owner = lookup(pid)
        guard owner > 0, owner != pid,
              let app = NSRunningApplication(processIdentifier: owner),
              app.activationPolicy == .regular else { return nil }
        return app.bundleIdentifier
    }
}

// MARK: - The recording permission

/// "Screen & System Audio Recording", system audio only.
///
/// There is no public call to read it. The TCC preflight is private, so it
/// is reached through dlopen and treated as optional: without it the status
/// is unknown and the system asks on its own the first time a tap is made.
enum AudioCapturePermission {
    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static var service: CFString { "kTCCServiceAudioCapture" as CFString }

    nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private static let preflight: Preflight? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: Preflight.self)
    }()

    private static let requestAccess: Request? = {
        guard let handle, let symbol = dlsym(handle, "TCCAccessRequest") else { return nil }
        return unsafeBitCast(symbol, to: Request.self)
    }()

    static var canAsk: Bool { requestAccess != nil }

    static func status() -> AppVolumeService.Permission {
        guard let preflight else { return .unknown }
        switch preflight(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    static func request(_ done: @escaping @Sendable (Bool) -> Void) {
        guard let requestAccess else { return }
        requestAccess(service, nil) { granted in done(granted) }
    }
}
