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
    @ViewBuilder var accessory: () -> Accessory

    private let chartHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("近七天")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                accessory()
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(headline.enumerated()), id: \.offset) { index, stat in
                    if index > 0 {
                        Rectangle().fill(.white.opacity(0.18)).frame(width: 0.5, height: 34)
                            .padding(.horizontal, 12)
                    }
                    big(stat)
                }
                Spacer(minLength: 0)
            }
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { StatChip(label: $0.label, value: "\($0.value)\($0.unit)") }
                }
            }
            chart
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func big(_ stat: WeeklyReportStat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(stat.value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .rollingValue(stat.value)
                if !stat.unit.isEmpty {
                    Text(stat.unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Text(stat.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Bars

    private var chart: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(report.days, id: \.key) { day in bar(day) }
                }
                .frame(height: chartHeight, alignment: .bottom)
                if let fraction = report.goalFraction {
                    goalLine(at: fraction)
                }
            }
            .frame(height: chartHeight)
            HStack(spacing: 8) {
                ForEach(report.days, id: \.key) { day in
                    VStack(spacing: 0) {
                        Text(day.dayLabel)
                            .font(.system(size: 10, weight: day.isToday ? .bold : .semibold))
                            .monospacedDigit()
                        Text(day.weekdayLabel)
                            .font(.system(size: 9, weight: day.isToday ? .bold : .medium))
                    }
                    .foregroundStyle(.white.opacity(day.isToday ? 0.95 : 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                if day.isToday { shape.strokeBorder(.white.opacity(0.9), lineWidth: 1.2) }
            }
            .frame(height: max(3, chartHeight * report.fraction(day)))
            .frame(maxWidth: .infinity, maxHeight: chartHeight, alignment: .bottom)
            .help("\(day.axisLabel)：\(valueText(day))\(day.isMet ? "，达标" : "")")
            .accessibilityElement()
            .accessibilityLabel("\(day.isToday ? "今天，" : "")\(day.axisLabel)，\(valueText(day))\(day.isMet ? "，达标" : "")")
    }

    private func goalLine(at fraction: Double) -> some View {
        let y = chartHeight * (1 - fraction)
        return ZStack(alignment: .topTrailing) {
            GoalRule()
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(maxWidth: .infinity)
                .frame(height: 1)
            if let goalLabel {
                Text(goalLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(.black.opacity(0.25)))
                    .offset(y: fraction > 0.85 ? 3 : -11)
            }
        }
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
         goalLabel: String?, valueText: @escaping (WeeklyReportDay) -> String) {
        self.init(report: report, accent: accent, headline: headline, chips: chips, goalLabel: goalLabel,
                  valueText: valueText, accessory: { EmptyView() })
    }
}

// MARK: - 喝水

struct WaterWeeklyReport: View {
    var days: [WaterDay]
    var goal: Int
    var ounces: Bool
    var accent: Color
    var now: Date

    var body: some View {
        let report = WeeklyReport.water(days, goal: goal, today: now)
        let cups = WeeklyReport.waterCups(days, today: now)
        let average = Int(report.average.rounded())
        let unit = WaterIntake.unitLabel(ounces: ounces)
        return WeeklyReportSection(
            report: report, accent: accent,
            headline: [
                WeeklyReportStat(value: WaterIntake.figure(average, ounces: ounces), unit: unit, label: "每日平均"),
                total(Int(report.total)),
            ],
            chips: [
                WeeklyReportStat(value: WeeklyReport.figure(Double(cups) / Double(report.days.count)), unit: " 杯",
                                 label: "日均杯数"),
                WeeklyReportStat(value: "\(report.metDays)", unit: " 天", label: "达标天数"),
            ],
            goalLabel: "目标 \(WaterIntake.amount(goal, ounces: ounces))",
            valueText: { WaterIntake.amount(Int($0.value), ounces: ounces) })
    }

    /// Litres past a litre, so a week's total stays short.
    private func total(_ millilitres: Int) -> WeeklyReportStat {
        if !ounces, millilitres >= 1000 {
            return WeeklyReportStat(value: WeeklyReport.figure(Double(millilitres) / 1000), unit: "升", label: "总量")
        }
        return WeeklyReportStat(value: WaterIntake.figure(millilitres, ounces: ounces),
                                unit: WaterIntake.unitLabel(ounces: ounces), label: "总量")
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
                WeeklyReportStat(value: "\(Int(report.average.rounded()))", unit: "分钟", label: "每日平均"),
                WeeklyReportStat(value: WeeklyReport.duration(minutes: Int(report.total)), label: "总时长"),
            ],
            chips: [
                WeeklyReportStat(value: "\(report.metDays)", unit: " 天", label: "达标天数"),
                WeeklyReportStat(value: report.best.map { "\($0.weekdayLabel) \(Int($0.value))" } ?? "无",
                                 unit: report.best == nil ? "" : " 分", label: "最长一天"),
            ],
            goalLabel: "目标 \(goal) 分钟",
            valueText: { WeeklyReport.duration(minutes: Int($0.value)) }
        ) {
            Stepper(value: Binding(
                get: { goal },
                set: { storedGoal = FocusLog.clampGoal($0) }),
                in: FocusLog.goalRange, step: FocusLog.goalStep) {
                    Text("每日目标 \(goal) 分钟")
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(.white.opacity(0.75))
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
        let total = FocusLog.addingTotal(seconds: seconds, stored: defaults.integer(forKey: Self.totalKey),
                                         lines: lines)
        let next = FocusLog.adding(seconds: seconds, endedAt: deadline, to: lines)
        lines = next
        defaults.set(next, forKey: Self.logKey)
        defaults.set(total, forKey: Self.totalKey)
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

    var body: some View {
        let report = WeeklyReport.habits(habits, today: now)
        return WeeklyReportSection(
            report: report, accent: accent,
            headline: [
                WeeklyReportStat(value: "\(WeeklyReport.habitCheckIns(habits, today: now))", unit: "次", label: "7 天完成次数"),
                WeeklyReportStat(value: "\(report.metDays)", unit: "天", label: "全勤天数"),
            ],
            chips: [
                WeeklyReportStat(value: "\(Int(report.average.rounded()))", unit: "%", label: "平均完成率"),
            ],
            goalLabel: "全勤",
            valueText: { "完成 \(Int($0.value.rounded()))%" })
    }
}
