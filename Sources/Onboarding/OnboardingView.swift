import AppKit
import AVFoundation
import EventKit
import SwiftUI

/// 首次启动的新手引导。
///
/// 六步：欢迎、选位置、选用途、权限、布置中（小组件一个个靠岸停进扩展栏）、完成。顶部是分段进度条和返回按钮，
/// 标题左对齐，选项是大卡片，底部一个大圆角的主按钮。位置一选就生效；
/// 小组件在“布置中”这一步真正写进当前布局（只追加，不删除已有的）。
/// 欢迎页可以点“先带我看看”，用聚光灯依次照出进度、跳过和开始按钮（见 `SpotlightOverlay`）。
struct OnboardingView: View {
    let app: AppState
    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var position: DockPosition
    @State private var uses: Set<OnboardingUse> = [.productivity, .system]
    @State private var built = false
    @State private var progress: Double = 0
    @State private var added: [String] = []
    /// 聚光灯导览走到第几站；nil 是没在导览。
    @State private var tourStop: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter startPosition: 选位置一步默认选中的边。首次启动是底部；
    ///   从设置里重新打开时是扩展栏现在所在的边，免得一路“继续”把它挪走。
    init(app: AppState, startPosition: DockPosition = .bottom, onFinish: @escaping () -> Void) {
        self.app = app
        self.onFinish = onFinish
        _position = State(initialValue: startPosition)
    }

    private var available: Set<String> { Set(WidgetCatalog.shippable.map(\.kind.rawValue)) }

    /// 选中的用途对应的代表小组件，不管当前布局里有没有。
    private var previewKinds: [String] { Onboarding.kinds(for: uses, available: available) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 18)

            Group {
                switch step {
                case .welcome: welcome
                case .position: positionStep
                case .uses: usesStep
                case .permissions: permissionsStep
                case .building: buildingStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .id(step)
            .transition(reduceMotion
                ? AnyTransition.opacity
                : AnyTransition.asymmetric(
                    insertion: AnyTransition.move(edge: .trailing).combined(with: .opacity),
                    removal: AnyTransition.opacity))

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
        }
        .frame(width: 560, height: 640)
        .background(.background)
        .overlayPreferenceValue(SpotlightAnchorKey.self) { anchors in
            SpotlightOverlay(stops: SpotlightTour.onboarding, anchors: anchors, index: $tourStop)
        }
    }

    // MARK: - 顶部：返回 + 分段进度条 + 跳过

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(step.canGoBack ? 1 : 0)
            .disabled(!step.canGoBack)
            .help("返回")
            .accessibilityLabel("返回")

            SegmentedProgress(total: OnboardingStep.allCases.count, filled: step.filledSegments)
                .frame(height: 6)
                .spotlightTarget("progress")

            Button("跳过", action: skip)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(step == .done ? 0 : 1)
                .disabled(step == .done || tourStop != nil)
                .spotlightTarget("skip")
        }
    }

    // MARK: - 底部主按钮

    private var footer: some View {
        Button(action: primaryAction) {
            Text(primaryTitle)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(Color.accentColor.opacity(primaryEnabled ? 1 : 0.4),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!primaryEnabled)
        // 导览开着时回车留给导览卡片的“下一步”，不要直接翻到下一页。
        .keyboardShortcut(tourStop == nil ? KeyboardShortcut.defaultAction : nil)
        .spotlightTarget("primary")
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: tr("开始")
        case .permissions: tr("继续")
        case .building: progress >= 1 ? tr("继续") : tr("正在布置…")
        case .done: tr("开始使用")
        default: tr("继续")
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case .building: progress >= 1
        default: true
        }
    }

    private func primaryAction() {
        switch step {
        case .position:
            // 只在和现在不一样时才应用：扩展栏已经在这条边上（比如跟随系统程序坞
            // 正好落在底部）就保持原样，不去关掉跟随。
            if position != app.effectivePosition { app.applyOnboardingPosition(position) }
            advance()
        case .done:
            onFinish()
        default:
            advance()
        }
    }

    private func advance() {
        guard let next = step.next else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { step = next }
        if next == .building { startBuilding() }
    }

    private func goBack() {
        guard step.canGoBack, let previous = step.previous else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { step = previous }
    }

    private func skip() { onFinish() }

    // MARK: - ① 欢迎

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            Text("欢迎使用码头")
                .font(.system(size: 30, weight: .bold))
            Text("把时间、日程、待办、音乐这些常看的东西，做成小组件放进一条像程序坞一样的扩展栏，一眼就能看到。")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("接下来用不到一分钟，帮你把码头布置好。")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { tourStop = 0 }
            } label: {
                Label("先带我看看", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("用聚光灯依次指出进度、跳过和开始按钮")
            Spacer()
        }
    }

    // MARK: - ② 选位置

    private var positionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(title: tr("扩展栏放在哪里？"), subtitle: tr("选好后立即生效，以后可以在“设置 ▸ 扩展栏”里修改。"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 14) {
                ForEach(DockPosition.allCases, id: \.self) { edge in
                    PositionCard(edge: edge, selected: position == edge) {
                        position = edge
                        if edge != app.effectivePosition { app.applyOnboardingPosition(edge) }
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - ③ 选用途

    private var usesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTitle(title: tr("你想用码头做什么？"), subtitle: tr("可以多选，我们会为每一类挑两三个小组件。"))
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(OnboardingUse.allCases, id: \.self) { use in
                        UseCard(use: use, selected: uses.contains(use)) {
                            if uses.contains(use) { uses.remove(use) } else { uses.insert(use) }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - ④ 权限

    private var permissionsStep: some View {
        let needed = Onboarding.permissions(for: previewKinds)
        return VStack(alignment: .leading, spacing: 18) {
            StepTitle(title: tr("授予需要的权限"),
                      subtitle: needed.isEmpty
                        ? tr("你选的小组件不需要额外权限，直接继续就好。")
                        : tr("只列出你选的小组件真正用得到的权限。现在不授权也没关系，可以跳过，以后用到时再开。"))
            if needed.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.green)
                    Text("不需要任何权限")
                        .font(.system(size: 15, weight: .medium))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(needed, id: \.self) { permission in
                        PermissionRow(permission: permission,
                                      usedBy: kindsNeeding(permission))
                    }
                }
            }
            Spacer()
        }
    }

    private func kindsNeeding(_ permission: String) -> String {
        previewKinds
            .filter { WidgetSearch.permissions[$0] == permission }
            .compactMap { WidgetKind(rawValue: $0).flatMap { WidgetCatalog.entry($0)?.name } }
            .joined(separator: tr("、"))
    }

    // MARK: - ⑤ 布置中

    private var buildingStep: some View {
        VStack(spacing: 18) {
            DockingView(kinds: previewKinds.isEmpty ? ["clock"] : previewKinds,
                        position: position, progress: progress)
                .frame(width: 300, height: 260)
                .frame(maxWidth: .infinity)

            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText())

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 260)

            VStack(alignment: .leading, spacing: 10) {
                let checked = Onboarding.checkedItems(progress: progress)
                ForEach(Array(Onboarding.checklist.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 10) {
                        Image(systemName: index < checked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index < checked ? Color.accentColor : Color.secondary.opacity(0.5))
                        Text(line)
                            .foregroundStyle(index < checked ? .primary : .secondary)
                    }
                    .font(.system(size: 13))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// 真正写入布局，然后用约 2.5 秒把百分比从 0 走到 100%。
    ///
    /// 布局在一开始就写好了，动画只是让人看清发生了什么；“减少动态效果”打开时直接显示结果。
    private func startBuilding() {
        if !built {
            built = true
            added = app.addOnboardingWidgets(for: uses)
        }
        guard !reduceMotion else {
            progress = 1
            return
        }
        progress = 0
        Task { @MainActor in
            let start = Date()
            while true {
                let elapsed = Date().timeIntervalSince(start)
                let t = min(1, elapsed / Onboarding.buildDuration)
                // 先快后慢，最后一段放缓，读起来像真的在收尾。
                let eased = 1 - pow(1 - t, 2)
                withAnimation(.linear(duration: 0.05)) { progress = eased }
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(40))
            }
            progress = 1
            try? await Task.sleep(for: .milliseconds(600))
            if step == .building {
                withAnimation(.snappy(duration: 0.3)) { step = .done }
            }
        }
    }

    // MARK: - ⑥ 完成

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 112, height: 112)
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            Text("码头已就绪")
                .font(.system(size: 30, weight: .bold))
            Text(doneSummary)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("想调整时，右键扩展栏或打开“设置”；想再看一遍这份引导，在“设置 ▸ 通用”里找。")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var doneSummary: String {
        let names = added.compactMap { WidgetKind(rawValue: $0).flatMap { WidgetCatalog.entry($0)?.name } }
        if names.isEmpty {
            return tr("扩展栏已经放在屏幕\(position.displayName)。你选的小组件都已经在布局里了，没有重复添加。")
        }
        return tr("扩展栏已经放在屏幕\(position.displayName)，并添加了 \(names.count) 个小组件：\(names.joined(separator: tr("、")))。")
    }
}

// MARK: - 组件

/// 左对齐的大标题和一行说明。
private struct StepTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 顶部的分段进度条。
private struct SegmentedProgress: View {
    let total: Int
    let filled: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
        }
        .animation(.snappy(duration: 0.3), value: filled)
        .accessibilityElement()
        .accessibilityLabel(tr("第 \(filled) 步，共 \(total) 步"))
    }
}

/// 选位置的卡片：一块屏幕示意图，扩展栏贴在选中的边上。
private struct PositionCard: View {
    let edge: DockPosition
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ScreenSketch(edge: edge)
                    .frame(height: 96)
                HStack {
                    Text(edge.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                }
            }
            .padding(12)
            .background(.quaternary.opacity(selected ? 0.2 : 0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.06),
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("扩展栏放在\(edge.displayName)"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 一块简化的屏幕：顶部一条菜单栏，选中的边上一条带几个圆点的扩展栏。
private struct ScreenSketch: View {
    let edge: DockPosition

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.06)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(height: 6)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
            }
            .overlay(alignment: alignment) { shelf.padding(6).padding(.top, edge == .top ? 6 : 0) }
    }

    private var shelf: some View {
        let dots = ForEach(0..<4, id: \.self) { index in
            Circle()
                .fill([Color.orange, .pink, .blue, .green][index])
                .frame(width: 7, height: 7)
        }
        return Group {
            if edge.isVertical {
                VStack(spacing: 4) { dots }
                    .padding(.vertical, 6)
                    .frame(width: 14)
            } else {
                HStack(spacing: 4) { dots }
                    .padding(.horizontal, 8)
                    .frame(height: 14)
            }
        }
        .background(.background.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
    }

    private var alignment: Alignment {
        switch edge {
        case .left: .leading
        case .top: .top
        case .bottom: .bottom
        case .right: .trailing
        }
    }
}

/// 选用途的卡片：彩色圆形图标、名称、例子，右侧勾选。
private struct UseCard: View {
    let use: OnboardingUse
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: use.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: use.colorHex), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(use.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(use.caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.quaternary.opacity(selected ? 0.2 : 0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.06),
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(use.title)：\(use.caption)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 靠岸动画

/// 所选小组件像一艘艘小船，排着队从画面外沿水道驶来，一个接一个停进扩展栏（码头）里。
///
/// 完全由布置进度驱动：第几个小组件走到哪里由 `Onboarding.dockingFraction` 算出，
/// 进度走满时全部靠岸。“减少动态效果”打开时进度直接是 1，画面一开始就是停好的样子。
/// 扩展栏的方向跟着上一步选的位置：左右两侧是竖着的，小组件从下方驶来；
/// 顶部和底部是横着的，小组件从右边驶来。
private struct DockingView: View {
    let kinds: [String]
    let position: DockPosition
    let progress: Double

    private let canvas = CGSize(width: 300, height: 260)

    var body: some View {
        let vertical = position.isVertical
        let layout = DockingGeometry(count: kinds.count, vertical: vertical, canvas: canvas)
        ZStack(alignment: .topLeading) {
            // 水面：几道浅浅的波纹，沿着小组件驶来的水道。
            Waves(vertical: vertical, lane: layout.lane)
                .stroke(Color.accentColor.opacity(0.18), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: canvas.width, height: canvas.height)

            // 扩展栏：一条圆角的栈桥，起点是码头图标。
            RoundedRectangle(cornerRadius: layout.tile * 0.42, style: .continuous)
                .fill(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: layout.tile * 0.42, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .frame(width: layout.shelf.width, height: layout.shelf.height)
                .offset(x: layout.shelf.minX, y: layout.shelf.minY)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: layout.tile, height: layout.tile)
                .position(layout.slot(-1))

            ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                let fraction = Onboarding.dockingFraction(index: index, count: kinds.count, progress: progress)
                let eased = CGFloat(1 - pow(1 - fraction, 3))
                let from = layout.entry(index)
                let to = layout.slot(index)
                // 行驶中轻轻起伏，越靠近码头越平稳。
                let bob = CGFloat(fraction > 0 && fraction < 1 ? sin(fraction * .pi * 4) * 4 * (1 - fraction) : 0)
                let x = from.x + (to.x - from.x) * eased + (vertical ? bob : 0)
                let y = from.y + (to.y - from.y) * eased + (vertical ? 0 : bob)
                ZStack {
                    // 船尾的一道水痕，靠岸后消失。
                    Capsule()
                        .fill(Color(hex: Onboarding.colorHex(for: kind)).opacity(0.25 * (1 - fraction)))
                        .frame(width: vertical ? 4 : layout.tile * 0.9, height: vertical ? layout.tile * 0.9 : 4)
                        .offset(x: vertical ? 0 : layout.tile * 0.75, y: vertical ? layout.tile * 0.75 : 0)
                    Image(systemName: Onboarding.symbol(for: kind))
                        .font(.system(size: layout.tile * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: layout.tile, height: layout.tile)
                        .background(Color(hex: Onboarding.colorHex(for: kind)),
                                    in: RoundedRectangle(cornerRadius: layout.tile * 0.28, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                }
                .opacity(fraction > 0 ? 1 : 0)
                .position(x: x, y: y)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(tr("正在把 \(kinds.count) 个小组件停进扩展栏，已靠岸 \(Onboarding.dockedCount(count: kinds.count, progress: progress)) 个"))
    }

    /// 栈桥和每个泊位的位置。
    private struct DockingGeometry {
        let vertical: Bool
        let canvas: CGSize
        let tile: CGFloat
        let spacing: CGFloat
        let shelf: CGRect
        /// 水道的中线：横向时是 y，竖向时是 x。
        let lane: CGFloat

        init(count: Int, vertical: Bool, canvas: CGSize) {
            self.vertical = vertical
            self.canvas = canvas
            let length = (vertical ? canvas.height : canvas.width) - 28
            let slots = CGFloat(count + 1)
            spacing = 6
            tile = min(34, max(14, (length - 16 - spacing * (slots - 1)) / slots))
            let used = slots * tile + (slots - 1) * spacing + 16
            let thickness = tile + 16
            if vertical {
                lane = canvas.width / 2
                shelf = CGRect(x: lane - thickness / 2, y: 14, width: thickness, height: used)
            } else {
                lane = canvas.height / 2
                shelf = CGRect(x: 14, y: lane - thickness / 2, width: used, height: thickness)
            }
        }

        /// 第 `index` 个泊位的中心，-1 是最前面的码头图标。
        func slot(_ index: Int) -> CGPoint {
            let along = 8 + tile / 2 + CGFloat(index + 1) * (tile + spacing)
            return vertical
                ? CGPoint(x: lane, y: shelf.minY + along)
                : CGPoint(x: shelf.minX + along, y: lane)
        }

        /// 出发点：画面外，沿着水道排在泊位后面。
        func entry(_ index: Int) -> CGPoint {
            vertical
                ? CGPoint(x: lane, y: canvas.height + tile)
                : CGPoint(x: canvas.width + tile, y: lane)
        }
    }
}

/// 几道和水道平行的波纹。
private struct Waves: Shape {
    let vertical: Bool
    let lane: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for offset in [-44.0, -30.0, 30.0, 44.0] {
            let base = lane + CGFloat(offset)
            let length = vertical ? rect.height : rect.width
            var t: CGFloat = 0
            var first = true
            while t <= length {
                let wobble = sin(t / 14 + CGFloat(offset)) * 2.5
                let point = vertical ? CGPoint(x: base + wobble, y: t) : CGPoint(x: t, y: base + wobble)
                if first { path.move(to: point); first = false } else { path.addLine(to: point) }
                t += 4
            }
        }
        return path
    }
}

// MARK: - 权限

/// 权限页的一行：名称、用到它的小组件、状态和“去授权”按钮。
private struct PermissionRow: View {
    let permission: String
    let usedBy: String

    @State private var status: PermissionStatus = .unknown

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: OnboardingPermissions.symbol(permission))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(trKey(permission))
                    .font(.system(size: 14, weight: .semibold))
                Text(usedBy.isEmpty ? status.caption : tr("\(usedBy)用到 · \(status.caption)"))
                    .font(.system(size: 12))
                    .foregroundStyle(status == .granted ? Color.green : .secondary)
                    .lineLimit(2)
            }
            Spacer()
            if status == .granted {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("去授权") {
                    Task { @MainActor in
                        await OnboardingPermissions.request(permission)
                        status = OnboardingPermissions.status(permission)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { status = OnboardingPermissions.status(permission) }
        // 从“系统设置”回来时刷新一次。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = OnboardingPermissions.status(permission)
        }
    }
}

enum PermissionStatus: Equatable {
    case granted, notDetermined, denied, unknown

    var caption: String {
        switch self {
        case .granted: tr("已授权")
        case .notDetermined: tr("尚未授权")
        case .denied: tr("已拒绝，需要在“系统设置”里打开")
        case .unknown: tr("需要在“系统设置”里打开，或首次使用时由系统询问")
        }
    }
}

/// 把 `WidgetSearch.permissions` 里的中文权限名对应到实际的检查和申请。
///
/// 能直接弹系统授权框的（日历、提醒事项、麦克风、屏幕录制）先弹框；
/// 已拒绝的、或者没有公开申请接口的（自动化、完全磁盘访问、系统音频录制），
/// 打开“系统设置”里对应的隐私页。
@MainActor
enum OnboardingPermissions {
    static func symbol(_ permission: String) -> String {
        switch permission {
        case "日历": "calendar"
        case "提醒事项": "list.bullet"
        case "麦克风": "mic.fill"
        case "屏幕录制": "rectangle.dashed.badge.record"
        case "完全磁盘访问权限": "internaldrive.fill"
        case "录制系统音频": "speaker.wave.2.fill"
        default: "gearshape.2.fill" // 自动化（音乐 App / 邮件）
        }
    }

    static func status(_ permission: String) -> PermissionStatus {
        switch permission {
        case "日历": eventKit(.event)
        case "提醒事项": eventKit(.reminder)
        case "麦克风": microphone()
        case "屏幕录制": CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        default: .unknown
        }
    }

    private static func microphone() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private static func eventKit(_ type: EKEntityType) -> PermissionStatus {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request(_ permission: String) async {
        let current = status(permission)
        switch (permission, current) {
        case ("日历", .notDetermined):
            _ = try? await EKEventStore().requestFullAccessToEvents()
        case ("提醒事项", .notDetermined):
            _ = try? await EKEventStore().requestFullAccessToReminders()
        case ("麦克风", .notDetermined):
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case ("屏幕录制", .notDetermined):
            // 第一次会弹系统框；之后系统不再弹，只能去“系统设置”里开。
            if !CGRequestScreenCaptureAccess() { openSettings(for: permission) }
        default:
            openSettings(for: permission)
        }
    }

    private static func openSettings(for permission: String) {
        let pane: String = switch permission {
        case "日历": "Privacy_Calendars"
        case "提醒事项": "Privacy_Reminders"
        case "麦克风": "Privacy_Microphone"
        case "屏幕录制": "Privacy_ScreenCapture"
        case "完全磁盘访问权限": "Privacy_AllFiles"
        case "录制系统音频": "Privacy_AudioCapture"
        default: "Privacy_Automation"
        }
        guard let url = WidgetTarget.settings("com.apple.preference.security?\(pane)").settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
