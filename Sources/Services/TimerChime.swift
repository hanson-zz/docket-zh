import AppKit
import Foundation

/// 计时类小组件到点时的提示音：倒计时到了、闹钟在响、专注或休息结束。
///
/// 用系统自带的提示音，和“声音”设置里选的提示音无关，也不受“播放用户界面
/// 音效”开关影响：这是到点提醒，不是界面音效。每种声音只建一次。
@MainActor
enum TimerChime {
    enum Kind {
        case countdown, alarm, focus, posture

        var soundName: String {
            switch self {
            case .countdown: "Glass"
            case .alarm: "Sosumi"
            case .focus: "Hero"
            case .posture: "Purr"
            }
        }
    }

    private static var cache: [String: NSSound] = [:]

    static func play(_ kind: Kind) {
        let name = kind.soundName
        let sound: NSSound?
        if let cached = cache[name] {
            sound = cached
        } else {
            // `NSSound(named:)` 给的是共用的一份，复制一份免得和别处抢。
            sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound
            if let sound { cache[name] = sound }
        }
        guard let sound else { NSSound.beep(); return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}

/// 专注计时一个环节到点后接下一个：专注完自动开始休息，休息完回到专注等开始。
///
/// 从启动起每秒看一次，所以没有专注计时卡片在屏幕上时也照样走。到点先让
/// 专注记录和电子宠物把这一轮记上（它们只认“专注阶段、已到点”），再换环节，
/// 免得换得太快它们没看到。
@MainActor
final class FocusCycleDriver {
    static let shared = FocusCycleDriver()

    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { FocusCycleDriver.shared.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func tick(now: Date = .now) {
        let provider = TimerStateProvider.shared
        let state = provider.state
        guard let next = FocusCycle.advanced(state, now: now) else { return }
        if state.phase == .focus {
            FocusLogStore.shared.check(now: now)
            PetFocusWatcher.shared.check(now: now)
        }
        let stale = now.timeIntervalSince(state.deadline ?? now) > FocusCycle.staleAfter
        provider.state = next
        // 合盖很久回来的不响，只有刚到点的才提醒。
        if state.alerts, !stale, now.timeIntervalSince(state.deadline ?? now) < 60 {
            TimerChime.play(.focus)
        }
    }
}
