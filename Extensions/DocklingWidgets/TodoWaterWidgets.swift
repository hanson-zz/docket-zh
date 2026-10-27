import AppIntents
import SwiftUI
import WidgetKit

// MARK: - 码头 · 快速待办

/// 小号 3 条、中号 4 条、大号 10 条。点圆圈打勾（App Intents），叠上去马上显示，
/// 主 App 合并进卡片后和扩展栏上一致；今天勾掉的留在下面，能再点回去。
struct TodoWidgetView: View {
    var entry: CardEntry<SystemWidgetSnapshot.TodoCard>
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }

    private var rowLimit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 10
        default: 4
        }
    }

    var body: some View {
        CardOrHint(entry: entry, kind: words("快速待办")) { card in
            content(card)
        }
        .dockBackground()
    }

    private func content(_ card: SystemWidgetSnapshot.TodoCard) -> some View {
        let open = SystemWidgetSnapshot.openToday(card.items)
        let rows = SystemWidgetSnapshot.shownTodos(card.items, limit: rowLimit)
        return VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: words("今天"))
                    .font(.system(size: family == .systemSmall ? 17 : 20, weight: .bold))
                Spacer(minLength: 4)
                Text(verbatim: open == 0 ? words("全部完成") : words("还剩 %@ 件", "\(open)"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(open == 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Look.panda))
                    .widgetAccentable()
            }
            if rows.isEmpty {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    PetArt.view("pet-panda-cheer", height: 44)
                    Text(verbatim: words("今天都做完了"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(rows, id: \.id) { item in
                    row(item, card: card.id)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: SystemWidgetSnapshot.TodoItem, card: String) -> some View {
        let tint = Look.color(hex: item.color) ?? Color.secondary
        return HStack(spacing: 8) {
            Button(intent: ToggleTodoIntent(card: card, item: item.id, done: !item.done)) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(item.done ? AnyShapeStyle(tint.opacity(0.8)) : AnyShapeStyle(tint))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.done ? words("标为未完成") : words("标为完成"))
            Text(verbatim: item.text)
                .font(.system(size: family == .systemSmall ? 13 : 14))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .secondary : .primary)
                .lineLimit(1)
            if !item.today, !item.done {
                Spacer(minLength: 2)
                Text(verbatim: words("以后"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SystemWidgetStore.kindPrefix + "todo", intent: TodoConfigIntent.self,
            provider: CardProvider<TodoConfigIntent, SystemWidgetSnapshot.TodoCard>(
                cards: { $0.todos }, id: { $0.id },
                sample: { words in
                    .init(id: "sample", title: words("快速待办"), items: [
                        .init(id: "1", text: words("交周报"), color: "#E5484D"),
                        .init(id: "2", text: words("买牛奶")),
                        .init(id: "3", text: words("给妈妈打电话"), done: true),
                    ])
                }, midnight: true)
        ) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 快速待办")
        .description("扩展栏上的快速待办，点圆圈就能打勾。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - 码头 · 喝水

struct WaterWidgetView: View {
    var entry: CardEntry<SystemWidgetSnapshot.WaterCard>
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }

    var body: some View {
        CardOrHint(entry: entry, kind: words("喝水")) { card in
            content(card)
        }
        .dockBackground()
    }

    private func amount(_ ml: Int, ounces: Bool) -> String {
        ounces ? String(format: "%.0f", Double(ml) / 29.5735) : "\(ml)"
    }

    private func unit(_ ounces: Bool) -> String { ounces ? words("盎司") : words("毫升") }

    private func content(_ card: SystemWidgetSnapshot.WaterCard) -> some View {
        let total = card.day == SystemWidgetSnapshot.dayKey(entry.date) ? card.total : 0
        let progress = card.goal > 0 ? min(1, Double(total) / Double(card.goal)) : 0
        let met = card.goal > 0 && total >= card.goal
        return Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Caption(text: card.title, symbol: "drop.fill")
                        Spacer(minLength: 0)
                        PetArt.view(met ? "pet-panda-cheer" : "pet-panda-drink", height: 40)
                    }
                    Spacer(minLength: 0)
                    tally(total: total, card: card, size: 30)
                    bar(progress)
                    addButton(card)
                }
            } else {
                HStack(spacing: 14) {
                    ZStack {
                        ring(progress)
                        PetArt.view(met ? "pet-panda-cheer" : "pet-panda-drink", height: 58)
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 6) {
                        Caption(text: card.title, symbol: "drop.fill")
                        Spacer(minLength: 0)
                        tally(total: total, card: card, size: 32)
                        Text(verbatim: met ? words("今天喝够了") :
                                words("还差 %@ %@", amount(max(0, card.goal - total), ounces: card.ounces),
                                      unit(card.ounces)))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        addButton(card)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func tally(total: Int, card: SystemWidgetSnapshot.WaterCard, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: amount(total, ounces: card.ounces))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(verbatim: "/ \(amount(card.goal, ounces: card.ounces)) \(unit(card.ounces))")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func bar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Look.water).frame(width: max(6, proxy.size.width * progress))
                    .widgetAccentable()
            }
        }
        .frame(height: 6)
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(Look.water, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }

    private func addButton(_ card: SystemWidgetSnapshot.WaterCard) -> some View {
        Button(intent: AddWaterIntent(card: card.id)) {
            Label {
                Text(verbatim: words("一杯 %@ %@", amount(card.cup, ounces: card.ounces), unit(card.ounces)))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } icon: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Look.water)
        .controlSize(.regular)
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SystemWidgetStore.kindPrefix + "water", intent: WaterConfigIntent.self,
            provider: CardProvider<WaterConfigIntent, SystemWidgetSnapshot.WaterCard>(
                cards: { $0.waters }, id: { $0.id },
                sample: { words in
                    .init(id: "sample", title: words("喝水"), day: SystemWidgetSnapshot.dayKey(.now),
                          total: 1250, goal: 2000, cup: 250)
                }, midnight: true)
        ) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 喝水")
        .description("今天喝了多少，点一下加一杯。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 码头 · 纪念日

struct AnniversaryWidgetView: View {
    var entry: CardEntry<SystemWidgetSnapshot.AnniversaryCard>
    @Environment(\.widgetFamily) private var family

    private var words: Words { entry.words }

    var body: some View {
        CardOrHint(entry: entry, kind: words("纪念日")) { card in
            content(card)
        }
        .dockBackground()
    }

    private func days(_ event: SystemWidgetSnapshot.AnniversaryEvent) -> Int {
        SystemWidgetSnapshot.days(to: event.target, from: entry.date) ?? 0
    }

    /// 「还有」「就是今天」「已经」。
    private func phrase(_ n: Int) -> String {
        n > 0 ? words("还有") : (n == 0 ? words("就是今天") : words("已经"))
    }

    @ViewBuilder
    private func content(_ card: SystemWidgetSnapshot.AnniversaryCard) -> some View {
        let featured = card.pinned.flatMap { id in card.events.first { $0.id == id } } ?? card.events.first
        if let featured {
            if family == .systemSmall {
                big(featured)
            } else {
                HStack(spacing: 14) {
                    big(featured)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(card.events.filter { $0.id != featured.id }.prefix(3), id: \.id) { event in
                            line(event)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            EmptyHint(words: words, line: words("在纪念日卡片里加一个日子"))
        }
    }

    private func big(_ event: SystemWidgetSnapshot.AnniversaryEvent) -> some View {
        let n = days(event)
        let tint = Look.color(hex: event.color) ?? Look.panda
        return VStack(alignment: .leading, spacing: 2) {
            Caption(text: event.title, symbol: "heart.fill")
            Spacer(minLength: 0)
            Text(verbatim: phrase(n))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            if n != 0 {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "\(abs(n))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: words("天"))
                        .font(.system(size: 15, weight: .semibold))
                }
            } else {
                PetArt.view("pet-panda-cheer", height: 44)
            }
            Text(verbatim: event.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func line(_ event: SystemWidgetSnapshot.AnniversaryEvent) -> some View {
        let n = days(event)
        return HStack(alignment: .firstTextBaseline) {
            Circle().fill(Look.color(hex: event.color) ?? Look.panda).frame(width: 7, height: 7)
                .widgetAccentable()
            Text(verbatim: event.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: n == 0 ? words("今天") : (n > 0 ? words("%@ 天后", "\(n)") : words("%@ 天", "\(-n)")))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct AnniversaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SystemWidgetStore.kindPrefix + "anniversary", intent: AnniversaryConfigIntent.self,
            provider: CardProvider<AnniversaryConfigIntent, SystemWidgetSnapshot.AnniversaryCard>(
                cards: { $0.anniversaries }, id: { $0.id },
                sample: { words in
                    let soon = Calendar.current.date(byAdding: .day, value: 59, to: .now) ?? .now
                    return .init(id: "sample", title: words("纪念日"), events: [
                        .init(id: "1", title: words("圣诞节"), target: SystemWidgetSnapshot.dayKey(soon),
                              subtitle: words.dayLine(soon)),
                    ])
                }, midnight: true)
        ) { entry in
            AnniversaryWidgetView(entry: entry)
        }
        .configurationDisplayName("码头 · 纪念日")
        .description("离重要的日子还有几天、已经几天。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
