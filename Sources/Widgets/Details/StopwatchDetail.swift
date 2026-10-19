import SwiftUI

/// The stopwatch at reading size, with the two glyphs the tile shrinks to 9pt
/// named as buttons.
///
/// Everything here is the tile's own two config keys: `started`, the epoch the
/// current run began, and `elapsed`, what earlier runs banked. The panel reads
/// and writes them exactly as the tile does, so the two can never disagree
/// about whether the watch is running.
///
/// 计次记在 `laps` 里（`StopwatchLaps`），卡片放最近三圈，这里列全部，最快那圈标绿。
struct StopwatchDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint

    /// 秒表的强调色：原来的橙，颜色面板里选了颜色就换成选的。
    private var accent: Color { panelTint.accent(or: Self.orange) }
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // Tenths are the one thing a 21pt tile readout cannot carry, and the
        // panel's `context.now` is frozen at the moment it opened - so the
        // schedule is what moves the figure. A stopped watch has nothing to
        // redraw ten times a second; the schedule is rebuilt when the config
        // changes, which is the same moment `running` flips.
        TimelineView(.periodic(from: .now, by: running ? 0.1 : 1)) { tick in
            content(now: tick.date)
        }
    }

    private func content(now: Date) -> some View {
        let elapsed = elapsed(at: now)

        // Graphite lit with the stopwatch's orange, and a seconds dial sweeping
        // behind the figure: the one thing a stopwatch does is go round.
        return DetailCard {
            ZStack(alignment: .trailing) {
                MeshBackdrop(color: accent.mix(with: Color(white: 0.2), by: 0.55))
                SweepDial(fraction: elapsed.truncatingRemainder(dividingBy: 60) / 60,
                          running: running)
                    .frame(width: 230, height: 230)
                    .offset(x: 70)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(StopwatchTile.format(elapsed))
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetStyle.primary)
                            // Only the seconds roll: a tenth that animated would
                            // still be mid-transition when the next one landed.
                            .rollingValue(Int(elapsed))
                        Text(".\(Int(elapsed * 10) % 10)")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                    Text(caption)
                        .font(WidgetStyle.label(12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.top, 6)

                HStack(spacing: 10) {
                    ClockPanelButton(title: running ? tr("停止") : tr("开始"),
                                     fill: accent, ink: panelTint.ink(or: .white), action: toggle)
                    if running {
                        ClockPanelButton(title: tr("计次"), fill: nil) {
                            guard !context.isPreview else { return }
                            StopwatchActions.lap(instance)
                        }
                    } else {
                        ClockPanelButton(title: tr("重置"), fill: nil, action: reset)
                            .disabled(untouched)
                            .opacity(untouched ? 0.4 : 1)
                    }
                }

                lapList
            }
        }
    }

    private static let orange = Color(hex: PaletteColor.orange.hex)

    /// 全部计次，新的在上，最多显示 8 圈；最快那圈标绿。
    @ViewBuilder
    private var lapList: some View {
        let laps = StopwatchLaps.laps((WidgetWriter.current(instance.id) ?? instance).config)
        if !laps.isEmpty {
            VStack(spacing: 4) {
                ForEach(StopwatchLaps.recent(laps, count: 8), id: \.number) { lap in
                    HStack {
                        Text(tr("第 \(lap.number) 圈"))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(StopwatchLaps.lapText(lap.seconds))
                            .foregroundStyle(lap.fastest ? Color.timerGreen : .white)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: State
    //
    // The tile's accessors, key for key.

    private var startedAt: TimeInterval { (WidgetWriter.current(instance.id) ?? instance).config.double("started") }
    private var banked: TimeInterval { (WidgetWriter.current(instance.id) ?? instance).config.double("elapsed") }
    private var running: Bool { startedAt > 0 }
    /// A watch that has never run has nothing to clear.
    private var untouched: Bool { !running && banked == 0 }

    private func elapsed(at now: Date) -> TimeInterval {
        guard running else { return banked }
        return banked + max(0, now.timeIntervalSince1970 - startedAt)
    }

    /// The wall-clock moment the run on screen began - the one fact the config
    /// holds that neither the tile nor the readout can say. A run picked up
    /// after a stop says "Resumed", because `started` is then the resume
    /// rather than the beginning.
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
}

/// A ring of sixty ticks with the current second lit and a trail behind it,
/// set large and faint behind the figure.
private struct SweepDial: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var fraction: Double
    var running: Bool

    var body: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { tick in
                Capsule()
                    .fill(.white.opacity(tick % 5 == 0 ? 0.22 : 0.1))
                    .frame(width: tick % 5 == 0 ? 2 : 1, height: tick % 5 == 0 ? 10 : 6)
                    .offset(y: -105)
                    .rotationEffect(.degrees(Double(tick) * 6))
            }
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(panelTint.accent(or: Color(hex: PaletteColor.orange.hex)).opacity(running ? 0.55 : 0.3),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(18)
        }
        .accessibilityHidden(true)
    }
}

/// The panel-sized action the clock tiles can only offer as a glyph the size
/// of itself.
///
/// Shared by the Stopwatch, Countdown and Alarm panels so the three read as
/// one family, and weighted like the Focus Timer's pair: solid for the action
/// the panel is about, frosted for the one that throws work away. Drawn for a
/// coloured card, so the frosted form is a pane of white rather than an
/// outline that the card's colour would swallow.
struct ClockPanelButton: View {
    var title: String
    /// nil draws the frosted form.
    var fill: Color?
    /// Ink on the solid form. White on a saturated fill, the card's own colour
    /// on a white one.
    var ink: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WidgetStyle.label(13))
                .foregroundStyle(fill == nil ? Color.white : ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    Capsule()
                        .fill(fill ?? Color.white.opacity(0.14))
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(fill == nil ? 0.18 : 0), lineWidth: 0.5)
                        }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
