import AppKit

/// 贴图（Pro）：把编辑好的截图钉在屏幕最上层的小窗里，对照着写代码、填表时用。
///
/// - 拖动移位置；滚轮缩放（0.2 到 4 倍，中心不动）；按住 ⌥ 滚轮调透明度（20% 到 100%）。
/// - 右键菜单：拷贝、存到截图文件夹、透明度、恢复原大小、关闭。
/// - 点一下贴图再按 Esc 或 ⌘W 关掉；双击也关。可以同时钉好几张。
/// - 图只在内存里，关掉就没了；要留下来用右键「存到截图文件夹」。
/// 缩放和透明度的范围在 Core（`ShotPinMath`），有测试。
@MainActor
enum ShotPin {
    private static var panels: [ShotPinPanel] = []

    static func open(_ image: CGImage, frame: CGRect) {
        let panel = ShotPinPanel(image: image, frame: frame)
        panel.onClose = { [weak panel] in
            guard let panel else { return }
            panels.removeAll { $0 === panel }
        }
        panels.append(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }
}

final class ShotPinPanel: NSPanel {
    var onClose: (() -> Void)?

    private let image: CGImage
    private let baseSize: CGSize
    private var scale: CGFloat = 1

    init(image: CGImage, frame: CGRect) {
        self.image = image
        self.baseSize = frame.size
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = ShotPinView(image: image)
        view.owner = self
        contentView = view
        initialFirstResponder = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            dismiss()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "c" {
            copyImage()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func dismiss() {
        orderOut(nil)
        onClose?()
        onClose = nil
    }

    func zoom(by delta: CGFloat) {
        scale = ShotPinMath.zoomed(scale, scrollDelta: delta)
        resize()
    }

    func resetSize() {
        scale = 1
        resize()
    }

    private func resize() {
        let size = ShotPinMath.size(base: baseSize, scale: scale)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        setFrame(CGRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(),
                        width: size.width, height: size.height), display: true)
    }

    func fade(by delta: CGFloat) {
        alphaValue = CGFloat(ShotPinMath.faded(Double(alphaValue), scrollDelta: delta))
    }

    func setOpacity(_ value: Double) {
        alphaValue = CGFloat(min(max(value, ShotPinMath.opacityRange.lowerBound), ShotPinMath.opacityRange.upperBound))
    }

    @objc func copyImage() {
        ShotImaging.copy(image)
        QuickHint.show(tr("已拷贝贴图"), symbol: "doc.on.clipboard")
    }

    @objc func saveImage() {
        if let url = ShotImaging.save(image, format: .png) {
            QuickHint.show(tr("已存到“\(url.deletingLastPathComponent().lastPathComponent)”"), symbol: "square.and.arrow.down")
        }
    }

    @objc func resetSizeAction() { resetSize() }
    @objc func closeAction() { dismiss() }
    @objc func opacityAction(_ sender: NSMenuItem) {
        setOpacity(sender.representedObject as? Double ?? 1)
    }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: tr("拷贝"), action: #selector(copyImage), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("存到截图文件夹"), action: #selector(saveImage), keyEquivalent: "").target = self
        let opacity = NSMenuItem(title: tr("透明度"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for value in ShotPinMath.opacityChoices {
            let item = NSMenuItem(title: ShotPinMath.percent(value), action: #selector(opacityAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(Double(alphaValue) - value) < 0.026 ? .on : .off
            sub.addItem(item)
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(withTitle: tr("恢复原大小"), action: #selector(resetSizeAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("关闭贴图（Esc）"), action: #selector(closeAction), keyEquivalent: "").target = self
        return menu
    }
}

/// 贴图的内容：图铺满窗口，一圈细边；滚轮缩放，⌥ 滚轮调透明度，双击关闭。
private final class ShotPinView: NSView {
    weak var owner: ShotPinPanel?
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        toolTip = tr("拖动移动，滚轮缩放，按住 ⌥ 滚轮调透明度，Esc 或双击关闭，右键更多")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            owner?.dismiss()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        if event.clickCount == 2 {
            owner?.dismiss()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // 触控板的连续滚动一下来很多小步，按点数折成“格”。
        let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 8 : event.scrollingDeltaY
        guard raw != 0 else { return }
        if event.modifierFlags.contains(.option) {
            owner?.fade(by: raw)
        } else {
            owner?.zoom(by: raw)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        owner?.contextMenu()
    }
}
