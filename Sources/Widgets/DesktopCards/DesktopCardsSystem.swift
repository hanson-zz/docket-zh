import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 钉在桌面 · 系统组
//
// 电池、系统活动、网络、圆环仪表、快速开关、隔空投送、废纸篓、应用切换器、快捷指令、
// 搜索钉在桌面时的三档专属布局（小 160×160、中 340×160、大 340×340）。每档几个、几列、
// 列表几行按 Core 的 `DesktopSystemCards` 排。
//
// 数据和扩展栏是同一份：读同一个采样器（BatteryMetrics、SystemMetrics、NetworkMetrics……），
// 改设置走 `WidgetWriter`，开关、运行、发送调同一个服务，两边同时变。
// 卡片底是桌面卡片自己的液态玻璃，这里只画内容；颜色只用面板语义色，主题色当字时
// 用 panelReadable、当图形时用 panelGraphic，不铺大面积的发光色。字最小 13pt。

@MainActor
enum DesktopCardsSystem {
    /// 不是本组的小组件返回 nil，走原来的通用逻辑。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopSystemCards.handles(widget.kind) else { return nil }
        let widget = resolved(widget)
        let card: AnyView
        switch widget.kind {
        case .battery: card = AnyView(DeskBatteryCard(widget: widget, size: size, now: now))
        case .system: card = AnyView(DeskSystemCard(widget: widget, size: size, now: now))
        case .network: card = AnyView(DeskNetworkCard(widget: widget, size: size))
        case .gauges: card = AnyView(DeskGaugesCard(widget: widget, size: size))
        case .toggles: card = AnyView(DeskTogglesCard(widget: widget, size: size, now: now))
        case .airdrop: card = AnyView(DeskAirDropCard(widget: widget, size: size, now: now))
        case .trash: card = AnyView(DeskTrashCard(widget: widget, size: size, now: now))
        case .appSwitcher: card = AnyView(DeskAppSwitcherCard(widget: widget, size: size))
        case .shortcut: card = AnyView(DeskShortcutCard(widget: widget, size: size, now: now))
        case .search: card = AnyView(DeskSearchCard(widget: widget, size: size, now: now))
        default: return nil
        }
        // 整种是 Pro 的（废纸篓、应用切换器）没解锁时照扩展栏一样盖小锁。
        return AnyView(card
            .frame(width: size.width, height: size.height)
            .proLocked(widget))
    }

    /// 存着的配置补上目录里的默认值（老卡片没有后来加的键），和 `WidgetTile` 一样。
    static func resolved(_ widget: WidgetInstance) -> WidgetInstance {
        guard let defaults = WidgetCatalog.entry(widget.kind)?.defaults else { return widget }
        var copy = widget
        copy.config = widget.config.merging(defaults: defaults)
        return copy
    }

    /// 内容离卡片边：小号 14，中、大号 16。
    static func inset(_ size: DesktopPinSize) -> CGFloat { size == .small ? 14 : 16 }

    /// 「+N」和「打开面板」：从扩展栏上的卡片长出面板，卡片不在扩展栏上时浮在屏幕顶上。
    static func openPanel(_ widget: WidgetInstance) {
        WidgetPanelOpener.shared.open(widget.id)
    }
}

// MARK: - 共用的小块

/// 玻璃上的一小块：薄填充 + 细边。按下、开着时换成主题色的淡底和描边。
private struct DeskBlock: ViewModifier {
    var radius: CGFloat = 14
    var accent: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(accent.map { $0.opacity(0.2) } ?? Color.panelFill))
            .overlay(shape.strokeBorder(accent.map { $0.opacity(0.75) } ?? Color.panelStroke,
                                        lineWidth: accent == nil ? 0.6 : 1))
            .contentShape(shape)
    }
}

private extension View {
    func deskBlock(radius: CGFloat = 14, accent: Color? = nil) -> some View {
        modifier(DeskBlock(radius: radius, accent: accent))
    }

    /// 卡片里小标题那种字：13pt 次级色。
    func deskLabel() -> some View {
        font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
    }
}

/// 一根横向进度条。
private struct DeskBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.panelTrack)
                Capsule().fill(tint)
                    .frame(width: max(progress > 0 ? height : 0, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 大数字后面跟一个小一号的单位（「76」「%」）。
private struct DeskNumber: View {
    var value: String
    var unit: String
    var size: CGFloat
    var tint: Color = .panelPrimary

    var body: some View {
        // 一段文字：放不下时数字和单位一起缩（最多缩到 0.7），不会只剩单位被截掉。
        Text(text)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// 显式写 SwiftUI 的属性：同时导入了 AppKit，`.font` 会和 NSFont 那个属性撞名。
    private var text: AttributedString {
        typealias UI = AttributeScopes.SwiftUIAttributes
        var number = AttributedString(value)
        number[UI.FontAttribute.self] = Font.system(size: size, weight: .bold, design: .rounded)
        number[UI.ForegroundColorAttribute.self] = tint
        guard !unit.isEmpty else { return number }
        var suffix = AttributedString(" " + unit)
        suffix[UI.FontAttribute.self] = Font.system(size: max(13, (size * 0.42).rounded()), weight: .semibold)
        suffix[UI.ForegroundColorAttribute.self] = Color.panelSecondary
        return number + suffix
    }
}

/// 一根走势线：先铺一层很淡的面积，再描线。
private struct DeskSpark: View {
    var values: [Double]
    var peak: Double
    var tint: Color

    var body: some View {
        ZStack {
            Sparkline(values: values, peak: peak, closed: true)
                .fill(tint.opacity(0.14))
            Sparkline(values: values, peak: peak)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// 胶囊按钮：实心主题色（ink 字）或薄玻璃。
private struct DeskPill: View {
    var title: String
    var symbol: String?
    var accent: Color?
    var ink: Color = .white
    var height: CGFloat = 30
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(accent == nil ? Color.panelPrimary : ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(accent ?? Color.panelFill))
            .overlay(Capsule().strokeBorder(Color.panelStroke.opacity(accent == nil ? 1 : 0), lineWidth: 0.6))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 电池

/// 小号：设备名、大字电量、电量条、状态。中号：左边大字和电量条，右边状态、还能用多久，
/// 再列 2 个蓝牙设备（没有时写电池健康）。大号：大字和状态、最近 12 小时走势、
/// 4 个蓝牙设备、最大容量和循环次数。台式机没有电池时用第一个有电量的蓝牙设备当主角。
private struct DeskBatteryCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.panelTint) private var panelTint
    private var metrics: BatteryMetrics { BatteryMetrics.shared }

    struct Device: Identifiable {
        var id: String
        var name: String
        var symbol: String
        var level: Double
        var charging: Bool
        var onPower: Bool
        var present: Bool
        var isMac: Bool
    }

    private var mac: Device? {
        guard let device = metrics.device(.mac), device.present else { return nil }
        return Device(id: "mac", name: BatteryDeviceKind.mac.name, symbol: BatterySymbol.resolve("laptopcomputer"),
                      level: device.level, charging: device.charging, onPower: device.onPower,
                      present: true, isMac: true)
    }

    private var accessories: [Device] {
        metrics.accessories.compactMap { item in
            guard let level = item.level else { return nil }
            return Device(id: "bt.\(item.id)", name: item.displayName,
                          symbol: BatterySymbol.resolve(item.kind.symbol),
                          level: Double(level) / 100, charging: item.charging, onPower: false,
                          present: true, isMac: false)
        }
    }

    private var hero: Device {
        mac ?? accessories.first ?? Device(id: "none", name: BatteryDeviceKind.mac.name,
                                           symbol: BatterySymbol.resolve("laptopcomputer"),
                                           level: 0, charging: false, onPower: false, present: false, isMac: true)
    }

    private var others: [Device] {
        let main = hero.id
        return accessories.filter { $0.id != main }
    }

    private func tint(_ device: Device) -> Color {
        switch DesktopSystemCards.batteryTone(level: device.level, charging: device.charging,
                                              onPower: device.onPower, present: device.present) {
        case .critical: return Color(hex: "#FF453A").panelGraphic
        case .low: return Color(hex: "#FF9F0A").panelGraphic
        case .absent: return .panelTertiary
        case .normal: return panelTint.accent(or: Color(hex: MetricColor.batteryPresent)).panelGraphic
        }
    }

    private func percent(_ device: Device) -> String {
        device.present ? "\(BatteryColorMap.percent(device.level))" : "-"
    }

    private func state(_ device: Device) -> String {
        if device.isMac, device.onPower, !device.charging, metrics.power.charged {
            return tr("已充满")
        }
        return DesktopSystemCards.batteryState(present: device.present, charging: device.charging,
                                               onPower: device.onPower, level: device.level)
    }

    private var remaining: String? {
        guard let mac else { return nil }
        return DesktopSystemCards.batteryRemaining(charging: mac.charging, onPower: mac.onPower,
                                                   minutesToFull: metrics.power.minutesToFull,
                                                   minutesToEmpty: metrics.power.minutesToEmpty)
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { BatteryMetrics.shared.start() }
        .accessibilityElement(children: .combine)
    }

    private func nameRow(_ device: Device) -> some View {
        HStack(spacing: 6) {
            Image(systemName: device.symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: device.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if device.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint(device))
            }
        }
        .foregroundStyle(Color.panelSecondary)
    }

    private var small: some View {
        let device = hero
        return VStack(alignment: .leading, spacing: 0) {
            nameRow(device)
            Spacer(minLength: 4)
            DeskNumber(value: percent(device), unit: device.present ? "%" : "", size: 46, tint: .panelPrimary)
            DeskBar(progress: device.present ? device.level : 0, tint: tint(device), height: 10)
                .padding(.top, 6)
            Text(verbatim: state(device))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .padding(.top, 8)
        }
    }

    private var medium: some View {
        let device = hero
        let rows = Array(others.prefix(DesktopSystemCards.rows(.batteryAccessories, size: .medium)))
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                nameRow(device)
                Spacer(minLength: 4)
                DeskNumber(value: percent(device), unit: device.present ? "%" : "", size: 52)
                DeskBar(progress: device.present ? device.level : 0, tint: tint(device), height: 10)
                    .padding(.top, 6)
            }
            .frame(width: 136)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: state(device))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                if let remaining {
                    Text(verbatim: remaining)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if rows.isEmpty {
                    healthLine
                } else {
                    ForEach(rows) { deviceRow($0, bar: false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var large: some View {
        let device = hero
        let rows = Array(others.prefix(DesktopSystemCards.rows(.batteryAccessories, size: .large)))
        return VStack(alignment: .leading, spacing: 10) {
            nameRow(device)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                DeskNumber(value: percent(device), unit: device.present ? "%" : "", size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: state(device))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    if let remaining {
                        Text(verbatim: remaining)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelSecondary)
                    }
                }
                .lineLimit(1)
            }
            DeskBar(progress: device.present ? device.level : 0, tint: tint(device), height: 10)
            if mac != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: tr("最近 12 小时")).deskLabel()
                        Spacer(minLength: 0)
                        healthLine
                    }
                    BatteryHistoryLine(history: metrics.history, now: now, tint: tint(device))
                        .frame(minHeight: 40, maxHeight: .infinity)
                }
            }
            if !rows.isEmpty {
                VStack(spacing: 6) {
                    ForEach(rows) { deviceRow($0) }
                }
            }
            if mac == nil, rows.isEmpty {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var healthLine: some View {
        let health = metrics.health
        let parts = [health.capacityPercent.map { tr("最大容量") + " \($0)%" },
                     health.cycles.map { tr("循环次数") + " \($0)" }].compactMap { $0 }
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " · "))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
    }

    /// 一个蓝牙设备一行。中号右边只有 150 宽，不画电量条，名字放得下。
    private func deviceRow(_ device: Device, bar: Bool = true) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .frame(width: 18)
            Text(verbatim: device.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if bar {
                DeskBar(progress: device.level, tint: tint(device), height: 6)
                    .frame(width: 44)
            }
            Text(verbatim: "\(BatteryColorMap.percent(device.level))%")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 22)
    }
}

/// 最近 12 小时的电量折线，充电的那几段画在淡色底上。
private struct BatteryHistoryLine: View {
    var history: BatteryHistory
    var now: Date
    var tint: Color

    var body: some View {
        let from = now.addingTimeInterval(-12 * 3600)
        let segments = history.segments(from: from, to: now)
        let charging = history.chargingSpans(from: from, to: now)
        Canvas { context, size in
            let span = max(now.timeIntervalSince(from), 1)
            func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(from) / span) * size.width }
            func y(_ percent: Int) -> CGFloat { size.height * (1 - CGFloat(min(max(percent, 0), 100)) / 100) }
            for line in [0, 50, 100] {
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: y(line)))
                guide.addLine(to: CGPoint(x: size.width, y: y(line)))
                context.stroke(guide, with: .color(Color.panelSeparator), lineWidth: 0.5)
            }
            for charge in charging {
                let rect = CGRect(x: x(charge.start), y: 0, width: max(1, x(charge.end) - x(charge.start)),
                                  height: size.height)
                context.fill(Path(rect), with: .color(tint.opacity(0.12)))
            }
            for segment in segments where !segment.isEmpty {
                var path = Path()
                path.move(to: CGPoint(x: x(segment[0].date), y: y(segment[0].percent)))
                for sample in segment.dropFirst() {
                    path.addLine(to: CGPoint(x: x(sample.date), y: y(sample.percent)))
                }
                context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 系统活动

/// 读数按卡片设置里选的（`metrics`）：小号第一个大字带走势、第二个小字；中号一个读数一列，
/// 大字、走势或用量条；大号一个读数一行（名字、走势、大字），下面列最占 CPU 的几个 App
/// 和开机多久。超阈值提醒响着的读数变红，和扩展栏一样。
private struct DeskSystemCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var shown: [String] {
        DesktopSystemCards.systemMetrics(widget.config.strings("metrics", default: ["cpu", "memory"]), size: size)
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            SystemMetrics.shared.start()
            if shown.contains("network") { NetworkMetrics.shared.start() }
            if shown.contains("battery") { BatteryMetrics.shared.start() }
        }
    }

    // MARK: 读数

    private func label(_ metric: String) -> String {
        switch metric {
        case "cpu": "CPU"
        case "memory": tr("内存")
        case "network": tr("网络")
        case "disk": tr("磁盘")
        default: tr("电池")
        }
    }

    private func value(_ metric: String) -> Double {
        let live = SystemMetrics.shared
        switch metric {
        case "cpu": return live.cpu
        case "memory": return live.memory
        case "disk": return live.disk
        case "network": return SystemCardMetrics.networkFraction(NetworkMetrics.shared.download)
        default: return BatteryMetrics.shared.device(.mac)?.level ?? 0
        }
    }

    /// 网络写速率：小号、中号用短写法（「2.4M」），大号写全（「2.4 MB/s」）。
    private func reading(_ metric: String) -> (value: String, unit: String) {
        if metric == "network" {
            guard size == .large else { return (SystemReadout.shortRate(NetworkMetrics.shared.download), "") }
            let rate = SystemReadout.rate(NetworkMetrics.shared.download)
            return (rate.value, rate.unit)
        }
        return ("\(SystemReadout.percent(value(metric)))", "%")
    }

    private func history(_ metric: String) -> [Double] {
        switch metric {
        case "cpu", "memory": SystemMetrics.shared.history(for: metric)
        case "network": NetworkMetrics.shared.downloadHistory
        default: []
        }
    }

    private func tint(_ metric: String) -> Color {
        if let kind = SystemMetricKind(rawValue: metric), SystemAlerts.shared.firing.contains(kind) {
            return Color(hex: SystemActivityStyle.alertRed).panelGraphic
        }
        let hex = switch metric {
        case "cpu": MetricColor.cpu
        case "memory": MetricColor.memory
        case "network": MetricColor.netDownload
        case "disk": MetricColor.storage
        default: MetricColor.batteryPresent
        }
        return Color(hex: hex).panelGraphic
    }

    /// 有走势的画走势（CPU、内存、网络），没有的画用量条（磁盘、电池）。
    @ViewBuilder
    private func trend(_ metric: String, height: CGFloat) -> some View {
        let values = history(metric)
        if metric == "network" || metric == "cpu" || metric == "memory" {
            let peak = metric == "network" ? max(values.max() ?? 0, 1) : 1
            DeskSpark(values: values, peak: peak, tint: tint(metric))
                .frame(height: height)
        } else {
            DeskBar(progress: value(metric), tint: tint(metric), height: 8)
                .frame(height: height, alignment: .bottom)
        }
    }

    private func title(_ metric: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint(metric)).frame(width: 7, height: 7)
            Text(verbatim: label(metric)).deskLabel()
        }
    }

    // MARK: 三档

    private var small: some View {
        let main = shown.first ?? "cpu"
        let main2 = shown.dropFirst().first
        let read = reading(main)
        return VStack(alignment: .leading, spacing: 0) {
            title(main)
            DeskNumber(value: read.value, unit: read.unit, size: 44)
                .padding(.top, 2)
            Spacer(minLength: 4)
            trend(main, height: 30)
            if let main2 {
                let second = reading(main2)
                HStack(spacing: 6) {
                    Circle().fill(tint(main2)).frame(width: 7, height: 7)
                    Text(verbatim: label(main2))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                    Spacer(minLength: 0)
                    Text(verbatim: second.value + second.unit)
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                }
                .lineLimit(1)
                .padding(.top, 8)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 10) {
            ForEach(shown, id: \.self) { metric in
                let read = reading(metric)
                let crowded = shown.count >= 4
                VStack(alignment: .leading, spacing: 4) {
                    title(metric)
                    DeskNumber(value: read.value, unit: read.unit, size: crowded ? 22 : 32)
                    Spacer(minLength: 0)
                    trend(metric, height: 36)
                }
                .padding(crowded ? 8 : 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .deskBlock(radius: 14)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var large: some View {
        let processRows = DesktopSystemCards.rows(.processes(metrics: shown.count), size: .large)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(shown, id: \.self) { metric in
                let read = reading(metric)
                HStack(spacing: 10) {
                    title(metric).frame(width: 64, alignment: .leading)
                    trend(metric, height: 28)
                    DeskNumber(value: read.value, unit: read.unit, size: 24)
                        .frame(width: 92, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 42)
                .deskBlock(radius: 12)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            HStack {
                Text(verbatim: tr("最占 CPU")).deskLabel()
                Spacer(minLength: 0)
                if let boot = SystemMetrics.bootTime {
                    Text(verbatim: tr("已运行 \(SystemReadout.uptime(now.timeIntervalSince(boot)))"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
            }
            DeskProcessRows(limit: processRows)
        }
    }
}

/// 最占 CPU 的几个 App。只在大号卡片在桌面上时采样（和面板共用一个采样器，按人数开关）。
private struct DeskProcessRows: View {
    var limit: Int

    private var monitor: ProcessMonitor { ProcessMonitor.shared }

    var body: some View {
        let rows = Array(monitor.topCPU.prefix(limit))
        VStack(spacing: 4) {
            if rows.isEmpty {
                Text(verbatim: tr("正在读取"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 24 * CGFloat(max(limit, 1)), alignment: .leading)
            }
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Group {
                        if let icon = monitor.icon(for: row) {
                            Image(nsImage: icon).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "gearshape").foregroundStyle(Color.panelSecondary)
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(verbatim: monitor.name(for: row))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(verbatim: ProcessRanking.cpuText(row.cpuPercent))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                }
                .frame(height: 24)
            }
        }
        .onAppear { monitor.begin() }
        .onDisappear { monitor.end() }
    }
}

// MARK: - 网络

/// 小号：下行大字、上行小字，底下一条走势。中号：左边两行速率，右边走势，底下 Wi-Fi 和
/// 今天用了多少。大号：两块速率、走势、今天下载 / 上传、Wi-Fi 名字和信号。
/// 只看下行或上行（卡片设置）时只写那一个，单位跟卡片的 MB/s 或 Mbps 设置走。
private struct DeskNetworkCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var metrics: NetworkMetrics { NetworkMetrics.shared }
    private var wifi: WifiMetrics { WifiMetrics.shared }

    private var display: String { widget.config.string("display", default: "both") }
    private var showsDown: Bool { display != "upload" }
    private var showsUp: Bool { display != "download" }
    private var unit: NetworkRateUnit { NetworkRateUnit.from(widget.config) }

    private var down: Color { Color(hex: MetricColor.netDownload).panelGraphic }
    private var up: Color { Color(hex: MetricColor.netUpload).panelGraphic }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            NetworkMetrics.shared.start()
            if size != .small { WifiMetrics.shared.start() }
        }
    }

    private func rate(_ bytes: Double) -> (value: String, unit: String) {
        NetworkRateFormat.format(bytes, unit: unit)
    }

    private func rateRow(_ symbol: String, _ bytes: Double, _ tint: Color, size: CGFloat) -> some View {
        let r = rate(bytes)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: max(13, size * 0.45), weight: .bold))
                .foregroundStyle(tint)
            DeskNumber(value: r.value, unit: r.unit, size: size)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(symbol == "arrow.down" ? tr("下载") : tr("上传"))
    }

    private var chart: some View {
        let peak = max(metrics.downloadHistory.max() ?? 0, metrics.uploadHistory.max() ?? 0, 1)
        return ZStack {
            if showsDown { DeskSpark(values: metrics.downloadHistory, peak: peak, tint: down) }
            if showsUp {
                Sparkline(values: metrics.uploadHistory, peak: peak)
                    .stroke(up, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 2]))
            }
        }
        .accessibilityHidden(true)
    }

    private var wifiLine: String {
        guard wifi.isPoweredOn, let rssi = wifi.rssi else { return tr("没有用 Wi-Fi") }
        let name = wifi.ssid ?? "Wi-Fi"
        return "\(name) · \(WifiQuality.label(rssi: rssi))"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: tr("网络")).deskLabel()
            if showsDown { rateRow("arrow.down", metrics.download, down, size: showsUp ? 30 : 36) }
            if showsUp { rateRow("arrow.up", metrics.upload, up, size: showsDown ? 17 : 36) }
            Spacer(minLength: 2)
            chart.frame(height: 28)
        }
    }

    private var medium: some View {
        let today = metrics.todayShown()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if showsDown { rateRow("arrow.down", metrics.download, down, size: 28) }
                    if showsUp { rateRow("arrow.up", metrics.upload, up, size: 28) }
                }
                .frame(width: 140, alignment: .leading)
                chart.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: wifiLine).lineLimit(1)
                Spacer(minLength: 6)
                Text(verbatim: tr("今天") + " ↓" + NetworkByteFormat.text(today.download))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.panelSecondary)
        }
    }

    private var large: some View {
        let today = metrics.todayShown()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if showsDown { rateBlock(tr("下载"), metrics.download, down, symbol: "arrow.down") }
                if showsUp { rateBlock(tr("上传"), metrics.upload, up, symbol: "arrow.up") }
            }
            chart
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity)
            HStack(spacing: 10) {
                totalBlock(tr("今天下载"), NetworkByteFormat.text(today.download))
                totalBlock(tr("今天上传"), NetworkByteFormat.text(today.upload))
            }
            HStack(spacing: 8) {
                Image(systemName: wifi.rssi == nil ? "wifi.slash" : "wifi")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                Text(verbatim: wifiLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let rssi = wifi.rssi {
                    Text(verbatim: "\(WifiQuality.percent(rssi: rssi))%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .deskBlock(radius: 10)
        }
    }

    private func rateBlock(_ title: String, _ bytes: Double, _ tint: Color, symbol: String) -> some View {
        let r = rate(bytes)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text(verbatim: title).deskLabel()
            }
            DeskNumber(value: r.value, unit: r.unit, size: 30)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskBlock(radius: 12)
        .accessibilityElement(children: .combine)
    }

    private func totalBlock(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title).deskLabel()
            Spacer(minLength: 4)
            Text(verbatim: value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .deskBlock(radius: 10)
    }
}

// MARK: - 圆环仪表

/// 圆环按卡片设置里拖好的顺序（`GaugeReading.rings`），每个过了警戒线变红。小号：1 个是
/// 大圆环、读数写在环里；2 个并排；3、4 个 2×2。中号一排。大号一个圆环一行，写完整说明。
private struct DeskGaugesCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var rings: [String] { GaugeReading.rings(widget.config) }

    var body: some View {
        let grid = DesktopSystemCards.gaugeGrid(count: rings.count, size: size)
        let shown = Array(rings.prefix(grid.shown))
        Group {
            if size == .large {
                VStack(spacing: 8) {
                    ForEach(shown, id: \.self) { row($0) }
                    Spacer(minLength: 0)
                }
            } else if shown.count == 1, size == .small {
                big(shown[0])
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: max(grid.columns, 1))
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shown, id: \.self) { cell($0, captioned: grid.showsCaption, rows: grid.rows) }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            SystemMetrics.shared.start()
            BatteryMetrics.shared.start()
        }
    }

    private func reading(_ ring: String) -> GaugeLive.Reading {
        GaugeLive.reading(ring, config: widget.config, preview: false)
    }

    private func name(_ ring: String) -> String {
        switch ring {
        case "battery": tr("电池")
        case "cpu": "CPU"
        case "memory": tr("内存")
        default: tr("存储")
        }
    }

    /// 中号、小号格子里的短说明：存储写「可用」，电池写状态，CPU、内存写名字。
    private func short(_ ring: String, _ r: GaugeLive.Reading) -> String {
        switch ring {
        case "battery": r.caption
        case "cpu", "memory": name(ring)
        default: r.known ? tr("可用") : r.caption
        }
    }

    private func valueColor(_ r: GaugeLive.Reading) -> Color {
        r.alert ? GaugeLive.red.panelReadable : .panelPrimary
    }

    private func ring<Center: View>(_ r: GaugeLive.Reading, diameter: CGFloat, line: CGFloat,
                                    @ViewBuilder center: () -> Center) -> some View {
        let tint = r.tint.panelGraphic
        return MetricProgressRing(progress: r.progress, tint: tint,
                                  track: r.known ? r.tint.opacity(0.16) : Color.panelTrack,
                                  diameter: diameter, lineWidth: line, peak: r.peak, laps: true,
                                  content: center)
    }

    private func big(_ ringID: String) -> some View {
        let r = reading(ringID)
        return VStack(spacing: 6) {
            ring(r, diameter: 96, line: 9) {
                VStack(spacing: 0) {
                    Image(systemName: r.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(r.known ? r.tint.panelGraphic : .panelSecondary)
                    Text(verbatim: r.value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(valueColor(r))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(verbatim: short(ringID, r))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ ringID: String, captioned: Bool, rows: Int) -> some View {
        let r = reading(ringID)
        let diameter: CGFloat = size == .small ? (rows > 1 ? 42 : 56) : 60
        return VStack(spacing: 4) {
            ring(r, diameter: diameter, line: diameter > 50 ? 6 : 5) {
                Image(systemName: r.symbol)
                    .font(.system(size: diameter * 0.3, weight: .semibold))
                    .foregroundStyle(r.known ? r.tint.panelGraphic : .panelSecondary)
            }
            Text(verbatim: r.value)
                .font(.system(size: size == .small && rows > 1 ? 13 : 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor(r))
                .lineLimit(1)
                .fixedSize()
            if captioned {
                Text(verbatim: short(ringID, r))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// 大号每行名字下面那行：存储、电池写原来的说明；CPU、内存名字已经写过，写最近一分钟最高。
    private func detail(_ ringID: String, _ r: GaugeLive.Reading) -> String {
        guard ringID == "cpu" || ringID == "memory" else { return r.caption }
        guard let peak = r.peak else { return tr("正在读取") }
        return tr("1 分钟内最高 \(GaugeReading.percent(peak))")
    }

    private func row(_ ringID: String) -> some View {
        let r = reading(ringID)
        return HStack(spacing: 12) {
            ring(r, diameter: 48, line: 5) {
                Image(systemName: r.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(r.known ? r.tint.panelGraphic : .panelSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name(ringID))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(verbatim: r.alert ? tr("超过警戒线") : detail(ringID, r))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(r.alert ? GaugeLive.red.panelReadable : .panelSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            Text(verbatim: r.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor(r))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 66)
        .deskBlock(radius: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 快速开关

/// 卡片设置里勾的那几个，点一下就生效，和扩展栏的圆钮一样（Pro 工具没解锁时画暗、点了弹
/// 付费墙）。开着的整块亮主题色。排法见 `DesktopSystemCards.toggleGrid`；放不下的最后一格
/// 「+N」打开面板。大号再放「保持唤醒多久」。
private struct DeskTogglesCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.panelTint) private var panelTint

    private var accent: Color { panelTint.accent(or: Color(hex: QuickTogglesDetail.accentHex)) }
    private var ink: Color { panelTint.ink(or: Color(hex: QuickTogglesDetail.accentInkHex)) }
    private var unlocked: Bool { licenseUnlocked || supporter }
    private var actions: QuickActions { QuickActions.shared }
    private var chosen: [QuickToggle] { QuickToggle.chosen(widget.config) }
    private var awakeMinutes: Int { KeepAwakeTimer.minutes(widget.config) }

    var body: some View {
        let grid = DesktopSystemCards.toggleGrid(count: chosen.count, size: size)
        let items = Array(chosen.prefix(grid.shown))
        let chips = DesktopSystemCards.showsAwakeChips(count: chosen.count, hasKeepAwake: chosen.contains(.keepAwake),
                                                       size: size)
        VStack(alignment: .leading, spacing: 10) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<max(grid.rows, 1), id: \.self) { row in
                    GridRow {
                        ForEach(0..<max(grid.columns, 1), id: \.self) { column in
                            let index = row * grid.columns + column
                            if index < items.count {
                                cell(items[index], captioned: grid.showsCaption, wide: grid.columns == 1)
                            } else if index == items.count, grid.overflow > 0 {
                                more(grid.overflow)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if chips { awakeChips }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: awakeMinutes) { _, minutes in actions.changeKeepAwakeDuration(minutes: minutes) }
    }

    private func cell(_ toggle: QuickToggle, captioned: Bool, wide: Bool) -> some View {
        let on = toggle.hasState && actions.isOn(toggle)
        let locked = !ProLicenseGate.canUseTool(toggle, isOn: on, unlocked: unlocked)
        let state = locked ? ProFeatures.label
            : (toggle == .keepAwake && on
               ? KeepAwakeTimer.remaining(until: actions.keepAwakeUntil, now: now, minutesOnly: true)
               : toggle.caption(on: on))
        let name = size == .large && captioned ? toggle.panelTitle : toggle.shortTitle
        let iconSize: CGFloat = captioned ? 28 : (size == .small ? 40 : 32)
        let icon = Image(systemName: toggle.symbol)
            .font(.system(size: iconSize * 0.46, weight: .semibold))
            .foregroundStyle(on ? ink : Color.panelPrimary.opacity(locked ? 0.45 : 1))
            .frame(width: iconSize, height: iconSize)
            .background(Circle().fill(on ? accent : Color.panelSelected))
        return Button {
            if locked {
                PaywallWindow.shared.show()
            } else if toggle == .keepAwake {
                actions.toggleKeepAwake(minutes: awakeMinutes)
            } else {
                actions.perform(toggle)
            }
        } label: {
            Group {
                if captioned && wide {
                    // 小号一两个时上下两条：图标在左，名字和状态在右。
                    HStack(spacing: 10) {
                        icon
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: toggle.panelTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.panelPrimary.opacity(locked ? 0.6 : 1))
                            Text(verbatim: state)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(on ? accent.panelReadable : Color.panelSecondary)
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                } else if captioned {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            icon
                            Spacer(minLength: 0)
                            if locked { lockMark }
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelPrimary.opacity(locked ? 0.6 : 1))
                        Text(verbatim: state)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? accent.panelReadable : Color.panelSecondary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(9)
                } else {
                    VStack(spacing: 4) {
                        icon.overlay(alignment: .bottomTrailing) { if locked { lockMark.offset(x: 4, y: 4) } }
                        if size != .small {
                            Text(verbatim: name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.panelPrimary.opacity(locked ? 0.6 : 1))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .padding(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: captioned && !wide ? .topLeading : .center)
            .deskBlock(radius: 14, accent: on ? accent : nil)
        }
        .buttonStyle(.plain)
        .help(locked ? tr("\(toggle.title)：码头 Pro 专属，点一下解锁") : tr("\(toggle.title)：\(toggle.help)"))
        .accessibilityLabel(toggle.title)
        .accessibilityValue(state)
    }

    private var lockMark: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color(hex: ShelfColor.redPanda.hex))
            .accessibilityHidden(true)
    }

    private func more(_ count: Int) -> some View {
        Button { DesktopCardsSystem.openPanel(widget) } label: {
            Text(verbatim: "+\(count)")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .deskBlock(radius: 14)
        }
        .buttonStyle(.plain)
        .help(tr("还有 \(count) 个，打开面板"))
        .accessibilityLabel(tr("还有 \(count) 个，打开面板"))
    }

    private var awakeChips: some View {
        HStack(spacing: 6) {
            Text(verbatim: tr("唤醒"))
                .deskLabel()
            ForEach(KeepAwakeTimer.choices, id: \.self) { minutes in
                let selected = awakeMinutes == minutes
                Button {
                    guard !selected else { return }
                    let latest = WidgetWriter.current(widget.id) ?? widget
                    WidgetWriter.write(latest) { $0.set(KeepAwakeTimer.key, .string(String(minutes))) }
                } label: {
                    Text(verbatim: KeepAwakeTimer.title(minutes))
                        .font(.system(size: 13, weight: selected ? .bold : .semibold))
                        .foregroundStyle(selected ? ink : Color.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Capsule().fill(selected ? accent : Color.panelFill))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - 隔空投送

/// 整张卡片都是拖放区，文件拖进来松手直接调起隔空投送。小号：图标、状态、「选择文件…」。
/// 中号：左边拖放区，右边接收模式和两个按钮。大号：拖放区、按钮和最近发过的 3 个
/// （再发一次）。最近发过和扩展栏面板是同一份（存在卡片配置里）。
private struct DeskAirDropCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.panelTint) private var panelTint
    @State private var dragging = false
    @State private var files = 0
    @State private var mode: AirDropDetail.Discoverability?
    @State private var notice: String?

    private var accent: Color { panelTint.accent(or: Color(hex: "#8DB8FF")) }
    private var ink: Color { panelTint.ink(or: Color(hex: "#0A1B3A")) }
    private var available: Bool { AirDropSender.available }
    private var state: AirDropDrop.State {
        AirDropDrop.state(available: available, dragging: dragging, files: files)
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        .onDrop(of: [.fileURL, .item], delegate: AirDropDropDelegate(
            enabled: available,
            update: { inside, count in
                dragging = inside
                files = count
            },
            send: { [id = widget.id] urls in _ = AirDropSender.send(urls, recordInto: id) }))
        .onAppear(perform: readMode)
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { notice = nil }
        }
    }

    private func glyph(_ side: CGFloat) -> some View {
        let color: Color = state.disabled ? .panelTertiary : (state.highlighted ? accent.panelGraphic : .panelPrimary)
        return AirDropGlyph()
            .stroke(color, style: StrokeStyle(lineWidth: max(1.6, side * 0.06), lineCap: .round))
            .frame(width: side, height: side)
            .overlay {
                Circle().fill(color)
                    .frame(width: side * 0.16, height: side * 0.16)
                    .offset(y: side * 0.08)
            }
            .scaleEffect(state.highlighted ? 1.12 : 1)
            .animation(.snappy(duration: 0.18), value: state.highlighted)
            .accessibilityHidden(true)
    }

    /// 拖着文件停在卡片上时，拖放区换成虚线框。
    private var dropZone: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 6) {
            glyph(size == .large ? 40 : 44)
            Text(verbatim: state.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
            Text(verbatim: state.caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(state.highlighted ? accent.opacity(0.16) : Color.panelFill))
        .overlay(shape.strokeBorder(state.highlighted ? accent.panelGraphic : Color.panelStroke,
                                    style: StrokeStyle(lineWidth: state.highlighted ? 1.5 : 0.8, dash: [6, 4])))
    }

    private var chooseButton: some View {
        DeskPill(title: tr("选择文件…"), symbol: nil, accent: available ? accent : nil, ink: ink) {
            AirDropSender.chooseAndSend(recordInto: widget.id)
        }
        .disabled(!available)
    }

    private var small: some View {
        VStack(spacing: 6) {
            glyph(40)
            Text(verbatim: state.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
            Text(verbatim: state.caption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
            Spacer(minLength: 0)
            chooseButton
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            dropZone.frame(width: 148)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: tr("隔空投送"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                modeLine
                Spacer(minLength: 0)
                chooseButton
                DeskPill(title: tr("打开隔空投送"), symbol: nil, accent: nil, action: openWindow)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        let recent = Array(AirDropHistory.read(widget.config).prefix(DesktopSystemCards.rows(.airDropRecent, size: .large)))
        return VStack(alignment: .leading, spacing: 8) {
            dropZone.frame(height: 92)
            HStack(spacing: 8) {
                chooseButton
                DeskPill(title: tr("打开隔空投送"), symbol: nil, accent: nil, action: openWindow)
            }
            HStack {
                Text(verbatim: tr("最近发过")).deskLabel()
                Spacer(minLength: 0)
                if let notice {
                    Text(verbatim: notice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                } else {
                    modeLine
                }
            }
            if recent.isEmpty {
                Text(verbatim: tr("还没发过文件。拖到上面就能发。"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 4) {
                    ForEach(recent, id: \.path) { recentRow($0) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var modeLine: some View {
        if let mode {
            HStack(spacing: 6) {
                Circle().fill(mode.tint).frame(width: 8, height: 8)
                Text(verbatim: mode.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
            .help(mode.detail)
        }
    }

    private func recentRow(_ entry: AirDropHistory.Entry) -> some View {
        let url = URL(fileURLWithPath: entry.path)
        let exists = FileManager.default.fileExists(atPath: entry.path)
        return HStack(spacing: 10) {
            FileTypeBadgeView(file: ListedFile(url: url, date: entry.sent), size: 22)
                .opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(exists ? Color.panelPrimary : Color.panelTertiary)
                    .truncationMode(.middle)
                Text(verbatim: AirDropHistory.caption(entry, exists: exists, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                guard exists else {
                    NSSound.beep()
                    withAnimation(.easeIn(duration: 0.15)) { notice = AirDropHistory.goneNotice(entry.name) }
                    return
                }
                _ = AirDropSender.send([url], recordInto: widget.id)
            } label: {
                Text(verbatim: tr("再发一次"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(exists ? Color.panelPrimary : Color.panelTertiary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.panelSelected))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!available)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .deskBlock(radius: 10)
        .help(entry.path)
    }

    private func readMode() {
        _ = CFPreferencesAppSynchronize("com.apple.sharingd" as CFString)
        let raw = CFPreferencesCopyAppValue("DiscoverableMode" as CFString, "com.apple.sharingd" as CFString) as? String
        mode = raw.flatMap(AirDropDetail.Discoverability.init(preference:))
    }

    private func openWindow() {
        guard let url = URL(string: "nwnode://domain-AirDrop") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 废纸篓

/// 文件拖到卡片上就移到废纸篓（之后还能拿回来）。小号：桶和苍蝇、大字占用、几个项目、
/// 「清空…」（会先确认）。中号：再加最近扔的一个和「打开」。大号：最近扔的 4 个，每个能放回。
/// 没有完全磁盘访问权限时写明白，按钮换成「去授权」。
private struct DeskTrashCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @State private var targeted = false
    @State private var dragged = 0
    @State private var hovering = false
    @State private var scaredAt: Date?
    @State private var notice: String?

    private var monitor: TrashMonitor { TrashMonitor.shared }
    private var threshold: Int64 {
        TrashFlies.thresholdBytes(widget.config.string("threshold", default: TrashFlies.defaultThreshold))
    }
    private var flies: Int {
        widget.config.bool("flies", default: true) ? monitor.flies(now: now, threshold: threshold) : 0
    }
    private var locked: Bool { monitor.needsAccess }

    private var red: Color { Color(hex: "#FF6B5A") }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: DesktopCard.corner - 4, style: .continuous)
                    .strokeBorder(red.panelGraphic, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.rect)
        .onDrop(of: FileDropDelegate.types, delegate: FileDropDelegate(
            enabled: !locked,
            update: { inside, count in
                targeted = inside
                dragged = count
            },
            receive: { urls in _ = TrashMonitor.shared.trash(urls) }))
        .onHover { inside in
            hovering = inside
            scaredAt = inside ? .now : .now.addingTimeInterval(-0.6)
        }
        .onAppear { TrashMonitor.shared.start(threshold: threshold) }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { notice = nil }
        }
        .help(targeted ? tr("松开即可移到废纸篓") : tr("把文件拖到这里即可移到废纸篓"))
    }

    private var sizeText: String { locked ? tr("需要权限") : TrashFlies.format(bytes: monitor.bytes) }

    private var caption: String {
        if targeted { return tr("松开即可移到废纸篓") }
        if locked { return TilePermission.prompt(TilePermission.name(for: WidgetKind.trash.rawValue) ?? "完全磁盘访问权限") }
        if monitor.items == 0 { return tr("废纸篓是空的") }
        return flies > 0 ? tr("\(monitor.items) 个项目 · 该倒垃圾了") : tr("\(monitor.items) 个项目")
    }

    private var smallCaption: String {
        guard !locked, !targeted, monitor.items > 0 else { return caption }
        return tr("\(monitor.items) 个项目")
    }

    private func bin(_ side: CGFloat) -> some View {
        Image(systemName: monitor.items > 0 ? "trash.fill" : "trash")
            .font(.system(size: side * 0.5, weight: .medium))
            .foregroundStyle(targeted ? red.panelGraphic : Color.panelPrimary)
            .frame(width: side, height: side)
            .background(Circle().fill(Color.panelSelected))
            .scaleEffect(targeted ? 1.1 : 1)
            .animation(.snappy(duration: 0.2), value: targeted)
            .overlay {
                FlySwarm(count: flies, scaredAt: scaredAt, hovering: hovering, animated: true, flySize: side / 40)
                    .frame(width: side * 1.7, height: side * 1.5)
                    .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mainButton: some View {
        if locked {
            DeskPill(title: tr("去授权"), symbol: nil, accent: Color.panelPrimary, ink: .panelOnPrimary) {
                monitor.openAccessSettings()
            }
        } else {
            DeskPill(title: tr("清空…"), symbol: nil, accent: monitor.items > 0 ? red : nil, ink: .white) {
                monitor.empty()
            }
            .disabled(monitor.items == 0)
        }
    }

    /// 中号右边两个按钮并排只有 70 宽，写「打开」；大号写全。
    private var openButton: some View {
        DeskPill(title: size == .medium ? tr("打开") : tr("打开废纸篓"), symbol: nil, accent: nil) { monitor.open() }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            bin(40)
            Spacer(minLength: 4)
            Text(verbatim: sizeText)
                .font(.system(size: locked ? 20 : 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            // 小号只写几个项目，「该倒垃圾了」由桶边的苍蝇说。
            Text(verbatim: smallCaption)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .padding(.bottom, 8)
            mainButton
        }
    }

    private var medium: some View {
        let latest = locked ? nil : monitor.recent.first
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                bin(48)
                Spacer(minLength: 4)
                Text(verbatim: sizeText)
                    .font(.system(size: locked ? 22 : 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Text(verbatim: caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if let latest {
                    Text(verbatim: tr("最近扔进来")).deskLabel()
                    Text(verbatim: latest.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: RelativeAge.caption(latest.date, now: now))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                } else if !locked {
                    Text(verbatim: tr("把文件拖到这里即可移到废纸篓"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if !locked { openButton }
                    mainButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        let recent = locked ? [] : Array(monitor.recent.prefix(DesktopSystemCards.rows(.trashRecent, size: .large)))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                bin(52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: sizeText)
                        .font(.system(size: locked ? 22 : 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelPrimary)
                    Text(verbatim: caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                }
                .lineLimit(1)
            }
            .padding(.top, 4)
            if !recent.isEmpty {
                HStack {
                    Text(verbatim: tr("最近扔进来")).deskLabel()
                    Spacer(minLength: 0)
                    if let notice {
                        Text(verbatim: notice)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                    }
                }
                VStack(spacing: 4) {
                    ForEach(recent) { row($0) }
                }
            } else if locked {
                Text(verbatim: tr("读废纸篓要完全磁盘访问权限。授权后这里列出最近扔进来的文件。"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if !locked { openButton }
                mainButton
            }
        }
    }

    private func row(_ item: TrashedItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: monitor.location(of: item).path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .truncationMode(.middle)
                Text(verbatim: RelativeAge.caption(item.date, now: now))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                let message = monitor.putBack(item)
                withAnimation(.easeIn(duration: 0.15)) {
                    notice = message ?? tr("已放回「\(item.displayName)」")
                }
            } label: {
                Text(verbatim: tr("放回"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.panelSelected))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(item.origin.map { tr("放回「\(TrashPutBack.displayFolder($0.folder))」") }
                  ?? tr("不知道原来在哪，点了会说明"))
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .deskBlock(radius: 10)
        .contextMenu {
            Button(tr("在访达中显示")) { monitor.reveal(item) }
        }
    }
}

// MARK: - 应用切换器

/// 和扩展栏卡片同一份列表（固定的在前、按所选排序、隐藏的不列，`AppSwitcherList.tile`）。
/// 点一下切过去，没开的启动。小号 3×3 图标，中号两排六列，大号一行一个 App。
private struct DeskAppSwitcherCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint
    private var catalog: AppCatalog { AppCatalog.shared }
    private var accent: Color { panelTint.accent(or: Color(hex: "#A7B4FF")) }

    struct Entry: Identifiable {
        var item: AppSwitcherItem
        var pinned: Bool
        var id: String { item.id }
    }

    private var apps: [Entry] {
        let config = widget.config
        let running = catalog.running
        let slots = AppSwitcherList.tile(running.map { .init(id: $0.id, name: $0.name, isActive: $0.isActive) },
                                         recent: catalog.recentIDs, pinned: AppSwitcherList.pinned(config),
                                         hidden: AppSwitcherList.hidden(config), sort: AppSwitcherList.sort(config))
        return slots.map { slot in
            if let app = running.first(where: { $0.id == slot.id }) {
                return Entry(item: AppSwitcherItem(id: app.id, name: app.name, url: app.url, isActive: app.isActive),
                             pinned: slot.isPinned)
            }
            return Entry(item: AppSwitcherItem.notRunning(slot.id), pinned: slot.isPinned)
        }
    }

    var body: some View {
        let all = apps
        let grid = DesktopSystemCards.appGrid(count: all.count, size: size)
        let shown = Array(all.prefix(grid.shown))
        VStack(alignment: .leading, spacing: 8) {
            if size != .small {
                HStack {
                    Text(verbatim: tr("应用切换器"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Spacer(minLength: 0)
                    Text(verbatim: tr("\(catalog.running.count) 个在运行"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                }
                .lineLimit(1)
            }
            if all.isEmpty {
                Text(verbatim: catalog.running.isEmpty ? tr("没有正在运行的应用") : tr("正在运行的应用都隐藏了"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if size == .large {
                VStack(spacing: 4) {
                    ForEach(shown) { row($0.item, pinned: $0.pinned) }
                    if grid.overflow > 0 { moreRow(grid.overflow) }
                }
                Spacer(minLength: 0)
            } else {
                let side: CGFloat = size == .small ? 36 : 40
                Grid(horizontalSpacing: 6, verticalSpacing: size == .small ? 6 : 8) {
                    ForEach(0..<grid.rows, id: \.self) { r in
                        GridRow {
                            ForEach(0..<grid.columns, id: \.self) { c in
                                let index = r * grid.columns + c
                                if index < shown.count {
                                    icon(shown[index].item, side: side)
                                } else if index == shown.count, grid.overflow > 0 {
                                    more(grid.overflow, side: side)
                                } else {
                                    Color.clear.frame(width: side, height: side)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func open(_ app: AppSwitcherItem) {
        catalog.open(WidgetTarget.app(bundleID: app.id))
    }

    private func icon(_ app: AppSwitcherItem, side: CGFloat) -> some View {
        Button { open(app) } label: {
            AppSwitcherIcon(app: app, size: side)
                .opacity(app.isRunning ? 1 : 0.45)
                .overlay(alignment: .bottom) {
                    if app.isActive {
                        Circle().fill(Color.panelPrimary).frame(width: 4, height: 4).offset(y: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(app.isRunning ? app.name : tr("\(app.name)（没开，点了启动）"))
        .accessibilityLabel(app.isActive ? tr("\(app.name)（当前）")
                            : app.isRunning ? app.name : tr("\(app.name)，没开，点按启动"))
    }

    private func more(_ count: Int, side: CGFloat) -> some View {
        Button { DesktopCardsSystem.openPanel(widget) } label: {
            Text(verbatim: "+\(count)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelSecondary)
                .frame(width: side, height: side)
                .background(Circle().fill(Color.panelSelected))
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("还有 \(count) 个，打开面板"))
    }

    private func row(_ app: AppSwitcherItem, pinned: Bool) -> some View {
        Button { open(app) } label: {
            HStack(spacing: 10) {
                AppSwitcherIcon(app: app, size: 26)
                    .opacity(app.isRunning ? 1 : 0.45)
                Text(verbatim: app.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(app.isRunning ? Color.panelPrimary : Color.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelTertiary)
                }
                if app.isActive {
                    Text(verbatim: tr("当前"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.panelReadable)
                } else if !app.isRunning {
                    Text(verbatim: tr("没开"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .deskBlock(radius: 10, accent: app.isActive ? accent : nil)
        }
        .buttonStyle(.plain)
        .help(app.isRunning ? app.name : tr("\(app.name)（没开，点了启动）"))
    }

    private func moreRow(_ count: Int) -> some View {
        Button { DesktopCardsSystem.openPanel(widget) } label: {
            Text(verbatim: tr("还有 \(count) 个，打开面板"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .deskBlock(radius: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 快捷指令

/// 小号、中号是卡片上那几个（前 4 个），点一下运行、再点停止；大号一行一个，带上次运行的
/// 结果和运行键，最多 5 行。运行中、失败照扩展栏的样子标出来。
private struct DeskShortcutCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.panelTint) private var panelTint
    private var service: ShortcutsService { ShortcutsService.shared }
    private var accent: Color { panelTint.accent(or: Color(hex: "#C58BFF")) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: "#22093A")) }

    private var items: [ShortcutItem] {
        size == .large ? ShortcutDeck.items(widget.config) : ShortcutDeck.tileItems(widget.config)
    }

    var body: some View {
        let list = items
        let grid = DesktopSystemCards.shortcutGrid(count: list.count, size: size)
        let shown = Array(list.prefix(grid.shown))
        VStack(alignment: .leading, spacing: 8) {
            if size == .large {
                HStack {
                    Text(verbatim: tr("快捷指令"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                    Spacer(minLength: 0)
                    Text(verbatim: ShortcutRun.header(count: list.count))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                }
                .lineLimit(1)
            }
            if shown.isEmpty {
                empty
            } else if size == .large {
                VStack(spacing: 6) {
                    ForEach(shown) { row($0) }
                }
                Spacer(minLength: 0)
                if grid.overflow > 0 {
                    Button { DesktopCardsSystem.openPanel(widget) } label: {
                        Text(verbatim: tr("还有 \(grid.overflow) 个，打开面板"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelSecondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<grid.rows, id: \.self) { r in
                        GridRow {
                            ForEach(0..<grid.columns, id: \.self) { c in
                                let index = r * grid.columns + c
                                if index < shown.count {
                                    cell(shown[index], captioned: grid.showsCaption, single: shown.count == 1)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggle(_ item: ShortcutItem) {
        if service.isRunning(item.name) { service.stop(item.name) } else { service.run(item.name) }
    }

    private func status(_ item: ShortcutItem) -> (text: String, tone: ShortcutRun.Tone) {
        ShortcutRun.line(record: service.record(for: item.name), running: service.isRunning(item.name), now: now)
    }

    private func statusColor(_ tone: ShortcutRun.Tone) -> Color {
        switch tone {
        case .plain, .success: .panelSecondary
        case .running: accent.panelReadable
        case .failure: Color(hex: "#FF6B5A").panelReadable
        }
    }

    private func failed(_ item: ShortcutItem) -> Bool {
        guard !service.isRunning(item.name), case .failed = service.record(for: item.name)?.status else { return false }
        return true
    }

    private func badge(_ item: ShortcutItem, side: CGFloat) -> some View {
        ShortcutIcon(item: item, size: side, running: service.isRunning(item.name))
            .overlay(alignment: .topTrailing) {
                if failed(item) {
                    Circle()
                        .fill(Color(hex: "#FF6B5A"))
                        .frame(width: side * 0.24, height: side * 0.24)
                        .offset(x: side * 0.06, y: -side * 0.06)
                }
            }
    }

    private func cell(_ item: ShortcutItem, captioned: Bool, single: Bool) -> some View {
        let running = service.isRunning(item.name)
        let line = status(item)
        return Button { toggle(item) } label: {
            Group {
                if single {
                    VStack(alignment: .leading, spacing: 4) {
                        badge(item, side: size == .small ? 48 : 56)
                        Spacer(minLength: 2)
                        Text(verbatim: item.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(size == .small ? 2 : 1)
                        Text(verbatim: line.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(statusColor(line.tone))
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if captioned {
                    HStack(spacing: 10) {
                        badge(item, side: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: item.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.panelPrimary)
                            Text(verbatim: line.text)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(statusColor(line.tone))
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if size == .medium {
                    // 中号 3、4 个：两列两行，图标在左、名字在右。
                    HStack(spacing: 10) {
                        badge(item, side: 34)
                        Text(verbatim: item.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    badge(item, side: 44)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .deskBlock(radius: 14)
        }
        .buttonStyle(.plain)
        .help(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
        .accessibilityLabel(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
    }

    private func row(_ item: ShortcutItem) -> some View {
        let running = service.isRunning(item.name)
        let line = status(item)
        return HStack(spacing: 10) {
            badge(item, side: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                Text(verbatim: line.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(statusColor(line.tone))
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Button { toggle(item) } label: {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(running ? Color.panelPrimary : accentInk)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(running ? Color.panelSelected : accent))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
            .accessibilityLabel(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .deskBlock(radius: 12)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.panelTertiary)
            Text(verbatim: tr("还没选快捷指令"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
            Button { DesktopCardsSystem.openPanel(widget) } label: {
                Text(verbatim: tr("去选择"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(accent))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 搜索

/// 直接在卡片上打字（点一下卡片拿到键盘，Esc 交还）。网页搜索：回车用所选的搜索站打开，
/// 中号下面一排搜索站、大号三排带名字，点一个换成用它搜（框里有字时直接搜）。查找文件：
/// 回车查找，小号列 1 个、中号 2 个、大号 5 个结果，点一下打开，能拖出去。
/// 所选的搜索站存在卡片配置里，和扩展栏面板同一份；文件结果和面板共用一个查找。
private struct DeskSearchCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.panelTint) private var panelTint
    @State private var text = ""
    @FocusState private var focused: Bool

    private var accent: Color { panelTint.accent(or: Color(hex: "#4C9BFF")) }
    private var files: Bool { widget.config.string("layout", default: "web") == "files" }
    private var custom: [SearchSite] { SearchSites.decode(widget.config.string("customSites")) }
    private var sites: [SearchSite] { SearchSites.resolve(ids: widget.config.strings("sites"), custom: custom) }
    private var engine: SearchSite? { SearchSites.selected(widget.config.string("engine", default: "bing"), in: sites) }
    private var search: FileSearch { FileSearch.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if size == .small { smallHeader }
            field
            if files { results } else { siteArea }
        }
        .padding(DesktopCardsSystem.inset(size))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var smallHeader: some View {
        HStack(spacing: 8) {
            if files {
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
            } else if let engine {
                SiteBadge(site: engine, size: 24)
            }
            Text(verbatim: files ? tr("查找文件") : (engine?.title ?? tr("搜索")))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            if size != .small {
                if files {
                    Image(systemName: "folder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                } else if let engine {
                    SiteBadge(site: engine, size: 22)
                }
            }
            TextField("", text: $text,
                      prompt: Text(verbatim: files ? tr("文件名") : (size == .small ? tr("搜索网页…")
                                                     : tr("用\(engine?.title ?? tr("网页"))搜索")))
                        .foregroundStyle(Color.panelTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Color.panelPrimary)
                .focused($focused)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.panelRaised).panelLift())
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("搜索"))
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .deskBlock(radius: 12, accent: focused ? accent : nil)
    }

    @ViewBuilder
    private var siteArea: some View {
        let count = DesktopSystemCards.rows(.searchSites, size: size)
        let shown = Array(sites.prefix(count))
        if size == .small {
            Spacer(minLength: 0)
            Text(verbatim: tr("回车就搜"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        } else if size == .medium {
            HStack(spacing: 6) {
                ForEach(shown) { site in
                    siteButton(site) { SiteBadge(site: site, size: 30) }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 8) {
                ForEach(shown) { site in
                    siteButton(site) {
                        VStack(spacing: 4) {
                            SiteBadge(site: site, size: 30)
                            Text(verbatim: site.title)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.panelPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func siteButton<Label: View>(_ site: SearchSite, @ViewBuilder label: () -> Label) -> some View {
        let selected = site.id == engine?.id
        return Button { pick(site) } label: {
            label()
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.panelSelected : Color.panelFill))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.panelTertiary : Color.clear, lineWidth: 1))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(text.isEmpty ? tr("用\(site.title)搜索") : tr("用\(site.title)搜索“\(text)”"))
        .accessibilityLabel(site.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var results: some View {
        let limit = DesktopSystemCards.rows(.fileResults, size: size)
        if search.searching {
            note(tr("正在查找…"))
        } else if search.results.isEmpty {
            note(search.query.isEmpty ? tr("输入文件名后按下 Return。") : tr("没有找到“\(search.query)”。"))
        } else {
            VStack(spacing: 4) {
                ForEach(Array(search.results.prefix(limit))) { fileRow($0) }
            }
            Spacer(minLength: 0)
            if search.results.count > limit, size != .small {
                Text(verbatim: tr("共找到 \(search.results.count) 个"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
            }
        }
    }

    private func note(_ words: String) -> some View {
        Text(verbatim: words)
            .font(.system(size: 13))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileRow(_ file: ListedFile) -> some View {
        Button { FileActions.open(file.url) } label: {
            HStack(spacing: 8) {
                FileThumb(url: file.url, pixels: 96, fill: file.isImage)
                    .frame(width: 24, height: 24)
                    .clipShape(.rect(cornerRadius: 5, style: .continuous))
                Text(verbatim: file.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .deskBlock(radius: 10)
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: file.url as NSURL) }
        .help(file.url.path)
    }

    private func pick(_ site: SearchSite) {
        let latest = WidgetWriter.current(widget.id) ?? widget
        WidgetWriter.write(latest) { $0.set("engine", .string(site.id)) }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            open(site)
        } else {
            focused = true
        }
    }

    private func submit() {
        if files {
            search.search(text)
        } else if let engine {
            open(engine)
        }
    }

    private func open(_ site: SearchSite) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, let url = site.url(for: text) else { return }
        NSWorkspace.shared.open(url)
        text = ""
        DesktopPinController.shared.releaseFocus()
    }
}
