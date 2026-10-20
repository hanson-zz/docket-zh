import AVFoundation
import AppKit
import Observation

/// One-tap voice memos: the microphone into an AAC file in a folder.
///
/// `AVAudioRecorder`, the plain public API for this. Asking for the
/// microphone goes through `AVCaptureDevice`, which is what puts Docket in
/// System Settings under Privacy & Security, Microphone; the prompt text is
/// `NSMicrophoneUsageDescription` in Info.plist.
///
/// 面板改版后它还管：面板里直接播放和拖动进度（`AVAudioPlayer`）、读时长和
/// 波形（后台读一遍文件）、改名、删除、裁剪后存成新录音，以及每条录音的转写
/// 文字（存在应用支持文件夹的 recordings.json，见 `RecordingNotes`）。转写本身
/// 在 `RecordingTranscriber`。录、听、改名、删除免费；转文字、裁剪和编辑是 Pro，
/// 由面板和 `stop()` 看 `ProLicenseGate.canUseRecorderTools`。
@MainActor @Observable
final class VoiceRecorder {
    static let shared = VoiceRecorder()

    struct Recording: Identifiable, Equatable {
        var url: URL
        var date: Date
        var duration: TimeInterval?
        var id: URL { url }
    }

    /// 读一遍文件得到的时长和波形。
    struct Analysis: Equatable, Sendable {
        var duration: TimeInterval
        var bars: [Float]
    }

    private(set) var startedAt: Date?
    private(set) var recordings: [Recording] = []
    private(set) var error: String?
    private(set) var folder: URL = VoiceRecorder.folder(for: "")
    /// 读好的时长和波形，按文件。
    private(set) var analyses: [URL: Analysis] = [:]
    /// 每条录音的转写文字。
    private(set) var notes = RecordingNotes()
    /// 面板里正在播的那条（暂停时也还是它），和是不是在响。
    private(set) var playingURL: URL?
    private(set) var isPlaying = false
    /// 面板底下一行临时提示（改名失败、存为新录音失败）。
    private(set) var notice: String?

    var isRecording: Bool { startedAt != nil }

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var playerDelegate: PlayerDelegate?
    /// 试听选段时到结尾自动停的那个等待。
    @ObservationIgnored private var rangeStop: Task<Void, Never>?
    @ObservationIgnored private var analyzing: Set<URL> = []
    @ObservationIgnored private let notesURL: URL

    private init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.docket-zh.app"
        notesURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "recordings.json")
        notes = RecordingNotes.decode(try? Data(contentsOf: notesURL))
    }

    nonisolated static func folder(for path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Points at a folder and lists what is already recorded there.
    func use(folderPath: String) {
        let wanted = Self.folder(for: folderPath)
        if wanted != folder { folder = wanted }
        reload()
    }

    func toggle(folderPath: String) {
        if isRecording { stop() } else { start(folderPath: folderPath) }
    }

    func start(folderPath: String) {
        guard !isRecording else { return }
        use(folderPath: folderPath)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            begin()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if granted { begin() } else { denied() }
            }
        default:
            denied()
        }
    }

    func stop() {
        let finished = recordingURL
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        startedAt = nil
        reload()
        // 录完自动转文字（Pro）。没解锁时不转，文件照常留着。
        if let finished, ProLicenseGate.canUseRecorderTools(unlocked: ProAccess.isUnlocked) {
            RecordingTranscriber.shared.transcribe(finished)
        }
    }

    func trash(_ recording: Recording) {
        if playingURL == recording.url { stopPlayback() }
        RecordingTranscriber.shared.cancel(recording.url)
        do {
            try FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
            notes.remove(recording.url)
            analyses[recording.url] = nil
            saveNotes()
        } catch {
            NSSound.beep()
        }
        reload()
    }

    /// Opens the microphone pane, the only place a refusal can be undone.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func clearNotice() { notice = nil }

    // MARK: 时长和波形

    /// 还没读过的录音在后台读一遍时长和波形，读完放进 `analyses`。
    func analyzeIfNeeded(_ url: URL) {
        guard analyses[url] == nil, !analyzing.contains(url), url != recordingURL else { return }
        analyzing.insert(url)
        Task {
            let result = await Task.detached(priority: .utility) { Self.analyze(url) }.value
            analyzing.remove(url)
            guard let result else { return }
            analyses[url] = result
            if let i = recordings.firstIndex(where: { $0.url == url }), recordings[i].duration != result.duration {
                recordings[i].duration = result.duration
            }
        }
    }

    /// 读整个文件，每一小段取峰值，最后压成 `Waveform.barCount` 根。
    nonisolated static func analyze(_ url: URL) -> Analysis? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let total = file.length
        let rate = format.sampleRate
        guard total > 0, rate > 0 else { return Analysis(duration: 0, bars: Waveform.bars([])) }
        let buckets = 480
        var peaks = [Float](repeating: 0, count: buckets)
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { return nil }
        var position: AVAudioFramePosition = 0
        while position < total {
            do { try file.read(into: buffer, frameCount: chunk) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData?[0] else { break }
            for i in 0..<n {
                let bucket = min(buckets - 1, Int((position + AVAudioFramePosition(i)) * AVAudioFramePosition(buckets) / total))
                let v = abs(data[i])
                if v > peaks[bucket] { peaks[bucket] = v }
            }
            position += AVAudioFramePosition(n)
        }
        return Analysis(duration: Double(total) / rate, bars: Waveform.bars(peaks))
    }

    // MARK: 播放

    /// 现在播到第几秒（面板每帧读）。
    var currentTime: TimeInterval { player?.currentTime ?? 0 }

    /// 点播放钮：在播这条就暂停，暂停着就接着播，别的就从头播这条。
    func togglePlay(_ url: URL) {
        if playingURL == url, let player {
            if player.isPlaying { pause() } else { resume() }
            return
        }
        play(url, from: 0, until: nil)
    }

    /// 拖动或点波形跳到第几成。不是这条就先换成这条（暂停着）。
    func seek(_ url: URL, fraction: Double) {
        if playingURL != url { load(url) }
        guard let player else { return }
        rangeStop?.cancel()
        player.currentTime = max(0, min(player.duration, fraction * player.duration))
    }

    /// 试听选段：从 `start` 播到 `end`，到了自动停。
    func playRange(_ url: URL, start: TimeInterval, end: TimeInterval) {
        play(url, from: start, until: end)
    }

    func stopPlayback() {
        rangeStop?.cancel()
        rangeStop = nil
        player?.stop()
        player = nil
        playerDelegate = nil
        playingURL = nil
        isPlaying = false
    }

    private func pause() {
        rangeStop?.cancel()
        player?.pause()
        isPlaying = false
    }

    private func resume() {
        guard let player, player.play() else { return }
        isPlaying = true
    }

    @discardableResult
    private func load(_ url: URL) -> Bool {
        stopPlayback()
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            NSSound.beep()
            return false
        }
        let delegate = PlayerDelegate { [weak self] in self?.finished() }
        player.delegate = delegate
        player.prepareToPlay()
        self.player = player
        playerDelegate = delegate
        playingURL = url
        return true
    }

    private func play(_ url: URL, from start: TimeInterval, until end: TimeInterval?) {
        if playingURL != url || player == nil { guard load(url) else { return } }
        guard let player else { return }
        rangeStop?.cancel()
        player.currentTime = max(0, min(player.duration, start))
        guard player.play() else { return }
        isPlaying = true
        if let end, end > start {
            rangeStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(end - start))
                guard !Task.isCancelled else { return }
                self?.pause()
            }
        }
    }

    private func finished() {
        rangeStop?.cancel()
        isPlaying = false
        player?.currentTime = 0
    }

    // MARK: 改名、文字、存为新录音

    /// 改名：文件名一直以“录音 ”开头。名字没变或清理后是空的不改。
    @discardableResult
    func rename(_ recording: Recording, to raw: String) -> URL? {
        let fm = FileManager.default
        let current = recording.url.lastPathComponent
        let taken = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        guard let name = RecorderTitle.renamed(current, to: raw, taken: taken) else { return nil }
        let target = recording.url.deletingLastPathComponent().appendingPathComponent(name)
        if playingURL == recording.url { stopPlayback() }
        do {
            try fm.moveItem(at: recording.url, to: target)
        } catch {
            notice = tr("改名失败：\(error.localizedDescription)")
            return nil
        }
        notes.move(from: recording.url, to: target)
        if let analysis = analyses.removeValue(forKey: recording.url) { analyses[target] = analysis }
        saveNotes()
        reload()
        return target
    }

    func segments(for url: URL) -> [TranscriptSegment]? { notes.segments(for: url) }

    /// 存转写文字（转完或编辑态改完）。
    func setSegments(_ segments: [TranscriptSegment], for url: URL) {
        notes.set(segments, for: url)
        saveNotes()
    }

    /// 把选段存成一条新录音（原来那条不动），文字跟着裁好、改名。成功返回新文件。
    func saveExcerpt(of recording: Recording, title: String, trim: RecordingTrim,
                     segments: [TranscriptSegment]) async -> URL? {
        let fm = FileManager.default
        let taken = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        let base = RecorderTitle.clean(title) ?? RecorderTitle.display(fileName: recording.url.lastPathComponent)
        let wanted = trim.isFull ? tr("\(base) 副本") : RecorderTitle.excerptTitle(base)
        let cleaned = RecorderTitle.clean(wanted) ?? base
        let name = RecordingNaming.unique("\(RecordingNaming.prefix)\(cleaned).\(RecordingNaming.fileExtension)", taken: taken)
        let target = recording.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            if trim.isFull {
                try fm.copyItem(at: recording.url, to: target)
            } else {
                try await Self.export(recording.url, to: target, start: trim.start, end: trim.end)
            }
        } catch {
            try? fm.removeItem(at: target)
            notice = tr("存为新录音失败：\(error.localizedDescription)")
            return nil
        }
        let kept = trim.isFull ? segments : Transcript.trimmed(segments, start: trim.start, end: trim.end)
        if !kept.isEmpty { notes.set(kept, for: target) }
        saveNotes()
        reload()
        return target
    }

    private nonisolated static func export(_ source: URL, to target: URL,
                                           start: TimeInterval, end: TimeInterval) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                        end: CMTime(seconds: end, preferredTimescale: 600))
        try await session.export(to: target, as: .m4a)
    }

    private func saveNotes() {
        guard let data = notes.encoded() else { return }
        let dir = notesURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: notesURL, options: .atomic)
    }

    // MARK: Private

    private func denied() {
        error = tr("没有麦克风权限。请在 系统设置 ▸ 隐私与安全性 ▸ 麦克风 中允许码头。")
    }

    private func begin() {
        guard !isRecording else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            self.error = tr("无法创建文件夹“\(folder.lastPathComponent)”。")
            return
        }
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = RecordingNaming.unique(RecordingNaming.fileName(for: .now), taken: taken)
        let url = folder.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                error = tr("无法开始录音。请检查输入设备。")
                return
            }
            self.recorder = recorder
            recordingURL = url
            startedAt = .now
            error = nil
        } catch {
            self.error = tr("无法开始录音：\(error.localizedDescription)")
        }
    }

    /// The newest recordings in the folder. Small and synchronous: it lists
    /// one folder's names and stats at most twenty files. 正在录的那个文件不列。
    private func reload() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else {
            recordings = []
            return
        }
        let found: [Recording] = names.filter(RecordingNaming.isRecording).compactMap { name in
            let url = folder.appendingPathComponent(name)
            guard url != recordingURL else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return Recording(url: url, date: date, duration: analyses[url]?.duration)
        }
        let newest = Array(found.sorted { $0.date > $1.date }.prefix(20))
        if newest != recordings { recordings = newest }
        // 这个文件夹里已经不在的录音，文字也不留（在访达里删掉或改名的）。
        let before = notes
        notes.prune(folder: folder, existing: Set(names))
        if notes != before { saveNotes() }
        if let playingURL, !names.contains(playingURL.lastPathComponent),
           playingURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            stopPlayback()
        }
    }
}

/// `AVAudioPlayer` 的代理要是 NSObject；播完的回调转回主线程。
private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate, Sendable {
    private let onFinish: @MainActor @Sendable () -> Void

    init(onFinish: @escaping @MainActor @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let done = onFinish
        Task { @MainActor in done() }
    }
}
