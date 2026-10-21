import Foundation
import SwiftUI

// 时间进度面板顶部的主视觉，每种卡片样式一个，是卡片的放大版。
// 随分段控件换周期：日、周、月、年同一个画法（四格除外，它没有主周期）。

// MARK: - 圆环

/// 大圆环，环外一圈刻度（年 12 个月、月按天数、周 7 天、日 24 小时），
/// 旁边写周期、还剩几天、第几天、第几周。
struct TimeProgressRingHero: View {
    var model: TimeProgressPanelModel
    @Environment(\.timeProgressColors) private var colors

    private static let ring: CGFloat = 128
    private static let frame: CGFloat = 146

    var body: some View {
        let period = model.period
        let rest = TimeProgress.remainingParts(period, now: model.now)
        let facts = TimeProgress.facts(period, now: model.now, known: model.known)
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                ticks(period)
                GradientRing(progress: model.fraction(period), lineWidth: 13)
                    .frame(width: Self.ring, height: Self.ring)
                VStack(spacing: 2) {
                    TimeProgressPercent(value: model.percent(period), size: 38, signSize: 19, signColor: colors.light.panelReadable)
                    Text(tr("已过去"))
                        .font(TimeProgressType.smallMedium)
                        .foregroundStyle(.panelSecondary)
                }
            }
            .frame(width: Self.frame, height: Self.frame)

            VStack(alignment: .leading, spacing: 4) {
                Text(TimeProgress.label(period, now: model.now))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(tr("还剩"))
                    .font(TimeProgressType.smallMedium)
                    .foregroundStyle(.panelSecondary)
                    .padding(.top, 6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: rest.value)
                        .font(TimeProgressType.figure(26))
                        .foregroundStyle(.panelPrimary)
                        .rollingValue(rest.value)
                    Text(rest.unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .monospacedDigit()
                ForEach(facts, id: \.self) { line in
                    Text(line)
                        .font(TimeProgressType.small)
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                }
                .padding(.top, 2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// 环外的刻度：长刻度亮一点（季度、每周、每 6 小时）。
    private func ticks(_ period: TimeProgress.Period) -> some View {
        let count = TimeProgress.ringTickCount(period, now: model.now)
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = Self.ring / 2 + 2
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi
                let major = TimeProgress.isMajorTick(index, period: period)
                let inner = base + 1
                let outer = base + (major ? 6 : 4)
                var line = Path()
                line.move(to: CGPoint(x: center.x + inner * sin(angle), y: center.y - inner * cos(angle)))
                line.addLine(to: CGPoint(x: center.x + outer * sin(angle), y: center.y - outer * cos(angle)))
                context.stroke(line, with: .color(major ? Color.panelTertiary : Color.panelQuaternary), lineWidth: count > 24 ? 1 : 1.2)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 百分比

/// 72pt 的数字，右边周期、还剩、工作日；下面一条粗进度条，带刻度。
struct TimeProgressPercentageHero: View {
    var model: TimeProgressPanelModel
    @Environment(\.timeProgressColors) private var colors

    var body: some View {
        let period = model.period
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                TimeProgressPercent(value: model.percent(period), size: 72, signSize: 32, signColor: colors.light.panelReadable)
                    .padding(.leading, -3)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(TimeProgress.label(period, now: model.now))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Text(TimeProgress.remainingDetail(period, now: model.now))
                        .font(TimeProgressType.smallMedium)
                        .foregroundStyle(.panelSecondary)
                    Text(thirdLine)
                        .font(TimeProgressType.small)
                        .foregroundStyle(.panelSecondary)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 10)
            }
            GlowBar(progress: model.fraction(period), height: 10)
                .padding(.top, 8)
            scale(period).padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
    }

    /// 今天写今天是什么日子，别的周期写还剩几个工作日（法定假日不算，调休上班算）。
    private var thirdLine: String {
        if model.period == .day { return TimeProgress.todayStatus(model.now, known: model.known) }
        return tr("\(TimeProgress.workdaysLeft(model.period, now: model.now, known: model.known)) 个工作日")
    }

    /// 进度条下的刻度：日 0/6/12/18/24 时，周七天，月 1/8/15/22/月底，年按季度。
    private func scale(_ period: TimeProgress.Period) -> some View {
        let ticks = TimeProgress.scale(period, now: model.now)
        return Canvas { context, size in
            for tick in ticks {
                let x = CGFloat(tick.position) * size.width
                if period != .week {
                    context.fill(Path(CGRect(x: min(max(0, x - 0.5), size.width - 1), y: 0, width: 1, height: 4)),
                                 with: .color(.panelQuaternary))
                }
                let anchor: UnitPoint = tick.position <= 0.001 ? .leading : (tick.position >= 0.999 ? .trailing : .center)
                context.draw(Text(tick.label).font(TimeProgressType.small).foregroundStyle(.panelTertiary),
                             at: CGPoint(x: x, y: 15), anchor: anchor)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - 液态

/// 一大杯水，水位就是进度，右边刻度（日按小时，年按月）。只有这只大杯会动，
/// 关掉液态动效或打开「减少动态效果」时静止。
struct TimeProgressLiquidHero: View {
    var model: TimeProgressPanelModel
    var visible: Bool
    var still: Bool
    @Environment(\.timeProgressColors) private var colors

    private static let height: CGFloat = 178
    private static let corner: CGFloat = 22

    var body: some View {
        let period = model.period
        let fraction = model.fraction(period)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(.panelFill)
            LiquidWater(level: fraction, tint: colors.accent, visible: visible, still: still,
                        shine: true, bubbles: 5)
                .clipShape(.rect(cornerRadius: Self.corner, style: .continuous))
            ticks(period, fraction: fraction)
            VStack(alignment: .leading, spacing: 4) {
                TimeProgressPercent(value: model.percent(period), size: 48, signSize: 22,
                                    signColor: .panelPrimary)
                Text(verbatim: "\(TimeProgress.label(period, now: model.now)) · \(TimeProgress.remainingDetail(period, now: model.now))")
                    .font(TimeProgressType.smallMedium)
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .shadow(color: .black.opacity(0.25), radius: 2)
            .padding(.leading, 16)
            .padding(.top, 18)
            .padding(.trailing, 56)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(.panelStroke, lineWidth: 1)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .combine)
    }

    /// 杯壁右侧的刻度，只画中间的（0 和满不画）。周按七天太密，隔一天标一个。
    private func ticks(_ period: TimeProgress.Period, fraction: Double) -> some View {
        var ticks = TimeProgress.scale(period, now: model.now).filter { $0.position > 0.02 && $0.position < 0.98 }
        if period == .week {
            ticks = ticks.enumerated().filter { [0, 2, 4, 6].contains($0.offset) }.map(\.element)
        }
        return Canvas { context, size in
            for tick in ticks {
                let y = size.height * CGFloat(1 - tick.position)
                context.fill(Path(CGRect(x: size.width - 14, y: y - 0.5, width: 8, height: 1)),
                             with: .color(.panelTertiary))
                let under = tick.position <= fraction
                context.draw(Text(tick.label).font(TimeProgressType.smallMedium)
                                .foregroundStyle(.panelPrimary.opacity(under ? 0.9 : 0.7)),
                             at: CGPoint(x: size.width - 18, y: y), anchor: .trailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 进度条

/// 卡片 52 根竖条的放大版。年：12 行，一行一个月，每天一根；月：一行一周，
/// 一格一天；周：七行，每天 24 小时；日：四行，每行 6 小时，一格一刻钟。
/// 法定假日、调休上班、纪念日、今天各有颜色。
struct TimeProgressBarsHero: View {
    var model: TimeProgressPanelModel
    @Environment(\.timeProgressColors) private var colors

    private static let labelWidth: CGFloat = 36

    var body: some View {
        let period = model.period
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: "\(model.percent(period))")
                        .foregroundStyle(.panelPrimary)
                        .rollingValue(model.percent(period))
                    Text(verbatim: "%").foregroundStyle(.panelSecondary)
                }
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                Text(TimeProgress.caption(period, now: model.now))
                    .font(TimeProgressType.smallMedium)
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            grid(period).padding(.top, 10)
            legend(period).padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func grid(_ period: TimeProgress.Period) -> some View {
        switch period {
        case .year: yearGrid
        case .month: monthGrid
        case .week: weekGrid
        case .day: dayGrid
        }
    }

    /// 12 行 x 每月天数。
    private var yearGrid: some View {
        let days = model.days
        let current = TimeProgress.calendar.component(.month, from: model.now)
        let rowHeight: CGFloat = 14.6
        return Canvas { context, size in
            let left = Self.labelWidth
            let pitch = (size.width - left) / 31
            let width = pitch * 0.5
            for month in 1...12 {
                let y = CGFloat(month - 1) * rowHeight
                let on = month == current
                context.draw(Text(tr("\(month)月"))
                                .font(on ? TimeProgressType.smallBold : TimeProgressType.small)
                                .foregroundStyle(on ? colors.light.panelReadable : .panelTertiary),
                             at: CGPoint(x: 0, y: y + rowHeight / 2), anchor: .leading)
            }
            for day in days {
                let y = CGFloat(day.month - 1) * rowHeight
                let height: CGFloat = day.mark == .today ? 12 : 9.5
                let rect = CGRect(x: left + CGFloat(day.day - 1) * pitch, y: y + (rowHeight - height) / 2,
                                  width: width, height: height)
                let (color, opacity) = colors.day(day)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color.opacity(opacity)))
            }
        }
        .frame(height: rowHeight * 12)
        .accessibilityHidden(true)
    }

    /// 一行一周（周一开头），一格一天；上面一行星期。
    private var monthGrid: some View {
        let calendar = TimeProgress.calendar
        let month = calendar.component(.month, from: model.now)
        let days = model.days.filter { $0.month == month }
        let lead = days.first?.weekday ?? 0
        let rows = max(1, (days.count + lead + 6) / 7)
        let rowHeight: CGFloat = 24
        let header: CGFloat = 20
        let weekStart = days.first.map { TimeProgress.weekOfYear($0.date) } ?? 1
        return Canvas { context, size in
            let left = Self.labelWidth
            let pitch = (size.width - left) / 7
            for index in 0..<7 {
                context.draw(Text(TimeProgress.weekdayShort(index)).font(TimeProgressType.small)
                                .foregroundStyle(index >= 5 ? colors.contrast.panelReadable.opacity(0.85) : .panelTertiary),
                             at: CGPoint(x: left + (CGFloat(index) + 0.5) * pitch, y: header / 2 - 2), anchor: .center)
            }
            for row in 0..<rows {
                context.draw(Text(tr("\(weekStart + row)周")).font(TimeProgressType.small)
                                .foregroundStyle(.panelTertiary),
                             at: CGPoint(x: 0, y: header + CGFloat(row) * rowHeight + rowHeight / 2), anchor: .leading)
            }
            for day in days {
                let slot = day.day - 1 + lead
                let rect = CGRect(x: left + CGFloat(slot % 7) * pitch + pitch * 0.12,
                                  y: header + CGFloat(slot / 7) * rowHeight + 3,
                                  width: pitch * 0.76, height: rowHeight - 6)
                let (color, opacity) = colors.day(day)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(color.opacity(day.mark == .future ? 0.08 : opacity * 0.9)))
                if day.mark == .today {
                    context.stroke(path, with: .color(.panelPrimary), lineWidth: 1)
                }
                context.draw(Text(verbatim: "\(day.day)").font(TimeProgressType.small)
                                .foregroundStyle(day.mark == .today ? Color.panelOnPrimary
                                                 : Color.panelPrimary.opacity(day.isPast ? 0.9 : 0.6)),
                             at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
        .frame(height: header + CGFloat(rows) * rowHeight)
        .accessibilityHidden(true)
    }

    /// 七行（周一到周日），每行 24 根，一根一小时。
    private var weekGrid: some View {
        let week = model.weekDays
        let now = model.now
        let rowHeight: CGFloat = 17
        let kinds = week.map { TimeProgress.dayKind($0.date, known: model.known) }
        return Canvas { context, size in
            let left = Self.labelWidth
            let pitch = (size.width - left) / 24
            for day in week {
                let y = CGFloat(day.index) * rowHeight
                context.draw(Text(TimeProgress.weekdayShort(day.index))
                                .font(day.isToday ? TimeProgressType.smallBold : TimeProgressType.small)
                                .foregroundStyle(day.isToday ? colors.light.panelReadable
                                                 : (day.isWeekend ? colors.contrast.panelReadable.opacity(0.85) : .panelTertiary)),
                             at: CGPoint(x: 0, y: y + rowHeight / 2), anchor: .leading)
                let off: Bool = {
                    if case .holiday = kinds[day.index] { return true }
                    return false
                }()
                for hour in 0..<24 {
                    let start = day.date.addingTimeInterval(Double(hour) * 3600)
                    let lit = start.addingTimeInterval(3600) <= now
                    let current = !lit && start <= now
                    let color: Color = lit ? (off ? colors.contrast : colors.accent).opacity(0.85)
                        : (current ? colors.light.opacity(0.95) : .panelPrimary.opacity(0.12))
                    let rect = CGRect(x: left + CGFloat(hour) * pitch, y: y + 3, width: pitch * 0.55, height: rowHeight - 6)
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color))
                }
            }
        }
        .frame(height: rowHeight * 7)
        .accessibilityHidden(true)
    }

    /// 四行（0、6、12、18 时起），每行 6 小时，一根一刻钟，小时之间空大一点。
    private var dayGrid: some View {
        let start = TimeProgress.interval(.day, now: model.now)?.start ?? model.now
        let now = model.now
        let rowHeight: CGFloat = 22
        return Canvas { context, size in
            let left = Self.labelWidth
            let hourGap: CGFloat = 4
            let hourWidth = (size.width - left - hourGap * 5) / 6
            let pitch = hourWidth / 4
            for row in 0..<4 {
                let y = CGFloat(row) * rowHeight
                context.draw(Text(tr("\(row * 6)时")).font(TimeProgressType.small).foregroundStyle(.panelTertiary),
                             at: CGPoint(x: 0, y: y + rowHeight / 2), anchor: .leading)
                for hour in 0..<6 {
                    for quarter in 0..<4 {
                        let minutes = Double(((row * 6 + hour) * 4 + quarter) * 15)
                        let begin = start.addingTimeInterval(minutes * 60)
                        let lit = begin.addingTimeInterval(900) <= now
                        let current = !lit && begin <= now
                        let color: Color = lit ? colors.accent.opacity(0.85)
                            : (current ? colors.light.opacity(0.95) : .panelPrimary.opacity(0.12))
                        let x = left + CGFloat(hour) * (hourWidth + hourGap) + CGFloat(quarter) * pitch
                        let rect = CGRect(x: x, y: y + 4, width: pitch * 0.6, height: rowHeight - 8)
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color))
                    }
                }
            }
        }
        .frame(height: rowHeight * 4)
        .accessibilityHidden(true)
    }

    /// 图例：年和月标假日、调休、纪念日；周和日只有过去和当前。
    private func legend(_ period: TimeProgress.Period) -> some View {
        var items: [(String, Color)] = [(tr("已过"), colors.accent.opacity(0.85))]
        switch period {
        case .year, .month:
            items.append((tr("假日"), colors.contrast))
            items.append((tr("调休上班"), colors.contrast.opacity(0.4)))
            if model.hasAnniversaries { items.append((tr("纪念日"), colors.amber)) }
        case .week:
            items.append((tr("假日"), colors.contrast.opacity(0.85)))
            items.append((tr("这一小时"), colors.light))
        case .day:
            items.append((tr("这一刻钟"), colors.light))
        }
        return HStack(spacing: 12) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 0.8).fill(item.1).frame(width: 3.5, height: 10)
                    Text(item.0)
                        .font(TimeProgressType.small)
                        .foregroundStyle(.panelSecondary)
                }
            }
        }
        .lineLimit(1)
        .padding(.leading, period == .year || period == .day || period == .week ? Self.labelWidth : 0)
    }
}

// MARK: - 四格

/// 放大的四格：年、月、周、今天四块，今天最亮（同卡片）。没有主周期，不放分段控件。
struct TimeProgressQuadHero: View {
    var model: TimeProgressPanelModel
    @Environment(\.timeProgressColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(TimeProgress.dateTitle(model.now))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Spacer(minLength: 6)
                Text(tr("第 \(TimeProgress.weekOfYear(model.now)) 周"))
                    .font(TimeProgressType.small)
                    .foregroundStyle(.panelTertiary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach([TimeProgress.Period.year, .month, .week, .day], id: \.self) { span in
                    tile(span)
                }
            }
        }
    }

    private func tile(_ span: TimeProgress.Period) -> some View {
        let bright = span == .day
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(span.spoken)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary.opacity(bright ? 0.95 : 0.65))
                Spacer(minLength: 4)
                Text(TimeProgress.remainingShort(span, now: model.now))
                    .font(TimeProgressType.small)
                    .foregroundStyle(.panelSecondary)
            }
            HStack(alignment: .firstTextBaseline) {
                TimeProgressPercent(value: model.percent(span), size: 30, signSize: 15,
                                    signColor: bright ? colors.light.panelReadable : .panelPrimary)
                Spacer(minLength: 4)
                Text(TimeProgress.label(span, now: model.now))
                    .font(TimeProgressType.small)
                    .foregroundStyle(.panelSecondary)
            }
            TimeProgressThinBar(progress: model.fraction(span), color: colors.accent, bright: bright, height: 4)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bright ? Color.panelFillStrong : Color.panelFill))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(bright ? colors.light.opacity(0.9) : .panelStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("\(span.spoken)已过去 \(model.percent(span))%，\(TimeProgress.remainingShort(span, now: model.now))"))
    }
}
