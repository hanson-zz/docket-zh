import Foundation
import SwiftUI

/// 时间进度面板五套共用的模块：分段控件、四个周期对比、本周七天、今年
/// 365 天点阵、接下来的节点和一句话。同一个模块按样式有几种画法
/// （圆环用小环、液态用试管、四格用方块），数据都从 `TimeProgressPanelModel` 来。
@MainActor
struct TimeProgressParts {
    let model: TimeProgressPanelModel
    /// 写卡片的 period 键；预览里是 nil，分段和周期都只是字，不响应点按。
    let pick: ((TimeProgress.Period) -> Void)?

    private static let periods: [TimeProgress.Period] = [.day, .week, .month, .year]

    // MARK: 小标题

    /// 模块标题，右边可以带一句（「离周末 4 天」）。
    func section<Content: View>(_ title: String, trailing: String? = nil,
                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title, trailing: trailing)
            content()
        }
    }

    func header(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TimeProgressType.smallMedium)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(TimeProgressType.small)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// 「离周末 4 天」，周末当天写「今天周末」。
    var weekendText: String {
        let days = TimeProgress.daysToWeekend(model.now)
        return days == 0 ? tr("今天周末") : tr("离周末 \(days) 天")
    }

    // MARK: 分段控件

    var segmented: some View {
        TimeProgressSegmented(selected: model.period, pick: pick)
    }

    /// 周期是一个按钮（写卡片的 period），预览里只是本身。
    @ViewBuilder
    func periodButton<Label: View>(_ span: TimeProgress.Period, @ViewBuilder label: () -> Label) -> some View {
        if let pick {
            Button { pick(span) } label: { label().contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("在小组件上显示\(span.spoken)"))
                .accessibilityAddTraits(span == model.period ? [.isSelected] : [])
        } else {
            label()
        }
    }

    // MARK: 四个周期

    /// 圆环：四个小环，数字在环里。
    var ringPeriods: some View {
        TimeProgressColorsReader { colors in
            HStack(spacing: 0) {
                ForEach(Self.periods, id: \.self) { span in
                    periodButton(span) {
                        VStack(spacing: 8) {
                            ZStack {
                                GradientRing(progress: model.fraction(span), lineWidth: 5)
                                Text(verbatim: "\(model.percent(span))%")
                                    .font(TimeProgressType.smallBold)
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(width: 50, height: 50)
                            name(span, colors: colors)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// 百分比：一行一个周期，细条、百分比、剩多少，表格最快比较。
    var tablePeriods: some View {
        TimeProgressColorsReader { colors in
            VStack(spacing: 6) {
                ForEach(Self.periods, id: \.self) { span in
                    periodButton(span) {
                        HStack(spacing: 8) {
                            name(span, colors: colors, dot: false)
                                .frame(width: 34, alignment: .leading)
                            TimeProgressThinBar(progress: model.fraction(span), color: colors.accent,
                                                bright: span == model.period)
                            Text(verbatim: "\(model.percent(span))%")
                                .font(TimeProgressType.smallBold)
                                .foregroundStyle(.white)
                                .frame(width: 40, alignment: .trailing)
                            Text(TimeProgress.remainingShort(span, now: model.now))
                                .font(TimeProgressType.small)
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 78, alignment: .trailing)
                        }
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(height: 18)
                    }
                }
            }
        }
    }

    /// 液态：四支试管，水静止，只有上面的大杯会动。
    var tubePeriods: some View {
        TimeProgressColorsReader { colors in
            HStack(spacing: 0) {
                ForEach(Self.periods, id: \.self) { span in
                    periodButton(span) {
                        VStack(spacing: 6) {
                            TimeProgressGlass(level: model.fraction(span), corner: 12, color: colors.accent)
                                .frame(width: 26, height: 62)
                            Text(verbatim: "\(model.percent(span))%")
                                .font(TimeProgressType.smallBold)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .padding(.top, 4)
                            name(span, colors: colors, dot: false, tinted: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// 进度条：每条按真实单位分段（今天 24 小时、本周 7 天、本月按天数、今年 52 周）。
    var unitPeriods: some View {
        TimeProgressColorsReader { colors in
            VStack(spacing: 8) {
                ForEach(Self.periods, id: \.self) { span in
                    periodButton(span) {
                        HStack(spacing: 8) {
                            name(span, colors: colors, dot: false)
                                .frame(width: 34, alignment: .leading)
                            TimeProgressUnitBar(units: TimeProgress.unitCount(span, now: model.now),
                                                progress: model.fraction(span), colors: colors)
                                .frame(height: 12)
                            Text(verbatim: "\(model.percent(span))%")
                                .font(TimeProgressType.smallBold)
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                        .lineLimit(1)
                        .frame(height: 18)
                    }
                }
            }
        }
    }

    /// 周期的名字：今天、本周、本月、今年。卡片上显示的那个最亮，圆环下面加一个点。
    private func name(_ span: TimeProgress.Period, colors: TimeProgressColors,
                      dot: Bool = true, tinted: Bool = false) -> some View {
        let selected = span == model.period
        return VStack(spacing: 3) {
            Text(span.spoken)
                .font(selected ? TimeProgressType.smallBold : TimeProgressType.smallMedium)
                .foregroundStyle(selected ? (tinted ? colors.light : .white) : .white.opacity(0.6))
                .lineLimit(1)
            if dot {
                Circle()
                    .fill(colors.light)
                    .frame(width: 4, height: 4)
                    .opacity(selected ? 1 : 0)
            }
        }
    }

    // MARK: 本周

    /// 星期几的字：今天用浅主题色，周末用对比色。
    private func weekdayLabel(_ day: TimeProgress.WeekDay, colors: TimeProgressColors) -> some View {
        Text(TimeProgress.weekdayShort(day.index))
            .font(day.isToday ? TimeProgressType.smallBold : TimeProgressType.smallMedium)
            .foregroundStyle(day.isToday ? colors.light
                             : (day.isWeekend ? colors.contrast.opacity(0.85) : .white.opacity(0.6)))
    }

    /// 圆环：七个小环，过去的打钩。
    var ringWeek: some View {
        TimeProgressColorsReader { colors in
            HStack(spacing: 0) {
                ForEach(model.weekDays, id: \.index) { day in
                    VStack(spacing: 8) {
                        ZStack {
                            GradientRing(progress: day.fraction, lineWidth: 4)
                            if day.fraction >= 1 {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .frame(width: 30, height: 30)
                        weekdayLabel(day, colors: colors)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekendText)
        }
    }

    /// 百分比：一条分成七段的进度条。
    var segmentWeek: some View {
        TimeProgressColorsReader { colors in
            HStack(spacing: 3) {
                ForEach(model.weekDays, id: \.index) { day in
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.white.opacity(0.12))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(day.isToday ? colors.light : colors.accent.opacity(0.9))
                                    .frame(width: geo.size.width * day.fraction)
                            }
                        }
                        .frame(height: 8)
                        weekdayLabel(day, colors: colors)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekendText)
        }
    }

    /// 液态：七只小杯，水静止。
    var cupWeek: some View {
        TimeProgressColorsReader { colors in
            HStack(spacing: 0) {
                ForEach(model.weekDays, id: \.index) { day in
                    VStack(spacing: 8) {
                        TimeProgressGlass(level: day.fraction, corner: 7, color: colors.accent)
                            .frame(width: 24, height: 26)
                        weekdayLabel(day, colors: colors)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekendText)
        }
    }

    /// 四格：七个方块，从下往上填，字在方块里。
    var blockWeek: some View {
        TimeProgressColorsReader { colors in
            HStack(spacing: 4) {
                ForEach(model.weekDays, id: \.index) { day in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.07))
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(colors.accent.opacity(day.isToday ? 0.95 : 0.7))
                                    .frame(height: geo.size.height * day.fraction)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        Text(TimeProgress.weekdayShort(day.index))
                            .font(day.isToday ? TimeProgressType.smallBold : TimeProgressType.smallMedium)
                            .foregroundStyle(day.isWeekend ? colors.contrast : .white.opacity(day.fraction > 0 ? 1 : 0.6))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(day.isToday ? colors.light.opacity(0.9) : .white.opacity(0.06), lineWidth: 1)
                    }
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekendText)
        }
    }

    // MARK: 今年 365 天

    /// 53 列 x 7 行，一列一周、周一在上，一格一天。圆环和液态是圆点，百分比和四格是方块。
    func yearGrid(round: Bool) -> some View {
        TimeProgressColorsReader { colors in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("今年 \(model.days.count) 天"))
                        .font(TimeProgressType.smallMedium)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 6)
                    legend(colors)
                }
                .lineLimit(1)
                TimeProgressYearGrid(days: model.days, round: round, colors: colors)
            }
        }
    }

    private func legend(_ colors: TimeProgressColors) -> some View {
        HStack(spacing: 8) {
            legendItem(tr("假日"), Circle().fill(colors.contrast))
            if model.hasAnniversaries {
                legendItem(tr("纪念日"), Circle().fill(colors.amber))
            }
            legendItem(tr("今天"), Circle().strokeBorder(.white, lineWidth: 1))
        }
    }

    private func legendItem(_ title: String, _ mark: some View) -> some View {
        HStack(spacing: 3) {
            mark.frame(width: 6, height: 6)
            Text(title)
                .font(TimeProgressType.small)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: 接下来

    /// 最近的四个节点：周末、月底、节气、法定假日，按天数排。百分比样式每格底下
    /// 再加一条细条，越近越满。
    func milestones(corner: CGFloat, progress: Bool) -> some View {
        TimeProgressColorsReader { colors in
            VStack(alignment: .leading, spacing: 10) {
                header(tr("接下来"))
                HStack(spacing: 6) {
                    let farthest = Double(max(1, model.milestones.map(\.days).max() ?? 1))
                    ForEach(Array(model.milestones.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(TimeProgressType.smallMedium)
                                .foregroundStyle(.white.opacity(0.7))
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                if item.days == 0 {
                                    Text(tr("今天"))
                                        .font(TimeProgressType.figure(16))
                                        .foregroundStyle(index == 0 ? colors.light : .white)
                                } else {
                                    Text(verbatim: "\(item.days)")
                                        .font(TimeProgressType.figure(18))
                                        .foregroundStyle(index == 0 ? colors.light : .white)
                                    Text(tr("天"))
                                        .font(TimeProgressType.smallMedium)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            .monospacedDigit()
                            if progress {
                                TimeProgressThinBar(progress: max(0.04, 1 - (Double(item.days) / farthest).squareRoot()),
                                                    color: colors.light, bright: true, height: 2.5)
                                    .padding(.top, 2)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.white.opacity(0.06)))
                        .overlay {
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
                        }
                        .help(item.estimated ? tr("放假安排还没公布，按节日当天估算") : "")
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(item.days == 0 ? tr("\(item.title)，今天")
                                                           : tr("\(item.title)，还有 \(item.days) 天"))
                    }
                }
            }
        }
    }

    // MARK: 一句话

    var note: some View {
        HStack(alignment: .center, spacing: 6) {
            BasketPanda(cheer: false, height: 30)
            Text(model.note)
                .font(TimeProgressType.smallMedium)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 小部件

/// 从环境里读面板颜色，给不是 View 的 `TimeProgressParts` 用。
struct TimeProgressColorsReader<Content: View>: View {
    @Environment(\.timeProgressColors) private var colors
    @ViewBuilder var content: (TimeProgressColors) -> Content

    var body: some View { content(colors) }
}

/// 日、周、月、年分段控件。写的是卡片的 period 键。
struct TimeProgressSegmented: View {
    var selected: TimeProgress.Period
    var pick: ((TimeProgress.Period) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TimeProgress.Period.allCases, id: \.self) { span in
                let on = span == selected
                let label = Text(span.title)
                    .font(on ? TimeProgressType.smallBold : TimeProgressType.smallMedium)
                    .foregroundStyle(.white.opacity(on ? 1 : 0.62))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                                }
                                .padding(2)
                        }
                    }
                    .contentShape(.rect)
                if let pick {
                    Button { pick(span) } label: { label }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("在小组件上显示\(span.spoken)"))
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                } else {
                    label
                }
            }
        }
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.07)))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
        }
        .animation(.snappy(duration: 0.25), value: selected)
    }
}

/// 一条细进度：浅底加主题色，不带端点的光。
struct TimeProgressThinBar: View {
    var progress: Double
    var color: Color
    var bright: Bool = false
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(color.opacity(bright ? 0.95 : 0.65))
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 按单位分段的进度：过去的格子主题色，当前格子浅一点，后面的淡白。
struct TimeProgressUnitBar: View {
    var units: Int
    var progress: Double
    var colors: TimeProgressColors

    var body: some View {
        Canvas { context, size in
            let count = max(1, units)
            let gap: CGFloat = count > 20 ? 1.4 : 3
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let lit = min(1, max(0, progress)) * Double(count)
            for index in 0..<count {
                let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: max(0.5, width), height: size.height)
                let color: Color
                if index < Int(lit) {
                    color = colors.accent.opacity(0.85)
                } else if index == Int(lit) {
                    color = colors.light.opacity(0.95)
                } else {
                    color = .white.opacity(0.12)
                }
                context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 一只静止的小玻璃杯：淡底、细边，水不动（试管和本周小杯，11 个水面同时动太耗电）。
struct TimeProgressGlass: View {
    var level: Double
    var corner: CGFloat
    var color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.white.opacity(0.06))
            LiquidWater(level: level, tint: color, visible: false, still: true)
                .clipShape(.rect(cornerRadius: corner, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.9)
        }
        .accessibilityHidden(true)
    }
}

/// 今年 365 天点阵，下面写 1月、4月、7月 和今天是第几天。
struct TimeProgressYearGrid: View {
    var days: [TimeProgress.YearDay]
    var round: Bool
    var colors: TimeProgressColors

    var body: some View {
        let lead = days.first?.weekday ?? 0
        let columns = max(1, (days.count + lead + 6) / 7)
        // 面板内容宽 268pt：按它定格子大小和高度，画的时候再按实际宽度算。
        let height = 268 / CGFloat(columns) * 7 + 24
        Canvas { context, size in
                let pitch = size.width / CGFloat(columns)
                let side = pitch * 0.76
                for day in days {
                    let slot = day.ordinal - 1 + lead
                    let center = CGPoint(x: CGFloat(slot / 7) * pitch + pitch / 2,
                                         y: CGFloat(slot % 7) * pitch + pitch / 2)
                    let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                    let path = round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 0.9)
                    let (color, opacity) = colors.day(day)
                    if day.mark == .makeupWorkday {
                        context.stroke(path, with: .color(colors.contrast.opacity(0.9)), lineWidth: 0.8)
                    } else {
                        context.fill(path, with: .color(color.opacity(opacity)))
                    }
                    if day.mark == .today {
                        let ring = Path(ellipseIn: rect.insetBy(dx: -side * 0.45, dy: -side * 0.45))
                        context.stroke(ring, with: .color(.white), lineWidth: 0.9)
                    }
                }
                let labelY = 7 * pitch + 12
                let todayX = days.first { $0.mark == .today }
                    .map { CGFloat(($0.ordinal - 1 + lead) / 7) * pitch + pitch / 2 }
                for day in days {
                    let column = CGFloat((day.ordinal - 1 + lead) / 7)
                    guard day.day == 1, [1, 4, 7, 10].contains(day.month) else { continue }
                    // 和「第几天」挤在一起的月份不写。
                    if let todayX, abs(column * pitch - todayX) < 56 { continue }
                    context.draw(Text(tr("\(day.month)月")).font(TimeProgressType.small)
                                    .foregroundStyle(.white.opacity(0.55)),
                                 at: CGPoint(x: column * pitch, y: labelY), anchor: .leading)
                }
                if let todayX, let today = days.first(where: { $0.mark == .today }) {
                    let text = Text(tr("第 \(today.ordinal) 天")).font(TimeProgressType.smallBold)
                        .foregroundStyle(.white.opacity(0.9))
                    // 靠右时右对齐，不出边。
                    let anchor: UnitPoint = todayX > size.width - 40 ? .trailing : (todayX < 40 ? .leading : .center)
                    context.draw(text, at: CGPoint(x: anchor == .trailing ? size.width : (anchor == .leading ? 0 : todayX),
                                                   y: labelY), anchor: anchor)
                }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(tr("今年第 \(days.first { $0.mark == .today }?.ordinal ?? 0) 天，共 \(days.count) 天"))
    }
}
