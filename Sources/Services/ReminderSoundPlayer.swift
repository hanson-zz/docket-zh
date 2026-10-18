import AppKit
import CoreGraphics
import Foundation

/// 提醒事项、喝水、待办到点时那一声。
///
/// 统一音效开关和音量来自设置 ▸ 扩展栏 ▸ 音效，三类各自的音色来自其下的
/// “提醒音效”。勿扰/专注模式和屏幕共享时不响（判断得了的话，见
/// `ReminderSoundDecision`）；短时间里连着到点的几条只响一声。和
/// “播放用户界面音效”开关无关：这是到点提醒，不是界面音效，和 `TimerChime`
/// 一样。
@MainActor
final class ReminderSoundPlayer {
    static let shared = ReminderSoundPlayer()

    private(set) var master = WidgetSoundSettings()
    private(set) var settings = ReminderSoundSettings()
    private var gate = ReminderSoundGate()
    private var cache: [String: NSSound] = [:]

    private init() {}

    /// AppState 启动和设置变化时调用。
    func configure(master: WidgetSoundSettings, reminders: ReminderSoundSettings) {
        self.master = master
        settings = reminders
    }

    /// 某一类提醒到点了。返回真是真的响了。
    @discardableResult
    func play(_ kind: ReminderSoundKind, now: Date = .now) -> Bool {
        guard let tone = ReminderSoundDecision.toneToPlay(for: kind, settings: settings, master: master,
                                                          environment: Self.environment()),
              gate.allow(at: now)
        else { return false }
        start(tone)
        return true
    }

    /// 本应用的系统通知要不要带系统提示音（应用退出时系统按这个响）。
    func notificationHasSound(_ kind: ReminderSoundKind) -> Bool {
        ReminderSoundDecision.notificationHasSound(kind, settings: settings, master: master)
    }

    /// 试听：不看开关、勿扰和合并，只用统一音量。
    func preview(_ tone: ReminderTone, volume: Float) {
        guard tone != .off else { return }
        start(tone, volume: volume)
    }

    // MARK: 外部情况

    static func environment() -> ReminderSoundEnvironment {
        ReminderSoundEnvironment(focusActive: focusActive(), screenShared: screenShared())
    }

    /// 专注模式没有公开接口。这个文件要“完全磁盘访问权限”才读得到，读不到时
    /// 判断不了，照常响。
    private static func focusActive() -> Bool? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        return ReminderSoundDecision.focusActive(assertionsJSON: try? Data(contentsOf: url))
    }

    private static func screenShared() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return ReminderSoundDecision.screenShared(sessionValue: session["CGSSessionScreenIsShared"])
    }

    // MARK: 播放

    private func start(_ tone: ReminderTone, volume: Float? = nil) {
        guard let sound = sound(tone) else { NSSound.beep(); return }
        if sound.isPlaying { sound.stop() }
        sound.volume = volume ?? master.gain
        sound.play()
    }

    private func sound(_ tone: ReminderTone) -> NSSound? {
        for name in tone.fallbacks {
            if let cached = cache[name] { return cached }
            // `NSSound(named:)` 给的是共用的一份，复制一份免得音量影响别处。
            if let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound {
                cache[name] = sound
                return sound
            }
        }
        return nil
    }
}
