import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 扩展栏和分组窗口里的 App 图标收拖放（判定在 Core 的 `DockIconDrop`）：
///
/// - 不按键：和系统程序坞一样，拖文件上去用这个 App 打开；图标稍微压暗放大。
///   分组窗口里拖 App 照旧加进组。
/// - 按住 Option：松手把拖来的图片（文件或浏览器、预览里拖出来的图片数据）或另一个
///   App 的图标换成这个 App 在码头里的图标（码头 Pro）。图标放大并围一圈虚线，旁边的
///   玻璃小提示写「松手换成这个图标」，光标带拷贝的加号。免费用户松手弹升级提示，不换。
/// - 换好后图标轻轻弹一下，触控板轻震一下；撤销用右键「恢复默认图标」。
///
/// 拖来的东西直接从拖放剪贴板读（`DockIconDropPayload`），悬停时就能知道是不是图片，
/// 提示才能在松手前说清楚会发生什么。
struct DockIconDropTarget: ViewModifier {
    /// 不是 App 的格子传 nil，什么都不加。
    var bundleID: String?
    var ref: FileRef?
    var place: DockIconDrop.Place
    /// 提示放在图标哪一侧：扩展栏按停靠边，分组窗口在图标上方。
    var edge: DockPosition
    /// 分组窗口里：不按 Option 拖 App 能不能加进组（选择列表开着、锁定时不能）。
    var canAddToGroup = false
    var addToGroup: ([URL]) -> Void = { _ in }

    @State private var mode: DockIconDropMode?
    @State private var confirmTick = 0
    /// 格子大小，只在算提示位置时读；放在引用里，指针放大时改它不触发重画。
    @State private var size = DockIconDropSize()

    func body(content: Content) -> some View {
        if let bundleID {
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size.value = $0 }
                .brightness(mode == .open ? -0.16 : 0)
                .overlay {
                    if mode == .change {
                        DockIconDropRing()
                            .transition(.opacity)
                    }
                }
                .scaleEffect(mode == .change ? 1.1 : (mode == .open ? 1.04 : 1))
                .animation(.snappy(duration: 0.16), value: mode)
                .keyframeAnimator(initialValue: 1.0, trigger: confirmTick) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(DockIconDrop.confirmPeakScale, duration: DockIconDrop.confirmDuration * 0.4,
                                       spring: .snappy)
                        SpringKeyframe(1.0, duration: DockIconDrop.confirmDuration * 0.6, spring: .bouncy)
                    }
                }
                .onDrop(of: DockIconDropDelegate.types,
                        delegate: DockIconDropDelegate(
                            bundleID: bundleID, ref: ref,
                            place: canAddToGroup ? place : .shelf,
                            edge: edge,
                            size: size,
                            setMode: { new in if mode != new { mode = new } },
                            addToGroup: addToGroup,
                            changed: { confirmTick += 1 }))
        } else {
            content
        }
    }
}

enum DockIconDropMode: Equatable {
    /// 松手会用这个 App 打开（或加进分组）。
    case open
    /// 松手会换图标（或弹升级提示）。
    case change
}

/// 格子的当前大小。引用类型，写它不让视图重画。只在主线程读写。
final class DockIconDropSize: @unchecked Sendable {
    var value: CGSize = .zero
}

/// 按着 Option 悬停时围着图标的一圈虚线：跟随浅深色的主文字色，不用蓝色发光。
private struct DockIconDropRing: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .padding(-3)
        .allowsHitTesting(false)
    }
}

// MARK: - 拖来的东西

/// 拖放剪贴板里的东西：文件地址，或者没有文件的图片数据。
///
/// SwiftUI 的 `DropInfo` 只给异步的 item provider，悬停时等不到文件地址；拖放剪贴板
/// 在整个拖动过程中都能同步读，按它的 changeCount 缓存，一次拖动只读一次。
@MainActor
struct DockIconDropPayload {
    var urls: [URL] = []
    var sources: [DockIconDrop.Source] = []

    private static var cache: (change: Int, payload: DockIconDropPayload)?

    static func current() -> DockIconDropPayload {
        let pasteboard = NSPasteboard(name: .drag)
        if let cache, cache.change == pasteboard.changeCount { return cache.payload }
        var payload = DockIconDropPayload()
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            payload.urls = urls
            payload.sources = urls.map {
                DockIconDrop.source(pathExtension: $0.pathExtension, isAppBundle: DockAppIconStore.isApp($0))
            }
        } else if NSImage.canInit(with: pasteboard) {
            payload.sources = [.imageData]
        }
        cache = (pasteboard.changeCount, payload)
        return payload
    }

    /// 没有文件时的图片数据（浏览器、预览拖来的）。松手时同步读，拖放结束后剪贴板就换了。
    static func imageData() -> Data? {
        let pasteboard = NSPasteboard(name: .drag)
        for type in [NSPasteboard.PasteboardType.png, .tiff,
                     NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                     NSPasteboard.PasteboardType(UTType.heic.identifier)] {
            if let data = pasteboard.data(forType: type), !data.isEmpty { return data }
        }
        return NSImage(pasteboard: pasteboard)?.tiffRepresentation
    }
}

// MARK: - 拖放

@MainActor
struct DockIconDropDelegate: DropDelegate {
    static let types: [UTType] = [.fileURL, .image]

    var bundleID: String
    var ref: FileRef?
    var place: DockIconDrop.Place
    var edge: DockPosition
    var size: DockIconDropSize
    var setMode: (DockIconDropMode?) -> Void
    var addToGroup: ([URL]) -> Void
    var changed: () -> Void

    private var option: Bool {
        DockIconDrop.wantsIconChange(modifierFlags: UInt(NSEvent.modifierFlags.rawValue))
    }

    private var unlocked: Bool { DockAppIconPicker.unlocked }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: Self.types)
    }

    func dropEntered(info: DropInfo) {
        _ = refresh(info)
    }

    /// 指针移动、按下或松开 Option 时都会来，提示和光标跟着变。
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let action = refresh(info)
        let operation: DropOperation = switch DockIconDrop.cursor(for: action) {
        case .copy: .copy
        // SwiftUI 没有 generic；move 在 macOS 上同样不带角标，访达拖文件都允许。
        case .plain: .move
        case .forbidden: .forbidden
        }
        return DropProposal(operation: operation)
    }

    func dropExited(info: DropInfo) {
        setMode(nil)
        DockIconDropHint.shared.hide()
    }

    func performDrop(info: DropInfo) -> Bool {
        setMode(nil)
        DockIconDropHint.shared.hide()
        let payload = DockIconDropPayload.current()
        switch DockIconDrop.action(sources: payload.sources, option: option, unlocked: unlocked, place: place) {
        case .refuse:
            return false
        case .open(let indices):
            return open(indices.map { payload.urls[$0] })
        case .addToGroup(let indices):
            addToGroup(indices.map { payload.urls[$0] })
            return true
        case .upgrade:
            // 不换，弹和右键「更换图标…」一样的升级提示。
            PaywallWindow.shared.show()
            return true
        case .changeIcon(let index):
            let source = payload.sources[index]
            // 图片数据要在松手这一刻读，拖放结束后剪贴板就不是它了。
            let data = source == .imageData ? DockIconDropPayload.imageData() : nil
            let url = source.isFile ? payload.urls[index] : nil
            let target = self.bundleID
            let changed = self.changed
            Task { @MainActor in
                let store = DockAppIconStore.shared
                let result: Result<Void, DockAppIconStore.ChangeError>
                if let url {
                    result = await store.setIcon(from: url, for: target)
                } else if let data {
                    result = await store.setIcon(fromImageData: data, for: target)
                } else {
                    result = .failure(.unreadable)
                }
                if DockAppIconPicker.report(result) {
                    changed()
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
            return true
        }
    }

    /// 重新判定一次：更新图标高亮和旁边的提示，返回松手会做什么。
    private func refresh(_ info: DropInfo) -> DockIconDrop.Action {
        let payload = DockIconDropPayload.current()
        let option = self.option
        let unlocked = self.unlocked
        let action = DockIconDrop.action(sources: payload.sources, option: option, unlocked: unlocked, place: place)
        switch action {
        case .changeIcon, .upgrade: setMode(.change)
        case .open, .addToGroup: setMode(.open)
        case .refuse: setMode(nil)
        }
        let hint = DockIconDrop.hint(sources: payload.sources, option: option, unlocked: unlocked, place: place)
        if let label = DockIconDropHint.label(for: hint, appName: DockIconDropHint.appName(bundleID: bundleID, ref: ref)) {
            DockIconDropHint.shared.show(label, anchor: anchor(info), edge: edge)
        } else {
            DockIconDropHint.shared.hide()
        }
        return action
    }

    /// 提示指向的点（屏幕坐标）：格子朝外那条边的中点，和悬停名字一样。
    ///
    /// `info.location` 是指针在格子里的位置（从左上量），指针的屏幕位置减掉它就是
    /// 格子的左上角，不用每个格子常驻一个量屏幕坐标的读取器。
    private func anchor(_ info: DropInfo) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let side = size.value
        let rect = CGRect(x: mouse.x - info.location.x, y: mouse.y + info.location.y - side.height,
                          width: side.width, height: side.height)
        return switch edge {
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .left: CGPoint(x: rect.maxX, y: rect.midY)
        case .right: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// 和系统程序坞一样：拖来的文件交给这个 App 打开。
    private func open(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty,
              let app = ref?.resolve() ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration) { _, _ in }
        return true
    }
}

// MARK: - 提示

/// 拖到 App 图标上时图标旁边的玻璃小提示，在自己的窗口里（和悬停名字同理，见
/// `TooltipWindow`），不占扩展栏的地方，也不被扩展栏的边裁掉。
@MainActor
final class DockIconDropHint {
    static let shared = DockIconDropHint()

    struct Label: Equatable {
        var symbol: String
        var text: String
        /// 松手会换图标：字加粗一档。
        var emphasized = false
    }

    private var panel: NSPanel?
    private var hosting: NSHostingView<DockIconDropHintLabel>?
    private var current: Label?
    private var currentSize: NSSize = .zero
    private var currentFrame: CGRect = .zero
    private var names: [String: String] = [:]

    private init() {}

    /// 提示文字。`none` 时不显示。
    static func label(for hint: DockIconDrop.Hint, appName: String) -> Label? {
        switch hint {
        case .none, .addToGroup:
            nil
        case .open(let optionTip):
            Label(symbol: "arrow.up.forward.app",
                  text: optionTip ? tr("用“\(appName)”打开，按住 Option 换图标") : tr("用“\(appName)”打开"))
        case .holdOption:
            Label(symbol: "option", text: tr("按住 Option 换成这个图标"))
        case .changeIcon(let pro):
            Label(symbol: pro ? "lock.fill" : "photo.badge.checkmark",
                  text: ProFeatures.menuTitle(tr("松手换成这个图标"), isPro: pro),
                  emphasized: true)
        case .notAnImage:
            Label(symbol: "nosign", text: tr("只能用图片或 App 当图标"))
        }
    }

    /// App 名字，一次拖动里反复问到同一个 App 时不再读盘。
    static func appName(bundleID: String, ref: FileRef?) -> String {
        if let name = shared.names[bundleID] { return name }
        let name = DockAppIconPicker.appName(bundleID: bundleID, ref: ref)
        shared.names[bundleID] = name
        return name
    }

    func show(_ label: Label, anchor: CGPoint, edge: DockPosition) {
        // 悬停名字在拖动时不该和它叠在一起。
        TooltipWindow.shared.hide()
        let panel = existingOrNew()
        if current != label {
            hosting?.rootView = DockIconDropHintLabel(label: label)
            current = label
            currentSize = hosting?.fittingSize ?? .zero
        }
        let size = currentSize
        guard size.width > 1 else { return }
        let origin = Geometry.popupOrigin(edge: edge, anchor: anchor, size: size, gap: 8)
        let frame = CGRect(origin: clamped(origin, size: size), size: size)
        if abs(frame.origin.x - currentFrame.origin.x) > 0.5
            || abs(frame.origin.y - currentFrame.origin.y) > 0.5
            || frame.size != currentFrame.size {
            currentFrame = frame
            panel.setFrame(frame, display: false)
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard panel?.isVisible == true else { return }
        current = nil
        currentFrame = .zero
        names = [:]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.current == nil else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    private func clamped(_ origin: CGPoint, size: NSSize) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main
        else { return origin }
        let visible = screen.visibleFrame
        return CGPoint(x: min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4),
                       y: min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4))
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }
        let view = NSHostingView(rootView: DockIconDropHintLabel(label: Label(symbol: "photo", text: "")))
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        self.hosting = view
        return panel
    }
}

/// 液态玻璃胶囊：图标加一行 13pt 字，主文字色，跟随浅深色；细描边和轻阴影让它在
/// 浅色桌面上也有边，不用彩色发光。
struct DockIconDropHintLabel: View {
    var label: DockIconDropHint.Label

    var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: label.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(label.text)
                .font(.system(size: 13, weight: label.emphasized ? .semibold : .regular))
                .foregroundStyle(.primary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background {
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
        }
        .padding(8)
    }
}
