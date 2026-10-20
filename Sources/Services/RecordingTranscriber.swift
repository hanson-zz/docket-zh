import AppKit
import Observation
import Speech

/// 录音转文字：系统语音识别，只在本机识别（`requiresOnDeviceRecognition`），
/// 不联网。码头 Pro 的功能，调用的地方先看 `ProLicenseGate.canUseRecorderTools`。
///
/// 一次只转一条，其余排队。转完的文字按段存进 `VoiceRecorder` 的
/// `RecordingNotes`。这台 Mac 的语言都不支持本机识别时记成“无法转写”，不去
/// 联网识别；没有语音识别权限时记成“没有权限”，面板给“打开隐私设置”。权限说明
/// 是 Info.plist 的 `NSSpeechRecognitionUsageDescription`。
@MainActor @Observable
final class RecordingTranscriber {
    static let shared = RecordingTranscriber()

    enum Status: Equatable {
        /// 排队中。
        case queued
        /// 正在转，进度 0 到 1（还不知道时是 0）。
        case running(Double)
        /// 这台 Mac 不支持本机识别。
        case unavailable
        /// 没有语音识别权限。
        case denied
        /// 识别出错（比如录音里没有说话）。
        case failed(String)
    }

    /// 没转完或转不了的录音的状态；转完的不在这里，文字在 `VoiceRecorder.notes`。
    private(set) var statuses: [URL: Status] = [:]

    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var current: URL?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    /// 最近一次拿到的分段（识别中途出错时用它兜底）。
    @ObservationIgnored private var latest: [TranscriptWord] = []
    @ObservationIgnored private var duration: TimeInterval?

    private init() {}

    func status(_ url: URL) -> Status? { statuses[url] }

    func isBusy(_ url: URL) -> Bool {
        switch statuses[url] {
        case .queued?, .running?: true
        default: false
        }
    }

    /// 这台 Mac 有没有一种语言能本机识别。没有时面板直接写“无法转写”。
    /// 建识别器不便宜，第一次问时查一次记下来；转写时会重新查（用户可能刚下载
    /// 了听写的语言包）。
    var supportsOnDevice: Bool {
        if let onDevice { return onDevice }
        let value = Self.makeRecognizer() != nil
        onDevice = value
        return value
    }
    @ObservationIgnored private var onDevice: Bool?

    /// 排队转一条。已经在排或在转的不重复排。
    func transcribe(_ url: URL) {
        guard !isBusy(url) else { return }
        statuses[url] = .queued
        queue.append(url)
        next()
    }

    /// 不转这条了（删除时）。
    func cancel(_ url: URL) {
        queue.removeAll { $0 == url }
        if current == url {
            task?.cancel()
            task = nil
            current = nil
        }
        statuses[url] = nil
        next()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private func next() {
        guard current == nil, !queue.isEmpty else { return }
        let url = queue.removeFirst()
        current = url
        statuses[url] = .running(0)
        Task { await run(url) }
    }

    private func run(_ url: URL) async {
        var auth = SFSpeechRecognizer.authorizationStatus()
        if auth == .notDetermined { auth = await Self.requestAccess() }
        guard current == url else { return }
        guard auth == .authorized else {
            finish(url, status: .denied)
            return
        }
        guard let recognizer = Self.makeRecognizer() else {
            onDevice = false
            finish(url, status: .unavailable)
            return
        }
        onDevice = true
        guard FileManager.default.fileExists(atPath: url.path) else {
            finish(url, status: nil)
            return
        }
        self.recognizer = recognizer
        latest = []
        duration = VoiceRecorder.shared.analyses[url]?.duration
        if duration == nil {
            duration = await Task.detached(priority: .utility) { VoiceRecorder.analyze(url)?.duration }.value
        }
        guard current == url else { return }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] update in
            self?.receive(update, for: url)
        })
    }

    /// 识别回调里拿出来的东西（回调不在主线程时也只带可发送的值）。
    struct Update: Sendable {
        var words: [TranscriptWord]
        var isFinal: Bool
        var error: String?
    }

    /// 回调做成不属于主线程的闭包：系统在自己的队列上调它，转成 `Update` 后回主线程。
    private nonisolated static func handler(
        _ sink: @escaping @MainActor @Sendable (Update) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let words = result?.bestTranscription.segments.map {
                TranscriptWord(text: $0.substring, start: $0.timestamp, duration: $0.duration)
            } ?? []
            let update = Update(words: words, isFinal: result?.isFinal ?? false,
                                error: error.map { $0.localizedDescription })
            Task { @MainActor in sink(update) }
        }
    }

    private func receive(_ update: Update, for url: URL) {
        guard current == url else { return }
        if !update.words.isEmpty { latest = update.words }
        if update.isFinal {
            save(update.words.isEmpty ? latest : update.words, for: url)
            finish(url, status: nil)
            return
        }
        if let error = update.error {
            // 中途出错但已经识别出一些字：先存下来，不算失败。
            if Transcript.hasText(Transcript.paragraphs(latest)) {
                save(latest, for: url)
                finish(url, status: nil)
            } else {
                finish(url, status: .failed(error))
            }
            return
        }
        let heard = update.words.map { $0.start + $0.duration }.max() ?? 0
        statuses[url] = .running(Transcript.progress(heard: heard, duration: duration))
    }

    private func save(_ words: [TranscriptWord], for url: URL) {
        let segments = Transcript.paragraphs(words)
        // 没听到说话也存一份空的，面板写“没有识别到说话”，不会一直显示“转文字”。
        VoiceRecorder.shared.setSegments(segments, for: url)
    }

    private func finish(_ url: URL, status: Status?) {
        statuses[url] = status
        if current == url {
            current = nil
            task = nil
            recognizer = nil
        }
        next()
    }

    /// 第一种能本机识别的语言的识别器：先跟系统语言，再试简体中文和英文。
    private static func makeRecognizer() -> SFSpeechRecognizer? {
        let preferred = Locale.preferredLanguages + [Locale.current.identifier]
        for id in TranscribeLocales.candidates(preferred: preferred) {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.supportsOnDeviceRecognition {
                return r
            }
        }
        return nil
    }

    private nonisolated static func requestAccess() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}
