import AppKit
import QuartzCore

/// 窗口切换器里选中窗口的全尺寸预览：按窗口在屏幕上的真实位置和大小放一张截图，
/// 盖在其他窗口之上、切换器面板之下，淡入淡出。不接鼠标，不抢焦点。
///
/// 什么时候出、截哪张由 `WindowSwitcherController` 决定（选中变化后等 150ms，
/// 规则在 Core 的 `WindowSwitcherPreview`）。
@MainActor
final class WindowSwitcherBigPreview {
    private var window: NSPanel?
    private var imageLayer: CALayer?
    /// 正在显示的是哪个窗口（`Entry.key`）。
    private(set) var showingKey: String?

    /// 把截图放到 AppKit 屏幕坐标 `frame` 处，淡入。
    func show(_ image: CGImage, frame: CGRect, key: String, below panel: NSWindow?) {
        let window = existingOrNew()
        window.setFrame(frame, display: false)
        imageLayer?.contents = image
        imageLayer?.frame = CGRect(origin: .zero, size: frame.size)
        // 切换器面板在 .popUpMenu，预览低一层：盖住普通窗口和浮动窗口，不挡面板。
        window.level = NSWindow.Level(rawValue: (panel?.level ?? .popUpMenu).rawValue - 1)
        if showingKey == nil || !window.isVisible {
            window.alphaValue = 0
        }
        window.orderFrontRegardless()
        if let panel, panel.isVisible { panel.orderFrontRegardless() }
        showingKey = key
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// 淡出收起。`immediately` 时直接拿掉（切换器收起、切走的时候）。
    func hide(immediately: Bool = false) {
        showingKey = nil
        guard let window, window.isVisible else { return }
        if immediately {
            window.orderOut(nil)
            window.alphaValue = 0
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // 淡出期间又出了新的预览就别收。
                guard let self, self.showingKey == nil else { return }
                self.window?.orderOut(nil)
            }
        })
    }

    private func existingOrNew() -> NSPanel {
        if let window { return window }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.setAccessibilityElement(false)

        let view = NSView()
        view.wantsLayer = true
        let root = CALayer()
        root.masksToBounds = true
        // macOS 26 的窗口圆角大约 16pt，截图本身带透明圆角时这里也不会多出直角。
        root.cornerRadius = 16
        root.cornerCurve = .continuous
        view.layer = root
        let image = CALayer()
        image.contentsGravity = .resize
        image.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        root.addSublayer(image)
        panel.contentView = view

        window = panel
        imageLayer = image
        return panel
    }
}
