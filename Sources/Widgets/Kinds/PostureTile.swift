import Foundation
import SwiftUI

/// 久坐提醒：小熊猫陪你坐，坐久了伸个懒腰叫你起来。
///
/// 不再是又一个会填满的圆环（那是专注计时的样子），三种样子：
/// - 坐着：小熊猫打盹，“已坐 48 分钟”“60 分钟时叫你”，下面六格，每格是间隔的六分之一。
/// - 到点：小熊猫伸懒腰，“该起来走走了”“已坐 43 分钟”，点实心粉色的“起来了”记一次。
///   卡片照常是压暗的深色玻璃（浅色壁纸上也看得清），粉色只在小熊猫身后铺一层渐隐淡底。
/// - 开着专注计时（并且打开了“休息时提醒起身”）：小熊猫趴着不打扰，起身交给专注的
///   休息环节，这时不发通知，两个都放也只提醒一次（`SitFocus`）。
/// - 离开电脑中（锁屏、休眠或很久没碰键盘鼠标，见 `PostureAwayMonitor`）：到点不发
///   通知、不变成到点的样子；离开满设定时间自动算一次休息，回来从头计时。
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

    /// 离开电脑中，并且这张卡片开着离开检测：到点不提醒。
    private var away: Bool {
        !context.isPreview && PostureAway.suppresses(instance.config, away: PostureAwayMonitor.shared.isAway)
    }

    private var due: Bool { active && !yields && !away && remaining <= 0 }

    private var breaksToday: Int {
        if context.isPreview { return 3 }
        return PostureTally.today(storedDay: instance.config.string("breakDay"),
                                  count: instance.config.int("breakCount"), now: context.now)
    }

    /// 下一次通知的时刻；不在时段、开着专注时没有。
    private var nextReminder: Date? {
        guard !context.isPreview, !yields, !away else { return nil }
        return schedule.nextReminder(lastBreak: lastBreak, now: context.now)
    }

    var body: some View {
        // 不再用粉色顶替卡片的深色底：那样浅色壁纸上整张卡发白，白字对比度只有 1.9。
        WidgetSurface {
            ZStack {
                if due { pinkWash }
                if context.position.isVertical { column } else { row }
            }
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

    /// 小熊猫身后一层粉色淡底，往外渐隐。横排从左边铺到四成，竖排从上往下。
    private var pinkWash: some View {
        let vertical = context.position.isVertical
        return LinearGradient(stops: [.init(color: Color.timerPink.opacity(0.30), location: 0),
                                      .init(color: Color.timerPink.opacity(0), location: vertical ? 0.75 : 0.42)],
                              startPoint: vertical ? .top : .leading,
                              endPoint: vertical ? .bottom : .trailing)
            .padding(.horizontal, -WidgetStyle.inset)
            .padding(.vertical, -20)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: 横排（168 × 58）

    private var row: some View {
        HStack(spacing: 8) {
            TimerPanda(name: pandaName, fallback: "figure.stand", height: 48)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: due ? 1 : 2) {
                if due {
                    // 卡片只有 58pt 高，三行已塞满：标题 15pt，副标题和按钮 11pt。
                    Text(tr("该起来走走了"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(SitFocus.satText(max(60, sat)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetStyle.primary.opacity(0.8))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    TimerPill(title: tr("起来了"), size: 11, height: 18, tint: .timerPink,
                              solidInk: .timerPinkInk,
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
            TimerPanda(name: pandaName, fallback: "figure.stand", height: due ? 34 : 40)
            if due {
                Text(tr("\(max(1, Int(sat / 60))) 分钟"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TimerPill(title: tr("起来了"), size: 11, height: 18, tint: .timerPink, minWidth: 56,
                          solidInk: .timerPinkInk,
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
///
/// 除了原来的上次起身和今天次数，还记今天每次起身的时刻（`breaks`）和最近 7 天
/// 每天的次数（`history`），面板的时间轴和柱状图从这里画，见 `PostureTrack`。
@MainActor
enum PostureLog {
    static func logBreak(_ instance: WidgetInstance, now: Date = .now) {
        let config = instance.config
        let tally = PostureTally.logging(storedDay: config.string("breakDay"),
                                         count: config.int("breakCount"), now: now)
        let breaks = PostureTrack.breaksAfterLogging(config, now: now)
        let history = PostureTrack.historyAfterLogging(config, todayCount: tally.count, now: now)
        WidgetWriter.write(instance) { config in
            config.set("lastBreak", .number(now.timeIntervalSince1970))
            config.set("breakDay", .string(tally.day))
            config.set("breakCount", .number(Double(tally.count)))
            config.set(PostureTrack.breaksKey, .list(breaks))
            config.set(PostureTrack.historyKey, .list(history))
        }
    }

    /// 离开电脑满设定时间，自动算一次休息（`PostureAwayMonitor` 调）。
    ///
    /// 久坐计时从现在清零（回来时再改成回来那一刻）。`logged` 时和点「起来了」一样
    /// 记进今天的次数、`breaks`（记在离开那一刻）和近 7 天，另在 `autoBreaks` 里开一段
    /// 还没回来的自动休息，面板时间轴据此画成浅一点的「自动」。
    static func logAutoBreak(_ instance: WidgetInstance, since: Date, logged: Bool, now: Date = .now) {
        let config = instance.config
        guard logged else {
            WidgetWriter.write(instance) { $0.set("lastBreak", .number(now.timeIntervalSince1970)) }
            return
        }
        let tally = PostureTally.logging(storedDay: config.string("breakDay"),
                                         count: config.int("breakCount"), now: now)
        let breaks = PostureTrack.breaksAfterLogging(config, at: since, now: now)
        let history = PostureTrack.historyAfterLogging(config, todayCount: tally.count, now: now)
        let segments = PostureAway.segmentsAfterResting(config, since: since, now: now)
        WidgetWriter.write(instance) { config in
            config.set("lastBreak", .number(now.timeIntervalSince1970))
            config.set("breakDay", .string(tally.day))
            config.set("breakCount", .number(Double(tally.count)))
            config.set(PostureTrack.breaksKey, .list(breaks))
            config.set(PostureTrack.historyKey, .list(history))
            config.set(PostureAway.segmentsKey, .list(segments))
        }
    }

    /// 离开算过休息之后回来了：久坐从回来那一刻重新计时，还没收尾的自动休息收在这一刻。
    static func resume(_ instance: WidgetInstance, at: Date, now: Date = .now) {
        let segments = PostureAway.segmentsAfterReturning(instance.config, at: at, now: now)
        WidgetWriter.write(instance) { config in
            config.set("lastBreak", .number(at.timeIntervalSince1970))
            if !segments.isEmpty { config.set(PostureAway.segmentsKey, .list(segments)) }
        }
    }
}
