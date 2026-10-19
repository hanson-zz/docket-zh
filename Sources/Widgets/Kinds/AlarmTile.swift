import SwiftUI

/// 闹钟：管“今天某个时刻”要做什么。一张卡片放多个闹钟。
///
/// - 平时：左边铃铛（点它开关下一个闹钟），下一个最醒目，“14:30 给小王回电话”，
///   下面橙色的“还有 2 小时”，再下面一行小字是后面的闹钟。
/// - 正在响：卡片变橙，写着在响的那个，“稍后 9 分钟”和“关掉”直接在卡片上按，
///   不用跳去别的 App。响铃两分钟内每 4 秒响一声，十分钟没人管就自己停。提示音
///   和到点弹出的卡片由 `TimedAlertDriver` 管，扩展栏隐藏、卡片不在当前布局也照样响。
///
/// 卡片其余地方的点按留给码头（打开面板，面板里加、删、开关）。闹钟、已处理的
/// 响铃和稍后再响都在小组件自己的配置里（`AlarmBook`），旧的单个闹钟自动读成一个。
struct AlarmTile: View {
    /// 颜色面板里选的主题色（`WidgetTintStyle`），选过颜色时原来写死的强调色跟着换。
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme

    /// 原来的强调色，选过颜色就换成选的。
    private var accent: Color { theme.chosen(or: Color.timerOrange, dark: scheme == .dark) }
    var instance: WidgetInstance
    var context: WidgetContext

    private var config: WidgetConfig {
        context.isPreview ? Self.previewConfig : instance.config
    }

    /// 小组件库里给一张像样的：三个闹钟，第一个还有 2 小时。
    private static var previewConfig: WidgetConfig {
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let base = ((now.hour ?? 12) * 60 + (now.minute ?? 0) + 120) % (24 * 60)
        var config = WidgetConfig()
        AlarmBook.store([
            AlarmItem(id: "a1", minutes: base, name: tr("给小王回电话")),
            AlarmItem(id: "a2", minutes: (base + 210) % 1440, name: tr("取快递")),
            AlarmItem(id: "a3", minutes: (base + 420) % 1440, name: tr("吃药")),
        ], in: &config)
        return config
    }

    var body: some View {
        let ringing = context.isPreview ? nil : AlarmBook.ringing(config, now: context.now)
        Group {
            if let ringing {
                ringingCard(ringing.item)
            } else {
                WidgetSurface {
                    if AlarmBook.items(config).isEmpty {
                        PandaEmptyTile(empty: .alarm, title: tr("添加闹钟"), instance: instance, context: context)
                    } else if context.position.isVertical { column } else { row }
                }
            }
        }
    }

    // MARK: 平时（220 × 58）

    private var row: some View {
        let headline = AlarmBook.headline(config, now: context.now)
        let enabled = headline?.enabled ?? false
        return HStack(spacing: 10) {
            switchBadge(headline)
            if let headline {
                let at = AlarmBook.nextRing(headline, config: config, now: context.now)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(AlarmBook.clockText(at))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetStyle.primary)
                        Text(headline.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Text(enabled ? AlarmBook.untilText(at, now: context.now) : tr("已关闭"))
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(enabled ? accent : WidgetStyle.secondary)
                        .lineLimit(1)
                    if let later = AlarmBook.laterLine(config, now: context.now) {
                        Text(later)
                            .font(.system(size: 9.5))
                            .foregroundStyle(WidgetStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .opacity(enabled ? 1 : 0.55)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("还没有闹钟"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                    Text(tr("点开卡片添加"))
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 铃铛方底：开着是橙色铃铛，关着是灰的划掉的铃铛，点它开关卡片上那一个。
    @ViewBuilder
    private func switchBadge(_ headline: AlarmItem?) -> some View {
        let enabled = headline?.enabled ?? false
        let badge = TileBadge {
            Image(systemName: enabled ? "alarm.fill" : "alarm.slash.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(enabled ? accent : WidgetStyle.secondary)
        }
        if context.isPreview || headline == nil {
            badge
        } else if let headline {
            Button { toggle(headline) } label: { badge }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: WidgetStyle.innerCorner, style: .continuous))
                .accessibilityLabel(tr("\(enabled ? tr("关闭") : tr("开启")) \(headline.time) 的闹钟"))
        }
    }

    // MARK: 竖排（76 × 76）

    private var column: some View {
        let headline = AlarmBook.headline(config, now: context.now)
        return VStack(spacing: 2) {
            Image(systemName: headline?.enabled == true ? "alarm.fill" : "alarm.slash.fill")
                .font(.system(size: 13))
                .foregroundStyle(headline?.enabled == true ? accent : WidgetStyle.secondary)
            if let headline {
                Text(headline.time)
                    .font(WidgetStyle.value(18))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(headline.title)
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(tr("还没有闹钟"))
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        }
        .opacity(headline?.enabled == false ? 0.55 : 1)
    }

    // MARK: 正在响

    private func ringingCard(_ item: AlarmItem) -> some View {
        WidgetSurface(fill: accent.opacity(0.3)) {
            if context.position.isVertical {
                VStack(spacing: 3) {
                    Text(item.time)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                    TimerPill(title: tr("稍后"), size: 9.5, height: 16, minWidth: 48,
                              action: { snooze(item) })
                    TimerPill(title: tr("关掉"), size: 9.5, height: 16, tint: accent, minWidth: 48,
                              action: { dismiss(item) })
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.time)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetStyle.primary)
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 4)
                        Text(tr("正在响"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    HStack(spacing: 6) {
                        TimerPill(title: tr("稍后 \(AlarmBook.snoozeMinutes) 分钟"), size: 10.5, height: 20,
                                  minWidth: 92, action: { snooze(item) })
                        TimerPill(title: tr("关掉"), size: 10.5, height: 20, tint: accent, minWidth: 92,
                                  action: { dismiss(item) })
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("\(item.time) \(item.title) 正在响"))
    }

    // MARK: 动作

    private func toggle(_ item: AlarmItem) {
        guard !context.isPreview else { return }
        write { AlarmBook.setEnabled(item.id, !item.enabled, in: &$0) }
    }

    private func snooze(_ item: AlarmItem) {
        write { AlarmBook.snooze(item.id, in: &$0, now: .now) }
    }

    private func dismiss(_ item: AlarmItem) {
        write { AlarmBook.dismiss(item.id, in: &$0, now: .now) }
    }

    /// 旧的单个闹钟第一次改动时顺手写成列表。
    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        let current = WidgetWriter.current(instance.id) ?? instance
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(current) { config in
                if AlarmBook.isLegacy(config) { AlarmBook.store(AlarmBook.items(config), in: &config) }
                change(&config)
            }
        }
    }
}
