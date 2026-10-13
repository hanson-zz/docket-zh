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

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private let box = SynthBox()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var configObserver: NSObjectProtocol?

    private init() {}

    // MARK: Controls

    /// The widget's stored mix and volume, applied whether or not it plays.
    func apply(sounds: [AmbientSound], volume: Double) {
        self.sounds = sounds
        let playing = isPlaying
        box.update { synth in
            synth.setVolume(volume / 100)
            if playing { synth.setSounds(sounds) }
        }
        if playing, sounds.isEmpty { stop() }
    }

    func toggle(sounds: [AmbientSound], volume: Double) {
        isPlaying ? stop() : play(sounds: sounds, volume: volume)
    }

    func play(sounds: [AmbientSound], volume: Double) {
        guard !sounds.isEmpty else { return }
        stopTask?.cancel()
        stopTask = nil
        self.sounds = sounds
        if engine == nil || engine?.isRunning == false {
            guard startEngine() else { return }
        }
        box.update { synth in
            synth.setVolume(volume / 100)
            synth.setSounds(sounds)
        }
        isPlaying = true
        if timerMinutes > 0 { stopAt = .now.addingTimeInterval(Double(timerMinutes) * 60) }
        startTicker()
    }

    /// Fades out over about a second, then lets the engine go so nothing
    /// holds the audio hardware awake while silent.
    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        stopAt = nil
        box.update { $0.fadeOut() }
        ticker?.invalidate()
        ticker = nil
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            self?.tearDown()
        }
    }

    /// 0 turns the timer off. Counting starts now when playing, or at the
    /// next play otherwise.
    func setTimer(minutes: Int) {
        timerMinutes = max(0, minutes)
        stopAt = (isPlaying && timerMinutes > 0) ? .now.addingTimeInterval(Double(timerMinutes) * 60) : nil
    }

    // MARK: Engine

    private func startEngine() -> Bool {
        tearDown()
        let engine = AVAudioEngine()
        let output = engine.outputNode.outputFormat(forBus: 0)
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
        let current = sounds
        let volume = box.volume
        isPlaying = false
        let deadline = stopAt
        play(sounds: current, volume: volume * 100)
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
