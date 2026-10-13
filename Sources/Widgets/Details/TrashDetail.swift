import SwiftUI

/// The bin at reading size, with its flies, what is in it, and the two
/// things to do about it.
struct TrashDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var monitor: TrashMonitor { TrashMonitor.shared }
    @State private var scaredAt: Date?
    @State private var hovering = false
    @State private var targeted = false

    private var thresholdValue: String { instance.config.string("threshold", default: TrashFlies.defaultThreshold) }
    private var threshold: Int64 { TrashFlies.thresholdBytes(thresholdValue) }
    private var bytes: Int64 { context.isPreview ? 2_400_000_000 : monitor.bytes }
    private var items: Int { context.isPreview ? 37 : monitor.items }
    private var flies: Int {
        guard instance.config.bool("flies", default: true) else { return 0 }
        return context.isPreview ? 5 : monitor.flies(now: context.now, threshold: threshold)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.green))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        Image(systemName: items > 0 ? "trash.fill" : "trash")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(targeted ? Color.red : .white)
                        FlySwarm(count: flies, scaredAt: scaredAt, hovering: hovering,
                                 animated: !context.isPreview, flySize: 1.6)
                            .frame(width: 130, height: 110)
                            .allowsHitTesting(false)
                    }
                    .frame(width: 110, height: 96)
                    .contentShape(.rect)
                    .onHover { inside in
                        hovering = inside
                        scaredAt = inside ? .now : .now.addingTimeInterval(-0.6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(!context.isPreview && monitor.needsAccess ? "需要权限" : TrashFlies.format(bytes: bytes))
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(items == 0 ? "废纸篓是空的" : "\(items) 个项目")
                            .font(WidgetStyle.label(12))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(fliesLine)
                            .font(WidgetStyle.caption(11))
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if !context.isPreview, monitor.needsAccess {
                    Text("macOS 要求“完全磁盘访问权限”才能读取废纸篓的大小。打开设置后把“码头”加入列表并打开开关。")
                        .font(WidgetStyle.caption(11))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    PanelButton(title: "打开隐私设置", symbol: "lock.shield", prominent: true) {
                        monitor.openAccessSettings()
                    }
                }

                HStack(spacing: 8) {
                    PanelButton(title: "打开废纸篓", symbol: "folder") {
                        guard !context.isPreview else { return }
                        monitor.open()
                    }
                    PanelButton(title: "清空…", symbol: "trash", prominent: items > 0) {
                        guard !context.isPreview else { return }
                        monitor.empty()
                    }
                }

                Text("把文件拖到卡片上即可移到废纸篓，可以从废纸篓放回原处。苍蝇的灵感来自 BananaBin。")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !context.isPreview else { return false }
            return monitor.trash(urls)
        } isTargeted: { targeted = $0 }
        .onAppear { if !context.isPreview { monitor.start(threshold: threshold) } }
    }

    private var fliesLine: String {
        guard instance.config.bool("flies", default: true) else { return "苍蝇已关闭" }
        let label = TrashFlies.thresholds.first { $0.value == thresholdValue }?.label ?? "100 MB"
        if flies == 0 { return thresholdValue == "any" ? "有东西就会招来苍蝇" : "超过 \(label) 会招来苍蝇" }
        return "\(flies) 只苍蝇，放得越久越多"
    }
}
