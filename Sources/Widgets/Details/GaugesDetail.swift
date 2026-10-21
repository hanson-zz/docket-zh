import AppKit
import SwiftUI

/// 圆环仪表面板（效果图 panel-practicality-b 第 1 列「改后」），两个状态：
///
/// - 浏览：卡片上的圆环按卡片的先后每个一行，左边圆环，右边读数和警戒线说明，
///   行尾箭头跳到对应的地方（存储去「储存空间」设置、电池去「电池」设置、CPU 和
///   内存去活动监视器）。存储下面一条分段条：应用、下载、废纸篓、其他各占多少
///   （`StorageBreakdownReader`，面板打开时量，十分钟内不重量）；CPU 和内存下面
///   列占用最高的 3 个（`ProcessMonitor`，面板开着才读）。
/// - 编辑：圆环的「可拖动勾选列表」（勾选显示哪些、拖动排序），下面每个圆环一行
///   警戒线，加减按钮在几档里挪（`GaugeAlert`）。
struct GaugesDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing = false
    /// 这一次浏览态有没有让进程监视开读，关的时候只撤自己开的那一份。
    @State private var watching = false
    @Environment(\.panelTint) private var panelTint

    static let accentHex = "#7FD1FF"
    static let accentInkHex = "#04263A"

    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var ink: Color { panelTint.ink(or: Color(hex: Self.accentInkHex)) }

    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var rings: [String] { GaugeReading.rings(current.config) }
    private var monitor: ProcessMonitor { ProcessMonitor.shared }
    private var storageReader: StorageBreakdownReader { StorageBreakdownReader.shared }
    private var watchesProcesses: Bool { rings.contains("cpu") || rings.contains("memory") }

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
                if editing { edit } else { browse }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            SystemMetrics.shared.start()
            BatteryMetrics.shared.start()
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tr("圆环仪表"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(verbatim: editing ? tr("勾选显示哪些 · 拖动排序 · 警戒线")
                     : tr("\(rings.count) 个圆环 · 编辑里拖动排序"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !context.isPreview {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { editing.toggle() }
                } label: {
                    Text(verbatim: editing ? tr("完成") : tr("编辑"))
                        .font(.system(size: 13, weight: editing ? .bold : .semibold))
                        .foregroundStyle(editing ? ink : .panelPrimary)
                        .padding(.horizontal, editing ? 15 : 13)
                        .frame(height: 28)
                        .background(Capsule().fill(editing ? accent : .panelFill))
                        .overlay(Capsule().strokeBorder(editing ? Color.clear : Color.panelStroke, lineWidth: 0.6))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 浏览

    private var browse: some View {
        VStack(spacing: 8) {
            ForEach(rings, id: \.self) { ring in row(ring) }
        }
        .onAppear {
            guard !context.isPreview else { return }
            if watchesProcesses, !watching {
                monitor.begin()
                watching = true
            }
            if rings.contains("storage") { storageReader.refresh() }
        }
        .onDisappear {
            if watching {
                monitor.end()
                watching = false
            }
        }
    }

    private func row(_ ring: String) -> some View {
        let reading = GaugeLive.reading(ring, config: current.config, preview: context.isPreview)
        let line = GaugeAlert.value(ring, current.config)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                GaugeRing(reading: reading, diameter: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: headline(ring, reading))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(reading.alert ? GaugeLive.red.panelReadable : .panelPrimary)
                        .monospacedDigit()
                    Text(verbatim: GaugeAlert.caption(ring, line))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button { jump(ring) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.panelFill))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .help(jumpHelp(ring))
            }
            switch ring {
            case "storage": storageBar
            case "cpu": topList(cpu: true)
            case "memory": topList(cpu: false)
            default: EmptyView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(reading.alert ? GaugeLive.red.opacity(0.6) : .panelStroke, lineWidth: 0.6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GaugeAlert.title(ring))
    }

    /// “存储 · 剩 92 GB”“CPU · 35%”“电池 · 76% · 使用电池”。
    private func headline(_ ring: String, _ reading: GaugeLive.Reading) -> String {
        switch ring {
        case "storage": return tr("存储 · 剩 \(reading.value)")
        case "battery": return tr("电池 · \(reading.value) · \(reading.caption)")
        default: return "\(GaugeAlert.title(ring)) · \(reading.value)"
        }
    }

    // MARK: 存储分段条

    private static let partColors: [String: String] = [
        tr("应用"): "#7FD1FF", tr("下载"): "#F5C451", tr("废纸篓"): "#FF8A6B", tr("其他"): "#8E6CE0",
    ]

    @ViewBuilder
    private var storageBar: some View {
        let bytes = GaugeLive.storageBytes(preview: context.isPreview)
        let free = bytes.free
        let total = bytes.total
        let breakdown = context.isPreview
            ? StorageBreakdown(apps: 180_000_000_000, downloads: 104_000_000_000, trash: 38_000_000_000)
            : storageReader.breakdown
        if let breakdown, total > 0 {
            let parts = breakdown.parts(used: max(0, total - free), total: total)
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.name) { part in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(hex: Self.partColors[part.name] ?? "#8E6CE0"))
                                .frame(width: max(2, geo.size.width * min(part.fraction, 1) - 2))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 8)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.panelTrack))
                Text(verbatim: parts.filter { $0.name != tr("其他") }
                    .map { "\($0.name) \(GaugeReading.bytes($0.bytes))" }
                    .joined(separator: " · "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if total > 0 {
            Text(verbatim: storageReader.measuring ? tr("正在统计应用、下载和废纸篓…") : tr("面板打开时统计应用、下载和废纸篓"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
        }
    }

    // MARK: 占用最高

    @ViewBuilder
    private func topList(cpu: Bool) -> some View {
        let rows = context.isPreview ? Self.sampleRows : Array((cpu ? monitor.topCPU : monitor.topMemory).prefix(3))
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: tr("占用最高"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            if rows.isEmpty {
                Text(verbatim: tr("正在读取…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            ForEach(rows) { row in
                HStack {
                    Text(verbatim: context.isPreview ? row.name : monitor.name(for: row))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(verbatim: cpu ? ProcessRanking.cpuText(row.cpuPercent) : ProcessRanking.memoryText(row.memory))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
            }
        }
    }

    private static let sampleRows: [ProcessUsageRow] = [
        ProcessUsageRow(group: "a", name: tr("浏览器"), pids: [1], cpuPercent: 18, memory: 2_100_000_000),
        ProcessUsageRow(group: "b", name: "Xcode", pids: [2], cpuPercent: 9, memory: 1_600_000_000),
        ProcessUsageRow(group: "c", name: tr("音乐"), pids: [3], cpuPercent: 3, memory: 400_000_000),
    ]

    // MARK: 跳转

    private func jump(_ ring: String) {
        switch ring {
        case "storage":
            AppCatalog.shared.open(.settings("com.apple.settings.Storage"))
        case "battery":
            AppCatalog.shared.open(.settings("com.apple.Battery-Settings.extension"))
        default:
            AppCatalog.shared.open(.app(bundleID: "com.apple.ActivityMonitor"))
        }
    }

    private func jumpHelp(_ ring: String) -> String {
        switch ring {
        case "storage": tr("打开“储存空间”设置")
        case "battery": tr("打开“电池”设置")
        default: tr("打开活动监视器")
        }
    }

    // MARK: 编辑

    private var edit: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReorderableChecklist(
                choices: GaugeReading.allRings.map { ReorderableChecklist.Choice(value: $0, title: GaugeAlert.title($0)) },
                saved: rings,
                look: .panel(accent: accent, ink: ink),
                write: { list in
                    WidgetWriter.write(current) { $0.set("rings", .list(list.map { .string($0) })) }
                })
            Text(verbatim: tr("警戒线（过了线圆环变红）"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.top, 4)
            ForEach(rings, id: \.self) { ring in alertRow(ring) }
        }
    }

    private func alertRow(_ ring: String) -> some View {
        let line = GaugeAlert.value(ring, current.config)
        let choices = GaugeAlert.choices(ring)
        return HStack {
            Text(verbatim: GaugeAlert.title(ring))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton("minus", enabled: line != choices.first) { setLine(ring, GaugeAlert.stepped(ring, from: line, by: -1)) }
                Text(verbatim: GaugeAlert.short(ring, line))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 76)
                stepButton("plus", enabled: line != choices.last) { setLine(ring, GaugeAlert.stepped(ring, from: line, by: 1)) }
            }
            .frame(height: 30)
            .background(Capsule().fill(.panelFill))
            .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.panelFill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("\(GaugeAlert.title(ring))警戒线"))
        .accessibilityValue(GaugeAlert.short(ring, line))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setLine(ring, GaugeAlert.stepped(ring, from: line, by: 1))
            case .decrement: setLine(ring, GaugeAlert.stepped(ring, from: line, by: -1))
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.panelPrimary.opacity(enabled ? 0.85 : 0.3))
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || context.isPreview)
    }

    private func setLine(_ ring: String, _ value: Int) {
        guard !context.isPreview, value != GaugeAlert.value(ring, current.config) else { return }
        WidgetWriter.write(current) { $0.set(GaugeAlert.key(ring), .string(String(value))) }
    }
}
