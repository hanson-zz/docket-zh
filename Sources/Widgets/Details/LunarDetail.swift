import SwiftUI

/// 点开农历与假期：今天在两种历法里是哪天、卡片正在说的那件事、本月月历（标出休、
/// 班和节气），和接下来的节气与假期。放假和调休只来自 `HolidaySchedule`。
struct LunarDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var holidays: HolidayService { HolidayService.shared }
    private var showTerm: Bool { instance.config.bool("showTerm", default: true) }

    var body: some View {
        let now = context.now
        let breaks = holidays.breaks(now: now)
        let reading = LunarReading(now: now, config: instance.config, known: holidays.known, breaks: breaks)
        return DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.red))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLine(now))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(reading.lunar.full)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white.opacity(0.8))
                }

                headline(reading)
                month(now)
                upcoming(now, breaks: breaks)

                VStack(alignment: .leading, spacing: 2) {
                    if instance.config.bool("workAlert", default: true) {
                        Text(tr("调休补班会提前 \(LunarCard.leadDays(instance.config)) 天出现在卡片上，前一天晚上再提醒一次。"))
                    }
                    Text(HolidayService.attribution)
                }
                .font(WidgetStyle.caption(10))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if !context.isPreview { holidays.refresh() } }
    }

    // MARK: 卡片正在说的那件事

    private func headline(_ reading: LunarReading) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(reading.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(reading.isAlert ? LunarReading.red : .white)
            Text(reading.caption)
                .font(.system(size: 11, weight: reading.isCountdown ? .semibold : .regular))
                .foregroundStyle(reading.isCountdown ? LunarReading.red : .white.opacity(0.7))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 10)
    }

    // MARK: 本月

    private func month(_ now: Date) -> some View {
        let calendar = ChineseCalendar.gregorian
        let year = calendar.component(.year, from: now)
        let monthNumber = calendar.component(.month, from: now)
        let cells = LunarCard.month(year: year, month: monthNumber, now: now, known: holidays.known,
                                    showTerm: showTerm)
        let blanks = LunarCard.leadingBlanks(year: year, month: monthNumber)
        let slots: [LunarCard.MonthCell?] = Array(repeating: nil, count: blanks) + cells.map { Optional($0) }
        let rows = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<min($0 + 7, slots.count)]) }
        let lunarMonths = Array(NSOrderedSet(array: cells.map { ChineseCalendar.lunar($0.date).monthName }))
            .compactMap { $0 as? String }
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("\(String(year)) 年 \(monthNumber) 月"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(tr("农历\(lunarMonths.joined(separator: " · "))"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(WeekAgenda.weekdayNames[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { index in
                        if index < row.count, let cell = row[index] {
                            dayCell(cell)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 30)
                        }
                    }
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func dayCell(_ cell: LunarCard.MonthCell) -> some View {
        let tint: Color? = switch cell.mark {
        case .off: LunarReading.red
        case .work: Color(hex: "#FF9F45")
        case .none: nil
        }
        let sub: String = switch cell.mark {
        // 假期第一天写假期名（国庆），其余写「休」；节日、节气照写。
        case .off: cell.subIsSpecial ? trKey(cell.sub) : tr("休")
        case .work: tr("班")
        case .none: cell.subIsSpecial ? trKey(cell.sub) : cell.sub
        }
        let subColor: Color = tint ?? (cell.subIsSpecial ? Color(hex: "#FFD36B") : Color.white.opacity(0.45))
        return VStack(spacing: 0) {
            Text("\(cell.day)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(tint == nil && cell.isWeekend ? 0.7 : 1))
            Text(sub)
                .font(.system(size: 8, weight: cell.subIsSpecial || tint != nil ? .bold : .regular))
                .foregroundStyle(subColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background {
            if let tint {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.opacity(0.22))
            }
        }
        .overlay {
            if cell.isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
            }
        }
        .help(helpText(cell))
        .accessibilityElement(children: .combine)
    }

    /// 悬停：节日、节气名，或假期名和休、班。
    private func helpText(_ cell: LunarCard.MonthCell) -> String {
        let lunar = ChineseCalendar.lunar(cell.date).short
        switch HolidaySchedule.kind(of: cell.date, known: holidays.known) {
        case .holiday(let name): return tr("\(trKey(name)) · 放假 · 农历\(lunar)")
        case .makeupWorkday(let name): return tr("\(trKey(name))调休 · 上班 · 农历\(lunar)")
        default: return cell.subIsSpecial ? tr("\(trKey(cell.sub)) · 农历\(lunar)") : tr("农历\(lunar)")
        }
    }

    // MARK: 接下来

    private func upcoming(_ now: Date, breaks: [HolidayBreak]) -> some View {
        let items = LunarCard.upcoming(now: now, breaks: breaks, showTerm: showTerm)
        let calendar = ChineseCalendar.gregorian
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("接下来")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(tr("从今天 \(calendar.component(.month, from: now))月\(calendar.component(.day, from: now))日 算"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .bottom, spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.isHoliday ? LunarReading.red : Color(hex: "#FFD36B"))
                                .frame(width: 6, height: 6)
                            Text(tr("\(calendar.component(.month, from: item.date))月\(calendar.component(.day, from: item.date))日"))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 48, alignment: .leading)
                            Text(item.title)
                                .font(WidgetStyle.label(12))
                                .foregroundStyle(.white)
                            Spacer(minLength: 4)
                            Text(item.days > 0 ? tr("\(item.days) 天") : (item.isHoliday ? tr("放假中") : tr("今天")))
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(item.isHoliday ? LunarReading.red : Color(hex: "#FF9F45"))
                        }
                        .lineLimit(1)
                    }
                }
                if let panda = AIPandaArt.image {
                    Image(nsImage: panda)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func dateLine(_ date: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return tr("\(month)月\(day)日 \(LunarReading.weekday(date))")
    }
}
