import SwiftUI

/// Today in both calendars, the next solar term, and the coming breaks with
/// their make-up workdays.
struct LunarDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var holidays: HolidayService { HolidayService.shared }

    var body: some View {
        let now = context.now
        let breaks = holidays.breaks(now: now)
        let reading = LunarReading(now: now, config: instance.config, known: holidays.known, breaks: breaks)
        let upcoming = Array(breaks.filter {
            ChineseCalendar.days(from: now, to: $0.start) + $0.length > 0
        }.prefix(4))
        return DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.red))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateLine(now))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(reading.lunar.full + (reading.special.map { " · \($0)" } ?? ""))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white.opacity(0.8))
                }

                HStack(spacing: 8) {
                    if let term = ChineseCalendar.nextTerm(after: now) {
                        StatChip(label: "下一个节气", value: termLine(term, now: now))
                    }
                    if let alert = reading.alert {
                        StatChip(label: "提醒", value: alert)
                    }
                }

                VStack(spacing: 4) {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, item in
                        row(item, now: now)
                    }
                }

                Text(HolidayService.attribution)
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if !context.isPreview { holidays.refresh() } }
    }

    private func row(_ item: HolidayBreak, now: Date) -> some View {
        let days = ChineseCalendar.days(from: now, to: item.start)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.white)
                Text(HolidaySchedule.describe(item))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(days > 0 ? "\(days) 天后" : "放假中")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(days > 0 ? .white.opacity(0.8) : Color(hex: PaletteColor.red.hex))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassPane(cornerRadius: 9)
    }

    private func dateLine(_ date: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日 星期" + String(LunarReading.weekday(date).dropFirst())
    }

    private func termLine(_ term: ChineseCalendar.SolarTerm, now: Date) -> String {
        let days = ChineseCalendar.days(from: now, to: term.day)
        return days == 0 ? "今天\(term.name)" : "\(term.name) · \(days) 天后"
    }
}
