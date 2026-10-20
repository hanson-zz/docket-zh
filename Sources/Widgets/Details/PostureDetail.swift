import Foundation
import SwiftUI

/// 久坐提醒的面板：头图说现在该不该起身，三格是今天的起身、最长连坐和平均每次
/// 坐多久，下面是今天的时间轴和近 7 天的柱状图，再是提醒时段、间隔和一个大按钮。
///
/// 深色玻璃，粉色只做头图里小熊猫身后的淡底、时间轴的坐着段、今天的柱子和按钮。
/// 数据都在小组件自己的配置里（`breaks`、`history`、`goal`），算法见 `PostureTrack`。
/// 离开电脑自动记的休息（`autoBreaks`，见 `PostureAway`）在时间轴上画成浅色的一段、
/// 空心的点，和手动点「起来了」的实心白点区分，图例写「自动」。
struct PostureDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // A schedule rather than `context.now`, which is frozen when the
        // panel opens; see WaterDetail.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(model(now: tick.date))
        }
    }

    private var schedule: PostureSchedule { PostureSchedule(config: instance.config) }

    /// 自己记的起身和专注计时的休息结束，取晚的那个，和卡片一样。
    private var lastBreak: Date? {
        let raw = instance.config.double("lastBreak")
        return SitFocus.lastBreak(posture: raw > 0 ? Date(timeIntervalSince1970: raw) : nil,
                                  timer: TimerStateProvider.shared.state)
    }

    // MARK: 数据

    private struct Model {
        var now: Date
        var active: Bool
        var yields: Bool
        var due: Bool
        var left: TimeInterval
        var sat: TimeInterval
        var over: TimeInterval
        var count: Int
        var stretches: [PostureTrack.Stretch]
        /// 离开电脑自动记的休息，裁到时段和现在之内。
        var rests: [PostureTrack.Stretch]
        /// 离开电脑中（开着离开检测）：到点不提醒。
        var away: Bool = false
        var windowStart: Date
        var windowEnd: Date
        var week: [PostureTrack.Day]
        var goal: Int

        var longest: PostureTrack.Stretch? { PostureTrack.longest(stretches) }
        var average: TimeInterval? { PostureTrack.average(stretches) }
    }

    private func model(now: Date) -> Model {
        let calendar = Calendar.current
        let schedule = self.schedule
        let goal = PostureTrack.goal(instance.config)
        var length = schedule.end - schedule.start
        if length <= 0 { length += 1440 }
        if context.isPreview { return preview(now: now, goal: goal) }

        let timer = TimerStateProvider.shared.state
        let yields = SitFocus.postureYields(to: timer, now: now)
        let active = schedule.isActive(now)
        let away = PostureAway.suppresses(instance.config, away: PostureAwayMonitor.shared.isAway)
        let left = schedule.remaining(lastBreak: lastBreak, now: now)
        let count = PostureTally.today(storedDay: instance.config.string("breakDay"),
                                       count: instance.config.int("breakCount"), now: now)
        // 改版前只记了上次起身：时间轴至少在那一刻切一刀。专注休息结束也算一次起身。
        var breaks = PostureTrack.breaks(instance.config, now: now)
        if let lastBreak, PostureTally.dayKey(lastBreak) == PostureTally.dayKey(now) { breaks.append(lastBreak) }
        let segments = PostureAway.segments(instance.config, now: now)
        let window = PostureTrack.window(schedule, now: now)
        let todayStart = calendar.startOfDay(for: now).addingTimeInterval(TimeInterval(schedule.start * 60))
        let start = window?.start ?? todayStart
        return Model(now: now, active: active, yields: yields, due: active && !yields && !away && left <= 0,
                     left: left, sat: SitFocus.sat(schedule, lastBreak: lastBreak, now: now),
                     over: now.timeIntervalSince(schedule.due(lastBreak: lastBreak, now: now)),
                     count: count,
                     stretches: PostureTrack.stretches(schedule, breaks: breaks, away: segments, now: now),
                     rests: PostureAway.rests(schedule, segments: segments, now: now),
                     away: away,
                     windowStart: start,
                     windowEnd: window?.end ?? start.addingTimeInterval(TimeInterval(length * 60)),
                     week: PostureTrack.week(instance.config, todayCount: count, now: now),
                     goal: goal)
    }

    /// 小组件库里的示例：今天 14:03，到点超时 13 分钟，最长连坐 72 分，和效果图接近；
    /// 12:05 离开电脑 15 分钟，是一次自动记的休息。
    private func preview(now: Date, goal: Int) -> Model {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        func at(_ minutes: Int) -> Date { day.addingTimeInterval(TimeInterval(minutes * 60)) }
        let fake = at(14 * 60 + 3)
        let sample = PostureSchedule(interval: 1800, start: 9 * 60, end: 18 * 60)
        let breaks = [9 * 60 + 40, 10 * 60 + 52, 11 * 60 + 20, 12 * 60 + 5, 12 * 60 + 50, 13 * 60 + 20].map(at)
        let away = [PostureAway.Segment(start: at(12 * 60 + 5), end: at(12 * 60 + 20))]
        let counts = [6, 9, 5, 3, 1, 7, breaks.count]
        let week = PostureTrack.recentDays(now: fake).enumerated().map { index, date in
            PostureTrack.Day(date: date, count: counts[index], isToday: index == counts.count - 1)
        }
        return Model(now: fake, active: true, yields: false, due: true, left: 0, sat: 43 * 60, over: 13 * 60,
                     count: breaks.count,
                     stretches: PostureTrack.stretches(sample, breaks: breaks, away: away, now: fake),
                     rests: PostureAway.rests(sample, segments: away, now: fake),
                     windowStart: at(9 * 60), windowEnd: at(18 * 60), week: week, goal: goal)
    }

    // MARK: 画面

    private func content(_ m: Model) -> some View {
        DetailCard {
            LinearGradient(stops: [.init(color: Color(hex: "#2D242B"), location: 0),
                                   .init(color: Self.base, location: 0.35),
                                   .init(color: Color(hex: "#18181C"), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(m)
                stats(m)
                timeline(m)
                weekChart(m)
                HStack(spacing: 8) {
                    settingTile(tr("提醒时段"), hours)
                    settingTile(tr("间隔", context: "interval"), minutesText(schedule.interval))
                }
                breakButton
                if !instance.config.bool("notify", default: true) {
                    Text(tr("通知已关闭，可在小组件设置中打开。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: 头图

    private func header(_ m: Model) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerLabel(m))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(m.due ? Self.pinkLight : .white.opacity(0.7))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(headerTitle(m))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(headerCaption(m))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            TimerPanda(name: pandaName(m), fallback: "figure.stand", height: 84)
                .frame(width: 80)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 100)
        .background {
            ZStack {
                glass(12)
                RadialGradient(colors: [Color.timerPink.opacity(m.due ? 0.22 : 0.12), Color.timerPink.opacity(0)],
                               center: UnitPoint(x: 0.82, y: 0.5), startRadius: 0, endRadius: 160)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// 伸懒腰、趴着、打盹，和卡片一样。
    private func pandaName(_ m: Model) -> String {
        if m.due { return "pet-panda-cheer" }
        if m.yields { return "pet-panda-melt" }
        return "pet-panda-rest"
    }

    private func headerLabel(_ m: Model) -> String {
        if m.due { return m.over >= 60 ? tr("到点了 · 超时 \(minutesText(m.over))") : tr("到点了") }
        if m.yields { return tr("专注中") }
        guard m.active else { return tr("不在提醒时段") }
        if m.away { return tr("离开电脑中 · 到点不提醒") }
        return SitFocus.dueText(schedule.interval)
    }

    private func headerTitle(_ m: Model) -> String {
        if m.due { return tr("该起来走走了") }
        if m.yields { return tr("休息时再起身") }
        guard m.active else { return PostureSchedule.clock(schedule.start) }
        return SitFocus.satText(m.sat)
    }

    private func headerCaption(_ m: Model) -> String {
        if m.due || m.yields { return SitFocus.satText(m.sat) }
        guard m.active else { return tr("提醒从 \(PostureSchedule.clock(schedule.start)) 开始") }
        return tr("还有 \(docketClockString(m.left))")
    }

    // MARK: 三格

    private func stats(_ m: Model) -> some View {
        HStack(spacing: 8) {
            statTile(tr("今天起身"), "\(m.count)", tr("次"))
            statTile(tr("最长连坐"), m.longest.map { "\(Int($0.duration / 60))" } ?? "--", tr("分钟"))
            statTile(tr("平均每次"), m.average.map { "\(Int(($0 / 60).rounded()))" } ?? "--", tr("分钟"))
        }
    }

    private func statTile(_ label: String, _ number: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(number)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glass(10))
        .accessibilityElement(children: .combine)
    }

    // MARK: 今天时间轴

    private func timeline(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(tr("今天"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                legend
            }
            GeometryReader { geo in
                timelineCanvas(m, width: geo.size.width)
            }
            .frame(height: Self.labelRow + Self.barHeight + 22)
        }
    }

    /// 短 ▮▮▮▮▮ 长：坐着的段越久粉越深。
    private var legend: some View {
        HStack(spacing: 4) {
            Text(tr("短"))
            HStack(spacing: 1.5) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Self.segment(Double(index) / 4))
                        .frame(width: 10, height: 10)
                }
            }
            Text(tr("长"))
            awayDot
                .frame(width: 10, height: 10)
                .padding(.leading, 6)
            Text(tr("自动"))
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.62))
        .accessibilityHidden(true)
    }

    /// 自动记的休息：空心的点，比手动起身的实心白点浅。
    private var awayDot: some View {
        Circle()
            .fill(Self.base)
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.6))
    }

    private static let labelRow: CGFloat = 20
    private static let barHeight: CGFloat = 24

    private func timelineCanvas(_ m: Model, width: CGFloat) -> some View {
        let x = { (date: Date) -> CGFloat in
            CGFloat(PostureTrack.fraction(date, start: m.windowStart, end: m.windowEnd)) * width
        }
        let barTop = Self.labelRow + 2
        let showsNow = m.active && m.now > m.windowStart && m.now < m.windowEnd
        let nowX = x(m.now)
        let nowText = tr("现在 \(clock(m.now))")
        let nowWidth = Self.estimate(nowText, size: 13)
        let longest = m.longest
        let longestText = longest.map { tr("最长 \(Int($0.duration / 60)) 分") }
        let longestWidth = longestText.map { Self.estimate($0, size: 13) } ?? 0
        let longestX = longest.map { (x($0.start) + x($0.end)) / 2 } ?? 0
        let nowCenter = Self.clamp(nowX, half: nowWidth / 2, width: width)
        let longestCenter = Self.clamp(longestX, half: longestWidth / 2, width: width)
        // 两个标签挤在一起时只留「现在」，最长在上面的格子里也有。
        let showsLongest = longestText != nil
            && (!showsNow || abs(nowCenter - longestCenter) > (nowWidth + longestWidth) / 2 + 6)
        let futureFrom = showsNow ? nowX : (m.now <= m.windowStart ? 0 : width)

        return ZStack(alignment: .topLeading) {
            // 现在之后：虚线框。
            if futureFrom < width {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.6, dash: [2, 2]))
                    }
                    .frame(width: width - futureFrom, height: Self.barHeight)
                    .offset(x: futureFrom, y: barTop)
            }
            // 坐着的段，越久粉越深。
            ForEach(Array(m.stretches.enumerated()), id: \.offset) { _, stretch in
                let left = x(stretch.start), right = x(stretch.end)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Self.segment(PostureTrack.heat(stretch.duration, interval: schedule.interval)))
                    .frame(width: max(1, right - left - 1.6), height: Self.barHeight)
                    .offset(x: left + 0.8, y: barTop)
            }
            if showsLongest, let longestText {
                Text(longestText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.pinkLight)
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: longestCenter, y: Self.labelRow / 2)
            }
            if showsNow {
                Text(nowText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: nowCenter, y: Self.labelRow / 2)
                Rectangle()
                    .fill(.white)
                    .frame(width: 1.2, height: Self.barHeight + 6)
                    .offset(x: nowX - 0.6, y: barTop - 3)
            }
            // 离开电脑自动记的休息：浅色一段，够宽时写「自动」。
            ForEach(Array(m.rests.enumerated()), id: \.offset) { _, rest in
                let left = x(rest.start), right = x(rest.end)
                let span = right - left
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                    }
                    .frame(width: max(1, span - 1.6), height: Self.barHeight)
                    .offset(x: left + 0.8, y: barTop)
                if span >= Self.estimate(tr("自动"), size: 13) + 6 {
                    Text(tr("自动"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize()
                        .position(x: (left + right) / 2, y: barTop + Self.barHeight / 2)
                } else {
                    awayDot
                        .frame(width: 8, height: 8)
                        .position(x: (left + right) / 2, y: barTop + Self.barHeight / 2)
                }
            }
            // 起身：每段之间一个白点（自动休息之后开始的段不画，那段自己有标记）。
            ForEach(Array(m.stretches.dropFirst().filter { !$0.afterAway }.enumerated()), id: \.offset) { _, stretch in
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Self.base, lineWidth: 1.4))
                    .frame(width: 8, height: 8)
                    .position(x: x(stretch.start), y: barTop + Self.barHeight / 2)
            }
            // 刻度：两头贴边，中间居中。
            let ticks = PostureTrack.ticks(schedule)
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, minute in
                let text = PostureSchedule.clock(minute)
                let half = Self.estimate(text, size: 13) / 2
                let raw = CGFloat(minute - ticks[0]) / CGFloat(max(1, ticks.last! - ticks[0])) * width
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: index == 0 ? half : (index == ticks.count - 1 ? width - half : raw),
                              y: barTop + Self.barHeight + 12)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.rests.isEmpty ? tr("今天坐了 \(m.stretches.count) 段")
                            : tr("今天坐了 \(m.stretches.count) 段，自动记的休息 \(m.rests.count) 次"))
    }

    // MARK: 近 7 天

    private func weekChart(_ m: Model) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("近 7 天起身"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(tr("目标 \(m.goal) 次"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            GeometryReader { geo in
                bars(m, width: geo.size.width)
            }
            .frame(height: Self.chartTop + Self.chartHeight + 24)
        }
    }

    private static let chartTop: CGFloat = 20
    private static let chartHeight: CGFloat = 92

    private func bars(_ m: Model, width: CGFloat) -> some View {
        let ceiling = CGFloat(PostureTrack.chartCeiling(m.week, goal: m.goal))
        let bottom = Self.chartTop + Self.chartHeight
        let slot = width / CGFloat(max(1, m.week.count))
        let goalY = bottom - CGFloat(m.goal) / ceiling * Self.chartHeight
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: goalY))
                path.addLine(to: CGPoint(x: width, y: goalY))
            }
            .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 0.9, dash: [3, 2.5]))
            ForEach(Array(m.week.enumerated()), id: \.offset) { index, day in
                let center = slot * (CGFloat(index) + 0.5)
                let height = max(3, CGFloat(day.count) / ceiling * Self.chartHeight)
                let reached = day.count >= m.goal
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(day.isToday ? Color.timerPink.opacity(reached ? 1 : 0.72)
                                      : Color.white.opacity(reached ? 0.5 : 0.2))
                    .frame(width: 22, height: height)
                    .position(x: center, y: bottom - height / 2)
                Text(verbatim: "\(day.count)")
                    .font(.system(size: 13, weight: day.isToday ? .heavy : .semibold))
                    .foregroundStyle(.white.opacity(day.isToday ? 1 : 0.62))
                    .monospacedDigit()
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#1C1C20")))
                    .fixedSize()
                    .position(x: center, y: bottom - height - 10)
                Text(day.isToday ? tr("今天") : weekday(day.date))
                    .font(.system(size: 13, weight: day.isToday ? .bold : .medium))
                    .foregroundStyle(.white.opacity(day.isToday ? 1 : 0.55))
                    .fixedSize()
                    .position(x: center, y: bottom + 14)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("近 7 天起身") + " " + m.week.map { "\($0.count)" }.joined(separator: ", "))
    }

    private func weekday(_ date: Date) -> String {
        let names = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")]
        let index = Calendar.current.component(.weekday, from: date) - 1
        return names.indices.contains(index) ? names[index] : ""
    }

    // MARK: 时段、间隔、按钮

    private func settingTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glass(10))
        .accessibilityElement(children: .combine)
    }

    private var breakButton: some View {
        Button {
            guard !context.isPreview else { return }
            withAnimation(.snappy(duration: 0.35)) { PostureLog.logBreak(instance) }
        } label: {
            Text(tr("我起身活动了"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.timerPinkInk)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(Color.timerPink))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("记录一次起身"))
    }

    // MARK: 小工具

    private static let base = Color(hex: "#1D1D21")
    /// 深底上的粉色小字。
    private static let pinkLight = Color(hex: "#FFA8C6")

    /// 时间轴一段的颜色：从淡粉（粉色 30% 叠在深底上）到深粉 #C8336B。
    private static func segment(_ heat: Double) -> Color {
        let t = min(1, max(0, heat))
        let pale = (r: 98.0, g: 59.0, b: 76.0), deep = (r: 200.0, g: 51.0, b: 107.0)
        return Color(red: (pale.r + (deep.r - pale.r) * t) / 255,
                     green: (pale.g + (deep.g - pale.g) * t) / 255,
                     blue: (pale.b + (deep.b - pale.b) * t) / 255)
    }

    private func glass(_ corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.white.opacity(0.07))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
    }

    /// 放标签用的大概宽度：汉字按一个字号，数字和符号按六成。
    private static func estimate(_ text: String, size: CGFloat) -> CGFloat {
        text.unicodeScalars.reduce(0) { sum, scalar in
            sum + (scalar.value > 0x2E80 ? size : (scalar == " " ? size * 0.3 : size * 0.6))
        }
    }

    /// 标签中心别出两头。
    private static func clamp(_ x: CGFloat, half: CGFloat, width: CGFloat) -> CGFloat {
        guard width > half * 2 else { return width / 2 }
        return min(width - half, max(half, x))
    }

    private var hours: String {
        "\(PostureSchedule.clock(schedule.start))-\(PostureSchedule.clock(schedule.end))"
    }

    private func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return PostureSchedule.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// 「13 分钟」「1 小时 5 分」。
    private func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes < 60 { return tr("\(minutes) 分钟") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("\(h) 小时") : tr("\(h) 小时 \(m) 分")
    }
}
