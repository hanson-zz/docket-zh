import AppKit
import Foundation
import Observation

/// Runs `/usr/sbin/screencapture`, the same tool ⇧⌘3 and ⇧⌘4 drive.
///
/// The file goes where the user's own screenshots go, named the way macOS
/// names them, so the Screenshots widget picks it up like any other. The
/// tool is told the path as an argument rather than through a shell, so a
/// folder name with spaces needs no quoting.
///
/// Capturing other apps' windows needs Screen Recording consent for Docket:
/// without it the system hands back the desktop and the menu bar only.
@MainActor
enum ScreenCapture {
    enum Mode: CaseIterable {
        case window, region

        var arguments: [String] {
            switch self {
            case .window: ["-i", "-W"]
            case .region: ["-i", "-s"]
            }
        }
    }

    private static var running = false

    /// 截图工具卡片上的一个按钮。识字走快速开关的同一套实现（`TextCapture`），
    /// 录屏走 `ScreenRecording`。
    static func perform(_ action: CaptureAction) {
        switch action {
        case .region: capture(.region)
        case .window: capture(.window)
        case .text: TextCapture.start()
        case .record: ScreenRecording.shared.toggle()
        }
    }

    static func capture(_ mode: Mode) {
        guard !running else { return }
        running = true
        let folder = FolderFeed.folder(for: .screenshots)
        let url = folder.appendingPathComponent(CaptureFileName.screenshot(at: .now))
        let arguments = mode.arguments + [url.path]
        Task {
            _ = await Self.run(arguments)
            running = false
            FolderFeed.shared(.screenshots).refresh(force: true)
        }
    }

    nonisolated private static func run(_ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            // Waited on from a background thread, so the process object stays
            // alive exactly as long as the capture does.
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }
}

/// 截图工具卡片上的录屏：`screencapture -v` 录整个屏幕，再点一次停止。
///
/// `screencapture -v` 在终端里是“按任意键或 Ctrl-C 停止”。停止时发 SIGINT（和
/// Ctrl-C 一样，文件照样写完）；标准输入接一根不写的管道，免得它读到文件结尾就
/// 以为有人按了键、一开始就停。四秒后还没退出，再往管道里写一个字符。
/// 文件名和系统录屏一样以“录屏”开头，存到截图文件夹，最近截图里就有它。
/// 开始时不弹提示（会被录进去），只靠卡片上变红的按钮和计时。
/// 没有“屏幕录制”权限时进程会马上退出，这时提示去系统设置里打开。
@MainActor
@Observable
final class ScreenRecording {
    static let shared = ScreenRecording()

    /// 正在录时是开始的时间，卡片据此画计时。
    private(set) var startedAt: Date?
    var isRecording: Bool { startedAt != nil }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: Pipe?

    private init() {}

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        guard process == nil else { return }
        let folder = FolderFeed.folder(for: .screenshots)
        let url = folder.appendingPathComponent(CaptureFileName.recording(at: .now))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-v", url.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let began = Date()
        process.terminationHandler = { _ in
            Task { @MainActor in ScreenRecording.shared.finished(url: url, began: began) }
        }
        do {
            try process.run()
        } catch {
            QuickHint.show(tr("无法开始录屏"), symbol: "exclamationmark.triangle.fill", tint: .orange)
            return
        }
        self.process = process
        self.input = input
        startedAt = began
    }

    func stop() {
        guard let process, process.isRunning else { return }
        // 和在终端里按 Ctrl-C 一样：screencapture 收尾、把文件写完再退出。
        process.interrupt()
        let id = ObjectIdentifier(process)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, let current = self.process, ObjectIdentifier(current) == id,
                  current.isRunning else { return }
            // 还没停：照它自己说的“按任意键停止”，往标准输入写一个字符。
            // 进程刚好退出时写管道会收到 SIGPIPE，忽略它，变成一个抛出的错误。
            signal(SIGPIPE, SIG_IGN)
            try? self.input?.fileHandleForWriting.write(contentsOf: Data("q\n".utf8))
        }
    }

    private func finished(url: URL, began: Date) {
        process = nil
        try? input?.fileHandleForWriting.close()
        input = nil
        startedAt = nil
        FolderFeed.shared(.screenshots).refresh(force: true)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        if let size, size.intValue > 0 {
            QuickHint.show(tr("录屏已存到“\(url.deletingLastPathComponent().lastPathComponent)”"),
                           symbol: "record.circle")
        } else if Date().timeIntervalSince(began) < 3 {
            // 一开始就退出，几乎都是没有屏幕录制权限。
            QuickHint.show(tr("没有录到画面：请在“系统设置 ▸ 隐私与安全性 ▸ 屏幕录制”中允许码头。"),
                           symbol: "exclamationmark.triangle.fill", tint: .orange, seconds: 4)
        }
    }
}
