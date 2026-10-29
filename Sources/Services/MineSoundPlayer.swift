import AVFoundation
import Foundation

/// 扫雷的音效：Resources/Mines 里 scripts/make-mines-sounds.py 合成的原创 WAV，第一次用时
/// 用 AVAudioPlayer 预加载。开不开声音看卡片配置（`Minesweeper.soundOn`），由 `MinePlay`
/// 判断后再调这里；和系统静音、「减少动态效果」无关（系统静音时系统自己会把声音压掉）。
///
/// 连点格子时同一个声音会叠着响，每个文件备三个播放器轮着用。音量适中：文件峰值已经
/// 按声音分好（揭开最轻），这里统一再乘 0.7。
@MainActor
final class MineSoundPlayer {
    static let shared = MineSoundPlayer()

    private static let volume: Float = 0.7
    private var players: [MineSound: [AVAudioPlayer]] = [:]
    private var turn: [MineSound: Int] = [:]

    private init() {}

    private func preload() {
        for sound in MineSound.allCases where players[sound] == nil {
            guard let url = Bundle.main.url(forResource: sound.fileName, withExtension: "wav") else { continue }
            let set = (0..<3).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            set.forEach { $0.prepareToPlay() }
            players[sound] = set
        }
    }

    func play(_ sound: MineSound) {
        preload()
        guard let set = players[sound], !set.isEmpty else { return }
        let index = (turn[sound] ?? 0) % set.count
        turn[sound] = index + 1
        let player = set[index]
        player.stop()
        player.currentTime = 0
        player.volume = Self.volume
        player.play()
    }
}
