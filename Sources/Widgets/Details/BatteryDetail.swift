import SwiftUI

/// Every battery, one row each, where the tile had room for a row of glyphs:
/// the Mac, then every connected Bluetooth accessory.
///
/// The tile's gauge says how full a device is and nothing about which device
/// it is - a glyph inside a 42pt ring is all a shelf affords. A panel row is
/// wide enough to name the device, say whether it is charging, and still give
/// the percentage the size it deserves.
struct BatteryDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let all = items
        // The first device leads, large, and its charge colours the whole
        // card: green with room, amber getting low, red nearly out. The rest
        // follow as glass rows.
        let lead = all.first
        DetailCard {
            MeshBackdrop(color: ground(lead))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let lead { hero(lead) }
                if let lead, lead.isMac, lead.present { macSections }
                if all.count > 1 {
                    VStack(spacing: 6) {
                        ForEach(all.dropFirst()) { item in
                            row(item)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .glassPane(cornerRadius: 10)
                        }
                    }
                }
            }
        }
        // The panel can list accessories the tile was never configured to
        // show, so it cannot rely on a tile having started the sampler.
        .onAppear { if !context.isPreview { BatteryMetrics.shared.start() } }
    }

    /// The level as the card's colour. Charging reads as healthy whatever
    /// the level, since the level is on its way up.
    private func ground(_ device: Item?) -> Color {
        guard let device, device.present else { return Color(white: 0.3) }
        if device.charging || device.level > 0.5 { return Color(red: 0.12, green: 0.55, blue: 0.3) }
        if device.level > 0.2 { return Color(red: 0.75, green: 0.48, blue: 0.08) }
        return Color(red: 0.72, green: 0.16, blue: 0.14)
    }

    // MARK: Mac

    /// The widget's 外观, with a locked Pro 专属 look drawn as 经典.
    private var look: BatteryLook {
        BatteryLook.shown(config: instance.config, unlocked: Supporter.isUnlocked || context.isPreview)
    }

    private func gaugeState(_ device: Item) -> BatteryGaugeState {
        var state = BatteryGaugeState(level: device.level, charging: device.charging, present: device.present)
        if device.isMac, !context.isPreview {
            let metrics = BatteryMetrics.shared
            state.lowPower = metrics.lowPowerMode
            state.watts = metrics.power.watts
            state.pluggedAt = metrics.pluggedAt
            state.fullAt = metrics.fullAt
        }
        return state
    }

    /// Today's curve, then 最大容量, 循环次数 and 温度. Each figure the Mac
    /// does not publish is left out rather than shown as a dash.
    @ViewBuilder
    private var macSections: some View {
        if !context.isPreview {
            let metrics = BatteryMetrics.shared
            VStack(alignment: .leading, spacing: 6) {
                Text("今天")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.75))
                if metrics.history.samples(from: Calendar.current.startOfDay(for: context.now),
                                           to: context.now.addingTimeInterval(1)).isEmpty {
                    Text("每 5 分钟记录一次电量，稍后这里会画出今天的曲线")
                        .font(WidgetStyle.caption(11))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                } else {
                    BatteryDayChart(history: metrics.history, day: context.now, now: context.now)
                }
            }
            .padding(10)
            .glassPane(cornerRadius: 10)

            let health = metrics.health
            if !health.isEmpty {
                HStack(spacing: 6) {
                    if let percent = health.capacityPercent { stat("最大容量", "\(percent)%") }
                    if let cycles = health.cycles { stat("循环次数", "\(cycles)") }
                    if let celsius = health.celsius { stat("温度", BatteryHealth.celsiusText(celsius)) }
                }
            }

            ChargeLimitSection(now: context.now)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(WidgetStyle.caption(11))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(WidgetStyle.value(17))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }

    private func hero(_ device: Item) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label(device.name, systemImage: device.symbol)
                    .font(WidgetStyle.label(14))
                    .foregroundStyle(WidgetStyle.primary)
                if device.present {
                    let value = Int((min(max(device.level, 0), 1) * 100).rounded())
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(value)")
                            .font(.system(size: 60, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(WidgetStyle.primary)
                            .rollingValue(value)
                        Text("%")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .modifier(BatteryPlugBounce(trigger: gaugeState(device).pluggedAt))
                } else {
                    // A dash, never a zero: a device that is not here has no
                    // level.
                    Text("-")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(heroCaption(device))
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.75))
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if look != .classic {
                // The look, large: the panel is looked at, so it animates
                // whether or not the battery is charging.
                BatteryGauge(look: device.isMac ? look : (look == .panda ? .liquid : look),
                             state: gaugeState(device), diameter: 104,
                             center: .none, inPanel: true, isPreview: context.isPreview)
                    .padding(.bottom, 2)
            } else if device.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 6)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private func row(_ device: Item) -> some View {
        HStack(spacing: 12) {
            MetricProgressRing(progress: device.present ? device.level : 0,
                               tint: tint(device),
                               track: .white.opacity(0.14),
                               diameter: 34,
                               lineWidth: 4) {
                Image(systemName: device.symbol)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(device.present ? tint(device) : WidgetStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(WidgetStyle.primary)
                Text(caption(device))
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            Spacer(minLength: 8)
            if device.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .accessibilityLabel("正在充电")
            }
            percent(device)
        }
        .lineLimit(1)
        // One row is one fact; read as four labels it becomes a word salad.
        .accessibilityElement(children: .combine)
    }

    // MARK: Data

    private var present: Color { Color(hex: MetricColor.batteryPresent) }

    /// One row of the panel: the Mac, a configured slot, or an accessory.
    struct Item: Identifiable {
        var id: String
        var name: String
        var symbol: String
        /// 0...1. Meaningless unless `present`.
        var level: Double
        var charging: Bool
        var present: Bool
        /// AirPods: "左 80% · 右 78% · 盒 45%".
        var parts: String?

        var isMac: Bool { id == "fixed.mac" }
    }

    /// Configured devices always, plus everything else actually reporting.
    ///
    /// A device in the config was asked for, so "未连接" is the answer it
    /// is owed rather than being dropped. The rest are here because the
    /// panel is where the widget says everything it knows. With 显示蓝牙设备
    /// on, every connected accessory gets a row (AirPods with left, right
    /// and case), and the fixed AirPods and keyboard slots give way to those
    /// rows rather than repeating them. Off, the panel is what it always
    /// was. Accessories are ordered by kind and then name, so rows do not
    /// reshuffle as levels change.
    private var items: [Item] {
        let parsed = Set(instance.config
            .strings("devices", default: ["mac"])
            .compactMap(BatteryDeviceKind.init(configValue:)))
        let configured = parsed.isEmpty ? Set([BatteryDeviceKind.mac]) : parsed
        let bluetooth = BatteryShelf.showsBluetooth(instance.config)
        let accessories = bluetooth ? accessoryList : []
        let covered = !accessories.isEmpty || context.isPreview
        let kinds: [BatteryDeviceKind] = [.mac, .pods, .podsCase, .keyboard].filter { kind in
            let device = device(kind)
            if kind == .mac { return configured.contains(kind) || device.present }
            // A present AirPods or keyboard already has its accessory row.
            if bluetooth && device.present && covered { return false }
            return configured.contains(kind) || device.present
        }
        return kinds.map { item(device($0)) } + accessories.map { item($0) }
    }

    private var accessoryList: [BluetoothBattery] {
        if context.isPreview {
            return [BluetoothBattery(id: "preview.pods", name: "AirPods Pro", kind: .airpodsPro,
                                     left: 85, right: 82, caseLevel: 32),
                    BluetoothBattery(id: "preview.mouse", name: "妙控鼠标", kind: .mouse, main: 64)]
        }
        return BatteryMetrics.shared.accessories
    }

    private func item(_ device: BatteryDevice) -> Item {
        Item(id: "fixed.\(device.kind.rawValue)", name: device.kind.name,
             symbol: BatterySymbol.resolve(device.kind.symbol), level: device.level,
             charging: device.charging, present: device.present)
    }

    private func item(_ device: BluetoothBattery) -> Item {
        Item(id: "bt.\(device.id)", name: device.displayName,
             symbol: BatterySymbol.resolve(device.kind.symbol),
             level: Double(device.level ?? 0) / 100, charging: device.charging,
             present: device.level != nil, parts: device.partsCaption)
    }

    /// The service's own model rather than a second one: an absent device is
    /// `.absent`, whose zero level is never read because `present` is false.
    private func device(_ kind: BatteryDeviceKind) -> BatteryDevice {
        if context.isPreview {
            switch kind {
            case .mac: return BatteryDevice(id: "mac", kind: kind, level: 0.76, charging: false, present: true)
            case .pods: return BatteryDevice(id: "pods", kind: kind, level: 0.85, charging: false, present: true)
            case .podsCase: return BatteryDevice(id: "podsCase", kind: kind, level: 0.32, charging: true, present: true)
            case .keyboard: return BatteryDevice(id: "keyboard", kind: kind, level: 0.92, charging: false, present: true)
            }
        }
        guard let device = BatteryMetrics.shared.device(kind), device.present else {
            return .absent(kind)
        }
        return device
    }

    /// The tile's thresholds, so a battery does not change colour on its way
    /// from the shelf into the panel.
    private func tint(_ device: Item) -> Color {
        if look != .classic, device.present {
            let lowPower = device.isMac && !context.isPreview && BatteryMetrics.shared.lowPowerMode
            return BatteryColorMap.tint(level: device.level, lowPower: lowPower, charging: device.charging)
                .color.swiftUI
        }
        guard device.present, !device.charging else { return present }
        if device.level <= 0.10 { return Color(hex: "#FF453A") }
        if device.level <= 0.20 { return Color(hex: "#FF9F0A") }
        return present
    }

    /// The Mac's lead line says everything the power source knows:
    /// "充电中 · 67W · 约 48 分钟充满", "已充满", "使用电池 · 还能用约 2 小时".
    private func heroCaption(_ device: Item) -> String {
        if device.isMac, device.present {
            if context.isPreview { return "使用电池 · 还能用约 5 小时" }
            if let line = BatteryMetrics.shared.statusLine { return line }
        }
        return caption(device)
    }

    private func caption(_ device: Item) -> String {
        guard device.present else { return "未连接" }
        if let parts = device.parts { return device.charging ? "正在充电 · \(parts)" : parts }
        return device.charging ? "正在充电" : "使用电池"
    }

    @ViewBuilder
    private func percent(_ device: Item) -> some View {
        if device.present {
            let value = Int((min(max(device.level, 0), 1) * 100).rounded())
            HStack(spacing: 0) {
                Text("\(value)")
                    .font(WidgetStyle.value(20))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.primary)
                    .rollingValue(value)
                Text("%")
                    .font(WidgetStyle.value(20))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        } else {
            // A dash, never a zero: an accessory that is not here has no level.
            Text("-")
                .font(WidgetStyle.value(20))
                .foregroundStyle(WidgetStyle.secondary)
        }
    }
}
