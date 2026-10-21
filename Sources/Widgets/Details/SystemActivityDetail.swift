import AppKit
import SwiftUI

/// 系统活动面板（效果图 panels-batch1 第 4 列），两个状态：
///
/// - 浏览：头上“系统活动”和开机多久，右上“提醒”。CPU、内存、网络、磁盘四格
///   读数，各带一条小曲线（CPU、内存、网络是最近 60 秒，磁盘是最近一小时）。
///   下面是最近 24 小时的曲线，可切四个指标，标出峰值和时间（磁盘标可用最少
///   的那一刻）；数据是 SystemMetrics 每分钟记一条、存在 Application Support 的
///   24 小时环形缓冲。占用最高的 5 个进程和曲线分两页（顶部分段，记住切到的
///   那页），按 CPU 或内存排，普通 App 每行有“退出”，点了先在列表上方弹一张
///   红色确认卡，确认后礼貌地退出（不强制）。
/// - 提醒与管理：超阈值提醒的规则（码头 Pro）：指标、阈值滑杆、持续几分钟、
///   开关、添加和删除；到点发系统通知，卡片上那个读数变红。没解锁时规则照样
///   列出，改动弹付费墙，不判断也不提醒。最下面勾选卡片上显示哪几项（`metrics`）。
struct SystemActivityDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, manage }

    @State private var mode: Mode = .browse
    @State private var chartMetric: SystemMetricKind = .cpu
    /// 点了“退出”、等确认的那一行。
    @State private var pendingQuit: ProcessUsageRow?
    @State private var quitFailed: String?
    /// 展开编辑的那条规则。
    @State private var expandedRule: String?
    /// 拖滑杆时先不写配置，松手再写。
    @State private var draggingThreshold: Double?
    /// 浏览态记住的分页，见 `BrowsePage`。
    @AppStorage(DetailPanelSections.pageKey(.system)) private var storedPage = ""

    /// 浏览态四格读数下面的分页。
    private enum BrowsePage: String, CaseIterable {
        case day, processes

        var title: String {
            switch self {
            case .day: tr("24 小时")
            case .processes: tr("占用最高")
            }
        }
    }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.panelTint) private var panelTint

    private var accent: Color { panelTint.accent(or: Color(hex: SystemActivityStyle.accent)) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: SystemActivityStyle.accentInk)) }
    private var red: Color { Color(hex: SystemActivityStyle.alertRed) }
    private var unlocked: Bool { ProLicenseGate.systemAlertsActive(unlocked: licenseUnlocked || supporter) }

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var metrics: SystemMetrics { SystemMetrics.shared }
    private var monitor: ProcessMonitor { ProcessMonitor.shared }

    var body: some View {
        DetailCard {
            ZStack {
                Color(hex: SystemActivityStyle.base)
                // 右上角一抹很淡的绿，不做大面积发光。
                RadialGradient(colors: [accent.opacity(0.13), .clear],
                               center: UnitPoint(x: 0.95, y: 0), startRadius: 0, endRadius: 200)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch mode {
                case .browse: browse
                case .manage: manage
                }
            }
        }
        .onAppear { if !context.isPreview { SystemMetrics.shared.start() } }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: mode == .browse ? tr("系统活动") : tr("提醒与管理"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(verbatim: subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !context.isPreview {
                switch mode {
                case .browse:
                    Button { switchTo(.manage) } label: {
                        Text(verbatim: tr("提醒"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 13)
                            .frame(height: 28)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(tr("超阈值提醒和卡片上显示的读数"))
                case .manage:
                    Button { switchTo(.browse) } label: {
                        Text(verbatim: tr("完成"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accentInk)
                            .padding(.horizontal, 15)
                            .frame(height: 28)
                            .background(Capsule().fill(accent))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var subtitle: String {
        switch mode {
        case .browse:
            if context.isPreview { return SystemReadout.uptime(3 * 86_400 + 4 * 3_600) }
            guard let boot = SystemMetrics.bootTime else { return tr("CPU、内存、网络、磁盘") }
            return SystemReadout.uptime(Date.now.timeIntervalSince(boot))
        case .manage:
            return tr("超阈值提醒 · 卡片读数")
        }
    }

    private func switchTo(_ next: Mode) {
        pendingQuit = nil
        quitFailed = nil
        withAnimation(.easeInOut(duration: 0.2)) { mode = next }
    }

    // MARK: 浏览

    private var browse: some View {
        let page = DetailPanelSections.page(stored: storedPage, available: BrowsePage.allCases) ?? .day
        // 四格读数压到约 78pt、竖向间距 12→10、进程行 44→34：「占用最高」页
        // 5 行全显示，面板约 553pt，在 560 限高内不用滚。
        return VStack(alignment: .leading, spacing: 10) {
            readingsGrid
            // 面板统一限高后，四格读数下面分两页：最近 24 小时曲线和占用最高的进程。
            // 切到的那页记住。
            DetailSegmented(pages: BrowsePage.allCases, title: { $0.title }, selected: page) { picked in
                storedPage = picked.rawValue
            }
            switch page {
            case .day: dayChart
            case .processes: processes
            }
        }
        .onAppear { if !context.isPreview { ProcessMonitor.shared.begin() } }
        .onDisappear { if !context.isPreview { ProcessMonitor.shared.end() } }
    }

    // MARK: 四格读数

    private var readingsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(SystemMetricKind.allCases, id: \.self) { cell($0) }
        }
    }

    private func isFiring(_ metric: SystemMetricKind) -> Bool {
        !context.isPreview && SystemAlerts.shared.firing.contains(metric)
    }

    private func cell(_ metric: SystemMetricKind) -> some View {
        let reading = readout(metric)
        let firing = isFiring(metric)
        let tint = firing ? red : accent
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(verbatim: metric.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                if firing {
                    Circle().fill(red).frame(width: 6, height: 6)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: reading.value)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(firing ? red : .white)
                    .rollingValue(reading.value)
                Text(verbatim: reading.unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            spark(reading.series, minimumSpan: reading.minimumSpan)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(height: 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(reading.value) \(reading.unit)")
    }

    private struct Readout {
        var value: String
        var unit: String
        var series: [Double]
        var minimumSpan: Double
    }

    private func readout(_ metric: SystemMetricKind) -> Readout {
        if context.isPreview { return Self.sampleReadout(metric) }
        switch metric {
        case .cpu:
            return Readout(value: "\(SystemReadout.percent(metrics.cpu))", unit: "%",
                           series: metrics.cpuHistory, minimumSpan: 0.08)
        case .memory:
            let gib = 1024.0 * 1024 * 1024
            let total = Double(ProcessInfo.processInfo.physicalMemory) / gib
            return Readout(value: String(format: "%.1f", metrics.memory * total),
                           unit: String(format: "/ %.0f GB", total),
                           series: metrics.memoryHistory, minimumSpan: 0.04)
        case .network:
            let rate = SystemReadout.rate(NetworkMetrics.shared.download)
            return Readout(value: rate.value, unit: tr("\(rate.unit) 下行"),
                           series: NetworkMetrics.shared.downloadHistory, minimumSpan: 64 * 1024)
        case .disk:
            let free = Double(metrics.diskFree)
            // 磁盘一秒一秒看是一条平线，拿 24 小时记录里最近一小时画。
            let recent = metrics.dayHistory.window(now: .now).suffix(60).map(\.diskFree)
            return Readout(value: metrics.diskTotal > 0 ? SystemReadout.gigabytes(free) : "-",
                           unit: tr("GB 可用"),
                           series: recent.count > 1 ? Array(recent) : [free, free],
                           minimumSpan: 2_000_000_000)
        }
    }

    /// 按曲线自己的范围画，留一个最小跨度，几乎平的线就画成平的，不放大噪声。
    private func spark(_ series: [Double], minimumSpan: Double) -> Sparkline {
        let lo = series.min() ?? 0
        let hi = series.max() ?? 0
        let span = max(hi - lo, minimumSpan)
        let mid = (hi + lo) / 2
        return Sparkline(values: series, peak: mid + span * 0.55, floor: mid - span * 0.55)
    }

    // MARK: 24 小时

    private var dayChart: some View {
        let now = Date.now
        let history = context.isPreview ? Self.sampleHistory(now: now) : metrics.dayHistory
        let segments = history.segments(chartMetric, now: now)
        let peak = history.peak(chartMetric, now: now)
        // 峰值那一分钟在曲线上的点：横坐标和 segments 用同一个算法，取最近的一点。
        let peakPoint: (x: Double, y: Double)? = peak.flatMap { sample in
            let x = 1 - Double(SystemActivityHistory.minute(of: now) - sample.minute)
                / Double(SystemActivityHistory.minutes)
            return segments.joined().min { abs($0.x - x) < abs($1.x - x) }
        }
        let firing = isFiring(chartMetric)
        let tint = firing ? red : accent
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SystemMetricKind.allCases, id: \.self) { metric in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { chartMetric = metric }
                    } label: {
                        Text(verbatim: metric.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(chartMetric == metric ? 1 : 0.7))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(.white.opacity(chartMetric == metric ? 0.2 : 0)))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    // 三条淡淡的横线。
                    Path { path in
                        for k in 0..<3 {
                            let y = size.height * CGFloat(k) / 2
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    if segments.isEmpty {
                        Text(verbatim: tr("每分钟记一次，记满 24 小时就是完整的一天"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: size.width, height: size.height)
                    } else {
                        ForEach(segments.indices, id: \.self) { index in
                            let points = segments[index]
                            area(points, in: size)
                                .fill(LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                            line(points, in: size)
                                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        }
                        if let peak, let point = peakPoint {
                            let px = CGFloat(point.x) * size.width
                            let py = (1 - CGFloat(point.y)) * size.height
                            Circle()
                                .fill(.white)
                                .frame(width: 7, height: 7)
                                .position(x: px, y: py)
                            Text(verbatim: SystemReadout.peakLabel(chartMetric, sample: peak))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .monospacedDigit()
                                .fixedSize()
                                .alignmentGuide(.leading) { d in
                                    px - 8 - d.width >= 0 ? d.width - (px - 8) : -(px + 8)
                                }
                                .alignmentGuide(.top) { d in -max(py - d.height - 2, 0) }
                        }
                    }
                }
            }
            .frame(height: 72)
            .padding(.top, 16)
            HStack {
                Text(verbatim: tr("24 小时前"))
                Spacer(minLength: 0)
                Text(verbatim: tr("12 小时前"))
                Spacer(minLength: 0)
                Text(verbatim: tr("现在"))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.top, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("最近 24 小时"))
    }

    private func line(_ points: [(x: Double, y: Double)], in size: CGSize) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let p = CGPoint(x: CGFloat(point.x) * size.width, y: (1 - CGFloat(point.y)) * size.height)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            // 只有一个点时画成一小段，不然看不见。
            if points.count == 1, let point = points.first {
                let x = CGFloat(point.x) * size.width
                path.addLine(to: CGPoint(x: max(x - 1.5, 0), y: (1 - CGFloat(point.y)) * size.height))
            }
        }
    }

    private func area(_ points: [(x: Double, y: Double)], in size: CGSize) -> Path {
        var path = line(points, in: size)
        guard let first = points.first, let last = points.last, points.count > 1 else { return path }
        path.addLine(to: CGPoint(x: CGFloat(last.x) * size.width, y: size.height))
        path.addLine(to: CGPoint(x: CGFloat(first.x) * size.width, y: size.height))
        path.closeSubpath()
        return path
    }

    // MARK: 占用最高

    private var processes: some View {
        let rows = context.isPreview ? Self.sampleRows : monitor.rows
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: tr("占用最高"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                Menu {
                    ForEach(ProcessSort.allCases, id: \.self) { sort in
                        Button(sort.title) { ProcessMonitor.shared.sort = sort }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: monitor.sort.title)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(context.isPreview)
            }
            .padding(.bottom, 4)

            if let pending = pendingQuit {
                quitConfirm(pending)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let quitFailed {
                Text(verbatim: quitFailed)
                    .font(.system(size: 13))
                    .foregroundStyle(red)
                    .padding(.vertical, 4)
            }

            if rows.isEmpty {
                Text(verbatim: tr("正在读取进程…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 34)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    processRow(row)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(.white.opacity(0.1))
                            .frame(height: 0.6)
                            .padding(.leading, 34)
                    }
                }
            }
        }
    }

    private func processRow(_ row: ProcessUsageRow) -> some View {
        let name = context.isPreview ? row.name : monitor.name(for: row)
        let canQuit = !context.isPreview && monitor.canQuit(row)
        return HStack(spacing: 10) {
            processIcon(row, size: 24)
            Text(verbatim: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(verbatim: monitor.sort == .cpu ? ProcessRanking.cpuText(row.cpuPercent)
                                                : ProcessRanking.memoryText(row.memory))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
            if canQuit {
                Button {
                    quitFailed = nil
                    withAnimation(.easeOut(duration: 0.18)) { pendingQuit = row }
                } label: {
                    Text(verbatim: tr("退出"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 24)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(tr("退出 \(name)"))
            } else {
                // 系统进程和码头自己不给退出，留出同样的宽度让数字对齐。
                Color.clear.frame(width: 50, height: 24)
                    .help(tr("不是普通 App，不能在这里退出"))
            }
        }
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func processIcon(_ row: ProcessUsageRow, size: CGFloat) -> some View {
        if !context.isPreview, let image = monitor.icon(for: row) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.white.opacity(0.7))
                }
        }
    }

    /// 退出前的确认：红色描边的卡片，取消 / 退出（实心红，深色字）。
    private func quitConfirm(_ row: ProcessUsageRow) -> some View {
        let name = monitor.name(for: row)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                processIcon(row, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tr("退出「\(name)」？"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: tr("CPU \(ProcessRanking.cpuText(row.cpuPercent)) · 内存 \(ProcessRanking.memoryText(row.memory))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .monospacedDigit()
                }
            }
            Text(verbatim: tr("没保存的内容可能会丢失"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { pendingQuit = nil }
                } label: {
                    Text(verbatim: tr("取消"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Button {
                    let sent = ProcessMonitor.shared.quit(row)
                    withAnimation(.easeOut(duration: 0.18)) { pendingQuit = nil }
                    if !sent { quitFailed = tr("「\(name)」没有退出，它可能已经关了") }
                } label: {
                    Text(verbatim: tr("退出"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: SystemActivityStyle.alertInk))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Capsule().fill(red))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(red.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(red.opacity(0.7), lineWidth: 1))
    }

    // MARK: 提醒与管理

    private var rules: [SystemAlertRule] { SystemAlertRules.rules(current.config) }

    private var manage: some View {
        let list = rules
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(verbatim: tr("超阈值提醒"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                ProCrown()
                Spacer(minLength: 0)
                if list.count < SystemAlertRules.maxCount {
                    Button(action: addRule) {
                        Text(verbatim: tr("＋ 添加规则"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !unlocked {
                Text(verbatim: tr("超阈值提醒是码头 Pro 功能。解锁后按下面的规则发系统通知，卡片上的读数变红。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if list.isEmpty {
                Text(verbatim: tr("还没有规则，点“添加规则”加一条"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            ForEach(list) { rule in
                if expandedRule == rule.id {
                    expanded(rule)
                } else {
                    collapsed(rule)
                }
            }
            Text(verbatim: tr("卡片上显示"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.top, 8)
            cardMetrics
        }
    }

    private func toggle(_ rule: SystemAlertRule) -> some View {
        Toggle("", isOn: Binding(
            get: { rule.enabled },
            set: { on in
                update(rule.id) { $0.enabled = on }
            }))
            .toggleStyle(.switch)
            .tint(accent)
            .labelsHidden()
            .controlSize(.small)
            .disabled(context.isPreview)
            .help(unlocked ? "" : ProFeatures.help)
    }

    private func collapsed(_ rule: SystemAlertRule) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: rule.summary)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(rule.enabled ? 1 : 0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            toggle(rule)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.6))
        .contentShape(.rect)
        .onTapGesture {
            draggingThreshold = nil
            withAnimation(.easeInOut(duration: 0.18)) { expandedRule = rule.id }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("展开编辑这条规则"))
    }

    private func expanded(_ rule: SystemAlertRule) -> some View {
        let range = SystemAlertRule.range(rule.metric)
        let shown = draggingThreshold ?? rule.threshold
        var preview = rule
        preview.threshold = shown
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(verbatim: preview.summary)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                toggle(rule)
            }
            .contentShape(.rect)
            .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { expandedRule = nil } }

            HStack(spacing: 6) {
                fieldLabel(tr("指标"))
                ForEach(SystemMetricKind.allCases, id: \.self) { metric in
                    let selected = metric == rule.metric
                    Button {
                        update(rule.id) { $0 = $0.switching(to: metric) }
                    } label: {
                        Text(verbatim: metric.title)
                            .font(.system(size: 13, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? accentInk : .white)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(selected ? accent : .white.opacity(0.1)))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                fieldLabel(rule.isBelow ? tr("低于") : tr("超过"))
                Slider(value: Binding(
                    get: { draggingThreshold ?? rule.threshold },
                    set: { draggingThreshold = $0 }),
                       in: range, step: SystemAlertRule.step(rule.metric),
                       onEditingChanged: { editing in
                    if !editing, let value = draggingThreshold {
                        draggingThreshold = nil
                        update(rule.id) { $0.threshold = value }
                    }
                })
                .tint(accent)
                .controlSize(.small)
                .disabled(context.isPreview)
                Text(verbatim: preview.thresholdText)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: 62, alignment: .trailing)
            }

            HStack(spacing: 8) {
                fieldLabel(tr("持续"))
                HStack(spacing: 0) {
                    stepButton("minus", enabled: rule.minutes > SystemAlertRule.minuteRange.lowerBound) {
                        update(rule.id) { $0.minutes = max($0.minutes - Self.minuteStep($0.minutes, down: true), 1) }
                    }
                    Text(verbatim: tr("\(rule.minutes) 分钟"))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 64)
                    stepButton("plus", enabled: rule.minutes < SystemAlertRule.minuteRange.upperBound) {
                        update(rule.id) { $0.minutes = min($0.minutes + Self.minuteStep($0.minutes, down: false), 60) }
                    }
                }
                .frame(height: 28)
                .background(Capsule().fill(.white.opacity(0.1)))
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: tr("到了发系统通知，卡片读数变红"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                Button { removeRule(rule.id) } label: {
                    Text(verbatim: tr("删除"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(red)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
    }

    /// 1 到 5 分钟一分钟一档，往上五分钟一档。
    private static func minuteStep(_ minutes: Int, down: Bool) -> Int {
        down ? (minutes > 5 ? 5 : 1) : (minutes >= 5 ? 5 : 1)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .frame(width: 34, alignment: .leading)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 32, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || context.isPreview)
    }

    // MARK: 卡片上显示

    private var cardMetrics: some View {
        let shown = SystemCardMetrics.shown(current.config)
        return HStack(spacing: 6) {
            ForEach(SystemCardMetrics.all, id: \.self) { key in
                let on = shown.contains(key)
                Button {
                    let next = SystemCardMetrics.toggling(key, in: shown)
                    guard next != shown, !context.isPreview else { return }
                    WidgetWriter.write(current) { $0.set(SystemCardMetrics.key, .list(next.map { .string($0) })) }
                } label: {
                    HStack(spacing: 3) {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(accent)
                        }
                        Text(verbatim: Self.metricTitle(key))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(on ? 1 : 0.7))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(.white.opacity(on ? 0.16 : 0.06)))
                    .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.5 : 0.14), lineWidth: 0.8))
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private static func metricTitle(_ key: String) -> String {
        if key == "battery" { return tr("电池") }
        return SystemMetricKind(rawValue: key)?.title ?? key
    }

    // MARK: 写规则

    /// 改一条规则。没解锁时弹付费墙，不改配置。
    private func update(_ id: String, _ change: (inout SystemAlertRule) -> Void) {
        guard !context.isPreview else { return }
        guard unlocked else { PaywallWindow.shared.show(); return }
        var list = rules
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
        let next = list
        WidgetWriter.write(current) { SystemAlertRules.store(next, in: &$0) }
    }

    private func addRule() {
        guard !context.isPreview else { return }
        guard unlocked else { PaywallWindow.shared.show(); return }
        var list = rules
        guard list.count < SystemAlertRules.maxCount else { return }
        let rule = SystemAlertRules.newRule(after: list)
        list.append(rule)
        let next = list
        WidgetWriter.write(current) { SystemAlertRules.store(next, in: &$0) }
        withAnimation(.easeInOut(duration: 0.18)) { expandedRule = rule.id }
    }

    private func removeRule(_ id: String) {
        guard !context.isPreview else { return }
        guard unlocked else { PaywallWindow.shared.show(); return }
        let next = rules.filter { $0.id != id }
        WidgetWriter.write(current) { SystemAlertRules.store(next, in: &$0) }
        if expandedRule == id { expandedRule = nil }
    }

    // MARK: 示例数据（小组件库的预览）

    private static func sampleReadout(_ metric: SystemMetricKind) -> Readout {
        func wave(_ base: Double, _ amp: Double, _ phase: Double) -> [Double] {
            var values: [Double] = []
            for i in 0..<30 {
                let t = Double(i)
                let slow: Double = sin(t / 3 + phase)
                let fast: Double = sin(t * 1.7)
                values.append(base + amp * slow + amp * 0.4 * fast)
            }
            return values
        }
        switch metric {
        case .cpu: return Readout(value: "23", unit: "%", series: wave(0.25, 0.08, 0), minimumSpan: 0.08)
        case .memory: return Readout(value: "11.2", unit: "/ 16 GB", series: wave(0.66, 0.02, 1), minimumSpan: 0.04)
        case .network: return Readout(value: "2.4", unit: tr("MB/s 下行"), series: wave(0.3, 0.12, 2), minimumSpan: 0.08)
        case .disk: return Readout(value: "212", unit: tr("GB 可用"), series: [0.3, 0.3], minimumSpan: 0.08)
        }
    }

    private static func sampleHistory(now: Date) -> SystemActivityHistory {
        var history = SystemActivityHistory()
        let end = SystemActivityHistory.minute(of: now)
        for step in 0..<96 {
            let minute = end - (95 - step) * 15
            let t = Double(step)
            let offset: Double = (t - 56) / 2.2
            let spike: Double = 0.7 * exp(-(offset * offset))
            let base: Double = 0.22 + 0.06 * sin(t / 2.3)
            let cpu = min(max(base + spike, 0.02), 0.98)
            let memory: Double = 0.66 + 0.03 * sin(t / 5)
            let network: Double = 400_000 + 300_000 * max(sin(t / 3), 0)
            let disk: Double = 212e9 - t * 1e8
            history.record(SystemMinuteSample(minute: minute, cpu: cpu, memory: memory,
                                              network: network, diskFree: disk))
        }
        return history
    }

    private static let sampleRows: [ProcessUsageRow] = [
        ProcessUsageRow(group: "a", name: tr("视频剪辑"), pids: [1], cpuPercent: 62, memory: 3_100_000_000),
        ProcessUsageRow(group: "b", name: tr("浏览器"), pids: [2], cpuPercent: 18, memory: 2_400_000_000),
        ProcessUsageRow(group: "c", name: tr("设计工具"), pids: [3], cpuPercent: 9, memory: 1_800_000_000),
        ProcessUsageRow(group: "d", name: tr("代码编辑器"), pids: [4], cpuPercent: 6, memory: 1_200_000_000),
        ProcessUsageRow(group: "e", name: tr("音乐"), pids: [5], cpuPercent: 2, memory: 400_000_000),
    ]
}

/// 效果图上的 Pro 标：金色小皇冠加“Pro”，13pt。
private struct ProCrown: View {
    var body: some View {
        let gold = Color(hex: SystemActivityStyle.gold)
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: ProFeatures.badgeTitle)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(gold)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(gold.opacity(0.16)))
        .overlay(Capsule().strokeBorder(gold.opacity(0.55), lineWidth: 0.6))
        .fixedSize()
        .help(ProFeatures.help)
        .accessibilityLabel(ProFeatures.label)
    }
}
