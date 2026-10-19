import AVFoundation
import Foundation

/// 解锁动画的音效：Resources/Unlock 里合成的 WAV，弹窗出现前用 AVAudioPlayer 预加载，
/// 按 `ProUnlockSoundSchedule` 排好的时刻播放。设置 ▸ 码头 Pro 的“解锁动画音效”关掉时不响。
///
/// 同一个文件可能同时响两次（左右两发烟花、标签的“叮”和点熊猫），所以每个文件
/// 备两个播放器轮着用，各自设置声像。
@MainActor
final class ProUnlockSoundPlayer {
    static let shared = ProUnlockSoundPlayer()

    private var players: [String: [AVAudioPlayer]] = [:]
    private var turn: [String: Int] = [:]
    private var pending: [Task<Void, Never>] = []

    private init() {}

    static var isEnabled: Bool {
        ProUnlockFirstRun.soundEnabled(UserDefaults.standard.object(forKey: ProUnlockFirstRun.soundKey))
    }

    /// 读文件、准备好缓冲。重复调用不会重读。
    func preload() {
        for sound in ProUnlockSound.all where players[sound.fileName] == nil {
            guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: "wav") else { continue }
            let pair = (0..<2).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            pair.forEach { $0.prepareToPlay() }
            players[sound.fileName] = pair
        }
    }

    /// 按时刻表播放一串声音（从现在算起）。会先停掉上一串还没响的。
    func play(_ cues: [ProUnlockSoundCue]) {
        guard Self.isEnabled, !cues.isEmpty else { return }
        preload()
        cancel()
        for cue in cues {
            if cue.time <= 0 {
                fire(cue)
                continue
            }
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(cue.time))
                guard !Task.isCancelled else { return }
                self?.fire(cue)
            }
            pending.append(task)
        }
    }

    /// 在已排好的之外再加几声（点熊猫），不打断原来的时刻表。
    func add(_ cues: [ProUnlockSoundCue]) {
        guard Self.isEnabled else { return }
        preload()
        for cue in cues {
            pending.append(Task { @MainActor [weak self] in
                if cue.time > 0 { try? await Task.sleep(for: .seconds(cue.time)) }
                guard !Task.isCancelled else { return }
                self?.fire(cue)
            })
        }
    }

    /// 关弹窗时：还没响的不再响，正在响的停掉。
    func stop() {
        cancel()
        players.values.flatMap { $0 }.forEach { $0.stop() }
    }

    private func cancel() {
        pending.forEach { $0.cancel() }
        pending.removeAll()
    }

    private func fire(_ cue: ProUnlockSoundCue) {
        let name = cue.sound.fileName
        guard let pair = players[name], !pair.isEmpty else { return }
        let index = (turn[name] ?? 0) % pair.count
        turn[name] = index + 1
        let player = pair[index]
        player.stop()
        player.currentTime = 0
        player.pan = cue.pan
        player.volume = 0.9
        player.play()
    }
}
