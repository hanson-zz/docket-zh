import AppKit
import Foundation
@preconcurrency import UserNotifications

/// 专注计时一个环节到点：按面板设置里选的系统声音响（专注结束、休息结束各一种，可以
/// 连响几次，隔 0.9 秒，离开电脑一会儿也听得到；选「不响」就不响），再发一条本机通知。
/// 通知自己不带声音，免得和提示音叠在一起。声音只用 /System/Library/Sounds 里的。
@MainActor
enum FocusEndAlert {
    private static var cache: [String: NSSound] = [:]
    private static var asked = false

    static func ring(ended: TimerState, next: TimerState) {
        play(FocusEndSound.ending(ended), times: FocusEndSound.repeats(ended))
        if ended.notifyEnd {
            let title = FocusEndNotice.title(ended: ended)
            let body = FocusEndNotice.body(ended: ended, next: next)
            Task { await FocusEndAlert.notify(title: title, body: body) }
        }
    }

    /// 试听和到点都走这里。
    static func play(_ name: String, times: Int = 1) {
        guard name != FocusEndSound.none else { return }
        for index in 0..<max(1, times) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.9) {
                MainActor.assumeIsolated { FocusEndAlert.playOnce(name) }
            }
        }
    }

    private static func playOnce(_ name: String) {
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

    private static func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = BannerPresenter.shared }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(identifier: "docket.focus." + UUID().uuidString,
                                            content: content, trigger: nil)
        try? await center.add(request)
    }
}
