import AppKit
import ApplicationServices
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import Vision

// 快速开关的第二批工具里需要窗口、摄像头、截屏和识别的部分。
// 纯逻辑（预览文字、网址判断、二维码放大倍数、演示模式的恢复计算、
// pmset 输出解析）在 Core/QuickToolLogic.swift，有测试。

// MARK: - 轻提示

/// 屏幕上方居中的一个小胶囊，几秒后自己淡出，不抢焦点也不挡鼠标。
@MainActor
enum QuickHint {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ text: String, symbol: String = "checkmark.circle.fill",
                     tint: Color = .accentColor, seconds: Double = 2.4) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: QuickHintView(text: text, symbol: symbol, tint: tint))
        let size = host.fittingSize
        panel.contentView = host
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 28,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            panel.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

private struct QuickHintView: View {
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: Capsule())
        .padding(8)
    }
}

// MARK: - 截屏框选和命令行

enum QuickTool {
    /// 跑一个命令行工具，返回退出码和标准输出。在后台线程等，不卡界面。
    nonisolated static func run(_ tool: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
                } catch {
                    continuation.resume(returning: (-1, ""))
                }
            }
        }
    }

    /// `screencapture -i` 让用户框选一块区域，存到临时文件。
    /// 用户按 Esc 取消时文件不会生成，返回 nil。
    nonisolated static func pickRegion() async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dockling-capture-\(UUID().uuidString).png")
        _ = await run("/usr/sbin/screencapture", ["-i", "-x", url.path])
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        guard let size, size.intValue > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// Vision 识别图片里的文字，简体、繁体中文和英文，精确模式。
    nonisolated static func recognizeText(at url: URL) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(url: url, options: [:])
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: RecognizedText.joined(lines))
            }
        }
    }

    /// 识别图片里的二维码：先用 Vision，认不出再用 CIDetector 试一次。
    nonisolated static func decodeQR(at url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                let handler = VNImageRequestHandler(url: url, options: [:])
                try? handler.perform([request])
                if let text = (request.results ?? []).compactMap(\.payloadStringValue).first(where: { !$0.isEmpty }) {
                    continuation.resume(returning: text)
                    return
                }
                guard let image = CIImage(contentsOf: url),
                      let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = detector.features(in: image)
                    .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
                    .first { !$0.isEmpty }
                continuation.resume(returning: text)
            }
        }
    }

    @MainActor
    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }
}

// MARK: - 截图识字

@MainActor
enum TextCapture {
    private static var running = false

    static func start() {
        guard !running else { return }
        running = true
        Task { @MainActor in
            defer { running = false }
            // 取消框选：什么都不做。
            guard let url = await QuickTool.pickRegion() else { return }
            let text = await QuickTool.recognizeText(at: url)
            try? FileManager.default.removeItem(at: url)
            guard !text.isEmpty else {
                QuickHint.show("没有识别到文字", symbol: "text.viewfinder", tint: .secondary)
                return
            }
            QuickTool.copy(text)
            QuickHint.show("已拷贝：\(RecognizedText.preview(text))", symbol: "text.viewfinder")
        }
    }
}

// MARK: - 取色器

@MainActor
enum ColorPickerTool {
    static func start() {
        ColorSampling.sample { code in
            QuickTool.copy(code.hex)
            QuickHint.show(code.copiedHint, symbol: "circle.fill",
                           tint: Color(.sRGB, red: code.red, green: code.green, blue: code.blue))
        }
    }
}

// MARK: - 浮窗

/// 不抢焦点的浮窗里的 SwiftUI 视图，第一下点击就生效。
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 镜子的浮窗：无边框，但能成为键盘焦点（要收 Esc）。
private final class MirrorPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - 只锁键盘

/// 只锁键盘：屏幕照常，键盘被和清洁模式同一个事件拦截锁住，
/// 屏幕上方一个小浮窗，鼠标长按按钮 3 秒解锁，10 分钟后自动解锁。
@MainActor
final class KeyboardLockMode {
    static let shared = KeyboardLockMode()

    private var panel: NSPanel?
    private var timer: Timer?

    var isActive: Bool { panel != nil }

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !isActive, !CleanMode.shared.isActive else { return }
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        guard trusted, KeyboardBlocker.shared.start() else {
            // 和清洁模式同一句话。
            QuickHint.show("键盘未锁定：需要在“辅助功能”中允许码头。",
                           symbol: "exclamationmark.triangle.fill", tint: .orange, seconds: 4)
            return
        }
        let ends = Date().addingTimeInterval(KeyboardLockTiming.autoUnlockSeconds)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = FirstClickHostingView(rootView: KeyboardLockView(ends: ends) { [weak self] in self?.stop() })
        panel.contentView = host
        let size = host.fittingSize
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 40,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: KeyboardLockTiming.autoUnlockSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        QuickActions.shared.noteChange()
    }

    func stop() {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        KeyboardBlocker.shared.stop()
        panel?.orderOut(nil)
        panel = nil
        QuickActions.shared.noteChange()
    }
}

private struct KeyboardLockView: View {
    var ends: Date
    var unlock: () -> Void

    @State private var pressStart: Date?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 16, weight: .semibold))
                Text("键盘已锁定")
                    .font(.system(size: 15, weight: .semibold))
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pressStart == nil)) { context in
                let progress = pressStart.map {
                    KeyboardLockTiming.holdProgress(elapsed: context.date.timeIntervalSince($0))
                } ?? 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    GeometryReader { proxy in
                        Capsule().fill(Color.accentColor.opacity(0.85))
                            .frame(width: proxy.size.width * progress)
                    }
                    Text(pressStart == nil ? "长按 3 秒解锁" : "继续按住…")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 200, height: 32)
                .clipShape(Capsule())
                .contentShape(Capsule())
            }
            .onLongPressGesture(minimumDuration: KeyboardLockTiming.holdSeconds, maximumDistance: 60) {
                pressStart = nil
                unlock()
            } onPressingChanged: { pressing in
                pressStart = pressing ? Date() : nil
            }
            .accessibilityLabel("长按 3 秒解锁")
            .accessibilityAddTraits(.isButton)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(KeyboardLockTiming.remainingText(ends.timeIntervalSince(context.date)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(10)
    }
}

// MARK: - 二维码

@MainActor @Observable
final class QRCodeModel {
    var check: QRText.Check = .empty
    var image: NSImage?
    var scanned: String?
    var scanMessage: String?
    var scanning = false

    func readClipboard() {
        check = QRText.check(NSPasteboard.general.string(forType: .string))
        if case .ok(let text) = check {
            image = Self.qrImage(for: text)
            if image == nil { check = .tooLong }
        } else {
            image = nil
        }
    }

    /// CIQRCodeGenerator 的原图一个模块 1 像素，按整数倍放大到两倍点数
    /// （视网膜屏），显示时关掉插值，边缘就是锐利的。
    static func qrImage(for text: String, side: CGFloat = 200) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let factor = CGFloat(QRText.scale(moduleSide: output.extent.width, target: side * 2))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width / 2, height: scaled.extent.height / 2))
    }
}

@MainActor
final class QRCodePanel {
    static let shared = QRCodePanel()

    let model = QRCodeModel()
    private var panel: NSPanel?

    func show() {
        model.readClipboard()
        model.scanMessage = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible { panel.center() }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 420),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "二维码"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.contentView = NSHostingView(rootView: QRCodeView(model: model, scan: { [weak self] in self?.scan() }))
        return panel
    }

    /// 先把面板藏起来，免得它挡住要框选的二维码；框选完再拿回来。
    func scan() {
        guard !model.scanning else { return }
        model.scanning = true
        model.scanMessage = nil
        panel?.orderOut(nil)
        Task { @MainActor in
            defer {
                model.scanning = false
                NSApp.activate()
                panel?.makeKeyAndOrderFront(nil)
            }
            guard let url = await QuickTool.pickRegion() else { return }
            let text = await QuickTool.decodeQR(at: url)
            try? FileManager.default.removeItem(at: url)
            guard let text else {
                model.scanned = nil
                model.scanMessage = "框选的区域里没有找到二维码"
                return
            }
            QuickTool.copy(text)
            model.scanned = text
            model.scanMessage = nil
        }
    }
}

private struct QRCodeView: View {
    var model: QRCodeModel
    var scan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            generated
            Divider()
            Button(action: scan) {
                Label(model.scanning ? "正在框选…" : "识别屏幕上的二维码", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.scanning)
            scanned
        }
        .padding(16)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var generated: some View {
        switch model.check {
        case .ok(let text):
            if let image = model.image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                Text(RecognizedText.preview(text, limit: 60))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("拷贝图片") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                        QuickHint.show("已拷贝二维码图片", symbol: "qrcode")
                    }
                    Button("重新读取剪贴板") { model.readClipboard() }
                }
            }
        case .empty:
            message("剪贴板里没有文字，先拷贝一段文字或网址再打开。")
        case .tooLong:
            message("剪贴板里的文字太长，生成不了二维码（最多约 2000 字节）。")
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新读取剪贴板") { model.readClipboard() }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    @ViewBuilder
    private var scanned: some View {
        if let text = model.scanned {
            VStack(alignment: .leading, spacing: 6) {
                Label("已拷贝识别结果", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                Text(text)
                    .font(.system(size: 12))
                    .lineLimit(4)
                    .textSelection(.enabled)
                if let url = QRText.webURL(text) {
                    Button("打开网址") { NSWorkspace.shared.open(url) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let message = model.scanMessage {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 镜子

/// 摄像头会话放在自己的串行队列上开和关，startRunning 会卡住调用的线程。
private final class MirrorCamera: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.docket-zh.mirror")

    func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.commitConfiguration()
        return true
    }

    func start() { queue.async { self.session.startRunning() } }
    func stop() { queue.async { self.session.stopRunning() } }
}

private final class MirrorPreviewView: NSView {
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        // 水平镜像，和照镜子一样。
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        } else {
            preview.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        }
        preview.cornerRadius = 18
        preview.masksToBounds = true
        preview.backgroundColor = NSColor.black.cgColor
        layer = preview
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
final class MirrorWindow {
    static let shared = MirrorWindow()

    private var panel: MirrorPanel?
    private var camera: MirrorCamera?
    private var monitors: [Any] = []
    /// 点镜子按钮本身来关时，按下先关、松开又会打开，用这个挡一下。
    private var closedAt = Date.distantPast

    var isOpen: Bool { panel != nil }

    func open() {
        guard !isOpen, Date().timeIntervalSince(closedAt) > 0.4 else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            present()
        case .notDetermined:
            Task { @MainActor in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { self.present() } else { Self.denied() }
            }
        default:
            Self.denied()
        }
    }

    private static func denied() {
        QuickHint.show("没有摄像头权限：请在“系统设置 ▸ 隐私与安全性 ▸ 摄像头”中允许码头。",
                       symbol: "video.slash.fill", tint: .orange, seconds: 4)
    }

    private func present() {
        guard !isOpen else { return }
        let camera = MirrorCamera()
        guard camera.configure() else {
            QuickHint.show("没有找到可用的摄像头", symbol: "video.slash.fill", tint: .orange)
            return
        }
        let size = NSSize(width: 360, height: 270)
        let panel = MirrorPanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = MirrorPreviewView(session: camera.session)
        panel.onCancel = { [weak self] in self?.close() }
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + 80))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        camera.start()
        self.panel = panel
        self.camera = camera
        watch()
    }

    /// 点浮窗外面任何地方、或按 Esc 就关。
    private func watch() {
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let outside: (NSEvent) -> Void = { [weak self] event in
            guard let self, let panel = self.panel else { return }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            if !panel.frame.contains(point) { self.close() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: outside) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouse, handler: { event in
            outside(event)
            return event
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, let self, self.isOpen else { return event }
            self.close()
            return nil
        }) { monitors.append(keys) }
    }

    func close() {
        guard isOpen else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        camera?.stop()
        camera = nil
        panel?.orderOut(nil)
        panel = nil
        closedAt = Date()
    }
}
