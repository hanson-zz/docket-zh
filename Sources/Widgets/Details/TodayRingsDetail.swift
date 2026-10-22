import SwiftUI

/// 小熊猫的竹篮选了「三环」样式时的面板：今日三环大图（中间小熊猫，全满时欢呼），
/// 还差什么或全满的竹叶庆祝行，三项数值与目标，近 7 天三环小格（全满的日子点亮成
/// 那天的竹叶，写连续几天），设置目标。液态玻璃，跟随浅色 / 深色（竹篮样式的面板
/// 是插画底的保持暗色例外，这里不是）。数据和竹篮同一份，见 `TodayRings`。
struct TodayRingsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext
    /// 去看本月竹篮和徽章（竹篮样式的面板）。
    var onBasket: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var center: PerfectDayCenter { .shared }
    private var calendar: Calendar { PerfectDay.calendar }

    private var items: [PerfectDayProgress] {
        context.isPreview ? TodayRings.sample : center.progress(now: context.now)
    }

    private var records: [PerfectDayRecord] {
        context.isPreview ? PerfectDay.sample(today: context.now) : center.records(now: context.now)
    }

    var body: some View {
        let items = items
        let all = records
        let week = TodayRings.week(all, today: context.now)
        return DetailCard {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(items)
                        hero(items)
                        line(items)
                        rows(items)
                        weekSection(week, records: all)
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: 560)
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
        }
        .onAppear { if !context.isPreview { center.refresh(now: context.now) } }
    }

    // MARK: Header

    private func header(_ items: [PerfectDayProgress]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("今日三环"))
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(dateLine)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(TodayRings.status(items))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(.panelFill))
                .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.5))
        }
    }

    /// "10月22日 周四"。
    private var dateLine: String {
        let c = calendar.dateComponents([.month, .day, .weekday], from: context.now)
        let names = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")]
        let weekday = names[((c.weekday ?? 1) - 1 + 7) % 7]
        return tr("\(c.month ?? 0)月\(c.day ?? 0)日 \(weekday)")
    }

    // MARK: Rings

    private func hero(_ items: [PerfectDayProgress]) -> some View {
        let full = TodayRings.isFull(items)
        let diameter: CGFloat = 220
        return ZStack {
            TodayRingsGraphic(items: items, diameter: diameter, line: 18, gap: 4)
            panda(cheer: full)
                .frame(height: full ? 92 : 74)
                .offset(y: full ? -6 : 0)
            Text(verbatim: "\(TodayRings.percent(items))%")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .offset(y: diameter * 0.4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: diameter)
        .animation(.smooth(duration: 0.4), value: full)
    }

    @ViewBuilder
    private func panda(cheer: Bool) -> some View {
        if let image = PetArt.image(.redPanda, cheer ? .cheer : .idle) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }

    /// 还差什么；全满时是竹叶庆祝行，竹叶按竹篮的规则。
    @ViewBuilder
    private func line(_ items: [PerfectDayProgress]) -> some View {
        if let celebration = TodayRings.celebration(items) {
            let tier = PerfectDay.record(items, key: "").tier
            HStack(spacing: 8) {
                LeafGlyph(tier: tier, size: 22)
                Text(celebration)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(scheme == .dark ? Color.panelPrimary : Color(hex: "#5C3A00"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color(hex: "#FFBA3C").opacity(scheme == .dark ? 0.24 : 0.28)))
            .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.5))
            .frame(maxWidth: .infinity)
        } else {
            Text(TodayRings.remainingLine(items))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Rows

    private func rows(_ items: [PerfectDayProgress]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(TodayRings.order.enumerated()), id: \.element) { index, item in
                if let p = items.first(where: { $0.item == item }) {
                    if index > 0 {
                        Rectangle().fill(.panelSeparator).frame(height: 1).padding(.horizontal, 12)
                    }
                    row(p)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.5))
    }

    private func row(_ p: PerfectDayProgress) -> some View {
        let accent = Color(hex: p.item.hex)
        let figure = TodayRings.figure(p)
        let takes = p.mark.takesPart
        let over = takes && p.ratio >= 1
        return HStack(spacing: 10) {
            TodayRingBadge(item: p.item, size: 26, dimmed: !takes)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(TodayRings.note(p))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if takes {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(figure.value)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(accent.panelReadable)
                        Text(figure.unit)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                    }
                    Text(verbatim: "\(TodayRings.percent(p))%")
                        .font(.system(size: 13, weight: over ? .semibold : .regular))
                        .foregroundStyle(over ? accent.panelReadable : Color.panelSecondary)
                }
                .monospacedDigit()
                .lineLimit(1)
            } else if let fix = PerfectDay.fix(for: p) {
                Button { open(fix, for: p.item) } label: {
                    Text(fix.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.panelReadable)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.18)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: Week

    private func weekSection(_ week: [TodayRingsDay], records: [PerfectDayRecord]) -> some View {
        let streak = TodayRings.fullStreak(records, today: context.now)
        let readings = weekReadings(week)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(tr("近 7 天"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 4)
                if streak > 0 {
                    LeafGlyph(tier: .gold, size: 16)
                    Text(tr("连续 \(streak) 天"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 0) {
                ForEach(week) { day in
                    VStack(spacing: 6) {
                        cell(day, readings: readings[day.key])
                            .frame(width: 34, height: 34)
                        Text(day.label)
                            .font(.system(size: 13, weight: day.isToday ? .semibold : .regular))
                            .foregroundStyle(day.isToday ? Color.panelPrimary : Color.panelSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(day.isFull ? tr("\(day.label)，全满") : day.label)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func cell(_ day: TodayRingsDay, readings: [PerfectDayProgress]?) -> some View {
        if let leaf = day.leaf {
            // 全满：暖色小底上一片那天的竹叶。
            ZStack {
                Circle().fill(Color(hex: "#FFBE50").opacity(scheme == .dark ? 0.28 : 0.26))
                LeafGlyph(tier: leaf, size: 24)
            }
        } else {
            TodayRingsGraphic(items: readings ?? [], diameter: 34, line: 3.5, gap: 1, icons: false)
                .opacity(day.record == nil && !day.isToday ? 0.5 : 1)
        }
    }

    /// 近 7 天每天的三项进度。预览里按示例记录画（达标满圈、没达标半圈）。
    private func weekReadings(_ week: [TodayRingsDay]) -> [String: [PerfectDayProgress]] {
        guard !context.isPreview else {
            var result: [String: [PerfectDayProgress]] = [:]
            for day in week {
                guard let record = day.record else { continue }
                result[day.key] = PerfectDayItem.allCases.map { item in
                    let mark = record.mark(item)
                    return PerfectDayProgress(item: item, mark: mark, fraction: mark == .met ? 1 : 0.5, detail: "")
                }
            }
            return result
        }
        return center.progress(days: week.map(\.date), now: context.now)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Menu {
                Button(tr("喝水目标")) { openSource(.water) }
                Button(tr("专注目标")) { openSource(.timer) }
                Button(tr("习惯打卡")) { openSource(.habit) }
            } label: {
                Text(tr("设置目标"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelOnPrimary)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(Capsule().fill(.panelPrimary))
                    .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(context.isPreview)
            Text(tr("目标和喝水、专注计时、习惯打卡同步"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .frame(maxWidth: .infinity)
            Button(action: onBasket) {
                Text(tr("本月竹篮和徽章"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Opening

    /// 目标在各自的小组件里设：有就打开它的面板，没有就去添加小组件。
    private func openSource(_ kind: WidgetKind) {
        guard !context.isPreview else { return }
        if let widget = center.widgets().first(where: { $0.kind == kind }) {
            WidgetPanelOpener.shared.open(widget.id)
        } else {
            LibraryWindow.shared.openFromEmptyState()
        }
    }

    private func open(_ fix: PerfectDayFix, for item: PerfectDayItem) {
        switch item {
        case .water: openSource(.water)
        case .focus: openSource(.timer)
        case .habit: openSource(.habit)
        }
    }
}
