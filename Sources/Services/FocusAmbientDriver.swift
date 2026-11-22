import Foundation
import Observation

/// 专注计时的番茄段（今天时间轴用），全应用一份，存在 UserDefaults，格式见 `FocusDay`。
/// 一轮专注完整结束时由 `FocusLogStore.check` 记一段。
@MainActor @Observable
final class FocusSessionStore {
    static let shared = FocusSessionStore()
    nonisolated static let key = "docket.focus.segments"

    private(set) var lines: [String]

    private init() {
        lines = FocusDay.pruned(UserDefaults.standard.stringArray(forKey: Self.key) ?? [], now: .now)
    }

    func record(seconds: TimeInterval, endedAt: Date, task: String) {
        let next = FocusDay.adding(seconds: seconds, endedAt: endedAt, task: task, to: lines)
        guard next != lines else { return }
        lines = next
        UserDefaults.standard.set(next, forKey: Self.key)
    }

    /// 小组件库里的示例：今天上午四个番茄，和效果图一样。
    static func sample(today: Date) -> [String] {
        let day = Calendar.current.startOfDay(for: today)
        func at(_ hours: Double) -> Date { day.addingTimeInterval(hours * 3600) }
        let blocks: [(Double, Double)] = [(8.6, 9.02), (9.1, 9.52), (9.62, 10.04)]
        return blocks.map { FocusDay.line(FocusDay.Segment(start: at($0.0), end: at($0.1), task: tr("写第二批面板说明"))) }
    }
}

/// 开始专注自动放环境音（或收音机收藏里选的一个台），休息时（开着“休息时声音停下”）、
/// 暂停、重置时停。环境音开始约 1.5 秒淡入，停下约 1.5 秒淡出（`AmbientFade`）。
///
/// 和环境音小组件共用一个 `AmbientPlayer`，和收音机小组件共用一个 `RadioPlayer`。
/// 只管自己放起来的声音（`AmbientOwner.focus`）：环境音小组件已经在放用户自己的组合、
/// 收音机正在放用户点的别的台时不去抢；专注中用户手动停了或换了，这一轮也不再放回来，
/// 停的时候也不碰；声音设备起不来时这一轮不再每秒重试。这三种让开的原因见
/// `FocusAmbientSkip`，专注面板上用一行小字说明；用户在专注面板里改选别的声音算明确要放，
/// 让开作废（规则见 `FocusAmbientRound`，电台的规则见 `FocusPlayback`）。
/// 专注计时每秒走一次 `sync`（见 `FocusCycleDriver`），面板上一按也马上走一次。
@MainActor
final class FocusAmbientDriver {
    static let shared = FocusAmbientDriver()

    private var round = FocusAmbientRound()
    /// 电台这一路自己放起来的、让没让给用户。
    private var radio = FocusPlayback()

    /// 每个布局里的小组件，读收音机的收藏用（启动时接上）。
    var widgets: () -> [WidgetInstance] = { [] }

    private init() {}

    /// 这一轮环境音让开的原因，专注面板那一行小字用。
    var skip: FocusAmbientSkip? { round.skip }

    /// 选的环境音正由专注放着。
    var isPlayingOurs: Bool {
        let player = AmbientPlayer.shared
        return round.playing != nil && player.isPlaying && player.owner == .focus
    }

    /// 所有收音机小组件收藏的台，专注计时面板的「收音机收藏」一组。
    func radioFavourites() -> [RadioStation] {
        FocusRadio.favourites(widgets().filter { $0.kind == .radio }.map(\.config))
    }

    /// 专注面板里选了一种声音：专注没在放时试听几秒（专注在放时 `sync` 会直接换过去）。
    func audition(_ state: TimerState, now: Date = .now) {
        // 这一轮声音设备起不来让开了：再点一次声音（哪怕是同一种，`update` 不会触发 `sync`）就马上重试。
        if round.skip == .audioFailed {
            round.retryAfterFailure()
            sync(state, now: now)
        }
        guard let sound = FocusAmbient.sound(state) else {
            AmbientPlayer.shared.endPreview()
            return
        }
        guard FocusAmbient.wanted(state, now: now) == nil else { return }
        AmbientPlayer.shared.preview(sound, volume: Double(FocusAmbient.clampVolume(state.ambientVolume)))
    }

    func sync(_ state: TimerState, now: Date = .now) {
        syncRadio(state, now: now)
        let player = AmbientPlayer.shared
        let wanted = FocusAmbient.wanted(state, now: now)
        let level = FocusAmbient.clampVolume(state.ambientVolume)
        let ours = player.isPlaying && player.owner == .focus && round.playing.map { player.sounds == [$0] } == true
        let blocked = AmbientOwner.blocksFocus(owner: player.owner, playing: player.isPlaying)
        switch round.step(wanted: wanted, choice: state.ambient, level: level, ours: ours, blocked: blocked) {
        case .none:
            break
        case .stop:
            player.stop(fadingOut: AmbientFade.fadeOut)
        case .retune(let sound, let volume):
            player.apply(sounds: [sound], volume: Double(volume), owner: .focus)
        case .start(let sound):
            player.play(sounds: [sound], volume: Double(level), fadeIn: AmbientFade.fadeIn, owner: .focus)
            if player.isPlaying, player.owner == .focus {
                round.started(sound, volume: level)
            } else {
                // 声音设备起不来：这一轮不再每秒重试。
                round.failed(choice: state.ambient)
            }
        }
    }

    /// 选的是收音机收藏里的台：和环境音一样的时机放、停，每台的音量按台记住（没记过用面板音量）。
    private func syncRadio(_ state: TimerState, now: Date) {
        let player = RadioPlayer.shared
        // 先不读收藏看该不该放，不该放时不必每秒翻一遍所有小组件。
        var wanted = FocusRadio.wanted(state, now: now)
        if wanted != nil { wanted = FocusRadio.wanted(state, now: now, favourites: radioFavourites()) }
        let playing = player.isPlaying ? player.station?.id : nil
        switch radio.step(wanted: wanted?.id, playing: playing) {
        case .none:
            break
        case .stop:
            player.stop()
        case .start, .switchTo:
            guard let wanted else { return }
            player.play(wanted, volume: Double(FocusAmbient.clampVolume(state.ambientVolume)))
            // 地址不对放不起来：这一轮不再每秒重试。
            if !player.isPlaying { radio.failed() }
        }
    }
}
