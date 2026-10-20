import Foundation

/// 环境音每种声音自己的音量，存在小组件设置的 `levels` 下，一条一种：`rain:75`。
///
/// 0 到 100，没存过的按 `defaultLevel` 算。`defaultLevel` 正好是改版前每种声音
/// 的固定响度，所以老卡片升级后听起来一点没变；往上还能再推 25%，雨大一点、
/// 火小一点就是一个推上去、一个拉下来。总音量（`volume`）照旧压在所有声音上面。
public enum AmbientLevels {
    public static let key = "levels"
    public static let defaultLevel = 80

    public static func clamp(_ level: Int) -> Int { min(100, max(0, level)) }

    /// 合成器里这种声音的增益：`defaultLevel` 是 1，100 是 1.25。
    public static func gain(_ level: Int) -> Float {
        Float(clamp(level)) / Float(defaultLevel)
    }

    public static func level(_ sound: AmbientSound, in levels: [AmbientSound: Int]) -> Int {
        levels[sound].map(clamp) ?? defaultLevel
    }

    /// `rain:75`、`fire：30`。认不得的声音、不是数字的丢掉，同一种声音后写的算。
    public static func parse(_ raw: [String]) -> [AmbientSound: Int] {
        var result: [AmbientSound: Int] = [:]
        for item in raw {
            guard let found = entry(item) else { continue }
            result[found.0] = found.1
        }
        return result
    }

    static func entry(_ raw: String) -> (AmbientSound, Int)? {
        let parts = raw.split(whereSeparator: { ":：".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let sound = AmbientSound(rawValue: parts[0].lowercased()),
              let value = Double(parts[1]), value.isFinite else { return nil }
        // 先夹到 0...100 再转整数：写成 1e300 这种大数时 Int() 会直接崩。
        return (sound, clamp(Int(min(100, max(0, value)).rounded())))
    }

    /// 写回设置用：按声音的固定顺序，等于默认的不写。
    public static func encode(_ levels: [AmbientSound: Int]) -> [String] {
        AmbientSound.allCases.compactMap { sound in
            guard let level = levels[sound].map(clamp), level != defaultLevel else { return nil }
            return "\(sound.rawValue):\(level)"
        }
    }
}

/// 存下来的一个组合：名字和里面每种声音的音量。设置里写成 `雨夜篝火=rain:75,fire:30`。
public struct AmbientMix: Equatable, Sendable {
    public var name: String
    /// 组合里的声音，按存的先后（卡片上画第一种的图标）；不在里面的声音就是不放。
    public private(set) var sounds: [AmbientSound]
    /// 组合里每种声音的音量。
    public private(set) var levels: [AmbientSound: Int]

    /// `sounds` 去重，没给音量的按默认；`levels` 里不在 `sounds` 的丢掉。
    public init(name: String, sounds: [AmbientSound], levels: [AmbientSound: Int]) {
        var ordered: [AmbientSound] = []
        for sound in sounds where !ordered.contains(sound) { ordered.append(sound) }
        self.name = name
        self.sounds = ordered
        var picked: [AmbientSound: Int] = [:]
        for sound in ordered { picked[sound] = AmbientLevels.level(sound, in: levels) }
        self.levels = picked
    }

    public var text: String {
        name + "=" + sounds.map { "\($0.rawValue):\(levels[$0] ?? AmbientLevels.defaultLevel)" }
            .joined(separator: ",")
    }

    /// 没有名字、或一种认得的声音都没有时是 nil。
    public static func parse(_ raw: String) -> AmbientMix? {
        guard let cut = raw.lastIndex(where: { $0 == "=" || $0 == "＝" }) else { return nil }
        let name = AmbientMixes.cleanName(String(raw[..<cut]))
        guard !name.isEmpty else { return nil }
        var sounds: [AmbientSound] = []
        var levels: [AmbientSound: Int] = [:]
        for item in raw[raw.index(after: cut)...].split(whereSeparator: { ",，".contains($0) }) {
            guard let found = AmbientLevels.entry(String(item)) else { continue }
            if !sounds.contains(found.0) { sounds.append(found.0) }
            levels[found.0] = found.1
        }
        guard !sounds.isEmpty else { return nil }
        return AmbientMix(name: name, sounds: sounds, levels: levels)
    }
}

/// 环境音的「我的组合」：最多 6 个，存在 `mixes` 下，面板和卡片右键一点就换过去。
public enum AmbientMixes {
    public static let key = "mixes"
    public static let limit = 6
    /// 名字最多几个字：面板上一排胶囊放得下，菜单里也不会太长。
    public static let nameLimit = 10

    /// 去掉首尾空白和换行，等号换成空格（它是名字和声音的分隔），截到 `nameLimit` 个字。
    public static func cleanName(_ raw: String) -> String {
        let flat = raw.map { "=＝\n\r\t".contains($0) ? " " : String($0) }.joined()
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(nameLimit)).trimmingCharacters(in: .whitespaces)
    }

    /// 存着的组合：解析不了的跳过，同名的只留第一个，最多 `limit` 个。
    public static func all(_ raw: [String]) -> [AmbientMix] {
        var result: [AmbientMix] = []
        for item in raw {
            guard result.count < limit, let mix = AmbientMix.parse(item),
                  !result.contains(where: { $0.name == mix.name }) else { continue }
            result.append(mix)
        }
        return result
    }

    public enum SaveResult: Equatable, Sendable {
        /// 存好了，这是新的 `mixes` 列表。
        case saved([String])
        case emptyName
        case noSounds
        /// 已经有 6 个，而且不是覆盖同名的那个。
        case full
    }

    /// 把现在点亮的声音和它们的音量存成一个组合。同名的覆盖（满了也能覆盖），
    /// 新名字加在最后。
    public static func saving(name: String, sounds: [AmbientSound], levels: [AmbientSound: Int],
                              in raw: [String]) -> SaveResult {
        let name = cleanName(name)
        guard !name.isEmpty else { return .emptyName }
        guard !sounds.isEmpty else { return .noSounds }
        let mix = AmbientMix(name: name, sounds: sounds, levels: levels)
        var current = all(raw)
        if let index = current.firstIndex(where: { $0.name == name }) {
            current[index] = mix
        } else {
            guard current.count < limit else { return .full }
            current.append(mix)
        }
        return .saved(current.map(\.text))
    }

    public static func removing(_ name: String, in raw: [String]) -> [String] {
        all(raw).filter { $0.name != name }.map(\.text)
    }

    /// 改名。新名字空了、或和别的组合重名时是 nil（不改）。
    public static func renaming(_ old: String, to new: String, in raw: [String]) -> [String]? {
        let name = cleanName(new)
        var current = all(raw)
        guard !name.isEmpty, let index = current.firstIndex(where: { $0.name == old }) else { return nil }
        if name == old { return current.map(\.text) }
        guard !current.contains(where: { $0.name == name }) else { return nil }
        current[index].name = name
        return current.map(\.text)
    }

    /// 正在放的声音和音量恰好是哪个组合（面板上那个胶囊亮着、标题写它的名字）。
    public static func matching(sounds: [AmbientSound], levels: [AmbientSound: Int],
                                in mixes: [AmbientMix]) -> AmbientMix? {
        // 只比声音和音量，不比先后：同样的几种换了顺序还是那个组合。
        let on = Set(sounds)
        guard !on.isEmpty else { return nil }
        return mixes.first { mix in
            Set(mix.sounds) == on && on.allSatisfy { mix.levels[$0] == AmbientLevels.level($0, in: levels) }
        }
    }

    /// 换到一个组合后的 `sounds` 和 `levels`：组合里的声音点亮并用它的音量，
    /// 不在组合里的声音熄掉，但它们之前调过的音量留着，下次点亮还是那个音量。
    public static func applying(_ mix: AmbientMix, levels: [AmbientSound: Int])
        -> (sounds: [AmbientSound], levels: [AmbientSound: Int]) {
        var merged = levels
        for (sound, level) in mix.levels { merged[sound] = level }
        return (mix.sounds, merged)
    }

    /// 「存为组合」框里先填的名字：组合 1、组合 2，跳过已经用掉的。
    public static func suggestedName(existing: [AmbientMix]) -> String {
        let used = Set(existing.map(\.name))
        var index = existing.count + 1
        while used.contains(tr("组合 \(index)")) { index += 1 }
        return tr("组合 \(index)")
    }
}

/// 定时关闭的「自定义」：5 分钟到 8 小时，5 分钟一档。
public enum AmbientCustomTimer {
    public static let range = 5...480
    public static let step = 5
    public static let fallback = 45

    public static func clamp(_ minutes: Int) -> Int {
        let stepped = Int((Double(minutes) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }

    /// 正在用的定时不是固定的几档时，「自定义」那格亮着。
    public static func isCustom(_ minutes: Int) -> Bool {
        minutes > 0 && !AmbientTimer.choices.contains(minutes)
    }
}
