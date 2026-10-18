import SwiftUI

/// 秒表：只往上数。横向大数字带两位小数，旁边最近三次计次，最快那圈标绿。
///
/// 不再用圆形徽章：码头上只有专注计时保留圆环，秒表一眼看上去就是一串数字。
/// - 宽卡片（168）：左边数字和“计次”“暂停”（停着时是“开始”“重置”），右边最近三圈。
/// - 窄卡片（120）：只有数字和一行说明，开始、计次都在面板里。
///
/// 按钮只有自己那么大，卡片其余地方的点按留给码头。状态是小组件自己配置里的
/// `started`、`elapsed` 和 `laps`（`StopwatchLaps`），重启后照样接着数。
struct StopwatchTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        let running = !context.isPreview && StopwatchLaps.isRunning(instance.config)
        // 两位小数要比码头每秒一次的刷新快；只在跑着、卡片看得见时快刷。
        TimelineView(.animation(minimumInterval: 1.0 / 20,
                                paused: !running || !ShelfVisibility.shared.cardsOnScreen)) { tick in
            let now = running ? tick.date : context.now
            content(now: now, running: running)
        }
    }

    @ViewBuilder
    private func content(now: Date, running: Bool) -> some View {
        let elapsed = context.isPreview ? 83.45 : StopwatchLaps.elapsed(instance.config, now: now)
        let laps = context.isPreview ? [24.33, 31.02, 28.10] : StopwatchLaps.laps(instance.config)
        WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 3) {
                    figure(elapsed, size: 15)
                    controls(running: running, elapsed: elapsed, laps: laps, size: 9)
                }
            } else if instance.expanded {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        figure(elapsed, size: 20)
                        controls(running: running, elapsed: elapsed, laps: laps, size: 10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !laps.isEmpty {
                        Rectangle()
                            .fill(WidgetStyle.primary.opacity(0.1))
                            .frame(width: 1, height: 40)
                        lapList(laps)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    figure(elapsed, size: 19)
                    Text(StopwatchLaps.caption(running: running, elapsed: elapsed, lapCount: laps.count))
                        .font(.system(size: 9.5))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// “01:23”加小一号、淡一点的“.45”。
    private func figure(_ elapsed: TimeInterval, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(StopwatchLaps.main(elapsed))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetStyle.primary)
            Text(StopwatchLaps.hundredths(elapsed))
                .font(.system(size: size * 0.62, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// 跑着：计次、暂停。停着：开始（或继续）、有数时重置。
    @ViewBuilder
    private func controls(running: Bool, elapsed: TimeInterval, laps: [TimeInterval], size: CGFloat) -> some View {
        let live = !context.isPreview
        HStack(spacing: 4) {
            if running {
                TimerPill(title: tr("计次"), size: size, height: size + 8,
                          action: live ? { lap() } : nil)
                TimerPill(title: tr("暂停"), size: size, height: size + 8,
                          action: live ? { toggle() } : nil)
            } else {
                TimerPill(title: elapsed > 0 ? tr("继续") : tr("开始"), size: size, height: size + 8,
                          tint: Color.timerGreen, action: live ? { toggle() } : nil)
                if elapsed > 0 {
                    TimerPill(title: tr("重置"), size: size, height: size + 8,
                              action: live ? { reset() } : nil)
                }
            }
        }
    }

    /// 最近三圈，新的在上，最快那圈标绿。
    private func lapList(_ laps: [TimeInterval]) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(StopwatchLaps.recent(laps), id: \.number) { lap in
                HStack(spacing: 5) {
                    Text(verbatim: "\(lap.number)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(WidgetStyle.secondary)
                    Text(StopwatchLaps.lapText(lap.seconds))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(lap.fastest ? Color.timerGreen : WidgetStyle.primary)
                }
                .monospacedDigit()
                .lineLimit(1)
            }
        }
        .fixedSize()
    }

    // MARK: 动作

    /// 停下时把跑过的攒进 `elapsed`，再开始是接着数。
    private func toggle() {
        guard !context.isPreview else { return }
        StopwatchActions.toggle(instance)
    }

    private func lap() {
        guard !context.isPreview else { return }
        StopwatchActions.lap(instance)
    }

    private func reset() {
        guard !context.isPreview else { return }
        StopwatchActions.reset(instance)
    }

    /// 面板里的大数字也用这个格式。
    static func format(_ elapsed: TimeInterval) -> String {
        StopwatchLaps.main(elapsed)
    }
}

/// 卡片和面板共用的三个写入，都从保存着的那份配置改，免得写回旧的。
@MainActor
enum StopwatchActions {
    static func toggle(_ instance: WidgetInstance) {
        let current = WidgetWriter.current(instance.id) ?? instance
        let started = current.config.double("started")
        let banked = current.config.double("elapsed")
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { config in
                if started > 0 {
                    config.set("elapsed", .number(banked + max(0, Date.now.timeIntervalSince1970 - started)))
                    config.set("started", .number(0))
                } else {
                    config.set("started", .number(Date.now.timeIntervalSince1970))
                }
            }
        }
    }

    static func lap(_ instance: WidgetInstance) {
        let current = WidgetWriter.current(instance.id) ?? instance
        let elapsed = StopwatchLaps.elapsed(current.config, now: .now)
        let laps = StopwatchLaps.addingLap(to: StopwatchLaps.laps(current.config), elapsed: elapsed)
        withAnimation(.snappy(duration: 0.25)) {
            WidgetWriter.write(current) { StopwatchLaps.store(laps, in: &$0) }
        }
    }

    static func reset(_ instance: WidgetInstance) {
        let current = WidgetWriter.current(instance.id) ?? instance
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { config in
                config.set("started", .number(0))
                config.set("elapsed", .number(0))
                StopwatchLaps.store([], in: &config)
            }
        }
    }
}
