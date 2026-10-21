import AppKit
import SwiftUI

/// 废纸篓面板，照第三批效果图（L3）：上面是桶、苍蝇、大小和项目数；中间「最近扔的」
/// 列最近 5 个，每行「放回」（放回访达记下的原位置）和「显示」（在访达里选中）；
/// 底下「打开废纸篓」和实心的「清空…」。废纸篓从有到空时桶会吞几张纸。
///
/// 读废纸篓要「完全磁盘访问权限」：没有时不列，只给说明和去设置的按钮。放不回去
/// （不知道原位置、原文件夹不在了、同名、没权限）时在列表下面写一句明确的话。
struct TrashDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint

    private var monitor: TrashMonitor { TrashMonitor.shared }
    @State private var scaredAt: Date?
    @State private var hovering = false
    @State private var targeted = false
    @State private var swallowAt: Date?
    /// 放回失败时的一句话，几秒后自己消失；`noticeID` 防止旧的计时清掉新的话。
    @State private var notice: (text: String, ok: Bool)?
    @State private var noticeID = 0

    private var accent: Color { panelTint.accent(or: Color(hex: "#7BD88F")) }
    private var ink: Color { panelTint.ink(or: Color(hex: "#06240E")) }

    private var thresholdValue: String { instance.config.string("threshold", default: TrashFlies.defaultThreshold) }
    private var threshold: Int64 { TrashFlies.thresholdBytes(thresholdValue) }
    private var bytes: Int64 { context.isPreview ? 2_400_000_000 : monitor.bytes }
    private var items: Int { context.isPreview ? 37 : monitor.items }
    private var needsAccess: Bool { !context.isPreview && monitor.needsAccess }
    private var flies: Int {
        guard instance.config.bool("flies", default: true) else { return 0 }
        return context.isPreview ? 5 : monitor.flies(now: context.now, threshold: threshold)
    }

    /// 预览（添加小组件面板）不读磁盘，放三条示例。
    private var recent: [TrashedItem] {
        guard context.isPreview else { return monitor.recent }
        let now = context.now
        return [TrashedItem(trashName: tr("旧稿.key"), date: now.addingTimeInterval(-300)),
                TrashedItem(trashName: "截屏 10.12.png", date: now.addingTimeInterval(-3600)),
                TrashedItem(trashName: tr("安装包.dmg"), date: now.addingTimeInterval(-86_400))]
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.green))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                summary
                if needsAccess {
                    accessNote
                } else if !recent.isEmpty {
                    recentList
                }
                if let notice { noticeLine(notice) }
                HStack(spacing: 8) {
                    pill(tr("打开废纸篓"), solid: false) {
                        guard !context.isPreview else { return }
                        monitor.open()
                    }
                    pill(tr("清空…"), solid: items > 0) {
                        guard !context.isPreview else { return }
                        monitor.empty()
                    }
                }
                Text(verbatim: tr("把文件拖到卡片上即可移到废纸篓。苍蝇的灵感来自 BananaBin。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !context.isPreview else { return false }
            return monitor.trash(urls)
        } isTargeted: { targeted = $0 }
        .onAppear { if !context.isPreview { monitor.start(threshold: threshold) } }
        .onChange(of: items) { before, now in
            if !context.isPreview, before > 0, now == 0 { swallowAt = .now }
        }
        .task(id: swallowAt) {
            guard swallowAt != nil else { return }
            try? await Task.sleep(for: .seconds(SwallowMotion.duration))
            guard !Task.isCancelled else { return }
            swallowAt = nil
        }
        .task(id: noticeID) {
            guard noticeID > 0 else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { notice = nil }
        }
    }

    // MARK: 桶和大小

    private var summary: some View {
        HStack(spacing: 14) {
            ZStack {
                SwallowingBin(startedAt: swallowAt, binSize: 40) {
                    Image(systemName: items > 0 ? "trash.fill" : "trash")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(targeted ? Color.red.panelReadable : .panelPrimary)
                }
                FlySwarm(count: flies, scaredAt: scaredAt, hovering: hovering,
                         animated: !context.isPreview, flySize: 1.5)
                    .frame(width: 110, height: 90)
                    .allowsHitTesting(false)
            }
            .frame(width: 84, height: 76)
            .contentShape(.rect)
            .onHover { inside in
                hovering = inside
                scaredAt = inside ? .now : .now.addingTimeInterval(-0.6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: needsAccess ? tr("需要权限") : TrashFlies.format(bytes: bytes))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: items == 0 ? tr("废纸篓是空的") : tr("\(items) 个项目"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                Text(verbatim: fliesLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var accessNote: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: tr("macOS 要求“完全磁盘访问权限”才能读取废纸篓的大小和最近扔的东西。打开设置后把“码头”加入列表并打开开关。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            pill(tr("打开隐私设置"), solid: true) { monitor.openAccessSettings() }
        }
    }

    // MARK: 最近扔的

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: tr("最近扔的"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.bottom, 2)
            ForEach(recent) { item in
                row(item)
            }
        }
    }

    private func noticeLine(_ notice: (text: String, ok: Bool)) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: notice.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(notice.ok ? accent.panelReadable : Color(hex: "#FFB547").panelReadable)
            Text(verbatim: notice.text)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity)
    }

    private func row(_ item: TrashedItem) -> some View {
        HStack(spacing: 10) {
            icon(item)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: caption(item))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button {
                guard !context.isPreview else { return }
                monitor.reveal(item)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 28, height: 26)
                    .background(Capsule().fill(.panelFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(tr("在访达中显示"))
            .accessibilityLabel(tr("显示"))
            Button {
                putBack(item)
            } label: {
                Text(verbatim: tr("放回"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(.panelFill))
                    .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(item.origin.map { tr("放回「\(TrashPutBack.displayFolder($0.folder))」") }
                  ?? tr("不知道原来在哪，点了会说明"))
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.panelFill))
        .contextMenu {
            Button(tr("放回原处")) { putBack(item) }
            Button(tr("在访达中显示")) { if !context.isPreview { monitor.reveal(item) } }
        }
    }

    @ViewBuilder
    private func icon(_ item: TrashedItem) -> some View {
        if context.isPreview {
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(.panelSecondary)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: monitor.location(of: item).path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private func caption(_ item: TrashedItem) -> String {
        let when = RelativeAge.caption(item.date, now: context.now)
        guard let origin = item.origin else { return when }
        return "\(when) · \(TrashPutBack.displayFolder(origin.folder))"
    }

    private func putBack(_ item: TrashedItem) {
        guard !context.isPreview else { return }
        let message = monitor.putBack(item)
        withAnimation(.snappy(duration: 0.2)) {
            notice = (message ?? tr("已放回「\(item.displayName)」"), message == nil)
        }
        noticeID += 1
    }

    private func pill(_ title: String, solid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? ink : .panelPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(solid ? accent : .panelFill))
                .overlay(Capsule().strokeBorder(solid ? Color.clear : Color.panelStroke, lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var fliesLine: String {
        guard instance.config.bool("flies", default: true) else { return tr("苍蝇已关闭") }
        let label = TrashFlies.thresholds.first { $0.value == thresholdValue }?.label ?? "100 MB"
        if flies == 0 { return thresholdValue == "any" ? tr("有东西就会招来苍蝇") : tr("超过 \(label) 会招来苍蝇") }
        return tr("\(flies) 只苍蝇，放得越久越多")
    }
}
