import AppKit
import SwiftUI

/// Charge for the Mac and whatever Bluetooth accessories are connected.
///
/// The configured devices (the Mac by default) keep their slots. With
/// 显示蓝牙设备 on, up to `BatteryShelf.accessorySlots` more slots go to
/// connected accessories, chosen by `BluetoothBatteries.tilePicks`: a
/// battery at or below 20% first, then earbuds and headphones, mouse,
/// trackpad, keyboard, controller, speaker. The panel lists all of them.
struct BatteryTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                column
            } else {
                switch layout {
                case "icon": icons
                // The single-device card keeps its look until an accessory
                // connects; then the same space holds a row of gauges.
                case "status" where slots.count == 1: status(slots[0])
                default: gauges
                }
            }
        }
        // A reminder going out flashes the tile twice, so a glance at the
        // shelf says which widget the notification came from.
        .phaseAnimator([0.0, 1.0, 0.0, 1.0, 0.0],
                       trigger: context.isPreview ? 0 : BatteryAlerts.shared.pulse) { content, glow in
            content
                .scaleEffect(1 + 0.05 * glow)
                .brightness(0.18 * glow)
        } animation: { _ in .easeInOut(duration: 0.22) }
        // ponytail: start-only; one sampler feeds every battery tile.
        .onAppear { if !context.isPreview { BatteryMetrics.shared.start() } }
    }

    // MARK: Layouts

    @ViewBuilder
    private func status(_ slot: Slot) -> some View {
        let reading = reading(slot)
        let symbol = Image(systemName: slot.symbol)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(reading.present ? WidgetStyle.primary : WidgetStyle.secondary)

        if context.position.isVertical {
            // A column has the height for the stacked card this was drawn as.
            VStack(spacing: 4) {
                symbol
                percent(reading, size: 30)
                Text(caption(reading))
                    .font(WidgetStyle.caption(12))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            .lineLimit(1)
        } else {
            // A bottom shelf is a 62pt strip: three stacked rows overflow it
            // and the caption gets sliced off. Lay it out across instead, as
            // the shelf's badge and reading: the ring is the level, in white
            // unless the battery is low enough to earn a colour.
            HStack(spacing: 10) {
                let shown = look(for: slot)
                if shown == .classic {
                    TileBadge {
                        ZStack {
                            TileRing(progress: reading.present ? reading.level : 0,
                                     tint: ringTint(reading))
                            Image(systemName: slot.symbol)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(reading.present ? WidgetStyle.primary : WidgetStyle.secondary)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if reading.charging { bolt }
                    }
                    TileReading(value: percentText(reading), caption: caption(reading))
                } else {
                    BatteryGauge(look: shown, state: gaugeState(slot), diameter: 40,
                                 center: shown == .panda ? .none : .symbol(slot.symbol),
                                 isPreview: context.isPreview)
                    TileReading(value: percentText(reading), caption: caption(reading))
                        .modifier(BatteryPlugBounce(trigger: gaugeState(slot).pluggedAt))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 电池格（存的值仍是 gauge，原来的“百分比圆环”）：经典外观直接画电池。
    /// 只有一台设备时是一块横向电池，旁边写百分比和状态；多台设备时每台
    /// 一块竖电池，下面写百分比。液态外观也画电池，里面装的是会晃的水；
    /// 像素电池、能量粒子、小熊猫照旧画它们自己的。
    private var gauges: some View {
        let axis = ShapeMeters.cellAxis(deviceCount: slots.count)
        return HStack(spacing: 0) {
            ForEach(slots) { slot in
                let reading = reading(slot)
                Group {
                    let shown = look(for: slot)
                    if ShapeMeters.drawsCell(look: shown.rawValue) {
                        if axis == .horizontal {
                            horizontalCell(slot, reading, liquid: shown == .liquid)
                        } else {
                            VStack(spacing: 3) {
                                cell(reading, vertical: true, liquid: shown == .liquid)
                                    .frame(width: 17, height: 30)
                                percent(reading, size: 11)
                            }
                        }
                    } else {
                        BatteryGauge(look: shown, state: gaugeState(slot), diameter: 42,
                                     center: shown == .panda ? .none : .symbol(slot.symbol),
                                     isPreview: context.isPreview)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slot.name)
                .accessibilityValue("\(percentText(reading)) \(caption(reading))")
                .help("\(slot.name) \(percentText(reading))")
            }
        }
        .lineLimit(1)
    }

    /// 一台设备：横向电池，放得下就在旁边写百分比和状态，窄卡片写在下面。
    private func horizontalCell(_ slot: Slot, _ reading: Reading, liquid: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                cell(reading, vertical: false, liquid: liquid)
                    .frame(width: 54, height: 26)
                TileReading(value: percentText(reading), caption: caption(reading))
                    .fixedSize()
            }
            VStack(spacing: 3) {
                cell(reading, vertical: false, liquid: liquid)
                    .frame(width: 38, height: 19)
                percent(reading, size: 11)
            }
        }
    }

    private func cell(_ reading: Reading, vertical: Bool, liquid: Bool) -> some View {
        BatteryCellShape(fill: ShapeMeters.cellFill(level: reading.level, present: reading.present),
                         tone: ShapeMeters.cellTone(level: reading.level, charging: reading.charging,
                                                    present: reading.present),
                         charging: reading.charging,
                         vertical: vertical,
                         liquid: liquid,
                         moving: !context.isPreview && ShelfVisibility.shared.cardsOnScreen)
    }

    /// Low batteries earn a colour. Everything else stays the neutral fill, so
    /// the tile is not a traffic light while nothing is wrong.
    private func tint(_ reading: Reading) -> Color {
        guard reading.present, !reading.charging else { return present }
        if reading.level <= 0.10 { return Color(hex: "#FF453A") }
        if reading.level <= 0.20 { return Color(hex: "#FF9F0A") }
        return present
    }

    /// White while nothing is wrong; the low-battery colours only when they
    /// mean something.
    /// 电量低时的红和橙照旧；其余时候是 nil，圆环用卡片的主题色
    /// （电池默认绿，见 `WidgetTint`），不再是一圈白。
    private func ringTint(_ reading: Reading) -> Color? {
        guard reading.present else { return WidgetStyle.primary }
        guard !reading.charging else { return nil }
        if reading.level <= 0.10 { return Color(hex: "#FF453A") }
        if reading.level <= 0.20 { return Color(hex: "#FF9F0A") }
        return nil
    }

    private func percentText(_ reading: Reading) -> String {
        reading.present ? "\(Int((min(max(reading.level, 0), 1) * 100).rounded()))%" : "-"
    }

    private var icons: some View {
        HStack(spacing: 8) {
            ForEach(slots) { slot in
                let reading = reading(slot)
                Image(systemName: slot.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(reading.present ? present : WidgetStyle.secondary)
                    .frame(width: 44)
                    .overlay(alignment: .topTrailing) {
                        if reading.charging { bolt }
                    }
                    .help("\(slot.name) \(percentText(reading))")
            }
        }
    }

    /// One 62pt row per slot - `WidgetCatalog.verticalHeight` hands out
    /// `BatteryShelf.slotCount * 62`. Rows share the height, so accessory
    /// slots nothing fills leave the column evenly spaced rather than a gap
    /// at the bottom. A lone device gets the bigger ring the room allows.
    private var column: some View {
        VStack(spacing: 0) {
            ForEach(slots) { slot in
                let reading = reading(slot)
                let single = slots.count == 1
                VStack(spacing: 3) {
                    let shown = look(for: slot)
                    if layout == ProFeatures.batteryGaugeLayout, ShapeMeters.drawsCell(look: shown.rawValue) {
                        cell(reading, vertical: true, liquid: shown == .liquid)
                            .frame(width: single ? 16 : 14, height: single ? 26 : 24)
                        percent(reading, size: single ? 12 : 11)
                    } else if shown == .classic {
                        MetricProgressRing(progress: reading.present ? reading.level : 0,
                                           tint: present,
                                           track: reading.present
                                               ? present.opacity(0.18)
                                               : Color.primary.opacity(0.10),
                                           diameter: single ? 42 : 34,
                                           lineWidth: single ? 5 : 4) {
                            percent(reading, size: single ? 14 : 11)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if reading.charging { bolt }
                        }
                    } else {
                        BatteryGauge(look: shown, state: gaugeState(slot), diameter: single ? 42 : 34,
                                     center: .percent(single ? 14 : 11), isPreview: context.isPreview)
                    }
                    Image(systemName: slot.symbol)
                        .font(.system(size: single ? 13 : 11, weight: .regular))
                        .foregroundStyle(reading.present ? WidgetStyle.primary : WidgetStyle.secondary)
                }
                .frame(minHeight: 62, maxHeight: .infinity)
                .help("\(slot.name) \(percentText(reading))")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var bolt: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(present)
            .padding(3)
            .background(Circle().fill(.background))
    }

    // MARK: Data

    private var present: Color { Color(hex: MetricColor.batteryPresent) }

    private var layout: String { instance.config.string("layout", default: "status") }

    /// The widget's 外观, with a locked Pro 专属 look drawn as 经典; the
    /// library's preview shows the real one, as the Wi-Fi rings do.
    private var chosenLook: BatteryLook {
        ProLicenseGate.batteryLook(config: instance.config, unlocked: ProAccess.isUnlocked || context.isPreview)
    }

    /// The panda holds the Mac's battery; any other slot in that look gets
    /// the free 液态 gauge rather than a row of pandas.
    private func look(for slot: Slot) -> BatteryLook {
        let look = chosenLook
        if look == .panda, !slot.isMac { return .liquid }
        return look
    }

    /// The Mac slot also carries the adapter, Low Power Mode and the
    /// plug-in and full-charge moments; accessories have none of those.
    private func gaugeState(_ slot: Slot) -> BatteryGaugeState {
        let reading = reading(slot)
        var state = BatteryGaugeState(level: reading.level, charging: reading.charging, present: reading.present)
        if slot.isMac, !context.isPreview {
            let metrics = BatteryMetrics.shared
            state.lowPower = metrics.lowPowerMode
            state.watts = metrics.power.watts
            state.pluggedAt = metrics.pluggedAt
            state.fullAt = metrics.fullAt
        }
        return state
    }

    private var devices: [BatteryDeviceKind] {
        let parsed = instance.config
            .strings("devices", default: ["mac"])
            .compactMap(BatteryDeviceKind.init(configValue:))
        // Accessories are opt-in, so anything listed here was explicitly
        // asked for: show it even when disconnected (as a dash, never an
        // invented percentage) rather than silently dropping it.
        return parsed.isEmpty ? [.mac] : parsed
    }

    /// One thing the card draws: a configured device, or a connected
    /// accessory filling one of the spare slots.
    enum Slot: Identifiable {
        case fixed(BatteryDeviceKind, source: BluetoothBattery?)
        case accessory(BluetoothBattery)

        var isMac: Bool {
            if case .fixed(.mac, _) = self { return true }
            return false
        }

        var id: String {
            switch self {
            case .fixed(let kind, _): "fixed.\(kind.rawValue)"
            case .accessory(let device): "bt.\(device.id)"
            }
        }

        var name: String {
            switch self {
            case .fixed(.pods, let source?): source.displayName
            case .fixed(.podsCase, let source?): tr("\(source.displayName) 充电盒")
            case .fixed(let kind, _): kind.name
            case .accessory(let device): device.displayName
            }
        }

        /// The fixed AirPods slot draws the model it is reading (Pro, Max).
        @MainActor var symbol: String {
            switch self {
            case .fixed(.pods, let source?) where source.kind.isAirPods:
                BatterySymbol.resolve(source.kind.symbol)
            case .fixed(let kind, _): BatterySymbol.resolve(kind.symbol)
            case .accessory(let device): BatterySymbol.resolve(device.kind.symbol)
            }
        }
    }

    private var slots: [Slot] {
        let metrics = BatteryMetrics.shared
        var result: [Slot] = devices.map { kind in
            .fixed(kind, source: context.isPreview ? nil : metrics.source(of: kind))
        }
        let room = BatteryShelf.accessoryRoom(instance.config)
        guard room > 0 else { return result }
        if context.isPreview {
            // The 状态 style previews as itself; the others show what an
            // accessory slot looks like.
            if layout != "status" || devices.count > 1 {
                result.append(.accessory(BluetoothBattery(id: "preview.mouse", name: tr("妙控鼠标"),
                                                          kind: .mouse, main: 64)))
            }
            return result
        }
        // A device the card already shows in a fixed slot is not shown twice.
        let shown = Set(devices.compactMap { metrics.slotSources[$0] })
        let picks = BluetoothBatteries.tilePicks(metrics.accessories, excluding: shown, limit: room)
        return result + picks.map(Slot.accessory)
    }

    /// What a tile needs to draw one device. An absent device keeps `level` at
    /// zero - a missing accessory must never show an invented percentage.
    private struct Reading {
        var level: Double
        var charging: Bool
        var present: Bool
        /// The Mac only: on the adapter, charging or not.
        var onPower = false
    }

    private func reading(_ slot: Slot) -> Reading {
        switch slot {
        case .fixed(let kind, _): return reading(kind)
        case .accessory(let device):
            guard let level = device.level else { return Reading(level: 0, charging: false, present: false) }
            return Reading(level: Double(level) / 100, charging: device.charging, present: true)
        }
    }

    private func reading(_ kind: BatteryDeviceKind) -> Reading {
        if context.isPreview {
            switch kind {
            case .mac: return Reading(level: 0.76, charging: false, present: true)
            case .pods: return Reading(level: 0.85, charging: false, present: true)
            case .podsCase: return Reading(level: 0.32, charging: true, present: true)
            case .keyboard: return Reading(level: 0.92, charging: false, present: true)
            }
        }
        guard let device = BatteryMetrics.shared.device(kind), device.present else {
            return Reading(level: 0, charging: false, present: false)
        }
        return Reading(level: device.level, charging: device.charging, present: true, onPower: device.onPower)
    }

    private func caption(_ reading: Reading) -> String {
        guard reading.present else { return tr("未连接") }
        if reading.charging { return tr("正在充电") }
        // On the adapter and not charging: full, or held back. It is not
        // running on battery, whatever the old caption said.
        if reading.onPower { return reading.level >= 0.995 ? tr("已充满") : tr("已接电源") }
        return tr("使用电池")
    }

    @ViewBuilder
    private func percent(_ reading: Reading, size: CGFloat) -> some View {
        if reading.present {
            HStack(spacing: 0) {
                Text("\(Int((min(max(reading.level, 0), 1) * 100).rounded()))")
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.primary)
                    .rollingValue(Int((min(max(reading.level, 0), 1) * 100).rounded()))
                Text("%")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        } else {
            Text("-")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(WidgetStyle.secondary)
        }
    }
}

extension BatteryDeviceKind {
    /// Config spells the AirPods case "case"; the service calls it `podsCase`.
    init?(configValue: String) {
        if configValue == "case" { self = .podsCase } else if let kind = BatteryDeviceKind(rawValue: configValue) {
            self = kind
        } else {
            return nil
        }
    }

    /// Spoken by the screen reader, since the gauge shows only a glyph.
    var name: String {
        switch self {
        case .mac: tr("电池")
        case .pods: "AirPods"
        case .podsCase: tr("AirPods 充电盒")
        case .keyboard: tr("键盘")
        }
    }

    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .pods: "airpods"
        case .podsCase: "airpodspro.chargingcase.wireless.fill"
        case .keyboard: "keyboard"
        }
    }
}

/// SF Symbols names checked against the running system, so a name this
/// macOS does not have draws the generic radio-waves glyph rather than
/// nothing.
enum BatterySymbol {
    @MainActor private static var known: [String: Bool] = [:]

    @MainActor static func resolve(_ name: String) -> String {
        if let ok = known[name] { return ok ? name : AccessoryKind.fallbackSymbol }
        let ok = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        known[name] = ok
        return ok ? name : AccessoryKind.fallbackSymbol
    }
}

/// 电池格画的那块电池：圆角外框、正极小凸起、里面按电量填满，充电时中间一道
/// 闪电。平时是不上色的白，低于 20% 橙、10% 红；没连上是空的虚框。
struct BatteryCellShape: View {
    var fill: Double
    var tone: ShapeMeters.CellTone
    var charging: Bool
    var vertical: Bool
    /// 液态外观：电量那一截里是会晃的水，不是一块实心的颜色。
    var liquid = false
    /// 卡片在屏幕上时水才动。
    var moving = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch tone {
        // 液态的水平时是电池绿，实心的一截平时不上色。
        case .normal: liquid ? Color(hex: MetricColor.batteryPresent) : WidgetStyle.primary
        case .low: Color(hex: "#FF9F0A")
        case .critical: Color(hex: "#FF453A")
        case .absent: WidgetStyle.secondary
        }
    }

    var body: some View {
        GeometryReader { geo in
            let long = vertical ? geo.size.height : geo.size.width
            let short = vertical ? geo.size.width : geo.size.height
            let nub = max(2, long * 0.07)
            let bodyLong = long - nub - 1
            let stroke = max(1.4, short * 0.08)
            let inset = stroke + max(1, short * 0.07)
            let radius = short * 0.26
            let innerLong = max(0, bodyLong - inset * 2)
            let innerShort = max(0, short - inset * 2)

            let outline = RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(WidgetStyle.primary.opacity(tone == .absent ? 0.3 : 0.55),
                              style: StrokeStyle(lineWidth: stroke, dash: tone == .absent ? [2, 2] : []))
            let cap = RoundedRectangle(cornerRadius: nub / 2, style: .continuous)
                .fill(WidgetStyle.primary.opacity(tone == .absent ? 0.3 : 0.55))
            let corner = max(1, radius - inset * 0.6)

            ZStack(alignment: .topLeading) {
                if vertical {
                    cap.frame(width: short * 0.42, height: nub)
                        .offset(x: short * 0.29, y: 0)
                    outline.frame(width: short, height: bodyLong)
                        .offset(y: nub + 1)
                    levelFill(width: innerShort, height: innerLong, corner: corner, vertical: true)
                        .offset(x: inset, y: nub + 1 + inset)
                } else {
                    outline.frame(width: bodyLong, height: short)
                    cap.frame(width: nub, height: short * 0.42)
                        .offset(x: bodyLong + 1, y: short * 0.29)
                    levelFill(width: innerLong, height: innerShort, corner: corner, vertical: false)
                        .offset(x: inset, y: inset)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: short * (vertical ? 0.5 : 0.55), weight: .bold))
                        .foregroundStyle(fill > 0.45 ? Color.black.opacity(0.7) : WidgetStyle.primary)
                        .frame(width: vertical ? short : bodyLong, height: vertical ? bodyLong : short)
                        .offset(y: vertical ? nub + 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fill)
            .accessibilityHidden(true)
        }
    }

    /// 电量那一截：竖电池从下往上，横电池从左往右。液态时是水，竖的水位就是
    /// 电量，横的是一截装满的水，水面轻轻晃。
    @ViewBuilder
    private func levelFill(width: CGFloat, height: CGFloat, corner: CGFloat, vertical: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if liquid {
            LiquidWater(level: vertical ? fill : (fill > 0 ? 0.88 : 0), tint: tint, shape: .rect, visible: moving)
                .frame(width: vertical ? width : width * fill, height: height)
                .clipShape(shape)
                .frame(width: width, height: height, alignment: vertical ? .bottom : .leading)
        } else {
            shape.fill(tint)
                .frame(width: vertical ? width : width * fill, height: vertical ? height * fill : height)
                .frame(width: width, height: height, alignment: vertical ? .bottom : .leading)
        }
    }
}
