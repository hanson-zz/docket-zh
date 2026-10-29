import SwiftUI

// MARK: - 卜卦 · 签历（Pro）
//
// 抽过的签按日期自动记下（Core 的 Divination.stickLog，留一年多，收藏的一直留着）。
// 月历每天一个小圆点按签级上色，点有点的日子在下面看那天的签、收藏；底下列出收藏的签。
// 只在解锁后从每日一签页的「签历」进来；按面板内容宽 266 排（七列各 38）。

struct DivinationArchiveView: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var onClose: () -> Void

    @State private var month: Date?
    @State private var selected: String?
    @State private var showFavorites = false

    private static let width = CGFloat(Divination.panelContentWidth)
    private static let cell = (CGFloat(Divination.panelContentWidth) / 7).rounded(.down)
    private var calendar: Calendar { WeekAgenda.calendar }
    private var config: WidgetConfig { instance.config }
    private var shownMonth: Date { month ?? MonthGrid.monthStart(context.now, calendar: calendar) }
    private var today: String { Divination.dayKey(context.now, calendar: calendar) }
    private var focusDay: String { selected ?? today }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                DivinationBackButton(title: tr("今天"), action: onClose)
                Spacer(minLength: 4)
                Text(tr("签历"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
            }
            monthBar
            grid
            legend
            dayDetail
            favoritesSection
        }
        .frame(width: Self.width)
    }

    // MARK: 月份

    private var isCurrentMonth: Bool {
        MonthGrid.monthStart(context.now, calendar: calendar) == shownMonth
    }

    private var monthBar: some View {
        HStack(spacing: 8) {
            ToothRoundButton(symbol: "chevron.left", diameter: 28, help: tr("上个月")) {
                month = MonthGrid.shift(shownMonth, by: -1, calendar: calendar)
            }
            Text(verbatim: Self.monthTitle(shownMonth, calendar: calendar))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
                .frame(maxWidth: .infinity)
            ToothRoundButton(symbol: "chevron.right", diameter: 28, help: tr("下个月")) {
                guard !isCurrentMonth else { return }
                month = MonthGrid.shift(shownMonth, by: 1, calendar: calendar)
            }
            .opacity(isCurrentMonth ? 0.35 : 1)
            .disabled(isCurrentMonth)
        }
    }

    private static func monthTitle(_ month: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.interfaceLocale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: month)
    }

    /// 周一开头的星期几（按界面语言）。
    private static var weekdays: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = L10n.interfaceLocale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return ["一", "二", "三", "四", "五", "六", "日"] }
        return Array(symbols[1...]) + [symbols[0]]
    }

    // MARK: 月历

    private var grid: some View {
        let levels = Divination.monthLevels(config, month: shownMonth, calendar: calendar)
        let weeks = MonthGrid.weeks(shownMonth, now: context.now, calendar: calendar)
        return VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(Self.weekdays.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                        .frame(width: Self.cell)
                }
            }
            ForEach(weeks) { week in
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        dayCell(day, levels: levels)
                    }
                }
            }
        }
        .frame(width: Self.width)
    }

    @ViewBuilder private func dayCell(_ day: MonthGrid.Day, levels: [String: StickLevel]) -> some View {
        let key = Divination.dayKey(day.date, calendar: calendar)
        let level = day.inMonth ? levels[key] : nil
        let isSelected = key == focusDay && day.inMonth
        Button {
            guard day.inMonth, level != nil else { return }
            selected = key
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: "\(calendar.component(.day, from: day.date))")
                    .font(.system(size: 13, weight: day.isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(day.inMonth ? (day.isToday ? DivinationStyle.red : Color.panelPrimary)
                                                 : Color.clear)
                Circle()
                    .fill(level.map(DivinationLevelDot.color) ?? Color.clear)
                    .frame(width: 7, height: 7)
            }
            .frame(width: Self.cell, height: 36)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.panelSelected)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // 不用 disabled：那会把没抽签的日子整格调暗。没签的日子点了不动。
        .allowsHitTesting(day.inMonth && level != nil)
        .accessibilityLabel(level.map { "\(key) \($0.title)" } ?? key)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(StickLevel.allCases, id: \.self) { level in
                HStack(spacing: 3) {
                    Circle().fill(DivinationLevelDot.color(level)).frame(width: 7, height: 7)
                    Text(verbatim: DivinationLevelDot.short(level))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: 那天的签

    @ViewBuilder private var dayDetail: some View {
        if let record = Divination.record(day: focusDay, in: config) {
            recordCard(record)
        } else {
            Text(focusDay == today ? tr("今天还没抽签") : tr("这天没有抽签"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    private func recordCard(_ record: Divination.StickRecord) -> some View {
        let stick = record.stick
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: DivinationShareCard.dateText(day: record.day, calendar: calendar))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    DivinationDailyPlay.toggleFavorite(day: record.day, in: instance)
                } label: {
                    Image(systemName: record.favorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(record.favorite ? DivinationStyle.red : Color.panelSecondary)
                        .frame(width: 28, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(record.favorite ? tr("取消收藏") : tr("收藏这支签"))
                .accessibilityLabel(record.favorite ? tr("取消收藏") : tr("收藏这支签"))
            }
            HStack(spacing: 8) {
                Text(verbatim: Divination.stickNumber(record.index))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                Text(verbatim: stick.level.title)
                    .font(.custom("Songti SC", size: 17).weight(.heavy))
                    .foregroundStyle(DivinationStyle.level(stick.level))
            }
            VStack(spacing: 2) {
                ForEach(stick.poemLines, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.custom("Songti SC", size: 15).weight(.semibold))
                        .foregroundStyle(Color.panelPrimary)
                }
            }
            (Text(tr("今日宜：")).font(.system(size: 13, weight: .bold)).foregroundStyle(DivinationStyle.red)
                + Text(verbatim: stick.good).font(.system(size: 13)).foregroundStyle(Color.panelPrimary)
                + Text(verbatim: "  ")
                + Text(tr("今日忌：")).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.panelPrimary)
                + Text(verbatim: stick.avoid).font(.system(size: 13)).foregroundStyle(Color.panelPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    // MARK: 收藏

    @ViewBuilder private var favoritesSection: some View {
        let favorites = Divination.favorites(config)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showFavorites.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DivinationStyle.red)
                    Text(tr("收藏的签"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: "\(favorites.count)")
                        .font(.system(size: 13))
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    if !favorites.isEmpty {
                        Image(systemName: showFavorites ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.panelSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(favorites.isEmpty)
            if favorites.isEmpty {
                Text(tr("点签旁边的星星收藏喜欢的签诗"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if showFavorites {
                ForEach(favorites) { record in
                    favoriteRow(record)
                }
            }
        }
    }

    private func favoriteRow(_ record: Divination.StickRecord) -> some View {
        Button {
            selected = record.day
            if let date = Divination.date(fromDay: record.day, calendar: calendar) {
                month = MonthGrid.monthStart(date, calendar: calendar)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: record.stick.poem.first ?? "")
                        .font(.custom("Songti SC", size: 14).weight(.semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                    Text(verbatim: "\(record.day) · \(Divination.stickNumber(record.index))")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(verbatim: record.stick.level.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DivinationStyle.level(record.stick.level))
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected == record.day ? Color.panelSelected : Color.panelFill))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
