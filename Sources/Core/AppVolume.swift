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
        playing == 0 ? "没有声音" : "\(playing) 个应用"
    }

    /// The first two names, then how many more.
    public static func caption(names: [String], permissionNeeded: Bool) -> String {
        if permissionNeeded { return "需要录音权限" }
        guard !names.isEmpty else { return "播放声音的应用会出现在这里" }
        let shown = names.prefix(2).joined(separator: "、")
        return names.count > 2 ? "\(shown) 等 \(names.count) 个" : shown
    }
}
