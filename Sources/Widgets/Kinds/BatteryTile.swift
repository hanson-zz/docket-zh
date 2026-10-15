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
                Spacer(minLength: 0)
            }
        }
    }

    /// The same gauge the activity tile draws: the arc is the reading, and the
    /// middle says what it is of. No figure underneath - it restates the arc
    /// and is what made the ring look cramped next to the metric rings.
    private var gauges: some View {
        HStack(spacing: 0) {
            ForEach(slots) { slot in
                let reading = reading(slot)
                MetricProgressRing(progress: reading.present ? reading.level : 0,
                                   tint: tint(reading),
                                   track: reading.present
                                       ? tint(reading).opacity(0.16)
                                       : Color.primary.opacity(0.10),
                                   diameter: 42,
                                   lineWidth: 4.5) {
                    Image(systemName: slot.symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(reading.present ? tint(reading) : WidgetStyle.secondary)
                }
                .overlay(alignment: .bottomTrailing) {
                    if reading.charging { bolt }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(slot.name)
                .accessibilityValue(caption(reading))
                .help("\(slot.name) \(percentText(reading))")
            }
        }
        .lineLimit(1)
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
    private func ringTint(_ reading: Reading) -> Color {
        guard reading.present, !reading.charging else { return WidgetStyle.primary }
        if reading.level <= 0.10 { return Color(hex: "#FF453A") }
        if reading.level <= 0.20 { return Color(hex: "#FF9F0A") }
        return WidgetStyle.primary
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

        var id: String {
            switch self {
            case .fixed(let kind, _): "fixed.\(kind.rawValue)"
            case .accessory(let device): "bt.\(device.id)"
            }
        }

        var name: String {
            switch self {
            case .fixed(.pods, let source?): source.displayName
            case .fixed(.podsCase, let source?): "\(source.displayName) 充电盒"
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
                result.append(.accessory(BluetoothBattery(id: "preview.mouse", name: "妙控鼠标",
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
        return Reading(level: device.level, charging: device.charging, present: true)
    }

    private func caption(_ reading: Reading) -> String {
        guard reading.present else { return "未连接" }
        return reading.charging ? "正在充电" : "使用电池"
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
        case .mac: "电池"
        case .pods: "AirPods"
        case .podsCase: "AirPods 充电盒"
        case .keyboard: "键盘"
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
