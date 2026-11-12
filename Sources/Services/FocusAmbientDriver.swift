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
/// 暂停、重置时停。开始约 1.5 秒淡入，停下约 0.8 秒淡出（`AudioFade`）。
///
/// 和环境音小组件共用一个 `AmbientPlayer`，和收音机小组件共用一个 `RadioPlayer`。
/// 只管自己放起来的声音：环境音小组件已经在放用户自己的组合、收音机正在放用户点的
/// 别的台时不去抢；专注中用户手动停了或换了，这一轮也不再放回来，停的时候也不碰
/// （电台的规则见 `FocusPlayback`）。专注计时每秒走一次 `sync`（见 `FocusCycleDriver`），
/// 面板上一按也马上走一次。
@MainActor
final class FocusAmbientDriver {
    static let shared = FocusAmbientDriver()

    /// 我们放起来的声音；nil 是现在没放，或这一轮让给了用户。
    private var started: AmbientSound?
    /// 这一轮用户接管了（手动停或换了组合），等专注停下再说。
    private var yielded = false
    private var volume: Int = FocusAmbient.defaultVolume
    /// 电台这一路自己放起来的、让没让给用户。
    private var radio = FocusPlayback()

    /// 每个布局里的小组件，读收音机的收藏用（启动时接上）。
    var widgets: () -> [WidgetInstance] = { [] }

    private init() {}

    /// 所有收音机小组件收藏的台，专注计时面板的「收音机收藏」一组。
    func radioFavourites() -> [RadioStation] {
        FocusRadio.favourites(widgets().filter { $0.kind == .radio }.map(\.config))
    }

    func sync(_ state: TimerState, now: Date = .now) {
        syncRadio(state, now: now)
        let player = AmbientPlayer.shared
        let wanted = FocusAmbient.wanted(state, now: now)
        let level = FocusAmbient.clampVolume(state.ambientVolume)
        guard let wanted else {
            if let started, player.isPlaying, player.sounds == [started] { player.stop(fadingOut: AudioFade.fadeOut) }
            started = nil
            yielded = false
            return
        }
        if yielded { return }
        if let started {
            guard player.isPlaying, player.sounds == [started] else {
                // 用户手动停了或换了别的组合：这一轮不再管。
                self.started = nil
                yielded = true
                return
            }
            if started != wanted || level != volume {
                player.apply(sounds: [wanted], volume: Double(level))
                self.started = wanted
                volume = level
            }
            return
        }
        // 环境音小组件正在放用户自己的组合，不去抢。
        if player.isPlaying {
            yielded = true
            return
        }
        player.play(sounds: [wanted], volume: Double(level), fadeIn: AudioFade.fadeIn)
        if player.isPlaying {
            started = wanted
            volume = level
        } else {
            // 声音设备起不来：这一轮不再每秒重试。
            yielded = true
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
