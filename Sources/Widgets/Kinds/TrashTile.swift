import SwiftUI

/// The Trash: how much is in it, files dropped on it are thrown away, and
/// once it passes the size you chose, flies.
///
/// More flies the fuller it gets and the longer it is left (one more every
/// hour), and the pointer scares them off for a few seconds. The idea is
/// BananaBin's; see `TrashFlies`.
struct TrashTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var monitor: TrashMonitor { TrashMonitor.shared }
    @State private var targeted = false
    @State private var scaredAt: Date?
    @State private var hovering = false
    @State private var swallowAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var threshold: Int64 {
        TrashFlies.thresholdBytes(instance.config.string("threshold", default: TrashFlies.defaultThreshold))
    }
    private var showsFlies: Bool { instance.config.bool("flies", default: true) }

    private var bytes: Int64 { context.isPreview ? 2_400_000_000 : monitor.bytes }
    private var items: Int { context.isPreview ? 37 : monitor.items }
    private var flies: Int {
        guard showsFlies else { return 0 }
        return context.isPreview ? 5 : monitor.flies(now: context.now, threshold: threshold)
    }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    bin(size: WidgetStyle.badgeCompact)
                    Text(TrashFlies.format(bytes: bytes))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    bin(size: WidgetStyle.badge)
                    TileReading(value: value, caption: caption, valueSize: 15)
                    Spacer(minLength: 0)
                }
            }
        }
        // 共用的拖入虚线框；扔进废纸篓是删除，用红色那档。
        .dropTargetOutline(targeted, tint: .destructive)
        .permissionLock(locked ? permission : nil, preview: context.isPreview)
        .dropDestination(for: URL.self) { urls, _ in
            guard !context.isPreview else { return false }
            return monitor.trash(urls)
        } isTargeted: { targeted = $0 }
        .onHover { inside in
            hovering = inside
            // Entering scares them; leaving starts the slow return.
            scaredAt = inside ? .now : .now.addingTimeInterval(-0.6)
        }
        .onAppear { if !context.isPreview { monitor.start(threshold: threshold) } }
        .onChange(of: threshold) { _, now in monitor.start(threshold: now) }
        .onChange(of: items) { before, now in
            // Emptied, here or in Finder: the bin swallows its paper.
            if !context.isPreview, before > 0, now == 0 { swallowAt = .now }
        }
        .task(id: swallowAt) {
            guard swallowAt != nil else { return }
            try? await Task.sleep(for: .seconds(SwallowMotion.duration))
            guard !Task.isCancelled else { return }
            swallowAt = nil
        }
        .help(targeted ? "松开即可移到废纸篓" : "把文件拖到这里即可移到废纸篓")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("废纸篓，\(value)，\(caption)")
    }

    private var value: String {
        if locked { return "需要权限" }
        return targeted ? "松开以删除" : TrashFlies.format(bytes: bytes)
    }

    private var caption: String {
        if locked { return TilePermission.prompt(permission) }
        if items == 0 { return "废纸篓是空的" }
        return flies > 0 ? "\(items) 个项目 · 该倒垃圾了" : "\(items) 个项目"
    }

    /// 没有完全磁盘访问权限时读不到废纸篓。
    private var locked: Bool { !context.isPreview && monitor.needsAccess }
    private var permission: String { TilePermission.name(for: WidgetKind.trash.rawValue) ?? "完全磁盘访问权限" }

    private func bin(size: CGFloat) -> some View {
        TileBadge(size: size) {
            SwallowingBin(startedAt: swallowAt, binSize: size * 0.42) {
                Image(systemName: items > 0 ? "trash.fill" : "trash")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(targeted ? Color.red : WidgetStyle.primary)
                    .scaleEffect(targeted && !reduceMotion ? 1.15 : 1)
                    .dockAnimation(.snappy(duration: 0.2), value: targeted)
            }
        }
        .overlay {
            FlySwarm(count: flies, scaredAt: scaredAt, hovering: hovering, animated: !context.isPreview)
                .frame(width: size * 1.7, height: size * 1.5)
                .allowsHitTesting(false)
        }
    }
}

/// The flies themselves: a small dark body, two flickering wings, each on
/// its own looping path around the bin.
struct FlySwarm: View {
    var count: Int
    var scaredAt: Date?
    var hovering: Bool
    var animated: Bool
    var flySize: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated || reduceMotion)) { timeline in
                Canvas { canvas, size in
                    let t = animated && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate : 1.7
                    draw(in: &canvas, size: size, t: t, now: timeline.date)
                }
            }
        }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, t: Double, now: Date) {
        var fled = scaredAt.map { TrashFlies.scare(elapsed: now.timeIntervalSince($0)) } ?? 0
        if hovering { fled = max(fled, scaredAt.map { min(1, now.timeIntervalSince($0) / 0.6) } ?? 1) }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let halfW = size.width / 2 / 1.7
        let halfH = size.height / 2 / 1.5
        for index in 0..<count {
            let p = TrashFlies.position(index: index, t: t + Double(index) * 0.31)
            let spread = 1 + fled * 2.2
            let point = CGPoint(x: center.x + p.x * halfW * spread, y: center.y + p.y * halfH * spread)
            let opacity = 1 - fled * 0.9
            guard opacity > 0.05 else { continue }
            drawFly(in: &canvas, at: point, heading: p.heading, t: t, index: index, opacity: opacity)
        }
    }

    private func drawFly(in canvas: inout GraphicsContext, at point: CGPoint, heading: Double,
                         t: Double, index: Int, opacity: Double) {
        var fly = canvas
        fly.opacity = opacity
        fly.translateBy(x: point.x, y: point.y)
        fly.rotate(by: .radians(heading))
        let s = 1.6 * flySize
        // Wings beat fast; drawn as two pale ellipses that open and close.
        let beat = 0.55 + 0.45 * abs(sin(t * 55 + Double(index)))
        let wing = Path(ellipseIn: CGRect(x: -s * 0.2, y: -s * 1.9 * beat, width: s * 1.5, height: s * 1.7 * beat))
        let wingColor = Color.white.opacity(0.55)
        fly.fill(wing, with: .color(wingColor))
        fly.fill(wing.applying(CGAffineTransform(scaleX: 1, y: -1)), with: .color(wingColor))
        let body = Path(ellipseIn: CGRect(x: -s * 1.1, y: -s * 0.6, width: s * 2.2, height: s * 1.2))
        fly.fill(body, with: .color(Color(white: 0.08)))
        let head = Path(ellipseIn: CGRect(x: s * 0.8, y: -s * 0.45, width: s * 0.9, height: s * 0.9))
        fly.fill(head, with: .color(Color(red: 0.35, green: 0.05, blue: 0.05)))
    }
}
