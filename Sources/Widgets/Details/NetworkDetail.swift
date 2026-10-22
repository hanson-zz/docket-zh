import AppKit
import SwiftUI

/// 网络活动面板（效果图 panel-practicality-a 第 3 列「改后」）。
///
/// 从上到下：标题和 MB/s ↔ Mbps 切换（写卡片的 `unit`，卡片跟着变）；网络名和
/// 本机 IP（点名字拷贝名字，「拷贝 IP」拷贝地址）；此刻上下行和最近 60 秒的曲线；
/// 「谁在用网」前 5 个 App 和各自的上下行（系统自带 nettop 读，只在面板开着时读，
/// 读不了就整块不显示）；「今天」累计下载和上传（码头开着时累计，零点清零）。
///
/// 卡片是 Wi-Fi 圆环外观时，标题下多一块「信号大环」：104pt 的环按卡片选的样式
/// （经典或数字）画，右边是强度大字、「-52 dBm · 63%」和「连接 866 Mbps」。
/// 卡片设成只看下载或只看上传时，面板也只说那一个方向。
struct NetworkDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint
    /// 刚拷贝的是哪一个（"name" / "ip"），一秒半后变回去。
    @State private var copied: String?

    private var metrics: NetworkMetrics { NetworkMetrics.shared }
    private var top: NetworkTopApps { NetworkTopApps.shared }
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var unit: NetworkRateUnit { NetworkRateUnit.from(current.config) }
    private var preview: Bool { context.isPreview }

    private var accent: Color { panelTint.accent(or: Color(hex: NetPanelStyle.accent)) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: NetPanelStyle.accentInk)) }

    var body: some View {
        DetailCard {
            ZStack {
                // 液态玻璃：原来这里先铺一层实心石墨底（#1D1D21），去掉，只留角上一抹主题色。
                RadialGradient(colors: [accent.opacity(0.13), .clear],
                               center: UnitPoint(x: 0.95, y: 0), startRadius: 0, endRadius: 200)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let wifi = wifiStyle { signalHero(wifi) }
                headline
                if window >= 2 { history }
                if preview || top.available { whoSection }
                todaySection
            }
        }
        .onAppear {
            guard !preview else { return }
            metrics.start()
            top.panelAppeared()
            if wifiStyle != nil { WifiMetrics.shared.start() }
        }
        .onDisappear {
            guard !preview else { return }
            top.panelDisappeared()
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: tr("网络活动"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                unitSwitch
            }
            HStack(spacing: 8) {
                Button { copy(placeName, tag: "name") } label: {
                    Text(verbatim: copied == "name" ? tr("已拷贝名称") : placeLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(preview || !canCopyName)
                .help(canCopyName ? tr("点一下拷贝网络名称") : "")
                Spacer(minLength: 4)
                if let ip = address {
                    Button { copy(ip, tag: "ip") } label: {
                        Text(verbatim: copied == "ip" ? tr("已拷贝") : tr("拷贝 IP"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent.panelReadable)
                            .lineLimit(1)
                            .fixedSize()
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(preview)
                    .help(tr("拷贝本机 IP 地址"))
                }
            }
        }
    }

    private var unitSwitch: some View {
        HStack(spacing: 0) {
            ForEach(NetworkRateUnit.allCases, id: \.self) { option in
                let on = option == unit
                Button { setUnit(option) } label: {
                    Text(verbatim: option.label)
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? accentInk : .panelPrimary)
                        .frame(width: 58, height: 22)
                        .background(Capsule().fill(on ? accent : .clear))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.panelFill))
        .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
        .help(tr("网速单位，卡片也跟着变"))
    }

    private func setUnit(_ option: NetworkRateUnit) {
        guard !preview, option != unit else { return }
        WidgetWriter.write(current) { $0[NetworkRateUnit.key] = .string(option.rawValue) }
    }

    private var placeName: String {
        if preview { return tr("家里-5G") }
        return NetworkPlaceText.name(onWifi: top.onWifi, ssid: top.ssid, hasAddress: top.address != nil)
    }

    private var address: String? { preview ? "192.168.1.23" : top.address }

    /// 只有真拿到了 Wi-Fi 名称才有东西可拷（「Wi-Fi」「有线网络」不拷）。
    private var canCopyName: Bool { top.onWifi && !(top.ssid ?? "").isEmpty }

    private var placeLine: String {
        let name = placeName
        guard let ip = address else { return name }
        // 网络名就是「Wi-Fi」时前面不再重复一遍。
        return (top.onWifi && name != "Wi-Fi") || preview ? "Wi-Fi \(name) · \(ip)" : "\(name) · \(ip)"
    }

    private func copy(_ text: String, tag: String) {
        guard !preview, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = tag }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copied == tag { withAnimation(.easeOut(duration: 0.15)) { copied = nil } }
        }
    }

    // MARK: Wi-Fi 圆环外观：顶部信号大环

    private var wifiStyle: WifiRingStyle? {
        WifiRingStyle.shown(layout: instance.config.string("layout", default: "speed"),
                            unlocked: ProAccess.isUnlocked || preview)
    }

    /// 大环的直径（效果图 104pt）。
    private static let heroRing: CGFloat = 104

    private func signalHero(_ style: WifiRingStyle) -> some View {
        let rssi = preview ? -52 : WifiMetrics.shared.rssi
        let rate = preview ? 866 : WifiMetrics.shared.rate
        let reading = WifiReading(rssi: rssi)
        let summary = WifiSignalSummary(rssi: rssi, rate: rate)
        return HStack(spacing: 16) {
            WifiRingView(style: style, reading: reading, diameter: Self.heroRing)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: summary.label)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(15.0 / 24)
                Group {
                    // 没连上时只留「未连接」一个词。
                    if let level = summary.level { Text(verbatim: level) }
                    if let link = summary.link { Text(verbatim: link) }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(13.0 / 15)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pane(0.06, radius: 16))
        .accessibilityElement(children: .combine)
    }

    // MARK: 此刻

    private var headline: some View {
        HStack(spacing: 12) {
            if showsDownload { reading("arrow.down", tr("下载"), download, Self.downTint) }
            if showsUpload { reading("arrow.up", tr("上传"), upload, Self.upTint) }
        }
    }

    private func reading(_ symbol: String, _ name: String, _ rate: Double, _ tint: Color) -> some View {
        let value = NetworkRateFormat.format(rate, unit: unit)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint.panelReadable)
            Text(verbatim: value.value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.panelPrimary)
                .contentTransition(.numericText())
            Text(verbatim: value.unit)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue("\(value.value) \(value.unit)")
    }

    // MARK: 最近 60 秒

    /// 两个方向同一把尺子（取两条的峰值，至少 1 KB/s），闲着的一分钟贴底。
    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if showsDownload {
                    DitherChart(samples: downloadHistory, tint: Self.downTint, filled: false, range: scale)
                }
                if showsUpload {
                    DitherChart(samples: uploadHistory, tint: Self.upTint, filled: false, range: scale)
                }
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            Text(verbatim: historyCaption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 曲线下一行：多长时间、峰值多少（原来面板的峰值换成一行字）。
    private var historyCaption: String {
        let span = window >= NetworkMetrics.historyLength ? tr("最近 60 秒") : tr("最近 \(window) 秒")
        var peaks: [String] = []
        if showsDownload { peaks.append("↓" + NetworkRateFormat.text(downloadHistory.max() ?? 0, unit: unit)) }
        if showsUpload { peaks.append("↑" + NetworkRateFormat.text(uploadHistory.max() ?? 0, unit: unit)) }
        return tr("\(span) · 峰值 \(peaks.joined(separator: " "))")
    }

    private var scale: ClosedRange<Double> {
        let peaks = [showsDownload ? (downloadHistory.max() ?? 0) : 0, showsUpload ? (uploadHistory.max() ?? 0) : 0]
        return 0...max(peaks.max() ?? 0, 1024)
    }

    // MARK: 谁在用网

    private var whoRows: [NetAppUsage] {
        if preview {
            return [
                NetAppUsage(id: "a", name: tr("浏览器"), bundleID: nil, download: 7_750_000, upload: 140_000),
                NetAppUsage(id: "b", name: tr("网盘同步"), bundleID: nil, download: 3_500_000, upload: 620_000),
                NetAppUsage(id: "c", name: tr("微信"), bundleID: nil, download: 762_000, upload: 90_000),
                NetAppUsage(id: "d", name: tr("音乐"), bundleID: nil, download: 287_000, upload: 4_000),
                NetAppUsage(id: "e", name: tr("系统更新"), bundleID: nil, download: 50_000, upload: 2_000),
            ]
        }
        return top.apps
    }

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("谁在用网"), trailing: tr("下载 / 上传"))
            let rows = whoRows
            if rows.isEmpty {
                Text(verbatim: preview || top.loaded ? tr("这会儿没有 App 在用网") : tr("正在读取…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(pane(0.06, radius: 11))
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        whoRow(row, striped: index.isMultiple(of: 2))
                    }
                }
            }
        }
    }

    private func whoRow(_ row: NetAppUsage, striped: Bool) -> some View {
        HStack(spacing: 10) {
            AppIconSquare(name: row.name, url: nil, bundleID: preview ? nil : row.bundleID, size: 24)
            Text(verbatim: row.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(verbatim: rowRates(row))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            if striped { pane(0.06, radius: 11) }
        }
        .accessibilityElement(children: .combine)
    }

    /// 「↓62 ↑1.2 Mbps」：单位只写一次，省地方。只看一个方向时只写那一个。
    private func rowRates(_ row: NetAppUsage) -> String {
        let down = NetworkRateFormat.format(row.download, unit: unit)
        let up = NetworkRateFormat.format(row.upload, unit: unit)
        if !showsUpload { return "\(down.value) \(down.unit)" }
        if !showsDownload { return "\(up.value) \(up.unit)" }
        if down.unit == up.unit { return "↓\(down.value) ↑\(up.value) \(up.unit)" }
        return "↓\(down.value) \(down.unit) ↑\(up.value) \(up.unit)"
    }

    // MARK: 今天

    private var todaySection: some View {
        let totals = preview ? (download: UInt64(3_435_973_837), upload: UInt64(429_916_160))
            : metrics.todayShown(at: context.now)
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("今天"), trailing: tr("零点清零"))
            HStack(spacing: 8) {
                totalTile(tr("下载"), NetworkByteFormat.text(totals.download))
                totalTile(tr("上传"), NetworkByteFormat.text(totals.upload))
            }
        }
        .help(tr("码头开着时累计，零点清零"))
    }

    private func totalTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Text(verbatim: value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(pane(0.07))
        .accessibilityElement(children: .combine)
    }

    // MARK: 零件

    private func sectionTitle(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(verbatim: text)
            Spacer(minLength: 8)
            if let trailing { Text(verbatim: trailing) }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.panelSecondary)
        .lineLimit(1)
        .padding(.top, 2)
    }

    private func pane(_ opacity: Double, radius: CGFloat = 12) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.panelFill) // 原来 0.06 到 0.07 的白底都落在薄玻璃填充档
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.panelStroke, lineWidth: 0.6))
    }

    // MARK: 配置和数据（和卡片同一套键）

    private static let downTint = Color(hex: MetricColor.netDownload)
    private static let upTint = Color(hex: MetricColor.netUpload)

    private var display: String { current.config.string("display", default: "both") }
    private var showsDownload: Bool { display != "upload" }
    private var showsUpload: Bool { display != "download" }

    private var window: Int { min(downloadHistory.count, uploadHistory.count) }

    private var download: Double { preview ? 12_400_000 : metrics.download }
    private var upload: Double { preview ? 800_000 : metrics.upload }

    private var downloadHistory: [Double] {
        preview ? Self.sample(peak: 15_000_000, phase: 0) : metrics.downloadHistory
    }

    private var uploadHistory: [Double] {
        preview ? Self.sample(peak: 1_200_000, phase: 1.7) : metrics.uploadHistory
    }

    private static func sample(peak: Double, phase: Double) -> [Double] {
        (0..<40).map { i in
            let t = Double(i) / 4 + phase
            return peak * (0.45 + 0.35 * sin(t) + 0.18 * sin(t * 2.3))
        }
    }
}

/// 网络活动面板的颜色，照效果图 ACC["net"]。
enum NetPanelStyle {
    static let base = "#1d1d21"
    static let accent = "#4FD1C5"
    static let accentInk = "#032B27"
}
