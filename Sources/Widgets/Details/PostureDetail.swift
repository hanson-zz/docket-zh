import Foundation
import SwiftUI

/// The stand-up reminder in wall-clock terms, with today's count and a
/// button big enough to press without aiming.
///
/// The widget keeps one day's count and the time of the last break, nothing
/// more, so the panel draws no history and no chart.
struct PostureDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // A schedule rather than `context.now`, which is frozen when the
        // panel opens; see WaterDetail.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private var schedule: PostureSchedule { PostureSchedule(config: instance.config) }

    private var lastBreak: Date? {
        let raw = instance.config.double("lastBreak")
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    private func content(now: Date) -> some View {
        let active = context.isPreview || schedule.isActive(now)
        let left = context.isPreview ? 1260 : schedule.remaining(lastBreak: lastBreak, now: now)
        let progress = context.isPreview ? 0.3 : schedule.progress(lastBreak: lastBreak, now: now)
        return DetailCard {
            ZStack(alignment: .bottom) {
                MeshBackdrop(color: accent)
                // The bar rises while you sit, the water panel's level
                // turned into a plain level.
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(MeshBackdrop.muted(accent, by: 0.7).opacity(0.55))
                            .frame(height: geo.size.height * (active ? progress : 0))
                    }
                }
                .animation(.smooth(duration: 0.8), value: progress)
                .accessibilityHidden(true)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(headlineLabel(active: active, left: left))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(headline(active: active, left: left, now: now))
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(caption(active: active, left: left, now: now))
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    StatChip(label: tr("今日起身"), value: tr("\(breaks(now: now)) 次"))
                    StatChip(label: tr("提醒时段"), value: hours)
                    StatChip(label: tr("间隔"), value: spelled(schedule.interval))
                }

                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.35)) { PostureLog.logBreak(instance) }
                } label: {
                    Label("我起身活动了", systemImage: "figure.walk")
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(.white.opacity(0.24)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("记录一次起身")

                if !instance.config.bool("notify", default: true) {
                    Text("通知已关闭，可在小组件设置中打开。")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func headlineLabel(active: Bool, left: TimeInterval) -> String {
        guard active else { return tr("不在提醒时段") }
        return left > 0 ? tr("下次起身时间") : tr("该起身了")
    }

    private func headline(active: Bool, left: TimeInterval, now: Date) -> String {
        guard active else { return PostureSchedule.clock(schedule.start) }
        return left > 0 ? clock(now.addingTimeInterval(left)) : tr("动一动")
    }

    private func caption(active: Bool, left: TimeInterval, now: Date) -> String {
        guard active else { return tr("提醒从 \(PostureSchedule.clock(schedule.start)) 开始") }
        guard left <= 0 else { return tr("还有 \(docketClockString(left))") }
        guard !context.isPreview else { return tr("站起来走动、伸展一下") }
        let over = now.timeIntervalSince(schedule.due(lastBreak: lastBreak, now: now))
        return over >= 60 ? tr("已超时 \(spelled(over))") : tr("站起来走动、伸展一下")
    }

    private func breaks(now: Date) -> Int {
        if context.isPreview { return 3 }
        return PostureTally.today(storedDay: instance.config.string("breakDay"),
                                  count: instance.config.int("breakCount"), now: now)
    }

    private var hours: String {
        "\(PostureSchedule.clock(schedule.start))-\(PostureSchedule.clock(schedule.end))"
    }

    private var accent: Color {
        WidgetCatalog.accentHex(.posture).map { Color(hex: $0) } ?? WidgetStyle.primary
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func spelled(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
