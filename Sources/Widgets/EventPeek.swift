import AppKit
import SwiftUI

/// 日历今日时间线和一周日程悬停时浮出来的小卡片：标题、时间、地点、日历颜色和
/// 名字，有会议链接、还没开完的带「加入会议」按钮。
///
/// 卡片只有 58pt 高，详情放不进去，原来只是把标题那行换成指着的那一块；现在像
/// 程序坞的名字标签一样另开一个窗口，浮在扩展栏外侧，对着指的那一块。窗口能接
/// 点击（「加入」按钮），指针从卡片移到浮出卡片上时不收；离开两者一小会儿后收起，
/// 在卡片上点一下（打开面板、点块加入）也收起。打开“减少动态效果”时直接出现和
/// 消失，没有淡入淡出。摆放和文字在 Core 的 `EventPeekLayout`、`EventPeekText`。
@MainActor
final class EventPeekWindow {
    static let shared = EventPeekWindow()

    private var panel: NSPanel?
    private var hosting: FirstMouseHostingView<EventPeekCard>?
    private var owner: UUID?
    private var key: String?
    /// 在卡片上点过一下：这一块先不再浮出，指针离开卡片后恢复。
    private var suppressed: String?
    private var cardHovered = false
    private var hideTask: Task<Void, Never>?
    private var clickMonitor: Any?
    private var shown: Placement?

    private struct Placement: Equatable {
        var key: String
        var tile: CGRect
        var focusX: CGFloat?
        var edge: DockPosition
        var peek: EventPeek
    }

    /// 离开卡片和浮出卡片后多久收起，够指针从卡片移到浮出卡片上。
    private let grace: Duration = .milliseconds(280)

    private init() {}

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// 指着某一块（某一天）：浮出它的详情。
    ///
    /// - Parameters:
    ///   - key: 指的是哪一块，换了才重画。
    ///   - owner: 哪张小组件卡片。
    ///   - tile: 卡片内容在屏幕上的范围（y 向上）。
    ///   - focusX: 横向对着哪里，屏幕坐标。
    func show(_ peek: EventPeek, key: String, owner: UUID, accent: Color, tile: CGRect, focusX: CGFloat?,
              edge: DockPosition) {
        guard suppressed != key else { return }
        hideTask?.cancel()
        hideTask = nil
        // 指针在同一块上移动：位置和内容都没变，什么也不做（量尺寸要走一遍 SwiftUI 排版）。
        let placement = Placement(key: key, tile: tile, focusX: focusX, edge: edge, peek: peek)
        if placement == shown, let panel, panel.isVisible, panel.alphaValue >= 1 { return }
        shown = placement
        let panel = existingOrNew()
        if self.key != key || hosting?.rootView.peek != peek {
            hosting?.rootView = card(peek, accent: accent)
        }
        self.key = key
        self.owner = owner
        let size = hosting?.fittingSize ?? .zero
        guard size.width > 1, size.height > 1 else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(tile) } ?? NSScreen.main
        let frame = EventPeekLayout.frame(edge: edge, tile: tile, focusX: focusX, size: size,
                                          visible: screen?.visibleFrame ?? tile.insetBy(dx: -2000, dy: -2000))
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
        guard !panel.isVisible || panel.alphaValue < 1 else { return }
        startWatchingClicks()
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    /// 指针离开了卡片上的块（或整张卡片）：等一小会儿，没移到浮出卡片上就收起。
    func leave(owner: UUID) {
        guard self.owner == owner else { return }
        suppressed = nil
        scheduleHide()
    }

    /// 卡片不见了（换布局、扩展栏收起）：马上收起。
    func dismiss(owner: UUID) {
        guard self.owner == owner else { return }
        suppressed = nil
        hide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self, grace] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let self, !self.cardHovered else { return }
            self.hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        stopWatchingClicks()
        key = nil
        shown = nil
        cardHovered = false
        guard let panel, panel.isVisible else { return }
        if reduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // 收起途中又浮出来了就不收。
                guard let self, self.key == nil else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func card(_ peek: EventPeek, accent: Color) -> EventPeekCard {
        EventPeekCard(peek: peek, accent: accent,
                      hover: { [weak self] inside in self?.cardHover(inside) },
                      join: { [weak self] url in
                          NSWorkspace.shared.open(url)
                          self?.hide()
                      })
    }

    private func cardHover(_ inside: Bool) {
        cardHovered = inside
        if inside {
            hideTask?.cancel()
            hideTask = nil
        } else {
            scheduleHide()
        }
    }

    /// 在卡片上点一下（打开面板、点块加入）时收起，指针不离开就不再浮出这一块。
    private func startWatchingClicks() {
        guard clickMonitor == nil else { return }
        let onClick: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.window !== self.panel else { return }
            self.suppressed = self.key
            self.hide()
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                        handler: { event in
            onClick(event)
            return event
        })
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }
        let view = FirstMouseHostingView(rootView: EventPeekCard(peek: EventPeek(items: []), accent: .orange,
                                                                 hover: { _ in }, join: { _ in }))
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        hosting = view
        return panel
    }
}

/// 浮出卡片画什么。
struct EventPeekCard: View {
    var peek: EventPeek
    var accent: Color
    var hover: (Bool) -> Void
    var join: (URL) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            content(now: tick.date)
        }
        .frame(width: EventPeekLayout.width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .onHover(perform: hover)
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !peek.heading.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(peek.heading)
                        .font(.system(size: 13, weight: .semibold))
                    if !peek.subheading.isEmpty {
                        Text(peek.subheading)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            if peek.items.isEmpty, !peek.heading.isEmpty {
                Text(tr("没有日程"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(peek.items) { item in
                row(item, now: now)
            }
            if peek.more > 0 {
                Text(EventPeekText.moreLine(peek.more))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: EventPeekItem, now: Date) -> some View {
        let color = item.colorHex.isEmpty ? accent : Color(hex: item.colorHex)
        let ended = !item.isAllDay && item.end <= now
        let place = EventPeekText.placeLine(item)
        return HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                line("clock", EventPeekText.timeLine(item, now: now))
                    .monospacedDigit()
                if !place.isEmpty { line("mappin.and.ellipse", place) }
                if !item.calendar.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 7, height: 7)
                            .frame(width: 12)
                        Text(item.calendar)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if EventPeekText.showsJoin(item, now: now), let link = item.link {
                    Button { join(link.url) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(link.provider.joinTitle)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(Color.black.opacity(0.82))
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(Capsule().fill(Color(hex: "#6FDC9A")))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                    .accessibilityLabel(link.provider.joinTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(ended ? 0.6 : 1)
        .accessibilityElement(children: .contain)
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }
}

/// 卡片上跟着指针：指针在哪（占这块的比例，y 向下）和这块在屏幕上的范围。
///
/// 和 `PointerFraction` 一样不拦点击（`hitTest` 为 nil），下面的按钮照常能按。
struct PointerPeekTracker: NSViewRepresentable {
    var onMove: (CGPoint?, CGRect) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onMove = onMove
    }

    final class TrackerView: NSView {
        var onMove: ((CGPoint?, CGRect) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        private var screenRect: CGRect {
            guard let window else { return .zero }
            return window.convertToScreen(convert(bounds, to: nil))
        }

        private func report(_ event: NSEvent) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let local = convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: local.x / bounds.width, y: 1 - local.y / bounds.height)
            let inside = (0...1).contains(point.x) && (0...1).contains(point.y)
            onMove?(inside ? point : nil, screenRect)
        }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil, screenRect) }
    }
}

/// 日历颜色转成 `#RRGGBB`，存进不带 AppKit 的值里。
enum CalendarColorHex {
    static func hex(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return "" }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent),
                      byte(rgb.blueComponent))
    }
}
