import AppIntents
import IOKit.ps
import SwiftUI
import WidgetKit

// MARK: - 码头 · 小熊猫

/// 只显示状态：小熊猫此刻的样子、名字和一句话，中号再加四项（饱食、心情、精力、清洁）。
/// 喂食这些还是在扩展栏面板里做。
struct PetWidgetView: View {
    var entry: CardEntry<SystemWidgetSnapshot.PetCard>
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }

    var body: some View {
        CardOrHint(entry: entry, kind: words("电子宠物")) { pet in
            if family == .systemSmall {
                VStack(spacing: 4) {
                    PetArt.view(pet.image, height: 84)
                    Text(verbatim: pet.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(verbatim: pet.status)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    PetArt.view(pet.image, height: 112)
                        .frame(width: 110)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: pet.name)
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                        Text(verbatim: pet.status)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        need(words("饱食"), pet.food, "fork.knife")
                        need(words("心情"), pet.mood, "heart.fill")
                        need(words("精力"), pet.energy, "bolt.fill")
                        need(words("清洁"), pet.clean, "sparkles")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .dockBackground()
    }

    private func need(_ title: String, _ value: Double, _ symbol: String) -> some View {
        let tint: Color = value < 35 ? .red : (value < 75 ? .orange : .green)
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 16)
                .widgetAccentable()
            Text(verbatim: title)
                .font(.system(size: 13))
                .frame(width: words.isEnglish ? 52 : 32, alignment: .leading)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint).frame(width: max(4, proxy.size.width * min(1, max(0, value / 100))))
                        .widgetAccentable()
                }
            }
            .frame(height: 6)
        }
    }
}

struct PetWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SystemWidgetStore.kindPrefix + "pet", intent: PetConfigIntent.self,
            provider: CardProvider<PetConfigIntent, SystemWidgetSnapshot.PetCard>(
                cards: { $0.pets }, id: { $0.id },
                sample: { words in
                    .init(id: "sample", name: words("小熊猫"), image: "pet-panda-cheer", status: words("心情很好"),
                          food: 82, mood: 90, energy: 70, clean: 64)
                }, refresh: 20 * 60)
        ) { entry in
            PetWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 小熊猫")
        .description("看看小熊猫现在怎么样。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 码头 · 便签

/// 只显示：便签最上面那张的字，纸色照便签。
struct NoteWidgetView: View {
    var entry: CardEntry<SystemWidgetSnapshot.NoteCard>
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var words: Words { entry.words }

    var body: some View {
        CardOrHint(entry: entry, kind: words("便签")) { note in
            let dark = Look.inkIsDark(on: note.paper)
            let ink: Color = renderingMode == .fullColor
                ? (dark ? Color.black.opacity(0.82) : Color.white.opacity(0.92)) : .primary
            Text(verbatim: note.text.isEmpty ? words("空白便签") : note.text)
                .font(.system(size: family == .systemSmall ? 14 : 15, weight: .medium))
                .foregroundStyle(ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) {
            if let paper = entry.card?.paper, let color = Look.color(hex: paper) {
                color
            } else {
                Color.clear.background(.background)
            }
        }
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SystemWidgetStore.kindPrefix + "note", intent: NoteConfigIntent.self,
            provider: CardProvider<NoteConfigIntent, SystemWidgetSnapshot.NoteCard>(
                cards: { $0.notes }, id: { $0.id },
                sample: { words in
                    .init(id: "sample", title: words("便签"),
                          text: words("周五前交方案\n☐ 订会议室\n☑ 发邮件"), paper: "#F5D15C")
                })
        ) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 便签")
        .description("把一张便签放在桌面上。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 码头 · 算

/// 只显示：「算」卡片固定的（或最近一次的）算式和结果。
struct CalcWidgetView: View {
    var entry: CardEntry<SystemWidgetSnapshot.CalcCard>

    private var words: Words { entry.words }

    var body: some View {
        CardOrHint(entry: entry, kind: words("算")) { calc in
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: calc.title, symbol: "equal.square.fill")
                Spacer(minLength: 0)
                Text(verbatim: calc.input.isEmpty ? words("点按开始计算") : calc.input)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: calc.result)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if !calc.unit.isEmpty {
                        Text(verbatim: calc.unit)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Look.panda)
                            .widgetAccentable()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .dockBackground()
    }
}

struct CalcWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SystemWidgetStore.kindPrefix + "calc", intent: CalcConfigIntent.self,
            provider: CardProvider<CalcConfigIntent, SystemWidgetSnapshot.CalcCard>(
                cards: { $0.calcs }, id: { $0.id },
                sample: { words in
                    .init(id: "sample", title: words("算"), input: "100 USD → CNY", result: "712.40", unit: "CNY")
                })
        ) { entry in
            CalcWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 算")
        .description("「算」卡片固定的那条算式和结果。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 码头 · 电池

/// 扩展自己读电源信息（IOKit，沙盒里可读），不经主 App。
struct BatteryReading: Sendable {
    var percent: Int
    var charging: Bool
    var plugged: Bool
    /// 剩余可用分钟（用电池时）或充满还要的分钟（充电时），系统还在估算时 nil。
    var minutes: Int?

    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  (description[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey as String] as? Int, capacity > 0 else { continue }
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let plugged = (description[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue
            let key: String = charging ? kIOPSTimeToFullChargeKey as String : kIOPSTimeToEmptyKey as String
            let minutes = (description[key] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return BatteryReading(percent: Int((Double(current) / Double(capacity) * 100).rounded()),
                                  charging: charging, plugged: plugged, minutes: minutes)
        }
        return nil
    }
}

struct BatteryEntry: TimelineEntry {
    let date: Date
    let words: Words
    let reading: BatteryReading?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, words: Words(lang: Shared.language(nil)),
                     reading: BatteryReading(percent: 76, charging: false, plugged: false, minutes: 312))
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(10 * 60))))
    }

    private func entry() -> BatteryEntry {
        BatteryEntry(date: .now, words: Words(lang: Shared.language(Shared.snapshot())), reading: BatteryReading.read())
    }
}

struct BatteryWidgetView: View {
    var entry: BatteryEntry
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }

    var body: some View {
        Group {
            if let reading = entry.reading {
                content(reading)
            } else {
                EmptyHint(words: words, line: words("这台 Mac 没有电池"))
            }
        }
        .dockBackground()
    }

    private func tint(_ reading: BatteryReading) -> Color {
        if reading.charging || reading.plugged { return .green }
        return reading.percent <= 20 ? .red : (reading.percent <= 40 ? .orange : .green)
    }

    private func state(_ reading: BatteryReading) -> String {
        if reading.charging { return words("正在充电") }
        if reading.plugged { return reading.percent >= 95 ? words("已充满") : words("已接通电源") }
        return words("使用电池")
    }

    private func remaining(_ reading: BatteryReading) -> String? {
        guard let minutes = reading.minutes else { return nil }
        let time = minutes >= 60 ? words("%@ 小时 %@ 分", "\(minutes / 60)", "\(minutes % 60)")
                                 : words("%@ 分钟", "\(minutes)")
        return reading.charging ? words("%@ 后充满", time) : words("剩余 %@", time)
    }

    private func content(_ reading: BatteryReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Caption(text: words("电池"), symbol: reading.charging ? "bolt.fill" : "battery.75percent")
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(reading.percent)")
                    .font(.system(size: family == .systemSmall ? 44 : 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: "%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                if family != .systemSmall {
                    Spacer(minLength: 8)
                    PetArt.view(reading.percent <= 20 && !reading.charging ? "pet-panda-rest" : "pet-panda-idle",
                                height: 56)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint(reading))
                        .frame(width: max(8, proxy.size.width * Double(reading.percent) / 100))
                        .widgetAccentable()
                }
            }
            .frame(height: 8)
            Text(verbatim: [state(reading), remaining(reading)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SystemWidgetStore.kindPrefix + "battery", provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 电池")
        .description("电量、是否在充电、还能用多久。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
