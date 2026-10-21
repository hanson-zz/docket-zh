import Observation
import SwiftUI

/// 近七天：喝水、专注计时和习惯打卡面板底部的同一块报告。
///
/// After Grow's seven day report, in idea only: two big figures on top (每日
/// 平均 and 总量, or whatever the widget counts), seven bars below with the
/// goal as a dashed line, and the day of the month over the weekday under
/// each bar. A bar that met its goal takes the widget's colour, one that did
/// not takes a pale wash of it, and today's is outlined.
///
/// The figures come from `WeeklyReport` in Core; this file only draws them,
/// and the three wrappers at the bottom feed it each widget's own log.
///
/// 字都不小于 13pt：大数字下的说明、小块、日期和星期、目标线说明都是 13pt，
/// 说明放不下时换到第二行；目标线的说明不再贴在虚线上，挪到柱子下面单独一行。
///
/// 给了 `foldKey` 时这块可以折叠：默认收起，只留「近七天」一行和第一个大数字，
/// 点一下展开，展开状态按 `foldKey` 记住（见 `DetailPanelSections`）。面板统一
/// 限高后，喝水和习惯打卡靠它把默认打开的高度压在上限内。
struct WeeklyReportStat: Hashable {
    var value: String
    var unit: String = ""
    var label: String
}

struct WeeklyReportSection<Accessory: View>: View {
    var report: WeeklyReport
    var accent: Color
    /// The two big figures.
    var headline: [WeeklyReportStat]
    /// Smaller chips under them.
    var chips: [WeeklyReportStat] = []
    /// The words on the goal line, e.g. "目标 50 分钟"; nil hides them.
    var goalLabel: String?
    /// One bar's figure, for its tooltip.
    var valueText: (WeeklyReportDay) -> String
    /// 记展开状态的 UserDefaults 键；nil 时不折叠，总是整块显示。
    var foldKey: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    private let chartHeight: CGFloat = 84
    /// 七根柱子之间的空隙。13pt 的「周三」「Wed」要放得下，比原来窄一点。
    private let barSpacing: CGFloat = 4

    var body: some View {
        if let foldKey {
            StoredFlag(key: foldKey) { expanded in
                section(expanded: expanded)
            }
        } else {
            section(expanded: nil)
        }
    }

    /// `expanded` 为 nil 时不折叠。
    private func section(expanded: Binding<Bool>?) -> some View {
        let open = expanded?.wrappedValue ?? true
        return VStack(alignment: .leading, spacing: 10) {
            if let expanded {
                foldHeader(expanded)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("近七天")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Spacer(minLength: 4)
                    accessory()
                }
            }
            if open {
                details
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    /// 折叠时的标题行：收起时右边写第一个大数字，展开时换成原来的附加控件。
    private func foldHeader(_ expanded: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("近七天")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    if !expanded.wrappedValue, let first = headline.first {
                        Spacer(minLength: 4)
                        Text(verbatim: "\(first.label) \(first.value)\(first.unit)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                }
                .frame(minHeight: 20)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded.wrappedValue ? tr("已展开") : tr("已收起"))
            if expanded.wrappedValue {
                Spacer(minLength: 4)
                accessory()
            }
        }
    }

    @ViewBuilder private var details: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(headline.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle().fill(.panelSeparator).frame(width: 0.5, height: 40)
                        .padding(.horizontal, 10)
                }
                big(stat)
            }
        }
        if !chips.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                ForEach(chips, id: \.self) { chip($0) }
            }
            // 两块一样高：一块说明换了行，另一块跟着拉高。
            .fixedSize(horizontal: false, vertical: true)
        }
        chart
        if let goalLabel, report.goalFraction != nil {
            goalLegend(goalLabel)
        }
    }

    private func big(_ stat: WeeklyReportStat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(stat.value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .rollingValue(stat.value)
                    .lineLimit(1)
                    // 22pt 的数字最多缩到 13pt。
                    .minimumScaleFactor(13.0 / 22.0)
                if !stat.unit.isEmpty {
                    Text(stat.unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(stat.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 大数字下面的小块，说明和数字都是 13pt；说明放不下换行。
    private func chip(_ stat: WeeklyReportStat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(stat.value)\(stat.unit)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .rollingValue("\(stat.value)\(stat.unit)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPane(cornerRadius: 10)
    }

    /// 柱子下面一行：一小段虚线加「目标 2000 毫升」，说明这条虚线是什么。
    private func goalLegend(_ text: String) -> some View {
        HStack(spacing: 6) {
            GoalRule()
                .stroke(.panelTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 16, height: 1)
            Text(verbatim: text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Bars

    private var chart: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(report.days, id: \.key) { day in bar(day) }
                }
                .frame(height: chartHeight, alignment: .bottom)
                if let fraction = report.goalFraction {
                    goalLine(at: fraction)
                }
            }
            .frame(height: chartHeight)
            HStack(spacing: barSpacing) {
                ForEach(report.days, id: \.key) { day in
                    VStack(spacing: 0) {
                        Text(day.dayLabel)
                            .font(.system(size: 13, weight: day.isToday ? .bold : .semibold))
                            .monospacedDigit()
                        Text(day.weekdayLabel)
                            .font(.system(size: 13, weight: day.isToday ? .bold : .medium))
                    }
                    .foregroundStyle(.panelPrimary.opacity(day.isToday ? 0.95 : 0.5))
                    .lineLimit(1)
                    // 放不下时让出柱子间的空隙，不缩字。
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func bar(_ day: WeeklyReportDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return shape
            .fill(day.isMet ? accent.opacity(day.isToday ? 1 : 0.85)
                            : accent.mix(with: .white, by: 0.55).opacity(day.value > 0 ? 0.35 : 0.12))
            .overlay {
                if day.isToday { shape.strokeBorder(.panelPrimary, lineWidth: 1.2) }
            }
            .frame(height: max(3, chartHeight * report.fraction(day)))
            .frame(maxWidth: .infinity, maxHeight: chartHeight, alignment: .bottom)
            .help("\(day.axisLabel)：\(valueText(day))\(day.isMet ? tr("，达标") : "")")
            .accessibilityElement()
            .accessibilityLabel("\(day.isToday ? tr("今天，") : "")\(day.axisLabel)，\(valueText(day))\(day.isMet ? tr("，达标") : "")")
    }

    /// 只画虚线；说明在柱子下面的 `goalLegend`。
    private func goalLine(at fraction: Double) -> some View {
        let y = chartHeight * (1 - fraction)
        return GoalRule()
            .stroke(.panelTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .offset(y: y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A horizontal line through the middle of its frame, dashed by the stroke.
private struct GoalRule: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

extension WeeklyReportSection where Accessory == EmptyView {
    init(report: WeeklyReport, accent: Color, headline: [WeeklyReportStat], chips: [WeeklyReportStat] = [],
         goalLabel: String?, valueText: @escaping (WeeklyReportDay) -> String, foldKey: String? = nil) {
        self.init(report: report, accent: accent, headline: headline, chips: chips, goalLabel: goalLabel,
                  valueText: valueText, foldKey: foldKey, accessory: { EmptyView() })
    }
}

/// 一个记在 UserDefaults 里的开关，交给里面的内容读写。给 `@AppStorage`
/// 一个运行时才知道的键用。
private struct StoredFlag<Content: View>: View {
    @AppStorage private var on: Bool
    private let content: (Binding<Bool>) -> Content

    init(key: String, @ViewBuilder content: @escaping (Binding<Bool>) -> Content) {
        _on = AppStorage(wrappedValue: false, key)
        self.content = content
    }

    var body: some View { content($on) }
}

// MARK: - 喝水

struct WaterWeeklyReport: View {
    var days: [WaterDay]
    var goal: Int
    var ounces: Bool
    var accent: Color
    var now: Date
    var foldKey: String? = nil

    var body: some View {
        let report = WeeklyReport.water(days, goal: goal, today: now)
        let cups = WeeklyReport.waterCups(days, today: now)
        let average = Int(report.average.rounded())
        let unit = WaterIntake.unitLabel(ounces: ounces)
        return WeeklyReportSection(
            report: report, accent: accent,
            headline: [
                WeeklyReportStat(value: WaterIntake.figure(average, ounces: ounces), unit: unit, label: tr("每日平均")),
                total(Int(report.total)),
            ],
            chips: [
                WeeklyReportStat(value: WeeklyReport.figure(Double(cups) / Double(report.days.count)), unit: tr(" 杯"),
                                 label: tr("日均杯数")),
                WeeklyReportStat(value: "\(report.metDays)", unit: tr(" 天"), label: tr("达标天数")),
            ],
            goalLabel: tr("目标 \(WaterIntake.amount(goal, ounces: ounces))"),
            valueText: { WaterIntake.amount(Int($0.value), ounces: ounces) },
            foldKey: foldKey)
    }

    /// Litres past a litre, so a week's total stays short.
    private func total(_ millilitres: Int) -> WeeklyReportStat {
        if !ounces, millilitres >= 1000 {
            return WeeklyReportStat(value: WeeklyReport.figure(Double(millilitres) / 1000), unit: tr("升"), label: tr("总量"))
        }
        return WeeklyReportStat(value: WaterIntake.figure(millilitres, ounces: ounces),
                                unit: WaterIntake.unitLabel(ounces: ounces), label: tr("总量"))
    }
}

// MARK: - 专注计时

struct FocusWeeklyReport: View {
    var accent: Color
    var now: Date
    var isPreview: Bool

    @AppStorage(FocusLogStore.goalKey) private var storedGoal = 0

    var body: some View {
        let goal = FocusLog.goal(stored: storedGoal)
        let lines = isPreview ? FocusLogStore.sample(today: now) : FocusLogStore.shared.lines
        let report = FocusLog.report(lines, goal: goal, today: now)
        return WeeklyReportSection(
            report: report, accent: accent,
            headline: [
                WeeklyReportStat(value: "\(Int(report.average.rounded()))", unit: tr("分钟"), label: tr("每日平均")),
                WeeklyReportStat(value: WeeklyReport.duration(minutes: Int(report.total)), label: tr("总时长")),
            ],
            chips: [
                WeeklyReportStat(value: "\(report.metDays)", unit: tr(" 天"), label: tr("达标天数")),
                WeeklyReportStat(value: report.best.map { "\($0.weekdayLabel) \(Int($0.value))" } ?? tr("无"),
                                 unit: report.best == nil ? "" : tr(" 分"), label: tr("最长一天")),
            ],
            goalLabel: tr("目标 \(goal) 分钟"),
            valueText: { WeeklyReport.duration(minutes: Int($0.value)) }
        ) {
            Stepper(value: Binding(
                get: { goal },
                set: { storedGoal = FocusLog.clampGoal($0) }),
                in: FocusLog.goalRange, step: FocusLog.goalStep) {
                    Text(tr("每日目标 \(goal) 分钟"))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                }
                .controlSize(.mini)
                .disabled(isPreview)
                .help("只统计完整结束的专注轮次")
        }
    }
}

/// 专注记录 kept for the whole app, in user defaults like the pet's credit:
/// the timer is one timer, so its log is one log.
@MainActor @Observable
final class FocusLogStore {
    static let shared = FocusLogStore()
    nonisolated static let logKey = "docket.focus.log"
    nonisolated static let goalKey = "docket.focus.dailyGoal"
    /// Every minute ever focused; see `FocusLog.lifetimeMinutes`.
    nonisolated static let totalKey = "docket.focus.totalMinutes"
    private nonisolated static let loggedKey = "docket.focus.loggedDeadline"
    /// 第一次在深夜（23 点到 4 点前）完成一轮专注的日子，给竹篮的夜猫子徽章。
    nonisolated static let lateNightKey = "docket.focus.lateNightDay"

    private(set) var lines: [String]
    @ObservationIgnored private var timer: Timer?

    private init() {
        lines = UserDefaults.standard.stringArray(forKey: Self.logKey) ?? []
    }

    /// Checked every few seconds from launch, like the pet's watcher, so a
    /// session that ends while no timer panel is open is still counted.
    func start() {
        guard timer == nil else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { FocusLogStore.shared.check() }
        }
    }

    func check(now: Date = .now) {
        let defaults = UserDefaults.standard
        let logged = defaults.double(forKey: Self.loggedKey)
        let state = TimerStateProvider.shared.state
        guard let deadline = VirtualPet.finishedFocus(state,
                                                      credited: logged > 0
                                                          ? Date(timeIntervalSince1970: logged) : nil,
                                                      now: now) else { return }
        defaults.set(deadline.timeIntervalSince1970, forKey: Self.loggedKey)
        let seconds = FocusLog.sessionSeconds(state)
        // 今天时间轴上的一段，带上任务名。
        FocusSessionStore.shared.record(seconds: seconds, endedAt: deadline, task: state.task)
        let total = FocusLog.addingTotal(seconds: seconds, stored: defaults.integer(forKey: Self.totalKey),
                                         lines: lines)
        let next = FocusLog.adding(seconds: seconds, endedAt: deadline, to: lines)
        lines = next
        defaults.set(next, forKey: Self.logKey)
        defaults.set(total, forKey: Self.totalKey)
        if defaults.string(forKey: Self.lateNightKey) == nil, FocusLog.isLateNight(deadline) {
            defaults.set(HabitTracker.dayKey(deadline), forKey: Self.lateNightKey)
        }
    }

    /// 有没有在深夜完成过一轮专注。从这一版开始记录。
    var hasLateNightFocus: Bool {
        UserDefaults.standard.string(forKey: Self.lateNightKey) != nil
    }

    /// Every minute ever focused, never fewer than the log holds.
    var lifetimeMinutes: Int {
        FocusLog.lifetimeMinutes(stored: UserDefaults.standard.integer(forKey: Self.totalKey), lines: lines)
    }

    /// The daily goal set in the 专注计时 panel.
    static var goal: Int {
        FocusLog.goal(stored: UserDefaults.standard.integer(forKey: goalKey))
    }

    /// A believable week for the widget library, which has no log.
    static func sample(today: Date) -> [String] {
        let calendar = HabitTracker.calendar
        let minutes = [25, 75, 50, 0, 100, 45, 30]
        var log: [String: Int] = [:]
        for (back, value) in minutes.reversed().enumerated() {
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            log[HabitTracker.dayKey(date, calendar: calendar)] = value
        }
        return FocusLog.lines(log, now: today, calendar: calendar)
    }
}

// MARK: - 习惯打卡

struct HabitWeeklyReport: View {
    var habits: [Habit]
    var accent: Color
    var now: Date
    var foldKey: String? = nil

    var body: some View {
        let report = WeeklyReport.habits(habits, today: now)
        return WeeklyReportSection(
            report: report, accent: accent,
            headline: [
                WeeklyReportStat(value: "\(WeeklyReport.habitCheckIns(habits, today: now))", unit: tr("次"), label: tr("7 天完成次数")),
                WeeklyReportStat(value: "\(report.metDays)", unit: tr("天"), label: tr("全勤天数")),
            ],
            chips: [
                WeeklyReportStat(value: "\(Int(report.average.rounded()))", unit: "%", label: tr("平均完成率")),
            ],
            goalLabel: tr("全勤"),
            valueText: { tr("完成 \(Int($0.value.rounded()))%") },
            foldKey: foldKey)
    }
}
