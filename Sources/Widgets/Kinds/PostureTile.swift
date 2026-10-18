import Foundation
import SwiftUI

/// 久坐提醒：小熊猫陪你坐，坐久了伸个懒腰叫你起来。
///
/// 不再是又一个会填满的圆环（那是专注计时的样子），三种样子：
/// - 坐着：小熊猫打盹，“已坐 48 分钟”“60 分钟时叫你”，下面六格，每格是间隔的六分之一。
/// - 到点：卡片变粉，小熊猫伸懒腰，“伸个懒腰吧”，点“起来了”记一次。
/// - 开着专注计时（并且打开了“休息时提醒起身”）：小熊猫趴着不打扰，起身交给专注的
///   休息环节，这时不发通知，两个都放也只提醒一次（`SitFocus`）。
///
/// 卡片其余地方的点按留给码头（打开面板）。
struct PostureTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var schedule: PostureSchedule { PostureSchedule(config: instance.config) }

    private var timer: TimerState { TimerStateProvider.shared.state }

    /// 自己记的起身和专注休息结束，取晚的那个。
    private var lastBreak: Date? {
        let raw = instance.config.double("lastBreak")
        return SitFocus.lastBreak(posture: raw > 0 ? Date(timeIntervalSince1970: raw) : nil, timer: timer)
    }

    private var active: Bool { context.isPreview || schedule.isActive(context.now) }

    /// 开着专注计时时让位。
    private var yields: Bool { !context.isPreview && SitFocus.postureYields(to: timer, now: context.now) }

    private var remaining: TimeInterval {
        if context.isPreview { return 720 }
        return schedule.remaining(lastBreak: lastBreak, now: context.now)
    }

    private var sat: TimeInterval {
        if context.isPreview { return schedule.interval * 0.8 }
        return SitFocus.sat(schedule, lastBreak: lastBreak, now: context.now)
    }

    private var due: Bool { active && !yields && remaining <= 0 }

    private var breaksToday: Int {
        if context.isPreview { return 3 }
        return PostureTally.today(storedDay: instance.config.string("breakDay"),
                                  count: instance.config.int("breakCount"), now: context.now)
    }

    /// 下一次通知的时刻；不在时段、开着专注时没有。
    private var nextReminder: Date? {
        guard !context.isPreview, !yields else { return nil }
        return schedule.nextReminder(lastBreak: lastBreak, now: context.now)
    }

    var body: some View {
        WidgetSurface(fill: due ? Color.timerPink.opacity(0.22) : nil) {
            if context.position.isVertical { column } else { row }
        }
        .onAppear { PostureNotifier.shared.update(instance, next: nextReminder) }
        .onChange(of: nextReminder) { _, next in PostureNotifier.shared.update(instance, next: next) }
        .onChange(of: instance.config.bool("notify", default: true)) { _, _ in
            PostureNotifier.shared.update(instance, next: nextReminder)
        }
    }

    /// 打盹、伸懒腰、趴着。
    private var pandaName: String {
        if due { return "pet-panda-cheer" }
        if yields { return "pet-panda-melt" }
        return "pet-panda-rest"
    }

    // MARK: 横排（168 × 58）

    private var row: some View {
        HStack(spacing: 8) {
            TimerPanda(name: pandaName, fallback: "figure.stand", height: 48)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                if due {
                    Text(tr("伸个懒腰吧"))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tr("坐了 \(max(1, Int(sat / 60))) 分钟 · 今天第 \(breaksToday + 1) 次"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(WidgetStyle.primary.opacity(0.75))
                        .lineLimit(1)
                    TimerPill(title: tr("起来了"), size: 10, height: 18, tint: .timerPink,
                              action: context.isPreview ? nil : { logBreak() })
                } else if yields {
                    Text(tr("专注中"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WidgetStyle.primary)
                    Text(tr("休息时再起身"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if !active {
                    Text(tr("不在提醒时段"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tr("今日已起身 \(breaksToday) 次"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(WidgetStyle.secondary)
                } else {
                    Text(SitFocus.satText(sat))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(SitFocus.dueText(schedule.interval))
                        .font(.system(size: 9.5))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    cells
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 六格：每格是提醒间隔的六分之一，坐满一格亮一格。
    private var cells: some View {
        let lit = SitFocus.litCells(sat: sat, interval: schedule.interval)
        return HStack(spacing: 3) {
            ForEach(0..<SitFocus.cells, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? Color.timerPink.opacity(0.85) : WidgetStyle.primary.opacity(0.14))
                    .frame(width: 13, height: 4)
            }
        }
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    // MARK: 竖排（76 × 88）

    private var column: some View {
        VStack(spacing: 2) {
            TimerPanda(name: pandaName, fallback: "figure.stand", height: 40)
            if due {
                TimerPill(title: tr("起来了"), size: 9.5, height: 16, tint: .timerPink,
                          action: context.isPreview ? nil : { logBreak() })
            } else {
                Text(yields ? tr("专注中") : (active ? tr("\(Int(sat / 60)) 分钟") : "--"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func logBreak() {
        withAnimation(.snappy(duration: 0.35)) { PostureLog.logBreak(instance) }
    }
}

/// The one write both the tile and the panel make.
@MainActor
enum PostureLog {
    static func logBreak(_ instance: WidgetInstance, now: Date = .now) {
        let tally = PostureTally.logging(storedDay: instance.config.string("breakDay"),
                                         count: instance.config.int("breakCount"), now: now)
        WidgetWriter.write(instance) { config in
            config.set("lastBreak", .number(now.timeIntervalSince1970))
            config.set("breakDay", .string(tally.day))
            config.set("breakCount", .number(Double(tally.count)))
        }
    }
}
