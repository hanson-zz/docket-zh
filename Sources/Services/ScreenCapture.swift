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
    }

    private static var running = false

    /// 截图工具卡片或面板上的一个按钮。识字走快速开关的同一套实现（`TextCapture`），
    /// 录屏走 `ScreenRecording`。`options` 是这张卡片的设置（截完后、格式、延时），
    /// `widget` 是卡片的 id，截完要打开标注时用它打开这张卡片的面板。
    /// 不带选项的调用（最近截图面板空状态、扩展栏上的快捷入口）照旧只存文件。
    static func perform(_ action: CaptureAction, options: CaptureOptions = CaptureOptions(after: .save),
                        widget: UUID? = nil) {
        switch action {
        case .region: capture(.region, options: options, widget: widget)
        case .window: capture(.window, options: options, widget: widget)
        case .text: TextCapture.start()
        case .record: ScreenRecording.shared.toggle()
        case .recordRegion: ScreenRecording.shared.toggleRegion()
        }
    }

    /// 截一张。不延时时直接交给 screencapture 框选或点选；延时时：截区域先用码头的
    /// 选框框好，倒数完截那块；截窗口倒数完截鼠标下面的那个窗口（找不到就截整个屏幕），
    /// 这样倒数期间可以打开菜单、悬停出提示。
    static func capture(_ mode: Mode, options: CaptureOptions = CaptureOptions(after: .save), widget: UUID? = nil) {
        guard !running else { return }
        running = true
        Task {
            defer { running = false }
            guard let target = await target(for: mode, delay: options.delay) else { return }
            await shoot(target, options: options, widget: widget)
        }
    }

    private static func target(for mode: Mode, delay: Int) async -> CaptureOptions.Target? {
        guard delay > 0 else { return mode == .region ? .interactiveRegion : .interactiveWindow }
        switch mode {
        case .region:
            guard case .rect(let rect)? = await RegionPicker.pick(prompt: tr("拖动框选要截的区域，Esc 取消"),
                                                                  allowsFullScreen: false) else { return nil }
            await countdown(delay)
            return .rect(rect)
        case .window:
            await countdown(delay)
            return windowUnderPointer().map { .window($0) } ?? .fullScreen
        }
    }

    /// 倒数：屏幕上方的小提示每秒更新，最后一秒前收起，免得被截进去。
    private static func countdown(_ seconds: Int) async {
        for left in stride(from: seconds, to: 0, by: -1) {
            if left > 1 {
                QuickHint.show(tr("\(left) 秒后截图"), symbol: "timer", seconds: 0.9)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        // 提示淡出要 0.3 秒。
        try? await Task.sleep(for: .milliseconds(150))
    }

    private static func windowUnderPointer() -> Int? {
        let point = CGEvent(source: nil)?.location ?? .zero
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return nil }
        let windows = raw.compactMap { info -> CaptureWindowPick.Window? in
            guard let id = info[kCGWindowNumber as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            return CaptureWindowPick.Window(id: id, layer: layer, bounds: bounds, ownerPID: pid, alpha: alpha)
        }
        return CaptureWindowPick.topmost(at: point, in: windows, excluding: ProcessInfo.processInfo.processIdentifier)
    }

    /// 跑 screencapture，然后按「截完后」处理：存文件、拷贝、两者、打开标注。
    private static func shoot(_ target: CaptureOptions.Target, options: CaptureOptions, widget: UUID?) async {
        let after = options.after
        if !after.savesFile {
            let board = NSPasteboard.general.changeCount
            _ = await run(options.arguments(target, path: nil))
            if NSPasteboard.general.changeCount != board {
                QuickHint.show(tr("截图已拷贝"), symbol: "doc.on.clipboard")
            }
            return
        }
        let folder = FolderFeed.folder(for: .screenshots)
        let url = folder.appendingPathComponent(CaptureFileName.screenshot(at: .now, format: options.format))
        _ = await run(options.arguments(target, path: url.path))
        FolderFeed.shared(.screenshots).refresh(force: true)
        // 按 Esc 取消时不会有文件。
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        guard let size, size.intValue > 0 else { return }
        if after.copiesAfterSaving {
            FileActions.copyImage(url)
            QuickHint.show(tr("截图已存好，也拷贝了"), symbol: "doc.on.clipboard")
        }
        if after.opensMarkup, let widget {
            CaptureMarkupInbox.shared.pending[widget] = url
            WidgetPanelOpener.shared.open(widget)
        }
    }

    nonisolated static func run(_ arguments: [String]) async -> Int32 {
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

/// 截完选了「标注」时，截好的图交给这张卡片的面板：面板打开时取走，进标注。
@MainActor
@Observable
final class CaptureMarkupInbox {
    static let shared = CaptureMarkupInbox()
    var pending: [UUID: URL] = [:]
    private init() {}

    func take(_ widget: UUID) -> URL? {
        pending.removeValue(forKey: widget)
    }
}

/// 截图工具卡片上的录屏：`screencapture -v` 录整个屏幕，再点一次停止。
/// 「录区域」先用码头的选框框一块（单击是整个屏幕），再 `screencapture -v -R` 录那块。
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

    @ObservationIgnored private var picking = false

    func toggle() {
        isRecording ? stop() : start()
    }

    /// 录区域：录着时停止，否则先框选。
    func toggleRegion() {
        if isRecording {
            stop()
            return
        }
        guard !picking, process == nil else { return }
        picking = true
        Task { @MainActor in
            defer { picking = false }
            let pick = await RegionPicker.pick(prompt: tr("拖动框选要录的区域，单击录整个屏幕，Esc 取消"),
                                               allowsFullScreen: true)
            switch pick {
            case .rect(let rect)?: start(rect: rect)
            case .fullScreen?: start()
            case nil: return
            }
        }
    }

    func start(rect: CaptureRect? = nil) {
        guard process == nil else { return }
        let folder = FolderFeed.folder(for: .screenshots)
        let url = folder.appendingPathComponent(CaptureFileName.recording(at: .now))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-v"] + (rect.map { ["-R", $0.argument] } ?? []) + [url.path]
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
