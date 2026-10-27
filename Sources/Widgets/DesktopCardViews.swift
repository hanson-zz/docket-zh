import AppKit
import SwiftUI

// MARK: - 桌面卡片的内容
//
// 钉在桌面的卡片是同一个小组件的另一个视图：每次从 AppState 读它现在的样子
// （`widgetAnywhere`），改动照旧走 `WidgetWriter`，扩展栏和桌面两边同步。
//
// 卡片必须完整显示（怎么摆见 Core 的 `DesktopPinFit`）：
// - 便签摊开整张纸（纸里滚动，点一下就写）；时钟小 / 中是大字时间；算小 / 中直接输入出结果。
// - 其余小 / 中：扩展栏上那张卡片放大摆在中间，能直接点（待办勾、计时开始），横排竖排取
//   放得更大的那种，不缩小到设计尺寸以下。
// - 大号：面板内容铺满卡片（面板自己那层玻璃不画，用卡片的），放得下就放大铺满，放大后放不下
//   就缩到正好放下，设计尺寸也放不下才在卡片里竖着滚，能滚到底，底边淡出提示下面还有。

/// 一张桌面卡片窗口的根视图。
struct DesktopCardHost: View {
    let pinID: UUID
    var app: AppState
    var ui: DesktopPinUI

    var body: some View {
        let settings = app.state.desktopPins
        if let pin = settings.pin(pinID), let widget = app.widgetAnywhere(pin.widgetID) {
            DesktopCard(pin: pin, widget: widget,
                        size: DesktopPinController.shared.drawnSize(pin),
                        ui: ui)
        } else {
            Color.clear
        }
    }
}

/// 卡片本身：液态玻璃（便签是纸）、内容、悬停时右上角的小操作条、排列时左上角的「−」。
struct DesktopCard: View {
    var pin: DesktopPin
    var widget: WidgetInstance
    var size: DesktopPinSize
    var ui: DesktopPinUI

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static let corner: CGFloat = 22
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.corner, style: .continuous) }
    private var isNote: Bool { widget.kind == .notes }

    /// 静止时降低刷新：时钟按分钟（设了秒针每秒），专注计时开着才每秒。
    private var cadence: TimeInterval {
        let running: Bool = {
            guard widget.kind == .timer else { return false }
            let timer = TimerStateProvider.shared.state
            return timer.deadline != nil && timer.paused == nil
        }()
        return DesktopPinCadence.interval(widget.kind, secondHand: ClockHands.showsSecondHand(widget.config),
                                          running: running)
    }

    var body: some View {
        // 从固定的起点数，整分整秒对齐；重画时不重新起算。
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: cadence)) { timeline in
            content(now: timeline.date)
        }
        .frame(width: size.width, height: size.height)
        .background { if !isNote { surface } }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.16 : 0.10), lineWidth: 0.5)
        }
        .overlay {
            if ui.editing { arrangeOverlay }
        }
        .overlay(alignment: .topTrailing) {
            // 拖着这张走的时候操作条不露，但不能移走：拖动手势挂在操作条的拖动键上，
            // 视图一移走手势就作废，网格和空位会留在桌面上。
            let dragging = ui.draggingPin == pin.id
            if (hovering && !ui.editing && ui.draggingPin == nil) || dragging {
                DesktopCardToolbar(pin: pin, widget: widget, shown: size, ui: ui)
                    .padding(8)
                    .opacity(dragging ? 0 : 1)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if ui.editing {
                Button { DesktopPinController.shared.unpin(pin.id) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.panelRaised))
                        .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(tr("取消钉"))
                .accessibilityLabel(tr("取消钉"))
            }
        }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovering = inside }
        }
        .environment(\.panelTint, PanelTint(kind: widget.kind, config: widget.config))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WidgetCatalog.entry(widget.kind)?.name ?? widget.kind.rawValue)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let context = WidgetContext(position: .bottom, now: now)
        if let card = DesktopCardLayouts.view(widget, size: size, now: now) {
            card
        } else {
            generic(context: context, now: now)
        }
    }

    @ViewBuilder
    private func generic(context: WidgetContext, now: Date) -> some View {
        switch (widget.kind, size) {
        case (.notes, _):
            DesktopNoteSheet(widget: widget, sheetID: pin.sheetID, size: size)
        case (.clock, .small), (.clock, .medium):
            DesktopClockFace(now: now, size: size)
        case (.calculator, .small), (.calculator, .medium):
            DesktopQuickCalc(widget: widget)
        case (_, .small), (_, .medium):
            DesktopTileFit(widget: widget, now: now, box: size.size)
        default:
            DesktopPanelBody(widget: widget, context: context, box: size.size)
        }
    }

    /// 液态玻璃，跟着卡片的浅色 / 深色走；降低透明度时换实心底。
    @ViewBuilder private var surface: some View {
        if reduceTransparency {
            shape.fill(scheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F4F4F6"))
        } else {
            Color.clear.glassEffect(.regular, in: shape)
        }
    }

    /// 排列时整张卡片都能拖，内容不接点击；橙色虚线框说明它能动。
    private var arrangeOverlay: some View {
        shape
            .fill(Color.black.opacity(0.001))
            .overlay {
                shape.strokeBorder(Color(hex: ShelfColor.redPanda.hex).opacity(0.8),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(shape)
            .gesture(DesktopPinController.shared.moveGesture(pin.id))
    }
}

// MARK: - 各组专属布局

/// 为桌面专门排的布局：每组一个文件，在 Sources/Widgets/DesktopCards/DesktopCards<组名>.swift，
/// 入口 `view(for:size:now:)`。按组的顺序（Time、Tasks、Media、System、Data、Files）问，第一个
/// 给出视图的就用它；都给 nil 走通用逻辑（放大的扩展栏卡片、面板内容）。每组在 `providers`
/// 加一行入口、在 `kinds` 并上自己做了小号的种类（Core 里），别处不用改。
@MainActor
enum DesktopCardLayouts {
    static let providers: [@MainActor (WidgetInstance, DesktopPinSize, Date) -> AnyView?] = [
        DesktopCardsTime.view,
        DesktopCardsTasks.view,
        DesktopCardsMedia.view,
        DesktopCardsSystem.view,
        DesktopCardsData.view,
        DesktopCardsFiles.view,
    ]

    /// 专属布局总能放下小号的种类：不再按扩展栏卡片能不能塞进 160×160 判断。
    static let kinds: Set<WidgetKind> = DesktopTimeCards.kinds
        .union(DesktopCardsTasksPlan.kinds)
        .union(DesktopCardsMediaPlan.kinds)
        .union(DesktopSystemCards.kinds)
        .union(DesktopCardsDataPlan.kinds)
        .union(DesktopCardsFilesPlan.kinds)

    static func view(_ widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        for provider in providers {
            if let card = provider(widget, size, now) { return card }
        }
        return nil
    }
}

// MARK: - 悬停操作条

/// 卡片右上角：小 / 中 / 大、拖动、取消钉、设置。不悬停时什么都不露。
struct DesktopCardToolbar: View {
    var pin: DesktopPin
    var widget: WidgetInstance
    var shown: DesktopPinSize
    var ui: DesktopPinUI

    private var sizes: [DesktopPinSize] {
        DesktopPinController.shared.sizes(for: widget)
    }

    var body: some View {
        HStack(spacing: 2) {
            if shown == .small {
                // 小卡只有 160 宽，三档放不下，收成一个菜单。
                Menu {
                    ForEach(sizes, id: \.self) { size in
                        let locked = DesktopPinGate.lockedSizes(unlocked: ui.unlocked).contains(size)
                        Button(ProFeatures.menuTitle(size.label, isPro: locked)) {
                            DesktopPinController.shared.resize(pin.id, to: size)
                        }
                    }
                } label: {
                    Text(shown.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 28, minHeight: 24)
                        .background(Capsule().fill(Color.panelRaised).panelLift())
                        .contentShape(.capsule)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(shown.label)
            } else {
                ForEach(sizes, id: \.self) { size in
                    let selected = size == shown
                    let locked = DesktopPinGate.lockedSizes(unlocked: ui.unlocked).contains(size)
                    Button { DesktopPinController.shared.resize(pin.id, to: size) } label: {
                        Text(size.title)
                            .font(.system(size: 13, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .frame(minWidth: 28, minHeight: 24)
                            .background {
                                if selected { Capsule().fill(Color.panelRaised).panelLift() }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(locked ? "\(size.label) · \(ProFeatures.label)" : size.label)
                    .accessibilityLabel(size.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Rectangle().fill(Color.panelSeparator).frame(width: 0.5, height: 14).padding(.horizontal, 3)
            icon("arrow.up.and.down.and.arrow.left.and.right", help: tr("拖动换位置"))
                .gesture(DesktopPinController.shared.moveGesture(pin.id))
            Button { DesktopPinController.shared.unpin(pin.id) } label: {
                icon("pin.slash", help: tr("取消钉"))
            }
            .buttonStyle(.plain)
            Menu {
                Button(tr("排列桌面卡片")) { DesktopPinController.shared.setEditing(true) }
                Button(tr("桌面卡片设置…")) { DesktopPinController.shared.openSettings() }
                Divider()
                Button(tr("取消钉"), role: .destructive) { DesktopPinController.shared.unpin(pin.id) }
            } label: {
                icon("gearshape", help: tr("设置"))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(3)
        .background { Color.clear.glassEffect(.regular, in: Capsule()) }
    }

    private func icon(_ symbol: String, help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.panelPrimary)
            .frame(width: 26, height: 24)
            .contentShape(.rect)
            .help(help)
            .accessibilityLabel(help)
    }
}

// MARK: - 内容

/// 大号：小组件的面板内容铺满卡片。按 `DesktopPinFit.panel` 放大、缩到正好放下或竖着滚。
///
/// 面板按固定的宽排版（只和面板宽、卡片尺寸有关），量到自然高度后再定缩放，缩放不改排版宽，
/// 所以量一次就定、不会来回跳。缩放用 scaleEffect，外面再按缩放后的大小占位，滚动区域
/// 因此按缩放后的高度算，能滚到底。始终套着同一个滚动区域，不换结构，面板里正在输入的
/// 文字、展开的编辑行不会丢。
struct DesktopPanelBody: View {
    var widget: WidgetInstance
    var context: WidgetContext
    var box: CGSize

    /// 面板按排版宽排出来的自然高度（缩放前）。
    @State private var natural: Double?

    /// 滚动时底边淡出的高度，内容底下也多留这么多，最后一行能完整滚出来。
    private static let fade: CGFloat = 18

    /// 不套面板卡片（DetailCard）、直接画在面板上的几种：桌面卡片给它们补内边距。
    static let drawnWithoutCard: Set<WidgetKind> = [.music, .cassette, .clock]

    private var hasCard: Bool { !Self.drawnWithoutCard.contains(widget.kind) }

    var body: some View {
        let plan = DesktopPinFit.panel(naturalHeight: natural, panelWidth: Double(WidgetDetail.width(widget)),
                                       hasCard: hasCard, box: box)
        let scale = CGFloat(plan.scale)
        let width = CGFloat(plan.layoutWidth)
        let tall = CGFloat(max(natural ?? 0, plan.minHeight))
        let scrolls = plan.mode == .scroll
        ScrollView(.vertical) {
            DesktopFillLayout(minHeight: CGFloat(plan.minHeight)) {
                WidgetDetailBody(instance: widget, context: context)
                    .environment(\.detailCardEmbedded, true)
                    .padding(hasCard ? 0 : DetailPanelWidth.padding)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: width)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                let value = Double(height)
                if natural.map({ abs($0 - value) > 0.5 }) ?? true { natural = value }
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width * scale, height: tall * scale, alignment: .topLeading)
            .padding(.bottom, scrolls ? Self.fade : 0)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(!scrolls)
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                if scrolls {
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fade)
                }
            }
        }
        .frame(width: box.width, height: box.height)
    }
}

/// 按内容的自然高度报告自己的大小（量高度用），但把内容按至少 `minHeight` 摆，内容比卡片
/// 矮时面板的底色往下铺满卡片。多出来的部分画在自己的范围外面，外面另按缩放后的大小占位。
struct DesktopFillLayout: Layout {
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? ideal.width, height: ideal.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: max(bounds.height, minHeight)))
    }
}

/// 小号、中号：扩展栏上那张卡片放大摆在中间，卡片上的按钮照样能点（待办勾、计时开始）。
/// 横排（扩展栏在下面时）和竖排（扩展栏在左右时）取放得更大的那种，见 `DesktopPinFit.tile`。
struct DesktopTileFit: View {
    var widget: WidgetInstance
    var now: Date
    var box: CGSize

    static func fit(_ widget: WidgetInstance, box: CGSize) -> DesktopPinFit.TileFit {
        DesktopPinFit.tile(horizontal: WidgetCatalog.contentSize(widget, position: .bottom),
                           vertical: WidgetCatalog.contentSize(widget, position: .left),
                           box: box)
    }

    var body: some View {
        let fit = Self.fit(widget, box: box)
        let position: DockPosition = fit.axis == .vertical ? .left : .bottom
        let natural = WidgetCatalog.contentSize(widget, position: position)
        WidgetTile(instance: widget, context: WidgetContext(position: position, now: now))
            .environment(\.widgetPlateHidden, true)
            .frame(width: natural.width, height: natural.height)
            .scaleEffect(CGFloat(fit.scale > 0 ? fit.scale : 1))
            .frame(width: box.width, height: box.height)
    }
}

/// 时钟的小 / 中：日期一行、大字时间。
struct DesktopClockFace: View {
    var now: Date
    var size: DesktopPinSize

    var body: some View {
        VStack(spacing: size == .small ? 6 : 8) {
            Text(ClockFormat.time(now, zone: .current))
                .font(.system(size: size == .small ? 40 : 64, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(now.formatted(.dateTime.weekday(.abbreviated).month().day()))
                .font(.system(size: size == .small ? 13 : 15, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 「算」小号：打字就出结果。算式存进卡片配置，和扩展栏、面板是同一份。
struct DesktopQuickCalc: View {
    var widget: WidgetInstance

    @State private var draft: String
    @FocusState private var focused: Bool

    init(widget: WidgetInstance) {
        self.widget = widget
        _draft = State(initialValue: widget.config.string(SmartCalc.expressionKey))
    }

    private var stored: String { widget.config.string(SmartCalc.expressionKey) }

    private var outcome: SmartCalc.Outcome? {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return try? SmartCalc.evaluate(draft, rates: CurrencyService.shared.rates,
                                       preferences: SmartCalc.Preferences(widget.config)).get()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WidgetCatalog.entry(.calculator)?.name ?? tr("算"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
            TextField("", text: $draft, prompt: Text(verbatim: "100 usd").foregroundStyle(Color.panelTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Color.panelPrimary)
                .focused($focused)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.panelFill))
                .onSubmit { commit() }
            Spacer(minLength: 0)
            if let outcome {
                Text(outcome.text)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .textSelection(.enabled)
                if !outcome.unit.isEmpty {
                    Text(outcome.unit)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
            } else {
                Text(tr("打字就出结果"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { CurrencyService.shared.refresh(force: false) }
        .onChange(of: stored) { _, value in if !focused { draft = value } }
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        guard draft != stored else { return }
        let latest = WidgetWriter.current(widget.id) ?? widget
        WidgetWriter.write(latest) { $0.set(SmartCalc.expressionKey, .string(draft)) }
    }
}

// 便签的一张纸（`DesktopNoteSheet`）在 DesktopCards/DesktopCardsTasks.swift。

// MARK: - 拖动和排列时的网格

/// 拖动时铺在整块屏幕上的网格点和橙色虚线空位；不接鼠标。
struct DesktopPinGridView: View {
    var ui: DesktopPinUI
    /// 网格所在屏幕的可用区域，换成本窗口里的坐标（左上原点）。
    var visible: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let step = CGFloat(DesktopPinLayout.grid)
                let left = CGFloat(DesktopPinLayout.margin)
                var y = CGFloat(DesktopPinLayout.margin)
                let dot = Color.primary.opacity(0.22)
                while y <= visible.height - left + 0.5 {
                    var x = left
                    while x <= visible.width - left + 0.5 {
                        context.fill(Path(ellipseIn: CGRect(x: visible.minX + x - 1, y: visible.minY + y - 1,
                                                            width: 2, height: 2)), with: .color(dot))
                        x += step
                    }
                    y += step
                }
            }
            if let slot = ui.slot {
                let orange = Color(hex: ShelfColor.redPanda.hex)
                RoundedRectangle(cornerRadius: DesktopCard.corner, style: .continuous)
                    .fill(orange.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesktopCard.corner, style: .continuous)
                            .strokeBorder(orange, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    }
                    .overlay {
                        VStack(spacing: 4) {
                            if ui.slotIsNew {
                                Text(tr("松手钉在这里"))
                                    .font(.system(size: 15, weight: .bold))
                            }
                            Text(ui.slotSize.label)
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.panelPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.panelRaised.opacity(0.9)))
                    }
                    .frame(width: slot.width, height: slot.height)
                    .offset(x: slot.minX, y: slot.minY)
                    .animation(.snappy(duration: 0.16), value: slot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 排列模式顶上的横条：「排列桌面卡片  拖动换位置 · 点 − 取消钉  [完成]」。
struct DesktopPinArrangeBar: View {
    @Environment(\.colorScheme) private var scheme

    static let size = CGSize(width: 520, height: 52)

    var body: some View {
        HStack(spacing: 14) {
            Text(tr("排列桌面卡片"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(tr("拖动换位置 · 点 − 取消钉"))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button { DesktopPinController.shared.setEditing(false) } label: {
                Text(tr("完成"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.panelOnPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.panelPrimary))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.leading, 20)
        .padding(.trailing, 11)
        .frame(width: Self.size.width, height: Self.size.height)
        .background { Color.clear.glassEffect(.regular, in: Capsule()) }
    }
}
