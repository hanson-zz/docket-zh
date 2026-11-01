import AVFoundation
import Foundation

// 打字音效的播放：AVAudioEngine 加一池播放节点，声音预先解码成内存里的 buffer，按键时
// 只是挑一个 buffer 排到空闲的节点上，几十微秒的事。所有引擎操作都在自己的串行队列上做，
// 不碰主线程；键盘监听线程只往队列里丢一个小任务就回去。
//
// 判断（响哪一类、哪个变体、连发和安全输入、导入包的哪一段）都在 Core 的 TypingSounds.swift。

/// 一套解码好的声音。只在 `TypingSoundEngine` 的队列里读写。
struct TypingSoundBank: @unchecked Sendable {
    /// 内置款：每一类的若干变体。
    var styled: [TypingSoundKey: [AVAudioPCMBuffer]] = [:]
    /// 导入包：每一段一份 buffer。
    var pack: MechvibesPack?
    var segments: [MechvibesPack.Segment: AVAudioPCMBuffer] = [:]
    /// 音高随机范围（音分）。
    var pitchSpread: Double = 40

    var isEmpty: Bool { styled.isEmpty && segments.isEmpty }
}

/// 解码：任何 Core Audio 认识的文件 → 引擎用的格式（44.1 kHz 单声道 Float32）。
enum TypingSoundDecoder {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    enum Failure: Error {
        case unreadable(String)
        case tooLong(String)
    }

    /// 整个文件解进来（最长 `TypingSoundPacks.maxFileSeconds` 秒）。ogg、flac 这类本机不一定
    /// 解得开，解不开时抛 `unreadable`，导入时据此提示。
    static func decode(_ url: URL) throws -> AVAudioPCMBuffer {
        let name = url.lastPathComponent
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw Failure.unreadable(name) }
        let source = file.processingFormat
        guard source.sampleRate > 0, file.length > 0 else { throw Failure.unreadable(name) }
        guard Double(file.length) / source.sampleRate <= TypingSoundPacks.maxFileSeconds else {
            throw Failure.tooLong(name)
        }
        guard let raw = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw Failure.unreadable(name)
        }
        do { try file.read(into: raw) } catch { throw Failure.unreadable(name) }
        return try convert(raw, name: name)
    }

    static func convert(_ input: AVAudioPCMBuffer, name: String) throws -> AVAudioPCMBuffer {
        if input.format == format { return input }
        guard let converter = AVAudioConverter(from: input.format, to: format) else { throw Failure.unreadable(name) }
        converter.downmix = true
        let ratio = format.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw Failure.unreadable(name)
        }
        let feed = OneShotFeed(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            guard let buffer = feed.take() else {
                outStatus.pointee = .endOfStream
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { throw Failure.unreadable(name) }
        return output
    }

    /// 从一整段里切出 [start, end) 毫秒，最长 `maxSegmentSeconds` 秒，尾巴淡出 4 ms 免得“啪”一声。
    static func slice(_ buffer: AVAudioPCMBuffer, startMs: Double?, endMs: Double?) -> AVAudioPCMBuffer? {
        let rate = buffer.format.sampleRate
        let total = Int(buffer.frameLength)
        let start = max(0, min(total, Int(((startMs ?? 0) / 1000 * rate).rounded())))
        var end = endMs.map { Int(($0 / 1000 * rate).rounded()) } ?? total
        end = min(total, end, start + Int(TypingSoundPacks.maxSegmentSeconds * rate))
        let count = end - start
        guard count > 16, let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(count)),
              let src = buffer.floatChannelData, let dst = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(count)
        let fade = min(count, Int(0.004 * rate))
        for channel in 0..<Int(buffer.format.channelCount) {
            let from = src[channel] + start
            let to = dst[channel]
            to.update(from: from, count: count)
            for i in 0..<fade {
                to[count - 1 - i] *= Float(i) / Float(fade)
            }
        }
        return out
    }
}

/// 给 AVAudioConverter 喂一次整段输入，第二次要时说“没了”。只在一次 convert 调用里用。
private final class OneShotFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// 打字音效的播放器。所有可变状态只在 `queue` 上碰。
final class TypingSoundEngine: @unchecked Sendable {
    static let shared = TypingSoundEngine()

    /// 节点池大小：快速打字时上一声还没放完，换一个节点放，不打断它。
    private static let voiceCount = 8
    /// 多久没出声就暂停引擎（放开音频设备，不白占 CPU）。下一次按键再开，第一声可能晚一点点。
    private static let idlePause: TimeInterval = 12

    private let queue = DispatchQueue(label: "dockling.typing-sounds", qos: .userInteractive)

    private var engine: AVAudioEngine?
    private var voices: [(player: AVAudioPlayerNode, pitch: AVAudioUnitVarispeed)] = []
    private var nextVoice = 0
    private var bank = TypingSoundBank()
    private var loadedKey: String?
    private var volume: Float = Float(TypingSoundSettings.defaultVolume)
    private var throttle = TypingSoundThrottle()
    private var picker = TypingSoundVariantPicker()
    private var idleTimer: DispatchSourceTimer?
    private var lastSound = DispatchTime.now()
    private var configObserver: NSObjectProtocol?
    private var broken = false

    private init() {}

    // MARK: 设置

    /// 换款式或音量。款式没变不重新解码。`packFolder` 是导入包的文件夹（内置款为 nil）。
    func configure(choice: TypingSoundChoice, packFolder: URL?, volume: Double) {
        queue.async { [self] in
            self.volume = Float(min(1, max(0, volume)))
            engine?.mainMixerNode.outputVolume = self.volume
            let key = choice.raw + "|" + (packFolder?.path ?? "")
            guard key != loadedKey else { return }
            bank = Self.load(choice: choice, packFolder: packFolder)
            loadedKey = key
            picker = TypingSoundVariantPicker()
        }
    }

    /// 停掉引擎、放掉声音（关掉打字音效、App 退出时）。同步做完，退出时不留尾巴。
    func shutdown() {
        queue.sync { [self] in
            teardownEngine()
            bank = TypingSoundBank()
            loadedKey = nil
        }
    }

    // MARK: 按键

    /// 键盘监听线程调这里：只排个任务，判断和播放在队列上做。
    func keyDown(keyCode: Int, isRepeat: Bool, secureInput: Bool) {
        let now = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        queue.async { [self] in
            guard throttle.admit(isRepeat: isRepeat, secureInput: secureInput, now: now) else { return }
            play(keyCode: keyCode)
        }
    }

    /// 试听：一串字、空格、删除、回车，按设置里选的那一款（没开总开关也能听）。
    func preview(choice: TypingSoundChoice, packFolder: URL?, volume: Double) {
        configure(choice: choice, packFolder: packFolder, volume: volume)
        // T y p i n g ␣ s o ⌫ u n d ⏎（键码）
        let script: [(Int, Double)] = [
            (17, 0), (16, 0.13), (35, 0.24), (34, 0.38), (45, 0.49), (5, 0.6), (49, 0.76), (1, 0.92),
            (31, 1.04), (51, 1.22), (32, 1.4), (45, 1.52), (2, 1.63), (36, 1.86),
        ]
        for (code, delay) in script {
            queue.asyncAfter(deadline: .now() + delay) { [self] in
                play(keyCode: code)
            }
        }
    }

    private func play(keyCode: Int) {
        guard !bank.isEmpty, let buffer = buffer(for: keyCode) else { return }
        guard ensureEngine() else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.pitch.rate = TypingSoundVariantPicker.rate(spread: bank.pitchSpread, random: Double.random(in: 0..<1))
        voice.player.volume = TypingSoundVariantPicker.gain(random: Double.random(in: 0..<1))
        voice.player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.player.isPlaying { voice.player.play() }
        lastSound = .now()
    }

    private func buffer(for keyCode: Int) -> AVAudioPCMBuffer? {
        if let pack = bank.pack {
            guard let segment = pack.segment(keyCode: keyCode, random: Double.random(in: 0..<1)) else { return nil }
            return bank.segments[segment]
        }
        guard let key = TypingSoundKey.of(keyCode: keyCode),
              let set = bank.styled[key] ?? bank.styled[.key], !set.isEmpty else { return nil }
        let index = picker.next(key.rawValue, count: set.count, random: Double.random(in: 0..<1))
        return set[index]
    }

    // MARK: 引擎

    /// 引擎在跑就直接用；没建就建，暂停了就再开。开不了（没有输出设备）就这一声不响，安静失败。
    private func ensureEngine() -> Bool {
        if let engine, engine.isRunning { return true }
        if engine == nil { buildEngine() }
        guard let engine else { return false }
        do {
            try engine.start()
            broken = false
            scheduleIdleCheck()
            return true
        } catch {
            broken = true
            return false
        }
    }

    private func buildEngine() {
        let engine = AVAudioEngine()
        let format = TypingSoundDecoder.format
        var built: [(AVAudioPlayerNode, AVAudioUnitVarispeed)] = []
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            let pitch = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: format)
            engine.connect(pitch, to: engine.mainMixerNode, format: format)
            built.append((player, pitch))
        }
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        self.engine = engine
        voices = built.map { (player: $0.0, pitch: $0.1) }
        nextVoice = 0
        // 换了输出设备（插拔耳机、蓝牙断开）时引擎会自己停：下一声按需重开。
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.voices.forEach { $0.player.stop() } }
        }
    }

    private func teardownEngine() {
        idleTimer?.cancel()
        idleTimer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        voices.forEach { $0.player.stop() }
        engine?.stop()
        if let engine {
            for voice in voices {
                engine.detach(voice.player)
                engine.detach(voice.pitch)
            }
        }
        voices = []
        engine = nil
    }

    /// 一段时间没出声就暂停引擎。
    private func scheduleIdleCheck() {
        guard idleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.idlePause, repeating: Self.idlePause / 2)
        timer.setEventHandler { [weak self] in
            guard let self, let engine = self.engine else { return }
            let idle = Double(DispatchTime.now().uptimeNanoseconds &- self.lastSound.uptimeNanoseconds) / 1e9
            guard idle >= Self.idlePause else { return }
            self.voices.forEach { $0.player.stop() }
            engine.pause()
            self.idleTimer?.cancel()
            self.idleTimer = nil
        }
        idleTimer = timer
        timer.resume()
    }

    // MARK: 解码

    private static func load(choice: TypingSoundChoice, packFolder: URL?) -> TypingSoundBank {
        switch choice {
        case .style(let style):
            return loadStyle(style)
        case .pack:
            guard let packFolder, let bank = try? loadPack(at: packFolder) else { return loadStyle(.free) }
            return bank
        }
    }

    /// 内置款：Resources/TypingSounds/typing-<款>-<键>.wav。缺文件的那一类退回普通键。
    static func loadStyle(_ style: TypingSoundStyle) -> TypingSoundBank {
        var bank = TypingSoundBank()
        bank.pitchSpread = style.pitchSpread
        for key in TypingSoundKey.allCases {
            let buffers = key.fileKeys.compactMap { name -> AVAudioPCMBuffer? in
                guard let url = Bundle.main.url(forResource: style.fileName(name), withExtension: "wav") else {
                    return nil
                }
                return try? TypingSoundDecoder.decode(url)
            }
            if !buffers.isEmpty { bank.styled[key] = buffers }
        }
        return bank
    }

    /// 导入包：读 config.json，解每个用到的文件，按段切好。整个文件解完就丢，只留切出来的小段。
    static func loadPack(at folder: URL) throws -> TypingSoundBank {
        let data = try Data(contentsOf: folder.appending(path: "config.json"))
        let pack = try MechvibesPack.parse(data)
        var bank = TypingSoundBank()
        bank.pack = pack
        bank.pitchSpread = 25
        let byFile = Dictionary(grouping: Set(pack.definitions.values), by: \.file)
        for (file, segments) in byFile {
            guard let whole = try? TypingSoundDecoder.decode(folder.appending(path: file)) else { continue }
            for segment in segments {
                if let piece = TypingSoundDecoder.slice(whole, startMs: segment.start, endMs: segment.end) {
                    bank.segments[segment] = piece
                }
            }
        }
        guard !bank.segments.isEmpty else { throw TypingSoundDecoder.Failure.unreadable(folder.lastPathComponent) }
        return bank
    }
}
