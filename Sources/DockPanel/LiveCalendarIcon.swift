import SwiftUI
import AppKit

// MARK: - 日历：真实日程驱动的液位，换场时整圈旋转

/// 程序坞里的日历图标整张换成码头画的日历：红色页眉写星期，中间是几号，下部一层液面随下一场
/// 日程的剩余时间下降，底部小胶囊写倒计时。数据来自 `LiveCalendarMonitor`（今天的定时日程，
/// 不含全天和已拒绝的），没有日历权限、今天没有要倒数的日程时画回系统原来的图标（`fallback`）。
///
/// 不是动画循环：只在倒计时的分钟数变、阶段变、液面降 1 像素时重画（`LiveCalendar.nextTick`，
/// 最长 60 秒一次，低电量模式不追像素）。换到下一场时先轻轻放大一下，再整枚图标在屏幕平面上
/// 顺时针转一整圈（0.9 秒，转到 180° 倒立时换成新场次），同一场绝不重复转；减弱动态效果时直接换。
/// 页眉的星期和中间的日期是图标图案，跟图标一起缩放；倒计时胶囊的字不小于 13pt，放不下就换短的写法。
struct LiveCalendarIcon<Fallback: View>: View {
    var side: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    @AppStorage(LiveCalendar.leadKey) private var leadStored = LiveCalendar.defaultLeadMinutes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    @State private var now = Date()
    @State private var flip = LiveCalendarFlip()
    /// 正在画的那一场：转圈转到一半才换成新的。nil 时跟着 target 走。
    @State private var shownID: String?
    @State private var angle: Double = 0
    @State private var emphasized = false
    /// 每要转一圈加 1，驱动下面那个 `.task(id:)`；转圈跟着视图走，视图没了自动取消。
    @State private var turnRequest = 0
    @State private var turning = false

    private var monitor: LiveCalendarMonitor { .shared }
    private var lead: TimeInterval { Double(LiveCalendar.leadMinutes(stored: leadStored)) * 60 }

    var body: some View {
        let target = LiveCalendar.target(monitor.events, now: now, calendar: .current)
        let shown = shownID.flatMap { id in monitor.events.first { $0.id == id } } ?? target
        Group {
            if let shown, target != nil {
                face(shown)
                    .scaleEffect(emphasized ? 1.07 : 1)
                    .rotationEffect(.degrees(angle))
            } else {
                fallback()
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
        .onChange(of: monitor.events) { now = .now }
        .onChange(of: target?.id, initial: true) { _, id in switchTo(id) }
        .task(id: "\(target?.id ?? "-")|\(leadStored)") { await tick() }
        .task(id: turnRequest) { await runTurn() }
    }

    // MARK: 节奏

    /// 按 `LiveCalendar.nextTick` 睡到下一次读数会变的时刻，再更新 `now`。
    private func tick() async {
        while !Task.isCancelled {
            now = .now
            let target = LiveCalendar.target(monitor.events, now: now, calendar: .current)
            let g = LiveIconGeometry.content(side: Double(side))
            let pixels = g.length * (1 - LiveCalendarFace.headerFraction) * Double(max(1, displayScale))
            let delay = LiveCalendar.nextTick(start: target?.start, now: now, lead: lead, pixelHeight: pixels,
                                              lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// 下一场变了：第一次出现、变成没日程时直接换；真换场时强调一下再整圈旋转。
    private func switchTo(_ id: String?) {
        // 换场前图标上画的那一场：转之前钉住它，转到一半再换。
        let previous = flip.shownID
        let shouldTurn = flip.update(to: id, at: .now)
        guard shouldTurn, !reduceMotion else {
            if !turning { shownID = nil }
            return
        }
        // 上一圈没转完（极少见）：先无动画归位，再从 0 开始转。
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            angle = 0
            emphasized = false
        }
        shownID = previous
        turning = true
        turnRequest += 1
    }

    /// 强调一下，再顺时针整圈旋转；转到 180° 时换成新场次，转完无动画归零。
    private func runTurn() async {
        guard turnRequest > 0, turning else { return }
        let request = turnRequest
        // 不管转完还是半路被取消，都回到「跟着下一场走、角度 0」；被新的一圈接替时不动它的状态。
        defer {
            if turnRequest == request {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    angle = 0
                    emphasized = false
                }
                shownID = nil
                turning = false
            }
        }
        do {
            withAnimation(.easeOut(duration: LiveCalendar.emphasisDuration)) { emphasized = true }
            try? await Task.sleep(for: .seconds(LiveCalendar.emphasisDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) { emphasized = false }
            withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: LiveCalendar.turnDuration)) { angle = 360 }
            try? await Task.sleep(for: .seconds(LiveCalendar.turnDuration / 2))
            guard !Task.isCancelled else { return }
            // 180°，倒立：换成新场次的液位和倒计时。
            shownID = nil
            now = .now
            try? await Task.sleep(for: .seconds(LiveCalendar.turnDuration / 2 + 0.05))
            guard !Task.isCancelled else { return }
            var done = Transaction()
            done.disablesAnimations = true
            withTransaction(done) { angle = 0 }
        }
    }

    // MARK: 画面

    private func face(_ event: LiveCalendarEvent) -> some View {
        let g = LiveIconGeometry.content(side: Double(side))
        let length = CGFloat(g.length)
        let corner = CGFloat(g.corner)
        let header = length * CGFloat(LiveCalendarFace.headerFraction)
        let pillFont = max(13, length * 0.3)
        let pillHeight = pillFont + 4
        let margin = max(1.5, length * 0.05)
        let dateArea = max(0, length - header - pillHeight - margin)
        let dateFont = max(1, min(length * 0.42, dateArea * 1.35))
        let phase = LiveCalendar.phase(start: event.start, now: now, lead: lead)
        let level = LiveCalendar.level(start: event.start, now: now, lead: lead)
        let label = LiveCalendar.label(start: event.start, now: now, lead: lead, calendar: .current)
        let palette = LiveCalendarPalette(dark: scheme == .dark, warm: phase.isWarm)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        return ZStack(alignment: .top) {
            shape.fill(LinearGradient(colors: palette.body, startPoint: .top, endPoint: .bottom))
            liquid(level: level, header: header, palette: palette)
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(hex: "#FF5F52"), Color(hex: "#DE322A")],
                                   startPoint: .top, endPoint: .bottom)
                    Text(verbatim: LiveCalendar.weekday(now, calendar: .current, english: L10n.isEnglish))
                        .font(.system(size: header * 0.62, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(height: header)
                Text(verbatim: LiveCalendar.dayNumber(now, calendar: .current))
                    .font(.system(size: dateFont, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.date)
                    .lineLimit(1)
                    .frame(height: dateArea)
                    .frame(maxWidth: .infinity)
                pill(label, palette: palette, font: pillFont, height: pillHeight, maxWidth: length - 3)
                    .frame(height: pillHeight)
                Spacer(minLength: 0)
            }
            // 玻璃的一抹高光，浅色深色都只是很淡的一层。
            shape.fill(LinearGradient(colors: [.white.opacity(palette.sheen), .white.opacity(0)],
                                      startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        .frame(width: length, height: length)
        .clipShape(shape)
        .overlay { shape.strokeBorder(palette.rim, lineWidth: 0.5) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: length * 0.03, y: length * 0.015)
        .frame(width: side, height: side)
    }

    /// 液面：从底往上到 `level` 的高度（满时到页眉下沿），水面一道很缓的弧和一条细亮线，不发光。
    private func liquid(level: Double, header: CGFloat, palette: LiveCalendarPalette) -> some View {
        Canvas { context, size in
            guard level > 0 else { return }
            let rect = CGRect(origin: .zero, size: size)
            let room = size.height - header
            let surface = size.height - room * CGFloat(min(1, level))
            let amplitude = size.height * 0.012
            let body = LiveOpenAIDrawing.wave(rect, surface: surface, amplitude: amplitude, phase: 0.8,
                                              cycles: 1.1, closed: true)
            context.fill(body, with: .linearGradient(Gradient(colors: palette.liquid),
                                                     startPoint: CGPoint(x: rect.midX, y: surface),
                                                     endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            let line = LiveOpenAIDrawing.wave(rect, surface: surface, amplitude: amplitude, phase: 0.8,
                                              cycles: 1.1, closed: false)
            context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: max(0.75, size.width * 0.018))
        }
    }

    /// 倒计时胶囊：等宽数字，字不小于 13pt；整句放不下就依次换短写法。
    private func pill(_ label: LiveCalendarLabel, palette: LiveCalendarPalette, font: CGFloat, height: CGFloat,
                      maxWidth: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach(label.candidates, id: \.self) { text in
                Text(verbatim: text)
                    .font(.system(size: font, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, max(3, font * 0.25))
                    .frame(height: height)
                    .background(Capsule(style: .continuous).fill(palette.pill))
            }
        }
        .frame(maxWidth: max(1, maxWidth))
    }
}

/// 日历图标的版面比例（泛型视图里放不了静态存储属性，单独放这里）。
enum LiveCalendarFace {
    /// 红色页眉占内容区的高度比例。
    static let headerFraction = 0.25
}

/// 日历图标的颜色，浅色和深色外观各一套。平时冷色（灰蓝，低不透明度，不发光），
/// 剩 5 分钟以内、即将开始、进行中换暖橙。
struct LiveCalendarPalette {
    var body: [Color]
    var date: Color
    var rim: Color
    var sheen: Double
    var liquid: [Color]
    var pill: Color

    init(dark: Bool, warm: Bool) {
        body = dark ? [Color(hex: "#3A3A3F"), Color(hex: "#242428")] : [Color(hex: "#FFFFFF"), Color(hex: "#ECECF1")]
        date = dark ? Color(hex: "#F2F2F7") : Color(hex: "#1D1D1F")
        rim = dark ? .white.opacity(0.14) : .black.opacity(0.10)
        sheen = dark ? 0.08 : 0.35
        switch (dark, warm) {
        case (false, false):
            liquid = [Color(hex: "#B7CCEB").opacity(0.55), Color(hex: "#88A7D8").opacity(0.65)]
            pill = Color(hex: LiveCalendar.pillHex(dark: false, warm: false))
        case (true, false):
            liquid = [Color(hex: "#6B87B8").opacity(0.5), Color(hex: "#4A6699").opacity(0.6)]
            pill = Color(hex: LiveCalendar.pillHex(dark: true, warm: false))
        case (false, true):
            liquid = [Color(hex: "#FFC796").opacity(0.7), Color(hex: "#F28B4E").opacity(0.8)]
            pill = Color(hex: LiveCalendar.pillHex(dark: false, warm: true))
        case (true, true):
            liquid = [Color(hex: "#E68D52").opacity(0.62), Color(hex: "#BF5F28").opacity(0.72)]
            pill = Color(hex: LiveCalendar.pillHex(dark: true, warm: true))
        }
    }
}

/// 悬停日历图标时名称标签旁的今天剩余日程（彩点 + 时间 + 名称，最多 4 条）。
/// 只给开着日历动态图标的日历格子；没有日程时是空的（不显示卡片）。只在内存里读，不上传。
@MainActor
enum LiveCalendarHover {
    static func agenda(bundleID: String?, now: Date = .now) -> [TooltipAgendaRow] {
        guard bundleID == LiveCalendar.bundleID,
              LiveIconToggles(defaults: .standard).isOn(.calendar) else { return [] }
        return LiveCalendarMonitor.shared.agenda(now: now).map {
            TooltipAgendaRow(id: $0.id, time: LiveCalendar.clock($0.start, calendar: .current),
                             title: $0.title, colorHex: $0.colorHex)
        }
    }
}
