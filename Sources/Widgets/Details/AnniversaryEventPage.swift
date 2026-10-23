import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 纪念日面板现在开在哪一页：时间线，还是某一个纪念日的专属页。
///
/// 放在这里而不是面板的 @State 里：面板窗口一直复用同一个 hosting view，@State
/// 会从上一次打开留到下一次；而多个卡片里点某一列时，要在面板打开之前就说好开哪一页。
/// 面板关上（点外面、Esc、再点卡片）就清掉这张卡片的记录，下次按卡片样式重新决定：
/// 单个卡片开它自己的专属页，多个卡片开时间线。
@MainActor @Observable
final class AnniversaryRoute {
    static let shared = AnniversaryRoute()

    enum Page: Equatable {
        case timeline
        case event(String)
    }

    private(set) var pages: [UUID: Page] = [:]
    @ObservationIgnored private var closeObserver: NSObjectProtocol?

    private init() {
        closeObserver = NotificationCenter.default.addObserver(
            forName: WidgetDetailWindow.didClose, object: nil, queue: nil) { note in
            let id = note.object as? UUID
            MainActor.assumeIsolated { AnniversaryRoute.shared.closed(id) }
        }
    }

    func page(_ id: UUID) -> Page? { pages[id] }

    func show(_ page: Page, in id: UUID) {
        if pages[id] != page { pages[id] = page }
    }

    private func closed(_ id: UUID?) {
        guard let id else { return pages.removeAll() }
        pages[id] = nil
    }

    /// 多个卡片里点了某一列：面板直接开在那一列的专属页。面板已经开着就原地换页。
    ///
    /// 由扩展栏来开，因为锚点在它手里；用的是 AI 助手那条“打开这张卡片的面板”的
    /// 通知，它只按小组件 id 找卡片，不管是哪种小组件。
    func open(_ eventID: String, in instanceID: UUID) {
        show(.event(eventID), in: instanceID)
        NotificationCenter.default.post(name: AIPanelState.openRequest, object: nil,
                                        userInfo: ["id": instanceID.uuidString, "toggle": false])
    }
}

/// 一个纪念日的专属页（单个卡片点开，340 宽）：一大块液态玻璃里是大沙漏、大字天数和
/// 天 / 时 / 分三格；下面这一轮的进度条和起止日子，日期 / 类型 / 重复三行，接下来三次，
/// 底部编辑、分享图和回到时间线。临近时沙漏和三格一起变暖；当天沙漏换成小熊猫捧场。
/// 数都来自 Core 的 `Anniversary`。
struct AnniversaryEventPage: View {
    var reading: AnniversaryReading
    var events: [AnniversaryEvent]
    var pinned: String?
    /// 单个卡片打开时右上角有“换一个”，改的是固定在卡片上的那个。
    var showsSwitcher: Bool
    var now: Date
    var isPreview: Bool
    /// 画哪种沙漏（线条或玻璃），跟卡片选的样式走。
    var look: AnniversaryLook
    var onBack: () -> Void
    var onEdit: () -> Void
    var onPick: (String) -> Void

    @State private var sharing = false
    @State private var notice: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var event: AnniversaryEvent { reading.event }
    private var tint: Color { AnniversaryTile.tint(event) }
    private var dark: Bool { scheme == .dark }
    private var near: Bool { Anniversary.isNear(reading, today: now) }
    private var celebrating: Bool { Anniversary.isCelebrating(reading) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            if sharing {
                sharePane
            } else {
                hero
                cycleSection
                factsSection
                nextSection
                actions
            }
        }
        .onChange(of: event.id) { _, _ in
            sharing = false
            notice = nil
        }
        .animation(.snappy(duration: 0.25), value: sharing)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: 8) {
            AnniversaryBackButton(action: onBack)
            Spacer(minLength: 0)
            if showsSwitcher, events.count > 1, !isPreview {
                Menu {
                    ForEach(events) { item in
                        Button {
                            onPick(item.id)
                        } label: {
                            if item.id == event.id {
                                Label(item.title, systemImage: "checkmark")
                            } else {
                                Text(item.title)
                            }
                        }
                    }
                } label: {
                    Text("换一个")
                        .font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help("换一个显示在单个卡片上")
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            if celebrating {
                pandaCheer
            } else {
                AnniversaryHourglass(look: look, sand: Anniversary.sand(reading, today: now),
                                     cap: AnniversaryTile.base(event), animate: !reduceMotion)
                    .frame(width: 66, height: 140)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    AnniversaryIconChip(event: event, diameter: 18)
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint.panelReadable)
                        .lineLimit(1)
                }
                if celebrating {
                    Text(reading.anniversaryNote.map { tr("\($0)啦") } ?? tr("就是今天"))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(Anniversary.cardLine(reading, today: now))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(2)
                } else {
                    Text(reading.word)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: reading.days.formatted(.number))
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .foregroundStyle(near ? AnniversarySandColor.warmInk(dark: dark) : Color.panelPrimary)
                            .monospacedDigit()
                            .rollingValue(reading.days)
                        Text("天")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.panelSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    clockCells
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if near {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AnniversarySandColor.warm.opacity(dark ? 0.14 : 0.1))
            }
        }
        .glassPane(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    /// 当天：小熊猫捧场，头上几片彩纸。
    @ViewBuilder
    private var pandaCheer: some View {
        Group {
            if let image = PandaArt.image("pet-panda-cheer") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "gift.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.panelPrimary)
            }
        }
        .frame(width: 92, height: 100)
        .overlay(alignment: .top) {
            AnniversaryConfetti()
                .frame(width: 100, height: 26)
                .offset(y: -8)
        }
        .accessibilityHidden(true)
    }

    /// 天、时、分三格，精确到分钟。临近时一起变暖。
    private var clockCells: some View {
        let clock = Anniversary.clock(reading, now: now)
        return HStack(spacing: 6) {
            clockCell(clock.days, unit: tr("天"))
            clockCell(clock.hours, unit: tr("时"), pad: true)
            clockCell(clock.minutes, unit: tr("分"), pad: true)
        }
    }

    private func clockCell(_ value: Int, unit: String, pad: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: pad ? String(format: "%02d", value) : value.formatted(.number))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(near ? AnniversarySandColor.warmInk(dark: dark) : Color.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(unit)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(near ? AnniversarySandColor.warm.opacity(dark ? 0.22 : 0.14) : Color.panelFill)
        }
    }

    // MARK: Cycle

    @ViewBuilder
    private var cycleSection: some View {
        if let cycle = Anniversary.cycle(reading, today: now) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("这一轮已过 \(cycle.percent)%"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(cycle.elapsed) / \(cycle.total)")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.panelTrack)
                        Capsule()
                            .fill(AnniversarySandColor.bar(near: near, dark: dark))
                            .frame(width: max(6, proxy.size.width * cycle.fraction))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(Anniversary.longText(cycle.start))
                    Spacer(minLength: 4)
                    Text(Anniversary.longText(cycle.end))
                }
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Facts

    private var factsSection: some View {
        let date = reading.kindDate
        var dateText = "\(Anniversary.longText(date)) \(Anniversary.weekdayShort(date))"
        if event.lunar { dateText += " · " + tr("农历\(Anniversary.lunarShort(date))") }
        return VStack(spacing: 0) {
            factRow(tr("日期"), dateText)
            Divider().overlay(.panelSeparator)
            factRow(tr("类型"), event.kind.title)
            Divider().overlay(.panelSeparator)
            factRow(tr("重复"), Anniversary.repeatText(event))
        }
        .padding(.horizontal, 12)
        .glassPane(cornerRadius: 12)
    }

    private func factRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(height: 34)
    }

    // MARK: Next times

    @ViewBuilder
    private var nextSection: some View {
        let next = Anniversary.nextTimes(event, today: now)
        if !next.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("接下来几次")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                ForEach(next) { item in nextRow(item) }
            }
        }
    }

    private func nextRow(_ item: AnniversaryOccurrence) -> some View {
        var date = "\(Anniversary.longText(item.date)) \(Anniversary.weekdayShort(item.date))"
        if event.lunar { date += " · " + tr("农历\(Anniversary.lunarShort(item.date))") }
        return HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AnniversarySandColor.bar(near: false, dark: dark))
                .frame(width: 16)
            Text(date)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if item.ordinal > 0 {
                Text(tr("第 \(item.ordinal) 个周年"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Text(item.daysLeft == 0 ? tr("就是今天") : tr("\(item.daysLeft) 天"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.daysLeft == 0 ? tint.panelReadable : .panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: 22)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            pill(tr("编辑"), symbol: "pencil", action: onEdit)
            pill(tr("分享图"), symbol: "square.and.arrow.up") { sharing = true }
            pill(tr("时间线"), symbol: "list.bullet", action: onBack)
            Spacer(minLength: 0)
        }
    }

    private func pill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .glassPane(cornerRadius: 15)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
    }

    // MARK: Share

    private var sharePane: some View {
        VStack(spacing: 12) {
            AnniversaryShareCard(reading: reading, today: now, panda: AIPandaArt.image)
                .scaleEffect(0.7)
                .frame(width: AnniversaryShareCard.size.width * 0.7, height: AnniversaryShareCard.size.height * 0.7)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tr("分享图预览"))
            HStack(spacing: 8) {
                Button("存为图片…", action: save)
                Button("拷贝图片", action: copy)
                Spacer(minLength: 4)
                Button("完成") { sharing = false }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
            .disabled(isPreview)
            if let notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func save() {
        guard let png = AnniversaryShareImage.render(reading: reading, today: now)?.png else {
            return say(tr("图片生成失败"))
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = AnniversaryShareImage.fileName(event)
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        // 面板在扩展栏那一层之上，存储窗口要再高一层才不会被它挡住。
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 3)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            say(tr("已存储：\(url.lastPathComponent)"))
        } catch {
            say(tr("无法存储图片"))
        }
    }

    private func copy() {
        guard let rendered = AnniversaryShareImage.render(reading: reading, today: now) else {
            return say(tr("图片生成失败"))
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([rendered.image])
        board.setData(rendered.png, forType: .png)
        say(tr("已拷贝图片"))
    }

    private func say(_ text: String) {
        withAnimation { notice = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { if notice == text { notice = nil } }
        }
    }
}

/// 左上角的“‹ 纪念日”：回到时间线。
struct AnniversaryBackButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("纪念日")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("回到时间线")
    }
}

// MARK: - Share image

/// 分享出去的竖版卡片：事件颜色的深色渐变，小熊猫，名称，大数字，日期区间，
/// 底部“码头 Dockling”。
struct AnniversaryShareCard: View {
    var reading: AnniversaryReading
    var today: Date
    var panda: NSImage?

    static let size = CGSize(width: 300, height: 420)

    /// 天、天后、天前。
    static func unit(_ reading: AnniversaryReading) -> String {
        switch reading.phase {
        case .upcoming: tr("天后")
        case .today: tr("天")
        case .past: reading.event.kind == .countup ? tr("天") : tr("天前")
        }
    }

    private var isToday: Bool {
        reading.phase == .today || (reading.isToday && reading.event.kind == .countdown)
    }

    /// 2019.5.20 → 2026.10.18：从那天到今天，或者从今天到那天。
    private var range: String {
        let start = Anniversary.calendar.startOfDay(for: today)
        if reading.phase == .upcoming, let next = reading.next {
            return "\(Anniversary.dotText(start)) → \(Anniversary.dotText(next))"
        }
        if reading.event.kind == .countdown, let next = reading.next {
            return Anniversary.dotText(next)
        }
        return "\(Anniversary.dotText(reading.original)) → \(Anniversary.dotText(start))"
    }

    var body: some View {
        let base = AnniversaryTile.base(reading.event)
        VStack(spacing: 0) {
            Spacer(minLength: 22)
            if let panda {
                Image(nsImage: panda)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 148)
            }
            Text(reading.event.title)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 14)
                .padding(.horizontal, 20)
            if isToday {
                Text("就是今天")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 6)
            } else {
                Text(verbatim: reading.days.formatted(.number))
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 20)
                Text(Self.unit(reading))
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0.85)
            }
            Text(verbatim: range)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .opacity(0.72)
                .padding(.top, 14)
            Spacer(minLength: 12)
            Text("码头 Dockling")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.5)
                .padding(.bottom, 18)
        }
        .foregroundStyle(.white)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                LinearGradient(colors: [base.mix(with: .black, by: 0.5), base.mix(with: .black, by: 0.82)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [base.opacity(0.28), .clear],
                               center: .top, startRadius: 0, endRadius: 260)
            }
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
enum AnniversaryShareImage {
    struct Rendered {
        var image: NSImage
        var png: Data
    }

    /// 两倍大小的卡片，图片和 PNG 数据各一份。
    static func render(reading: AnniversaryReading, today: Date) -> Rendered? {
        let renderer = ImageRenderer(content: AnniversaryShareCard(reading: reading, today: today,
                                                                   panda: AIPandaArt.image))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let image = NSImage(size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        image.addRepresentation(rep)
        return Rendered(image: image, png: png)
    }

    static func fileName(_ event: AnniversaryEvent) -> String {
        let safe = event.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return tr("码头纪念日-\(safe).png")
    }
}

// MARK: - Pointer

/// 指针在这块区域里的位置，按宽高的比例给出（左上角是 0,0），离开时是 nil。
///
/// 多个卡片悬停某一列时轻轻亮起要用。和 `HoverCatcher` 一样自己装 `.activeAlways`
/// 的跟踪区域，因为 `.onHover` 在这个不激活的面板里不会触发；按比例给，是因为卡片
/// 在扩展栏里整体缩放过。点击照样穿过去，交给下面的按钮。
struct PointerFraction: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onMove = onMove
    }

    final class TrackerView: NSView {
        var onMove: ((CGPoint?) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        private func report(_ event: NSEvent) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let local = convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: local.x / bounds.width, y: 1 - local.y / bounds.height)
            let inside = (0...1).contains(point.x) && (0...1).contains(point.y)
            onMove?(inside ? point : nil)
        }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
    }
}
