import Foundation

// MARK: - Settings

/// Which sounds play when a widget is added to or removed from the shelf.
public enum WidgetSoundStyle: String, Codable, CaseIterable, Sendable {
    /// Synthesised by the app itself: no files, identical on every Mac.
    case dockling
    /// The Dock's own sounds when this Mac has them, otherwise system alerts.
    case system

    public var title: String {
        switch self {
        case .dockling: "码头"
        case .system: "系统"
        }
    }
}

/// 设置 ▸ 扩展栏 ▸ 音效.
public struct WidgetSoundSettings: Codable, Hashable, Sendable {
    /// 添加和移除小组件时播放音效. On by default.
    public var enabled: Bool = true
    /// 0...1, on top of the system output volume.
    public var volume: Double = WidgetSoundSettings.defaultVolume
    public var style: WidgetSoundStyle = .dockling

    public static let defaultVolume = 0.6

    public init() {}

    /// The volume a player should use: clamped, and a damaged value is the default.
    public var gain: Float {
        guard volume.isFinite else { return Float(WidgetSoundSettings.defaultVolume) }
        return Float(min(1, max(0, volume)))
    }

    /// Lenient decoding, so a state file from before this existed, or one with
    /// a style a later version added, still loads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? WidgetSoundSettings.defaultVolume
        let raw = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        style = WidgetSoundStyle(rawValue: raw) ?? .dockling
    }
}

// MARK: - When to play

public enum WidgetSoundEvent: String, Sendable, CaseIterable {
    case added, removed
}

public enum WidgetSoundDecision {
    /// How many widgets a list holds, including ones tucked into groups.
    public static func widgetCount(_ items: [DockItem]) -> Int {
        items.reduce(0) { total, item in
            if item.isWidget { return total + 1 }
            if let group = item.group { return total + widgetCount(group.items) }
            return total
        }
    }

    /// What a single user edit did to the shelf's widgets, if anything.
    ///
    /// Counting rather than diffing ids is deliberate: moving a widget, putting
    /// it in a group or taking it out again keeps the count, so none of those
    /// make a sound, and an app pinned or unpinned never does.
    public static func event(before: [DockItem], after: [DockItem]) -> WidgetSoundEvent? {
        let old = widgetCount(before), new = widgetCount(after)
        if new > old { return .added }
        if new < old { return .removed }
        return nil
    }

    /// Whether to make a sound at all: the switch, and the system's own
    /// "播放用户界面音效", which every app's interface sounds answer to.
    public static func shouldPlay(_ settings: WidgetSoundSettings, systemUISoundsEnabled: Bool) -> Bool {
        settings.enabled && systemUISoundsEnabled && settings.gain > 0
    }

    /// Reads `com.apple.sound.uiaudio.enabled` as the global domain stores it.
    /// Missing means the Mac's default, which is on.
    public static func systemUISoundsEnabled(_ stored: Any?) -> Bool {
        switch stored {
        case let value as Bool: return value
        case let value as Int: return value != 0
        case let value as NSNumber: return value.intValue != 0
        case let value as String: return value != "0" && value.lowercased() != "false"
        default: return true
        }
    }
}

/// Keeps one gesture to one sound.
///
/// A shelf edit can reach the store more than once in quick succession (an
/// app adopted from the live Dock, then the widget appended), and adding three
/// widgets with three fast clicks should still be three clicks' worth of
/// sound, not a smear. Anything closer together than `interval` is the same
/// gesture.
public struct WidgetSoundGate: Sendable {
    public let interval: TimeInterval
    private var last: [WidgetSoundEvent: Date] = [:]

    public init(interval: TimeInterval = 0.12) {
        self.interval = interval
    }

    public mutating func allow(_ event: WidgetSoundEvent, at now: Date) -> Bool {
        if let previous = last[event], now.timeIntervalSince(previous) < interval,
           now >= previous {
            return false
        }
        last[event] = now
        return true
    }
}

// MARK: - System sound files

public enum WidgetSystemSounds {
    /// Where macOS keeps the Dock's own sounds. Private, so every one is
    /// checked before use and a missing file falls through to the next.
    public static let dockFolder =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock"

    public static func candidates(for event: WidgetSoundEvent) -> [String] {
        switch event {
        case .added:
            return ["\(dockFolder)/drag to dock.aif"]
        case .removed:
            return ["\(dockFolder)/poof item off dock.aif", "\(dockFolder)/drag to trash.aif"]
        }
    }

    /// The named system alert to fall back to, `NSSound(named:)` style.
    public static func fallbackNames(for event: WidgetSoundEvent) -> [String] {
        switch event {
        case .added: ["Pop", "Tink"]
        case .removed: ["Bottle", "Pop"]
        }
    }
}

// MARK: - The built-in "码头" set

/// The two short sounds the "码头" style plays, made from arithmetic.
///
/// Same idea as `AmbientSynth`: nothing to license or ship, and the tests can
/// render them and check what comes out.
public enum WidgetSoundSynth {
    public static let sampleRate = 44_100.0

    public static func render(_ event: WidgetSoundEvent, sampleRate: Double = sampleRate) -> [Float] {
        switch event {
        case .added: pop(sampleRate: sampleRate)
        case .removed: poof(sampleRate: sampleRate)
        }
    }

    /// A soft rising "pop": a sine gliding up, with a quick attack and decay.
    private static func pop(sampleRate: Double) -> [Float] {
        let duration = 0.11
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let frequency = 520 + 480 * min(1, progress * 2.2)
            phase += 2 * .pi * frequency / sampleRate
            let attack = min(1, t / 0.004)
            let decay = exp(-t * 38)
            // A touch of the octave gives it a rounder, bubble-like body.
            let tone = sin(phase) + 0.25 * sin(phase * 2)
            out[i] = Float(tone * attack * decay * 0.55)
        }
        return faded(out, sampleRate: sampleRate)
    }

    /// A breathy "poof": low-passed noise sweeping down, over a little thump.
    private static func poof(sampleRate: Double) -> [Float] {
        let duration = 0.28
        let count = Int(duration * sampleRate)
        var out = [Float](repeating: 0, count: count)
        var seed: UInt64 = 0x5EED_D0C1
        var low = 0.0, low2 = 0.0
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let white = Double(Int64(bitPattern: seed >> 1) % 2_000_001) / 1_000_000 - 1
            // The filter closes as the puff dies away, so it ends dull.
            let cutoff = 3_200 * exp(-t * 9) + 250
            let k = 1 - exp(-2 * .pi * cutoff / sampleRate)
            low += k * (white - low)
            low2 += k * (low - low2)
            let attack = min(1, t / 0.012)
            let body = exp(-t * 14)
            phase += 2 * .pi * (140 - 60 * min(1, t / duration)) / sampleRate
            let thump = sin(phase) * exp(-t * 30) * 0.35
            out[i] = Float((low2 * 1.8 * body + thump) * attack * 0.6)
        }
        return faded(out, sampleRate: sampleRate)
    }

    /// Hard limit and a 5 ms tail fade, so neither sound can click or clip.
    private static func faded(_ samples: [Float], sampleRate: Double) -> [Float] {
        var out = samples.map { min(0.95, max(-0.95, $0)) }
        let tail = min(out.count, Int(0.005 * sampleRate))
        for j in 0..<tail {
            out[out.count - 1 - j] *= Float(j) / Float(max(1, tail))
        }
        return out
    }

    /// 16-bit mono PCM in a WAV container, which `NSSound(data:)` plays.
    public static func wav(_ samples: [Float], sampleRate: Double = sampleRate) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let rate = UInt32(sampleRate)
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))            // PCM
        append(UInt16(1))            // mono
        append(rate)
        append(rate * 2)             // byte rate
        append(UInt16(2))            // block align
        append(UInt16(16))           // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in samples {
            let clamped = min(1, max(-1, sample.isFinite ? sample : 0))
            append(Int16(clamped * Float(Int16.max)))
        }
        return data
    }
}
