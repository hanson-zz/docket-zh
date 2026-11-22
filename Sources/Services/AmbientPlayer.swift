import AVFoundation
import Foundation
import Observation
import os

/// Plays the ambient widget's mix through the default output.
///
/// One player for the whole app: two ambient widgets on two layouts are two
/// remotes for the same speaker, not two streams fighting over it. The sound
/// itself comes from `AmbientSynth`, run inside an `AVAudioSourceNode`, so
/// there are no audio files and nothing to loop.
@MainActor @Observable
final class AmbientPlayer {
    static let shared = AmbientPlayer()

    private(set) var isPlaying = false
    /// When the sleep timer stops playback, or nil when it is off.
    private(set) var stopAt: Date?
    /// The sleep timer's length in minutes, 0 when off; kept so the panel can
    /// show which choice is active.
    private(set) var timerMinutes = 0
    /// What is playing, for the tile's caption.
    private(set) var sounds: [AmbientSound] = []
    /// Each sound's own level (see `AmbientLevels`), under the master volume.
    private(set) var levels: [AmbientSound: Int] = [:]
    /// 现在的声音是谁放起来的：环境音小组件、专注计时，还是专注面板里的试听。
    private(set) var owner: AmbientOwner = .widget

    @ObservationIgnored private var volume: Double = 60
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var elapsed: Double = 0
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let box = SynthBox()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var configObserver: NSObjectProtocol?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    private init() {}

    // MARK: Controls

    /// The widget's stored mix and volume, applied whether or not it plays.
    ///
    /// 小组件里用户改了声音或音量（`owner` 是 `.widget`）时，正在放的专注或试听也换成
    /// 用户的组合，算用户接管；专注驱动换声音、调音量时传 `.focus`。
    func apply(sounds: [AmbientSound], levels: [AmbientSound: Int] = [:], volume: Double,
               owner: AmbientOwner = .widget) {
        if isPlaying, owner == .widget, self.owner != .widget {
            previewTask?.cancel()
            previewTask = nil
            self.owner = .widget
        }
        self.sounds = sounds
        self.levels = levels
        self.volume = volume
        let playing = isPlaying
        box.update { synth in
            synth.setVolume(volume / 100)
            if playing { synth.setSounds(sounds, levels: levels) }
        }
        if playing, sounds.isEmpty { stop() }
        else if playing { publishSession() }
    }

    /// 小组件出现在屏幕上时同步自己存的组合。正在放专注或试听的声音时什么也不改，
    /// 见 `AmbientOwner.primeChangesPlayback`。
    func prime(sounds: [AmbientSound], levels: [AmbientSound: Int] = [:], volume: Double) {
        guard AmbientOwner.primeChangesPlayback(owner: owner, playing: isPlaying) else { return }
        apply(sounds: sounds, levels: levels, volume: volume)
    }

    func toggle(sounds: [AmbientSound], levels: [AmbientSound: Int] = [:], volume: Double) {
        isPlaying ? pause() : play(sounds: sounds, levels: levels, volume: volume)
    }

    /// 整体淡入 `fadeIn` 秒（默认 `AmbientFade.fadeIn`）：淡出途中再播放从当时的
    /// 音量往回升，不先掉到 0。`owner` 记下是谁放的；试听不接管系统的「正在播放」，
    /// 定时关闭只管小组件自己放的。
    func play(sounds: [AmbientSound], levels: [AmbientSound: Int] = [:], volume: Double,
              fadeIn: Double = AmbientFade.fadeIn, owner: AmbientOwner = .widget) {
        guard !sounds.isEmpty else { return }
        previewTask?.cancel()
        previewTask = nil
        // 还在淡出、引擎没放掉：接着用，从现在的音量升回去。正在放（试听被专注接过去）
        // 也一样，不先掉到 0 再起来，各个声音自己交叉淡入淡出。
        let resuming = engine?.isRunning == true && (stopTask != nil || isPlaying)
        stopTask?.cancel()
        stopTask = nil
        self.sounds = sounds
        self.levels = levels
        if engine == nil || engine?.isRunning == false {
            guard startEngine() else { return }
        }
        self.owner = owner
        if owner != .preview {
            MediaSessionCoordinator.shared.begin(.ambient) { [weak self] command, _ in self?.remote(command) }
        }
        self.volume = volume
        box.update { synth in
            synth.setVolume(volume / 100)
            synth.setSounds(sounds, levels: levels)
            if !resuming { synth.setFade(0) }
            synth.fade(to: 1, over: fadeIn)
        }
        startedAt = .now
        isPlaying = true
        // 环境音小组件的定时关闭不管专注和试听：专注那一轮到点会被当成「用户停了」。
        stopAt = owner == .widget && timerMinutes > 0 ? .now.addingTimeInterval(Double(timerMinutes) * 60) : nil
        startTicker()
        publishSession()
    }

    /// 专注面板里选了声音、专注还没开始时试听几秒，自己淡出停下。
    /// 小组件或专注正在放时不试听（不打断用户在听的东西），返回 false。
    @discardableResult
    func preview(_ sound: AmbientSound, volume: Double) -> Bool {
        if isPlaying, owner != .preview { return false }
        play(sounds: [sound], volume: volume, owner: .preview)
        guard isPlaying else { return false }
        let hold = max(0.5, AmbientFade.preview - AmbientFade.fadeOut)
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(hold * 1000)))
            guard !Task.isCancelled, let self, self.owner == .preview, self.isPlaying else { return }
            self.previewTask = nil
            self.stop(fadingOut: AmbientFade.fadeOut)
        }
        return true
    }

    /// 试听还在放就淡出停下（专注面板里改选「不播放」时）。
    func endPreview() {
        guard isPlaying, owner == .preview else { return }
        previewTask?.cancel()
        previewTask = nil
        stop(fadingOut: AmbientFade.fadeOut)
    }

    /// Fades out over about a second, then lets the engine go so nothing
    /// holds the audio hardware awake while silent.
    func stop() {
        previewTask?.cancel()
        previewTask = nil
        pause(immediate: true)
        elapsed = 0
        MediaSessionCoordinator.shared.end(.ambient)
    }

    /// 淡出 `seconds` 秒再停（专注驱动、试听用 `AmbientFade.fadeOut`），之后和 `stop()` 一样放掉引擎。
    /// 淡出途中再 `play` 会接上。
    func stop(fadingOut seconds: Double) {
        guard isPlaying, seconds > 0 else { stop(); return }
        elapsed = 0
        startedAt = nil
        isPlaying = false
        stopAt = nil
        box.update { $0.fade(to: 0, over: seconds) }
        ticker?.invalidate()
        ticker = nil
        MediaSessionCoordinator.shared.end(.ambient)
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int((seconds + AmbientFade.releaseMargin) * 1000)))
            guard !Task.isCancelled else { return }
            self?.box.update { $0.setFade(1) }
            self?.tearDown()
            self?.stopTask = nil
        }
    }

    func pause(immediate: Bool = false) {
        if immediate {
            stopTask?.cancel()
            stopTask = nil
            if !isPlaying { tearDown() }
        }
        guard isPlaying else { return }
        elapsed = sessionPosition
        startedAt = nil
        isPlaying = false
        stopAt = nil
        ticker?.invalidate()
        ticker = nil
        publishSession()
        stopTask?.cancel()
        if immediate { tearDown(); return }
        // 整体淡出，走完再放掉引擎；淡出途中再按播放从当时的音量往回升。
        let seconds = AmbientFade.fadeOut
        box.update { $0.fade(to: 0, over: seconds) }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int((seconds + AmbientFade.releaseMargin) * 1000)))
            guard !Task.isCancelled else { return }
            self?.box.update { $0.setFade(1) }
            self?.tearDown()
            self?.stopTask = nil
        }
    }

    private var sessionPosition: Double {
        elapsed + (startedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
    }

    private func publishSession() {
        guard owner != .preview else { return }
        MediaSessionCoordinator.shared.update(.ambient, title: AmbientSound.summary(sounds),
            subtitle: tr("环境音"), playing: isPlaying, position: sessionPosition)
    }

    private func remote(_ command: MediaCommand) {
        // 环境音小组件是 Pro；专注计时放的环境音免费，媒体键照样能停能放。
        guard ProAccess.isUnlocked || owner == .focus else { return }
        guard let action = MediaSessionRules.action(command, source: .ambient, playing: isPlaying) else { return }
        switch action {
        case .play: play(sounds: sounds, levels: levels, volume: volume, owner: owner)
        case .pause: pause()
        case .stop: stop()
        case .position, .station: break
        }
    }

    /// 0 turns the timer off. Counting starts now when playing, or at the
    /// next play otherwise.
    func setTimer(minutes: Int) {
        timerMinutes = max(0, minutes)
        let counts = isPlaying && owner == .widget && timerMinutes > 0
        stopAt = counts ? .now.addingTimeInterval(Double(timerMinutes) * 60) : nil
    }

    // MARK: Engine

    private func startEngine() -> Bool {
        tearDown()
        let engine = AVAudioEngine()
        let output = engine.outputNode.outputFormat(forBus: 0)
        // 没有可用的输出设备时格式是 0 声道：这时连起来 start 也只会抛错或者静音，直接算失败。
        guard output.channelCount > 0 else { return false }
        let rate = output.sampleRate > 0 ? output.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return false }
        box.reset(sampleRate: rate)
        let node = Self.makeSource(box: box, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return false
        }
        self.engine = engine
        // A new output (headphones in, a display's speakers) stops the
        // engine; start again on the new device if we were playing.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterDeviceChange() }
        }
        return true
    }

    private func restartAfterDeviceChange() {
        guard isPlaying else { return }
        // 试听只有几秒，换设备时直接停掉，不再从头放。
        if owner == .preview { stop(); return }
        elapsed = sessionPosition
        startedAt = nil
        let current = sounds
        let volume = box.volume
        isPlaying = false
        let deadline = stopAt
        // 换了输出设备：新引擎从 0 淡入，谁放的还是谁的（专注那一轮不会因此被当成用户换了）。
        play(sounds: current, levels: levels, volume: volume * 100, owner: owner)
        stopAt = deadline
    }

    private func tearDown() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.stop()
        engine = nil
    }

    /// Built outside the main actor on purpose. A closure written inside a
    /// main-actor method inherits that isolation under Swift 6, and the audio
    /// thread calling it would trap on the executor check.
    private nonisolated static func makeSource(box: SynthBox, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, bufferList -> OSStatus in
            box.render(UnsafeMutableAudioBufferListPointer(bufferList), frames: Int(frameCount))
            return noErr
        }
    }

    // MARK: Sleep timer

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard isPlaying, let stopAt else { return }
        if Date.now >= stopAt { stop() }
    }
}

/// The synthesiser behind a lock, shared by the main actor (which changes
/// the mix) and the audio thread (which renders it).
///
/// The lock is held only to copy a few floats in or to render one buffer,
/// and the main actor takes it a handful of times a minute, so the audio
/// thread practically never waits on it.
final class SynthBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: AmbientSynth())

    /// 0...1, what the synth is set to.
    var volume: Double { lock.withLock { $0.volume } }

    func reset(sampleRate: Double) {
        lock.withLock { synth in
            let volume = synth.volume
            synth = AmbientSynth(sampleRate: sampleRate, seed: UInt64.random(in: 1...UInt64.max))
            synth.setVolume(volume)
        }
    }

    func update(_ change: (inout AmbientSynth) -> Void) {
        lock.withLockUnchecked { synth in change(&synth) }
    }

    /// Renders into the first channel and copies it to the rest: the mix is
    /// mono, and nothing here may allocate on the audio thread.
    func render(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard buffers.count > 0,
              let first = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        lock.withLockUnchecked { synth in
            for frame in 0..<frames { first[frame] = synth.next() }
        }
        for index in 1..<buffers.count {
            if let data = buffers[index].mData {
                memcpy(data, first, frames * MemoryLayout<Float>.size)
            }
        }
    }
}
