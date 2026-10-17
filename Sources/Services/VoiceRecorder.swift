import AVFoundation
import AppKit
import Observation

/// One-tap voice memos: the microphone into an AAC file in a folder.
///
/// `AVAudioRecorder`, the plain public API for this. Asking for the
/// microphone goes through `AVCaptureDevice`, which is what puts Docket in
/// System Settings under Privacy & Security, Microphone; the prompt text is
/// `NSMicrophoneUsageDescription` in Info.plist.
@MainActor @Observable
final class VoiceRecorder {
    static let shared = VoiceRecorder()

    struct Recording: Identifiable, Equatable {
        var url: URL
        var date: Date
        var duration: TimeInterval?
        var id: URL { url }
    }

    private(set) var startedAt: Date?
    private(set) var recordings: [Recording] = []
    private(set) var error: String?
    private(set) var folder: URL = VoiceRecorder.folder(for: "")

    var isRecording: Bool { startedAt != nil }

    @ObservationIgnored private var recorder: AVAudioRecorder?

    private init() {}

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
        recorder?.stop()
        recorder = nil
        startedAt = nil
        reload()
    }

    func trash(_ recording: Recording) {
        do {
            try FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
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
            startedAt = .now
            error = nil
        } catch {
            self.error = tr("无法开始录音：\(error.localizedDescription)")
        }
    }

    /// The newest recordings in the folder. Small and synchronous: it lists
    /// one folder's names and stats at most twenty files.
    private func reload() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else {
            recordings = []
            return
        }
        let found: [Recording] = names.filter(RecordingNaming.isRecording).compactMap { name in
            let url = folder.appendingPathComponent(name)
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return Recording(url: url, date: date, duration: nil)
        }
        let newest = Array(found.sorted { $0.date > $1.date }.prefix(20))
        if newest != recordings { recordings = newest }
    }
}
