import AppKit

/// 框选的结果：一块区域，或者（录区域时单击）整个屏幕。
enum RegionPick: Equatable {
    case rect(CaptureRect)
    case fullScreen
}

/// 码头自己的框选：录区域和延时截区域要先知道框在哪，screencapture 的交互框选
/// 直接就截了，拿不到区域。盖在鼠标所在的那块屏幕上，压暗，拖出的框是亮的，
/// 旁边写尺寸；Esc 取消。`allowsFullScreen` 时单击（没拖）或按回车是整个屏幕。
@MainActor
enum RegionPicker {
    private static var window: RegionPickerWindow?
    private static var continuation: CheckedContinuation<RegionPick?, Never>?

    static func pick(prompt: String, allowsFullScreen: Bool) async -> RegionPick? {
        guard window == nil else { return nil }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let window = RegionPickerWindow(screen: screen, prompt: prompt, allowsFullScreen: allowsFullScreen)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    fileprivate static func finish(_ result: RegionPick?) {
        window?.orderOut(nil)
        window = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    /// 整个屏幕：主显示器就是 screencapture 不带区域，别的显示器按它的范围录。
    fileprivate static func whole(_ screen: NSScreen) -> RegionPick? {
        let primary = NSScreen.screens.first
        if screen == primary { return .fullScreen }
        return CaptureRect.from(cocoa: screen.frame, primaryHeight: primary?.frame.height ?? screen.frame.height)
            .map { .rect($0) }
    }

    fileprivate static func region(_ rect: NSRect) -> RegionPick? {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CaptureRect.from(cocoa: rect, primaryHeight: height).map { .rect($0) }
    }
}

private final class RegionPickerWindow: NSWindow {
    init(screen: NSScreen, prompt: String, allowsFullScreen: Bool) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
        let view = RegionPickerView(prompt: prompt, allowsFullScreen: allowsFullScreen, screen: screen)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }

    /// 切到别的 App（⌘Tab）时收起，不留一层压暗的罩子。
    override func resignKey() {
        super.resignKey()
        if isVisible { RegionPicker.finish(nil) }
    }
}

private final class RegionPickerView: NSView {
    private let prompt: String
    private let allowsFullScreen: Bool
    private let screen: NSScreen
    private var start: NSPoint?
    private var current: NSPoint?

    init(prompt: String, allowsFullScreen: Bool, screen: NSScreen) {
        self.prompt = prompt
        self.allowsFullScreen = allowsFullScreen
        self.screen = screen
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if let rect = selection {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            drawLabel("\(Int(rect.width)) × \(Int(rect.height))",
                      at: NSPoint(x: rect.minX, y: max(4, rect.minY - 26)))
        }
        let size = labelSize(prompt)
        drawLabel(prompt, at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - 60))
    }

    private var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
    }

    private func labelSize(_ text: String) -> NSSize {
        let size = (text as NSString).size(withAttributes: labelAttributes)
        return NSSize(width: size.width + 20, height: size.height + 8)
    }

    private func drawLabel(_ text: String, at origin: NSPoint) {
        let size = labelSize(text)
        let box = NSRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: size.height / 2, yRadius: size.height / 2).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 10, y: box.minY + 4), withAttributes: labelAttributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let rect = selection ?? .zero
        start = nil
        current = nil
        needsDisplay = true
        if rect.width < CaptureRect.minimumSide || rect.height < CaptureRect.minimumSide {
            // 单击：录区域时是整个屏幕，截区域时当没框，接着框。
            if allowsFullScreen { RegionPicker.finish(RegionPicker.whole(screen)) }
            return
        }
        guard let window else { return }
        let onScreen = window.convertToScreen(convert(rect, to: nil))
        RegionPicker.finish(RegionPicker.region(onScreen))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            RegionPicker.finish(nil)
        case 36, 76: // 回车
            if allowsFullScreen { RegionPicker.finish(RegionPicker.whole(screen)) }
        default:
            super.keyDown(with: event)
        }
    }
}
