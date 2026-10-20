import AVFoundation
import Foundation
import Observation

/// 麦克风面板的电平表：点一下才开，最多一分钟，面板关上就停。
///
/// 看电平要真的从麦克风取声音，需要麦克风权限，开着时系统菜单栏会亮橙点、
/// 码头自己也算「在用麦克风」。所以不跟着面板一打开就开，要用户点「测电平」。
/// 用 `AVAudioRecorder` 的电平读数，录到临时文件，停下就删，什么都不留。
@MainActor @Observable
final class MicLevelMeter {
    static let shared = MicLevelMeter()

    enum Status: Equatable { case idle, running, denied, failed }

    private(set) var status: Status = .idle
    /// 0 到 1。
    private(set) var level: Double = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt = Date.distantPast
    @ObservationIgnored private var url: URL?

    /// 最多测多久。
    static let maxDuration: TimeInterval = 60

    private init() {}

    var isRunning: Bool { status == .running }

    func toggle() {
        if isRunning { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { status = .denied; return }
        default:
            status = .denied
            return
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("docket-mic-level-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 8_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            url = file
        } catch {
            try? FileManager.default.removeItem(at: file)
            status = .failed
            return
        }
        MicrophoneMonitor.shared.excludeSelf = true
        startedAt = .now
        status = .running
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        level = 0
        if status == .running { status = .idle }
        MicrophoneMonitor.shared.excludeSelf = false
    }

    private func sample() {
        guard let recorder, recorder.isRecording else { stop(); return }
        if Date.now.timeIntervalSince(startedAt) > Self.maxDuration { stop(); return }
        recorder.updateMeters()
        let next = MicLevel.normalized(decibels: Double(recorder.averagePower(forChannel: 0)))
        // 往上跳得快、往下落得慢，像真的电平表。
        level = next > level ? next : max(next, level - 0.06)
    }
}
