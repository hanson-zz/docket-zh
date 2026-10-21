import AppKit
import SwiftUI

/// 秒表面板：60 格表盘中间是 mm:ss.cc，下面左边计次或重置、右边大的开始或停止，
/// 再往下是整张计次表（单圈、比上圈、累计），最快那圈标绿、最慢那圈标红，能复制。
///
/// Everything here is the tile's own config keys: `started`, the epoch the
/// current run began, `elapsed`, what earlier runs banked, and `laps`
/// (`StopwatchLaps`). The panel reads and writes them exactly as the tile
/// does, so the two can never disagree about whether the watch is running.
struct StopwatchDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint

    /// 秒表的强调色：原来的橙，颜色面板里选了颜色就换成选的。
    private var accent: Color { panelTint.accent(or: Self.orange) }
    /// 橙色实心按钮上的深字。
    private var ink: Color { panelTint.ink(or: CountdownDetail.orangeInk) }
    var instance: WidgetInstance
    var context: WidgetContext

    /// 计次表超过这么多行时在表里滚动。
    private static let visibleRows = 8
    private static let rowHeight: CGFloat = 30

    @State private var copied = false

    var body: some View {
        // The panel's `context.now` is frozen at the moment it opened, so the
        // schedule is what moves the figure. A stopped watch has nothing to
        // redraw often; the schedule is rebuilt when the config changes,
        // which is the same moment `running` flips.
        TimelineView(.periodic(from: .now, by: running ? 1.0 / 24 : 1)) { tick in
            content(now: tick.date)
        }
    }

    private var config: WidgetConfig { (WidgetWriter.current(instance.id) ?? instance).config }

    private func content(now: Date) -> some View {
        let elapsed = elapsed(at: now)
        let laps = StopwatchLaps.laps(config)

        return DetailCard {
            MeshBackdrop(color: Self.orange)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("秒表"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Spacer(minLength: 6)
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }

                dial(elapsed: elapsed, laps: laps)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    if running {
                        ClockPanelButton(title: tr("计次"), fill: nil, size: 15, height: 44) {
                            guard !context.isPreview else { return }
                            StopwatchActions.lap(instance)
                        }
                        .frame(width: 96)
                    } else {
                        ClockPanelButton(title: tr("重置"), fill: nil, size: 15, height: 44, action: reset)
                            .frame(width: 96)
                            .disabled(untouched)
                            .opacity(untouched ? 0.4 : 1)
                    }
                    ClockPanelButton(title: running ? tr("停止") : (banked > 0 ? tr("继续") : tr("开始")),
                                     fill: accent, ink: ink, size: 15, height: 44, action: toggle)
                }

                if !laps.isEmpty {
                    lapTable(laps, elapsed: elapsed)
                }
            }
        }
    }

    private static let orange = Color(hex: PaletteColor.orange.hex)

    // MARK: Dial

    private func dial(elapsed: TimeInterval, laps: [TimeInterval]) -> some View {
        ZStack {
            SweepDial(fraction: elapsed.truncatingRemainder(dividingBy: 60) / 60, running: running)
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(StopwatchLaps.main(elapsed))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(.panelPrimary)
                        // Only the seconds roll: a hundredth that animated
                        // would still be mid-transition when the next landed.
                        .rollingValue(Int(elapsed))
                    Text(StopwatchLaps.hundredths(elapsed))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent.panelReadable)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                if !laps.isEmpty {
                    Text(tr("第 \(laps.count + 1) 圈") + "  "
                         + StopwatchLaps.lapText(StopwatchLaps.currentLap(laps, elapsed: elapsed)))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 30)
        }
        .frame(width: 200, height: 200)
    }

    // MARK: Laps

    private func lapTable(_ laps: [TimeInterval], elapsed: TimeInterval) -> some View {
        let rows = StopwatchLaps.rows(laps)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("计次 \(laps.count)"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer()
                Button { copy(laps, elapsed: elapsed) } label: {
                    Label(copied ? tr("已复制") : tr("复制计次"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent.panelReadable)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
            }
            VStack(spacing: 0) {
                lapColumns(first: tr("圈"), lap: tr("单圈"), delta: tr("比上圈"), total: tr("累计"), header: true)
                    .frame(height: 28)
                if rows.count > Self.visibleRows {
                    ScrollView(.vertical) { lapRows(rows) }
                        .scrollIndicators(.automatic)
                        .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight)
                } else {
                    lapRows(rows)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
            .glassPane()
        }
    }

    private func lapRows(_ rows: [StopwatchLaps.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.number) { row in
                let mark: Color? = row.fastest ? .timerGreen : row.slowest ? .timerTomato : nil
                VStack(spacing: 0) {
                    Rectangle().fill(.panelSeparator).frame(height: 0.5)
                    lapColumns(
                        first: tr("第 \(row.number) 圈"),
                        lap: StopwatchLaps.lapText(row.seconds),
                        delta: row.delta.map(StopwatchLaps.deltaText) ?? "",
                        total: StopwatchLaps.lapText(row.total),
                        mark: mark)
                        .frame(height: Self.rowHeight - 0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(row.fastest ? tr("最快") : row.slowest ? tr("最慢") : "")
            }
        }
    }

    /// 四列：圈号靠左，单圈、比上圈、累计靠右。表头和每行共用，列宽对得齐。
    private func lapColumns(first: String, lap: String, delta: String, total: String,
                            mark: Color? = nil, header: Bool = false) -> some View {
        let isRow = !header
        return HStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(mark ?? .clear).frame(width: 6, height: 6)
                Text(first)
                    .foregroundStyle(isRow ? Color.panelSecondary : .panelTertiary)
            }
            .frame(width: 76, alignment: .leading)
            Text(lap)
                .font(isRow ? Font.system(size: 14, weight: .semibold, design: .rounded) : nil)
                .foregroundStyle(isRow ? (mark?.panelReadable ?? Color.panelPrimary) : Color.panelTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(delta)
                .foregroundStyle(Color.panelTertiary)
                .frame(width: 56, alignment: .trailing)
            Text(total)
                .foregroundStyle(isRow ? Color.panelSecondary : .panelTertiary)
                .frame(width: 66, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: State
    //
    // The tile's accessors, key for key.

    private var startedAt: TimeInterval { config.double("started") }
    private var banked: TimeInterval { config.double("elapsed") }
    private var running: Bool { startedAt > 0 }
    /// A watch that has never run has nothing to clear.
    private var untouched: Bool { !running && banked == 0 && StopwatchLaps.laps(config).isEmpty }

    private func elapsed(at now: Date) -> TimeInterval {
        guard running else { return banked }
        return banked + max(0, now.timeIntervalSince1970 - startedAt)
    }

    /// The wall-clock moment the run on screen began. A run picked up after
    /// a stop says "Resumed", because `started` is then the resume rather
    /// than the beginning.
    private var caption: String {
        guard running else { return banked > 0 ? tr("已暂停") : tr("就绪") }
        let since = Date(timeIntervalSince1970: startedAt)
            .formatted(date: .omitted, time: .standard)
        return (banked > 0 ? tr("继续于 ") : tr("开始于 ")) + since
    }

    // MARK: Actions

    /// 停下时把跑过的攒起来，再开始是接着数，和卡片同一套写法。
    private func toggle() {
        guard !context.isPreview else { return }
        StopwatchActions.toggle(instance)
    }

    /// 清零，计次一起清掉。
    private func reset() {
        guard !context.isPreview else { return }
        StopwatchActions.reset(instance)
    }

    /// 整张计次表复制成文字，按钮上显示两秒“已复制”。
    private func copy(_ laps: [TimeInterval], elapsed: TimeInterval) {
        guard !context.isPreview else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(StopwatchLaps.report(laps, elapsed: elapsed), forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// 60 格刻度，秒针扫过的一段弧和弧头一个点，放在大数字后面。
private struct SweepDial: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var fraction: Double
    var running: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side / 2
            let accent = panelTint.accent(or: Color(hex: PaletteColor.orange.hex))
            ZStack {
                ForEach(0..<60, id: \.self) { tick in
                    Capsule()
                        .fill(tick % 5 == 0 ? Color.panelQuaternary : Color.panelTrack)
                        .frame(width: tick % 5 == 0 ? 1.6 : 1, height: tick % 5 == 0 ? 9 : 5)
                        .offset(y: -radius + (tick % 5 == 0 ? 4.5 : 2.5))
                        .rotationEffect(.degrees(Double(tick) * 6))
                }
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accent.opacity(running ? 0.6 : 0.35),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(16)
                Circle()
                    .fill(accent.opacity(running ? 1 : 0.5))
                    .frame(width: 9, height: 9)
                    .offset(y: -(radius - 16))
                    .rotationEffect(.degrees(fraction * 360))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// The panel-sized action the clock tiles can only offer as a glyph the size
/// of itself.
///
/// Shared by the Stopwatch, Countdown, Alarm and Focus panels so they read as
/// one family: solid for the action the panel is about, frosted for the one
/// beside it. Drawn for a coloured card, so the frosted form is a pane of
/// white rather than an outline that the card's colour would swallow.
struct ClockPanelButton: View {
    var title: String
    /// nil draws the frosted form.
    var fill: Color?
    /// Ink on the solid form.
    var ink: Color = .white
    /// 字号和高度：主按钮大一号。
    var size: CGFloat = 13
    var height: CGFloat = 36
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(fill == nil ? Color.panelPrimary : ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background {
                    Capsule()
                        .fill(fill ?? Color.panelFillStrong)
                        .overlay {
                            Capsule().strokeBorder(Color.panelStroke.opacity(fill == nil ? 1 : 0), lineWidth: 0.5)
                        }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
