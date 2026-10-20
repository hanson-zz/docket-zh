import Foundation

/// 倒计时管“几分钟内”的事：泡面、晾衣服、等会议。卡片和面板只负责画，
/// 现在处在哪一步、还剩多少、到点后要不要晃和响，都由这里算。
///
/// 配置里的键：
/// - `duration`：这次（也是上次）的时长，秒。
/// - `deadline`：正在跑时的结束时刻（epoch）。到点后不清掉，留着表示“时间到，
///   还没人点停”，点一下停才清掉。
/// - `paused`：暂停时还剩的秒数；有它就是暂停，`deadline` 同时清掉。
/// - `presets`：卡片上的三个预设，分钟，面板里能改。没设时是 3、5、10。
/// - `sound`：到点响不响提示音。
public enum CountdownRun {
    public static let presetsKey = "presets"
    public static let soundKey = "sound"
    /// 卡片上放三个预设。
    public static let defaultPresets = [3, 5, 10]
    public static let presetCount = 3
    /// 倒计时只管几分钟到几小时以内，一个预设最长 4 小时，几天以上交给纪念日。
    public static let presetRange = 1...240
    /// 到点后卡片晃多久、提示音响多久（秒）。之后静止地停在“时间到”，等人点。
    public static let shakeSeconds: TimeInterval = 60
    public static let chimeSeconds = 30
    /// 每隔几秒响一下。
    public static let chimeEvery = 4

    public enum Phase: Equatable, Sendable {
        /// 没开始：卡片上是三个预设。
        case idle
        /// 正在跑，还剩 `left` 秒，`fraction` 是已经走过的比例（进度条）。
        case running(left: TimeInterval, fraction: Double)
        /// 暂停，还剩 `left` 秒。
        case paused(left: TimeInterval, fraction: Double)
        /// 时间到了，已经过了 `since` 秒，还没人点停。
        case ringing(since: TimeInterval)
    }

    public static func duration(_ config: WidgetConfig) -> TimeInterval {
        max(0, config.double("duration", default: 300))
    }

    public static func phase(_ config: WidgetConfig, now: Date) -> Phase {
        let total = max(1, duration(config))
        if config["paused"] != nil {
            let left = max(0, min(config.double("paused"), total))
            return .paused(left: left, fraction: 1 - left / total)
        }
        guard config["deadline"] != nil else { return .idle }
        let deadline = config.double("deadline")
        let left = deadline - now.timeIntervalSince1970
        if left <= 0 { return .ringing(since: -left) }
        let clamped = min(left, total)
        return .running(left: clamped, fraction: min(1, max(0, 1 - clamped / total)))
    }

    /// 卡片上的三个预设，分钟。存的可以是 "5" 或 "5 分钟"，读开头的数字；
    /// 不够三个时用默认的补齐，重复的去掉。
    public static func presets(_ config: WidgetConfig) -> [Int] {
        var picked: [Int] = []
        for raw in config.strings(presetsKey) {
            guard let minutes = Int(raw.trimmingCharacters(in: .whitespaces).prefix(while: \.isNumber)),
                  presetRange.contains(minutes), !picked.contains(minutes) else { continue }
            picked.append(minutes)
            if picked.count == presetCount { break }
        }
        for fallback in defaultPresets where picked.count < presetCount && !picked.contains(fallback) {
            picked.append(fallback)
        }
        return picked
    }

    /// 改第 `index` 个预设后的整组，夹在 1 到 240 分钟之间。
    public static func settingPreset(_ index: Int, to minutes: Int, in config: WidgetConfig) -> [Int] {
        var list = presets(config)
        guard list.indices.contains(index) else { return list }
        list[index] = min(presetRange.upperBound, max(presetRange.lowerBound, minutes))
        return list
    }

    /// 哪个预设是上次用的（高亮）。上次的时长不在预设里时没有高亮。
    public static func lastPresetIndex(_ config: WidgetConfig) -> Int? {
        let minutes = Int((duration(config) / 60).rounded())
        return presets(config).firstIndex(of: minutes)
    }

    /// 到点后卡片还晃不晃。打开“减少动态效果”时卡片不晃，只变色。
    public static func shakes(_ phase: Phase, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, case .ringing(let since) = phase else { return false }
        return since < shakeSeconds
    }

    /// 到点后的第几段：每 4 秒一段，段数一变就响一下；过了 30 秒是 nil，不再响。
    /// 按段而不是按“第 0、4、8 秒”判断，卡片哪一秒没刷新也不会漏掉一声。
    public static func chimeBucket(since: TimeInterval) -> Int? {
        guard since >= 0, since <= TimeInterval(chimeSeconds) else { return nil }
        return Int(since) / chimeEvery
    }

    /// “泡面 · 共 3 分钟”，没起名字时是“共 3 分钟”。
    public static func runningCaption(name: String, duration: TimeInterval) -> String {
        let length = lengthText(duration)
        return name.isEmpty ? tr("共 \(length)") : tr("\(name) · 共 \(length)")
    }

    /// “3 分钟”“1 小时 30 分”。
    public static func lengthText(_ duration: TimeInterval) -> String {
        let minutes = max(1, Int((duration / 60).rounded()))
        if minutes < 60 { return tr("\(minutes) 分钟") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("\(h) 小时") : tr("\(h) 小时 \(m) 分")
    }

    // MARK: 面板

    /// 面板“快速开始”里放几个时长。
    public static let quickCount = 8
    /// 常用时长（分钟），按先后补进快速开始：卡片上的三个预设之外从这里补。
    public static let commonMinutes = [1, 15, 25, 30, 60, 45, 20, 90, 120, 3, 5, 10]

    /// 面板“快速开始”的八个时长，从短到长：卡片上的三个预设一定在里面，
    /// 其余从常用时长里按先后补齐。
    public static func quickMinutes(_ config: WidgetConfig) -> [Int] {
        var picked = presets(config)
        for minutes in commonMinutes where picked.count < quickCount && !picked.contains(minutes) {
            picked.append(minutes)
        }
        return picked.sorted()
    }

    /// 自定义时长的档位：10 分钟以内一分钟一档，60 分钟以内五分钟一档，再往上十五分钟一档，最长 240。
    public static let customLadder: [Int] = Array(1...10) + Array(stride(from: 15, through: 60, by: 5))
        + Array(stride(from: 75, through: 240, by: 15))

    /// 自定义时长加减一档；不在档位上的先落到最近的一档。
    public static func stepping(_ minutes: Int, up: Bool) -> Int {
        if up { return customLadder.first { $0 > minutes } ?? presetRange.upperBound }
        return customLadder.last { $0 < minutes } ?? presetRange.lowerBound
    }

    /// 加时间（“+1 分钟”）：跑着的往后推结束时刻，暂停的加剩下的，
    /// 已经到点的从现在起再计这么久；时长一起加，进度条不会倒退一截。
    /// 没开始时不动。
    public static func adding(_ seconds: TimeInterval, to config: inout WidgetConfig, now: Date) {
        guard seconds > 0 else { return }
        switch phase(config, now: now) {
        case .idle:
            return
        case .running(let left, _):
            config.set("duration", .number(duration(config) + seconds))
            config.set("deadline", .number(now.timeIntervalSince1970 + left + seconds))
        case .paused(let left, _):
            config.set("duration", .number(duration(config) + seconds))
            config.set("paused", .number(left + seconds))
        case .ringing:
            config.set("duration", .number(seconds))
            config.set("paused", nil)
            config.set("deadline", .number(now.timeIntervalSince1970 + seconds))
        }
    }

    /// 面板头上的状态：“进行中”“已暂停”“时间到”，没开始时是 nil。
    public static func stateText(_ phase: Phase) -> String? {
        switch phase {
        case .idle: nil
        case .running: tr("进行中")
        case .paused: tr("已暂停")
        case .ringing: tr("时间到")
        }
    }

    /// 环里的大数字：一小时以内“02:47”，以上“1:02:47”。往上取整，
    /// 免得刚开始那一秒就少了一秒。
    public static func remainingText(_ left: TimeInterval) -> String {
        let total = Int(max(0, left).rounded(.up))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 预设按钮上的字：“3 分”“90 分”。
    public static func presetLabel(_ minutes: Int) -> String {
        tr("\(minutes) 分")
    }
}
