import Foundation
import SwiftUI

/// 时间进度的面板，跟着卡片样式走：圆环、百分比、液态、进度条、四格各一套。
///
/// 每套顶部是放大的同款主视觉，下面是同一组模块：四个周期对比、本周七天、
/// 今年 365 天点阵（进度条那套的主视觉本身就是整年，所以省掉）、接下来的
/// 四个节点和一句话。模块一样，画法跟样式：圆环用小环，液态用试管和小杯，
/// 四格用方块。
///
/// 样式按 `ProLicenseGate.timeProgressLayout` 读，和卡片一致：液态、四格没解锁
/// 时卡片画圆环，面板也开圆环。日、周、月、年的分段控件写卡片自己的 period 键，
/// 和点卡片上的名字是同一个写法；四格没有主周期，不放分段控件。
///
/// 一周固定从周一开始（`TimeProgress.calendar`），卡片也一样。法定假日和调休
/// 来自 `HolidayService`，纪念日读码头上纪念日卡片的配置，没有就不标；不读日历。
struct TimeProgressDetail: View {
    @Environment(\.panelTint) private var panelTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 和卡片一样读 @AppStorage：购买或试用到期时面板跟着卡片马上换样式。
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporterUnlocked = false
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // 一分钟一跳：「还剩 13 小时 36 分」要准到分钟。不能用 `context.now`，
        // 面板打开时只赋值一次，开着的时候会一直停在那一刻。
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let model = TimeProgressPanelModel(now: tick.date, period: period, layout: layout,
                                               known: known, anniversaries: anniversaries)
            DetailCard {
                MeshBackdrop(color: colors.accent)
            } content: {
                content(model)
            }
        }
        .environment(\.widgetTint, tintStyle)
        .environment(\.timeProgressColors, colors)
        .onAppear { if !context.isPreview { HolidayService.shared.refresh() } }
    }

    @ViewBuilder
    private func content(_ model: TimeProgressPanelModel) -> some View {
        let parts = TimeProgressParts(model: model, pick: context.isPreview ? nil : pick)
        VStack(alignment: .leading, spacing: 0) {
            switch layout {
            case TimeProgress.quadLayout:
                quadPanel(model, parts)
            case "percentage":
                percentagePanel(model, parts)
            case LiquidMotion.layout:
                liquidPanel(model, parts)
            case "ring":
                ringPanel(model, parts)
            default:
                barsPanel(model, parts)
            }
        }
    }

    // MARK: 五套

    private func ringPanel(_ model: TimeProgressPanelModel, _ parts: TimeProgressParts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            parts.segmented
            TimeProgressRingHero(model: model).padding(.top, 18)
            parts.section(tr("四个周期")) { parts.ringPeriods }.padding(.top, 22)
            parts.section(tr("本周"), trailing: parts.weekendText) { parts.ringWeek }.padding(.top, 18)
            parts.yearGrid(round: true).padding(.top, 18)
            parts.milestones(corner: 14, progress: false).padding(.top, 18)
            parts.note.padding(.top, 16)
        }
    }

    private func percentagePanel(_ model: TimeProgressPanelModel, _ parts: TimeProgressParts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            parts.segmented
            TimeProgressPercentageHero(model: model).padding(.top, 18)
            parts.section(tr("四个周期")) { parts.tablePeriods }.padding(.top, 22)
            parts.section(tr("本周"), trailing: parts.weekendText) { parts.segmentWeek }.padding(.top, 18)
            parts.yearGrid(round: false).padding(.top, 18)
            parts.milestones(corner: 10, progress: true).padding(.top, 18)
            parts.note.padding(.top, 16)
        }
    }

    private func liquidPanel(_ model: TimeProgressPanelModel, _ parts: TimeProgressParts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            parts.segmented
            TimeProgressLiquidHero(model: model,
                                   visible: !context.isPreview,
                                   still: !TimeProgress.liquidAnimates(instance.config, reduceMotion: reduceMotion))
                .padding(.top, 16)
            parts.section(tr("四个周期")) { parts.tubePeriods }.padding(.top, 20)
            parts.section(tr("本周"), trailing: parts.weekendText) { parts.cupWeek }.padding(.top, 18)
            parts.yearGrid(round: true).padding(.top, 18)
            parts.milestones(corner: 10, progress: false).padding(.top, 18)
            parts.note.padding(.top, 16)
        }
    }

    private func barsPanel(_ model: TimeProgressPanelModel, _ parts: TimeProgressParts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            parts.segmented
            TimeProgressBarsHero(model: model).padding(.top, 16)
            parts.section(tr("四个周期"), trailing: tr("每段一个单位")) { parts.unitPeriods }.padding(.top, 20)
            parts.milestones(corner: 10, progress: false).padding(.top, 18)
            parts.note.padding(.top, 16)
        }
    }

    private func quadPanel(_ model: TimeProgressPanelModel, _ parts: TimeProgressParts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TimeProgressQuadHero(model: model)
            parts.section(tr("本周"), trailing: parts.weekendText) { parts.blockWeek }.padding(.top, 18)
            parts.yearGrid(round: false).padding(.top, 18)
            parts.milestones(corner: 10, progress: false).padding(.top, 18)
            parts.note.padding(.top, 16)
        }
    }

    // MARK: 数据

    /// 实际画的样式：和卡片同一个判断，液态和四格没解锁时退回圆环（预览照常画）。
    private var layout: String {
        ProLicenseGate.timeProgressLayout(config: instance.config,
                                          unlocked: licenseUnlocked || supporterUnlocked || context.isPreview)
    }

    private var period: TimeProgress.Period { TimeProgress.period(instance.config) }

    /// 预览里用内置的一年，不去联网。
    private var known: [Int: [HolidayDay]] {
        context.isPreview ? HolidaySchedule.bundled : HolidayService.shared.known
    }

    /// 码头上所有纪念日卡片里的日子；没有纪念日卡片就是空的，点阵上不标。
    private var anniversaries: [AnniversaryEvent] {
        guard !context.isPreview else { return [] }
        return TimedAlertDriver.shared.widgets()
            .filter { $0.kind == .anniversary }
            .flatMap { Anniversary.events($0.config) }
    }

    /// 卡片的颜色主题（时间进度默认紫），圆环、进度条和水从环境里读它。
    private var tintStyle: WidgetTintStyle {
        WidgetTintStyle(kind: instance.kind, config: instance.config)
    }

    private var colors: TimeProgressColors {
        TimeProgressColors(accent: tintStyle.main(dark: true),
                           light: tintStyle.light(dark: true),
                           contrast: tintStyle.contrast(dark: true))
    }

    /// 写卡片上显示的周期。带动画，和卡片自己切换时一样，数字和进度是滑过去的。
    private func pick(_ span: TimeProgress.Period) {
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(instance) { config in
                config.set(TimeProgress.periodKey, .string(span.rawValue))
            }
        }
    }
}

// MARK: - 模型和颜色

/// 一分钟一份：面板这一刻要用的数，全部来自 Core 的 `TimeProgress`。
struct TimeProgressPanelModel {
    let now: Date
    let period: TimeProgress.Period
    let layout: String
    let known: [Int: [HolidayDay]]
    let days: [TimeProgress.YearDay]
    let milestones: [TimeProgress.Milestone]

    init(now: Date, period: TimeProgress.Period, layout: String,
         known: [Int: [HolidayDay]], anniversaries: [AnniversaryEvent]) {
        self.now = now
        self.period = period
        self.layout = layout
        self.known = known
        days = TimeProgress.yearDays(now: now, known: known, anniversaries: anniversaries)
        milestones = TimeProgress.milestones(now: now, known: known)
    }

    func fraction(_ span: TimeProgress.Period) -> Double { TimeProgress.fraction(span, now: now) }
    func percent(_ span: TimeProgress.Period) -> Int { TimeProgress.percent(fraction(span)) }
    var weekDays: [TimeProgress.WeekDay] { TimeProgress.weekDays(now: now) }
    var hasAnniversaries: Bool { days.contains { $0.mark == .anniversary } }
    var note: String {
        layout == TimeProgress.quadLayout ? TimeProgress.quadNote(now: now)
            : TimeProgress.note(period, now: now, known: known)
    }
}

/// 面板上的几种颜色：主题色（进度本身和当前项）、浅一点的写字用、对比色标
/// 法定假日，琥珀色只标纪念日。紫色只用在进度和当前项，不铺大面积。
struct TimeProgressColors: Equatable, Sendable {
    var accent: Color
    var light: Color
    var contrast: Color
    var amber = Color(hex: "#F5A524")

    static let fallback = TimeProgressColors(accent: Color(hex: "#8E5CF0"), light: Color(hex: "#B9A6FF"),
                                             contrast: Color(hex: "#3DDBB0"))

    /// 年度点阵和进度条里一天的颜色和不透明度。
    func day(_ day: TimeProgress.YearDay) -> (Color, Double) {
        switch day.mark {
        case .past: (accent, 0.82)
        case .future: (.white, 0.12)
        case .holiday: (contrast, day.isPast ? 1 : 0.6)
        case .makeupWorkday: (contrast, 0.4)
        case .anniversary: (amber, day.isPast ? 0.75 : 1)
        case .today: (.white, 1)
        }
    }
}

private struct TimeProgressColorsKey: EnvironmentKey {
    static let defaultValue = TimeProgressColors.fallback
}

extension EnvironmentValues {
    var timeProgressColors: TimeProgressColors {
        get { self[TimeProgressColorsKey.self] }
        set { self[TimeProgressColorsKey.self] = newValue }
    }
}

// MARK: - 字

enum TimeProgressType {
    /// 大数字：圆体粗字，等宽数字。
    static func figure(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 面板里最小的字，13pt。
    static let small = Font.system(size: 13, weight: .regular)
    static let smallMedium = Font.system(size: 13, weight: .medium)
    static let smallBold = Font.system(size: 13, weight: .bold)
}

/// 粗数字加小一号的百分号，百分号可以染色。
struct TimeProgressPercent: View {
    var value: Int
    var size: CGFloat
    var signSize: CGFloat
    var signColor: Color = .white.opacity(0.7)
    var weight: Font.Weight = .bold

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(verbatim: "\(value)")
                .font(TimeProgressType.figure(size, weight: weight))
                .foregroundStyle(.white)
                .rollingValue(value)
            Text(verbatim: "%")
                .font(TimeProgressType.figure(signSize, weight: .semibold))
                .foregroundStyle(signColor)
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}
