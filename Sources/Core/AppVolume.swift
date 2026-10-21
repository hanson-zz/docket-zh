import Foundation

// MARK: - Per-app volume: the arithmetic

/// What one app's slider means, kept apart from Core Audio so it can be
/// tested.
///
/// The slider runs from 0 to 150 percent. 100 is "leave the app alone": no
/// tap is built and the app's audio takes its normal path to the speaker, so
/// an app nobody touched can never be made quieter, louder or silent by a
/// tap that misbehaves. Anything else, or a mute, routes the app through a
/// process tap that scales its samples.
public enum AppVolume {
    public static let range: ClosedRange<Double> = 0...150
    public static let unity: Double = 100
    /// Close enough to 100 that the slider snaps there, so "back to normal"
    /// is easy to hit and actually removes the tap.
    public static let snapDistance: Double = 3

    public static func clamp(_ percent: Double) -> Double {
        guard percent.isFinite else { return unity }
        return min(range.upperBound, max(range.lowerBound, percent))
    }

    public static func snapped(_ percent: Double) -> Double {
        let value = clamp(percent)
        return abs(value - unity) <= snapDistance ? unity : value
    }

    /// Linear amplitude for a slider position.
    ///
    /// Square law rather than straight proportion: loudness follows the log
    /// of amplitude, and a linear slider puts nearly all of the audible
    /// change in its bottom fifth. Squaring is the usual cheap fit. 150
    /// percent is 2.25x, about +7 dB, which is a boost and not a distortion
    /// pedal; the renderer clips what goes past full scale.
    public static func gain(percent: Double, muted: Bool) -> Float {
        if muted { return 0 }
        let fraction = clamp(percent) / 100
        return Float(fraction * fraction)
    }

    /// Whether this app needs a tap at all.
    public static func needsTap(_ setting: AppVolumeSetting) -> Bool {
        setting.muted || abs(clamp(setting.percent) - unity) >= 0.5
    }

    public static func percentText(_ percent: Double) -> String {
        "\(Int(clamp(percent).rounded()))%"
    }

    public static func symbol(percent: Double, muted: Bool) -> String {
        let value = clamp(percent)
        if muted || value == 0 { return "speaker.slash.fill" }
        switch value {
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// One app's saved choice. Kept by bundle identifier, so it survives the app
/// quitting and coming back.
public struct AppVolumeSetting: Codable, Hashable, Sendable {
    public var percent: Double = AppVolume.unity
    public var muted: Bool = false

    public init(percent: Double = AppVolume.unity, muted: Bool = false) {
        self.percent = AppVolume.clamp(percent)
        self.muted = muted
    }

    /// Lenient, like every other saved struct here: a missing key is a
    /// default, never a thrown error that drops every other app's setting.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = AppVolume.clamp(try c.decodeIfPresent(Double.self, forKey: .percent) ?? AppVolume.unity)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }

    public var isDefault: Bool { !AppVolume.needsTap(self) }

    /// Saved settings with the untouched ones dropped, so the file only
    /// holds apps someone actually changed.
    public static func pruned(_ all: [String: AppVolumeSetting]) -> [String: AppVolumeSetting] {
        all.filter { !$0.value.isDefault }
    }

    public static func decode(_ data: Data?) -> [String: AppVolumeSetting] {
        guard let data,
              let all = try? JSONDecoder().decode([String: AppVolumeSetting].self, from: data)
        else { return [:] }
        return all
    }

    public static func encode(_ all: [String: AppVolumeSetting]) -> Data? {
        try? JSONEncoder().encode(pruned(all))
    }
}

// MARK: - Which apps are playing

/// One Core Audio process object, flattened off the HAL.
public struct AudioProcessInfo: Hashable, Sendable {
    public var objectID: UInt32
    public var pid: Int32
    public var bundleID: String
    public var isRunningOutput: Bool

    public init(objectID: UInt32, pid: Int32, bundleID: String, isRunningOutput: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }
}

/// Every process playing on behalf of one app.
///
/// Browsers and Electron apps play from helper processes, so one row in the
/// panel is often several process objects, and one tap covers them all.
public struct AudioAppGroup: Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var objectIDs: [UInt32]

    public var id: String { bundleID }

    public init(bundleID: String, objectIDs: [UInt32]) {
        self.bundleID = bundleID
        self.objectIDs = objectIDs.sorted()
    }
}

public enum AudioAppList {
    /// The app a helper process plays for, by bundle identifier.
    ///
    /// `com.google.Chrome.helper.Renderer` belongs to `com.google.Chrome`:
    /// the longest app identifier the helper's starts with, at a dot. An
    /// exact match wins outright; with no match the helper stands for itself.
    public static func owner(of bundleID: String, apps: [String]) -> String {
        let lower = bundleID.lowercased()
        var best: String?
        for app in apps where !app.isEmpty {
            let candidate = app.lowercased()
            if candidate == lower { return app }
            guard lower.hasPrefix(candidate + ".") else { continue }
            if (best?.count ?? 0) < app.count { best = app }
        }
        return best ?? bundleID
    }

    /// The processes playing right now, grouped by the app they belong to.
    ///
    /// `owners` is an explicit answer for a process (from the system's
    /// responsibility lookup) and beats the prefix guess. Sorted by bundle
    /// identifier so two reads of the same state compare equal.
    public static func groups(_ processes: [AudioProcessInfo], apps: [String],
                              owners: [UInt32: String] = [:],
                              excluding excluded: Set<String> = []) -> [AudioAppGroup] {
        var byOwner: [String: [UInt32]] = [:]
        for process in processes where process.isRunningOutput && !process.bundleID.isEmpty {
            let owner = owners[process.objectID] ?? owner(of: process.bundleID, apps: apps)
            guard !excluded.contains(owner), !excluded.contains(process.bundleID) else { continue }
            byOwner[owner, default: []].append(process.objectID)
        }
        return byOwner.map { AudioAppGroup(bundleID: $0.key, objectIDs: $0.value) }
            .sorted { $0.bundleID < $1.bundleID }
    }

    public struct Diff: Equatable, Sendable {
        public var added: [String]
        public var removed: [String]
        /// Still playing, but through a different set of processes, so any
        /// tap over the old set is tapping the wrong things.
        public var changed: [String]

        public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
    }

    public static func diff(old: [AudioAppGroup], new: [AudioAppGroup]) -> Diff {
        let before = Dictionary(old.map { ($0.bundleID, $0.objectIDs) }, uniquingKeysWith: { a, _ in a })
        let after = Dictionary(new.map { ($0.bundleID, $0.objectIDs) }, uniquingKeysWith: { a, _ in a })
        let added = after.keys.filter { before[$0] == nil }.sorted()
        let removed = before.keys.filter { after[$0] == nil }.sorted()
        var changed: [String] = []
        for (key, ids) in after {
            if let old = before[key], old != ids { changed.append(key) }
        }
        changed.sort()
        return Diff(added: added, removed: removed, changed: changed)
    }
}

/// Which taps to build and which to take down.
public enum AppTapPlan {
    public struct Plan: Equatable, Sendable {
        public var build: [AudioAppGroup]
        public var remove: [String]
    }

    /// `tapped` is what is tapped now, by app, with the process objects each
    /// tap covers. A tap whose app stopped playing, went back to 100 percent,
    /// or changed processes is removed; a changed one is also rebuilt.
    public static func plan(playing: [AudioAppGroup],
                            settings: [String: AppVolumeSetting],
                            tapped: [String: [UInt32]]) -> Plan {
        var build: [AudioAppGroup] = []
        var remove: [String] = []
        let wanted = playing.filter { AppVolume.needsTap(settings[$0.bundleID] ?? AppVolumeSetting()) }
        let wantedByID = Dictionary(wanted.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        for (bundleID, ids) in tapped {
            guard let group = wantedByID[bundleID] else { remove.append(bundleID); continue }
            if group.objectIDs != ids.sorted() { remove.append(bundleID) }
        }
        for group in wanted {
            let current = tapped[group.bundleID]?.sorted()
            if current != group.objectIDs { build.append(group) }
        }
        return Plan(build: build.sorted { $0.bundleID < $1.bundleID }, remove: remove.sorted())
    }
}

// MARK: - The render loop's arithmetic

/// What the tap's I/O callback does to each sample, kept here so it can be
/// tested without a sound card.
public enum SampleGain {
    /// Scaled and held inside full scale. A boost past 1.0 would otherwise
    /// wrap or crackle on the way out.
    @inline(__always)
    public static func apply(_ sample: Float, gain: Float) -> Float {
        let scaled = sample * gain
        if scaled > 1 { return 1 }
        if scaled < -1 { return -1 }
        return scaled.isFinite ? scaled : 0
    }

    /// Which input channel feeds an output channel: the same one when it
    /// exists, else the last one, so a stereo tap fills a stereo device one
    /// to one and a mono source reaches both speakers.
    @inline(__always)
    public static func sourceChannel(for output: Int, inputChannels: Int) -> Int? {
        guard inputChannels > 0, output >= 0 else { return nil }
        return min(output, inputChannels - 1)
    }

    /// Copies `frames` samples from a strided source to a strided
    /// destination, applying the gain. Strides are in samples, so an
    /// interleaved stereo buffer has stride 2 and a planar one stride 1.
    public static func copy(from source: UnsafePointer<Float>, sourceStride: Int,
                            to destination: UnsafeMutablePointer<Float>, destinationStride: Int,
                            frames: Int, gain: Float) {
        guard frames > 0, sourceStride > 0, destinationStride > 0 else { return }
        var s = 0
        var d = 0
        for _ in 0..<frames {
            destination[d] = apply(source[s], gain: gain)
            s += sourceStride
            d += destinationStride
        }
    }

    public static func silence(_ destination: UnsafeMutablePointer<Float>, stride: Int, frames: Int) {
        guard frames > 0, stride > 0 else { return }
        var d = 0
        for _ in 0..<frames {
            destination[d] = 0
            d += stride
        }
    }
}

/// The tile's words.
public enum AppVolumeText {
    public static func value(playing: Int) -> String {
        playing == 0 ? tr("没有声音") : tr("\(playing) 个应用")
    }

    /// The first two names, then how many more.
    public static func caption(names: [String], permissionNeeded: Bool) -> String {
        if permissionNeeded { return tr("需要录音权限") }
        guard !names.isEmpty else { return tr("播放声音的应用会出现在这里") }
        let shown = names.prefix(2).joined(separator: tr("、"))
        return names.count > 2 ? tr("\(shown) 等 \(names.count) 个") : shown
    }
}

// MARK: - 预设：没在出声的 App 先放进列表

/// 「＋ 添加 App」加进来的 App（bundle id，按加入顺序）。没在出声也留在面板里，
/// 可以先设好音量或静音，它一出声就按设好的来。存在 UserDefaults（`appVolume.pinned`）。
public enum AppVolumePresets {
    public static let defaultsKey = "appVolume.pinned"
    /// 面板放得下、也够用的数量。
    public static let limit = 12

    /// 加一个：已有的不重复，空的不加，满了不加（返回原样）。
    public static func adding(_ bundleID: String, to list: [String]) -> [String] {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !list.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }),
              list.count < limit else { return list }
        return list + [id]
    }

    public static func removing(_ bundleID: String, from list: [String]) -> [String] {
        list.filter { $0.caseInsensitiveCompare(bundleID) != .orderedSame }
    }

    /// 没在出声、要单独列在下面的预设，按加入顺序。
    public static func idle(pinned: [String], playing: Set<String>) -> [String] {
        pinned.filter { !playing.contains($0) }
    }

    public static func decode(_ data: Data?) -> [String] {
        guard let data, let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        var clean: [String] = []
        for id in list { clean = adding(id, to: clean) }
        return clean
    }

    public static func encode(_ list: [String]) -> Data? { try? JSONEncoder().encode(list) }
}

// MARK: - 开会模式

/// 一键开会：除会议 App 外，每个 App 降到 30%（本来就更低或静音的不动），
/// 再点一下全部回到原来的设置。
///
/// 不改存着的设置，只是叠一层：开会时算出「生效的设置」交给音频接入，关掉就
/// 回到存着的那份，所以恢复不会丢东西，开会途中才出声的 App 也会被降低。
/// 开会时在面板上拖某个 App，记成这次开会的临时值，关掉开会模式时一起丢掉。
public enum MeetingMode {
    public static let activeKey = "appVolume.meeting"
    public static let overridesKey = "appVolume.meetingOverrides"
    public static let customKey = "appVolume.meetingApps"
    public static let level: Double = 30

    /// 常见的会议和通话 App。浏览器里的网页会议分不出来，照样降低。
    public static let knownApps: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams", "com.microsoft.teams2",
        "com.tencent.meeting", "com.tencent.wemeet",
        "com.tencent.xinWeChat",
        "com.electron.lark", "com.bytedance.lark", "com.bytedance.feishu",
        "com.alibaba.DingTalkMac",
        "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark",
        "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.skype.skype",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan",
    ]

    /// 是不是会议 App：面板里右键改过的按改过的，否则看内置名单（不分大小写）。
    public static func isMeetingApp(_ bundleID: String, custom: [String: Bool] = [:]) -> Bool {
        if let chosen = custom[bundleID] { return chosen }
        return knownApps.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// 交给音频接入的设置。
    public static func effective(_ base: AppVolumeSetting, active: Bool, isMeetingApp: Bool,
                                 override: AppVolumeSetting? = nil) -> AppVolumeSetting {
        guard active, !isMeetingApp else { return base }
        if let override { return override }
        return AppVolumeSetting(percent: min(AppVolume.clamp(base.percent), level), muted: base.muted)
    }

    /// 开会模式下拖某个 App 时，改哪一份：非会议 App 改临时值，会议 App 和没开会时改存着的。
    public static func editsOverride(active: Bool, isMeetingApp: Bool) -> Bool {
        active && !isMeetingApp
    }

    public static func decodeCustom(_ data: Data?) -> [String: Bool] {
        guard let data, let value = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return value
    }

    public static func encodeCustom(_ value: [String: Bool]) -> Data? { try? JSONEncoder().encode(value) }

    /// 临时值不剪掉 100% 的：开会时拖回 100% 也是要的。
    public static func decodeOverrides(_ data: Data?) -> [String: AppVolumeSetting] {
        guard let data,
              let value = try? JSONDecoder().decode([String: AppVolumeSetting].self, from: data) else { return [:] }
        return value
    }

    public static func encodeOverrides(_ value: [String: AppVolumeSetting]) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

public extension AppVolumeText {
    /// 没在出声的预设下面那行。
    static func preset(_ setting: AppVolumeSetting) -> String {
        if setting.muted { return tr("没在出声 · 预设静音") }
        if setting.isDefault { return tr("没在出声 · 原音量") }
        return tr("没在出声 · 预设 \(AppVolume.percentText(setting.percent))")
    }

    /// 面板标题下那行。
    static func meetingCaption(active: Bool) -> String {
        active ? tr("开会中：其他 App 已降到 30%，再点恢复") : tr("除会议 App 外降到 30%")
    }
}
