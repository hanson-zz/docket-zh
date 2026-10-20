import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 隔空投送：把文件拖到卡片上，松手交给系统的隔空投送面板。
///
/// - 普通态横排：左边圆角方底的同心弧图标，右边「隔空投送」和「拖文件到这里」。
/// - 拖着文件停在卡片上：系统蓝虚线框、很淡的蓝底，写「发送给附近设备」和
///   「N 个文件 · 松手选设备」（共用的拖入提示，见 `DropPrompt`）。
/// - 竖排只在空间不够时用（竖排货架或窄卡）：图标在上，「隔空投送」拆两行。
/// - 用不了（系统没有隔空投送服务）或拖来的不是文件时整张灰掉。
///
/// 发送交给 `NSSharingService(named: .sendViaAirDrop)`，选设备、发送进度和
/// 结果都在系统面板里，卡片上不显示发送成功。状态和文字在 Core 的
/// `AirDropDrop`，这里只负责画和接住拖放。
struct AirDropTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetHovered) private var hovered
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragging = false
    @State private var files = 0

    /// 系统隔空投送的蓝，浅色外观用深一点的那档。
    private var blue: Color { WidgetStyle.dropBlue(scheme) }

    /// 系统有没有隔空投送服务，启动后不会变，读一次。
    @MainActor private static var available: Bool { AirDropSender.available }

    private var state: AirDropDrop.State {
        AirDropDrop.state(available: context.isPreview || Self.available,
                          dragging: dragging, files: files)
    }

    private var column: Bool {
        AirDropDrop.usesColumn(vertical: context.position.isVertical,
                               width: WidgetCatalog.contentSize(instance, position: context.position).width)
    }

    var body: some View {
        WidgetSurface {
            Group {
                if column {
                    columnLayout
                } else {
                    // 小组件库的缩略图很矮时退成只有标题的一行，图标不顶出卡片。
                    ViewThatFits(in: .vertical) {
                        rowLayout
                        HStack(spacing: 8) {
                            badge(size: 26)
                            title(13)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .tileDisabled(state.disabled)
            .dropHidden(state.highlighted)
            .dockAnimation(.snappy(duration: 0.18), value: state)
        }
        .dropTargetOutline(state.highlighted, prompt: .airDrop(files: files), compact: column)
        .onDrop(of: [.fileURL, .item], delegate: AirDropDropDelegate(
            enabled: !context.isPreview && Self.available,
            update: { inside, count in
                dragging = inside
                files = count
            },
            send: { [id = instance.id] urls in _ = AirDropSender.send(urls, recordInto: id) }))
        .help(state.disabled ? state.caption : tr("把文件拖到这里，用隔空投送发送"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.title)，\(state.caption)")
    }

    // MARK: Layouts

    /// 横排：图标和其它卡片一样是 40pt 的圆角方底，文字两级。
    private var rowLayout: some View {
        HStack(spacing: WidgetStyle.rowSpacing) {
            badge(size: WidgetStyle.badge)
            VStack(alignment: .leading, spacing: 2) {
                title(15)
                Text(state.caption)
                    .font(WidgetStyle.note)
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    /// 竖排：图标在上，标题拆两行。
    private var columnLayout: some View {
        VStack(spacing: 4) {
            badge(size: WidgetStyle.badgeColumn)
            Text(AirDropDrop.columnTitle)
                .font(WidgetStyle.label(12))
                .foregroundStyle(state.highlighted ? blue : WidgetStyle.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(0)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private func title(_ size: CGFloat) -> some View {
        Text(state.title)
            .font(WidgetStyle.label(size))
            .foregroundStyle(state.highlighted ? blue : WidgetStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// 悬停或拖入时图标变蓝、微微放大；灰掉时是次要色。
    private var glyphColor: Color {
        if state.disabled { return WidgetStyle.secondary }
        return state.highlighted || (hovered && !context.isPreview) ? blue : WidgetStyle.primary
    }

    private func badge(size: CGFloat) -> some View {
        // 和货架其他卡片一样的中性玻璃底，不用苹果的蓝色应用图标。
        TileBadge(size: size) {
            AirDropGlyph()
                .stroke(glyphColor, style: StrokeStyle(lineWidth: max(1.4, size * 0.05), lineCap: .round))
                .frame(width: size * 0.56, height: size * 0.56)
                .overlay(alignment: .center) {
                    Circle()
                        .fill(glyphColor)
                        .frame(width: size * 0.1, height: size * 0.1)
                        .offset(y: size * 0.56 * 0.08)
                }
        }
        .scaleEffect(TileState.resolve(hovered: false, targeted: state.highlighted)
            .badgeScale(reduceMotion: reduceMotion))
        .dockAnimation(.snappy(duration: 0.18), value: state.highlighted)
        .dockAnimation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// 接住拖放：数拖进来的文件个数给卡片显示，松手后读出文件地址再发送。
/// 卡片和面板（整块面板就是拖放区）共用。
@MainActor
struct AirDropDropDelegate: DropDelegate {
    var enabled: Bool
    var update: @MainActor (Bool, Int) -> Void
    var send: @MainActor ([URL]) -> Void

    private func count(_ info: DropInfo) -> Int {
        info.itemProviders(for: [.fileURL]).count
    }

    func dropEntered(info: DropInfo) {
        guard enabled else { return }
        update(true, count(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard enabled else { return DropProposal(operation: .forbidden) }
        let files = count(info)
        update(true, files)
        return DropProposal(operation: files > 0 ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        update(false, 0)
    }

    func validateDrop(info: DropInfo) -> Bool {
        enabled && info.hasItemsConforming(to: [.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        update(false, 0)
        let providers = info.itemProviders(for: [.fileURL])
        guard enabled, !providers.isEmpty else { return false }
        let send = self.send
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.load(provider) { urls.append(url) }
            }
            send(urls)
        }
        return true
    }

    /// 文件地址在拖放里是一段 file URL 的数据。
    @MainActor
    private static func load(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }
}

/// 隔空投送的样子：一个点外面三圈同心圆弧，底下留个缺口。SF Symbols 里
/// 没有这个图形，原来借的 Wi-Fi 式扇形波纹看起来像无线网，这里自己画。
struct AirDropGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08)
        let outer = min(rect.width, rect.height) / 2
        // 底部留 80 度的缺口（SwiftUI 角度从 3 点钟方向起、顺时针为正）。
        let start = Angle.degrees(130)
        let end = Angle.degrees(50)
        for ratio in [0.36, 0.68, 1.0] {
            // 先挪到这一圈的起点，不然三段弧会被直线连起来。
            let r = outer * ratio
            path.move(to: CGPoint(x: center.x + r * cos(start.radians), y: center.y + r * sin(start.radians)))
            path.addArc(center: center, radius: outer * ratio, startAngle: start, endAngle: end, clockwise: false)
        }
        return path
    }
}
