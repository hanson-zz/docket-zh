import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AI 助手的扩展栏卡片，按「Dock 小组件」效果图精修，尺寸仍用原来的。
///
/// 横版（多模型快速切换）：左边坐着的小熊猫，一道细分隔线，后面一排圆角方形
/// 模型键（服务现有的首字母或首字），当前模型高亮（暖橙描边、浅橙底、右上小
/// 橙点），末尾细虚线“＋”管理更多模型。点模型键直接用那个模型打开助手；放
/// 不下时按顺序少画几块，当前那块总留着，“＋”总留着。
///
/// 竖版（状态陪伴卡）：和横版分工，不放模型键、模型字母和 chevron。对着笔记本的
/// 小熊猫（生成中换等回答的那张）占大头，旁边一块玻璃写「问 AI」和一行提示：空闲时
/// 轮换设置里勾选的快捷操作（「可以试试：截图提问」），生成中、完成、出错只认码头
/// 拿得到的（API 方式的回答）。整块点一下开始提问，右键扩展栏菜单里有「截图提问」。
///
/// 右键模型键：设为默认、左移、右移、隐藏。点“＋”：按国内、国外列出全部服务，
/// 打勾的显示在卡片上，最后一项“自定义…”。右键卡片别处是扩展栏自己的菜单。
struct AIAssistantTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var config: WidgetConfig { instance.config }
    /// 拖着文字或文件停在卡片上。
    @State private var targeted = false
    /// 一次回答收尾时的短暂表态（答完、失败），过了回常态。
    @State private var pulse: PandaPulse?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var center: AIChatCenter { AIChatCenter.shared }
    private var services: [AIService] { AIServices.enabled(in: config) }
    private var square: Bool { AIServices.isSquare(config) }
    private var keySide: CGFloat { CGFloat(AIServices.keySide) }
    private var keySpacing: CGFloat { CGFloat(AIServices.keySpacing) }

    var body: some View {
        let shown = services
        let defaultID = AIServices.defaultService(in: config, enabled: shown)?.id
        let currentID = AIServices.currentKeyID(lastUsed: context.isPreview ? nil : center.current?.id,
                                                in: shown, defaultID: defaultID)
        let current = shown.first { $0.id == currentID }
        let phase = context.isPreview ? nil : center.pandaPhase(current)
        return WidgetSurface {
            if context.position.isVertical {
                if square {
                    tallSquare(current, phase: phase)
                } else {
                    column(shown, currentID: currentID, defaultID: defaultID, phase: phase)
                }
            } else if square {
                compact(current, phase: phase)
            } else {
                wide(shown, currentID: currentID, defaultID: defaultID, phase: phase)
            }
        }
        .onChange(of: phase) { old, new in
            if let next = PandaStateResolver.aiPulse(from: old, to: new, at: .now) { pulse = next }
        }
        // 表态到期：清掉，状态回到常态。
        .task(id: pulse) {
            guard let pulse else { return }
            let left = pulse.until.timeIntervalSinceNow
            if left > 0 { try? await Task.sleep(for: .seconds(left + 0.05)) }
            guard !Task.isCancelled else { return }
            self.pulse = nil
        }
        // 拖文字或文件过来：蓝色虚线框写“拿去问 AI”，松手打开提问面板并带进去。
        .dropTargetOutline(targeted, prompt: .askAI, compact: context.position.isVertical)
        .onDrop(of: [.fileURL, .url, .plainText], delegate: ContentDropDelegate(
            types: [.fileURL, .url, .plainText],
            enabled: !context.isPreview,
            targeted: { targeted = $0 },
            receive: { things in AIDropRouter.ask(things, instance: instance) }))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI 助手")
    }

    private func status(_ phase: AIQuickResultPhase?) -> AIDockStatus {
        AIDockStatus.resolve(base: PandaStateResolver.aiBase(phase), pulse: pulse, now: .now)
    }

    // MARK: Layouts

    /// 横版：小熊猫、分隔线、一排模型键和“＋”。宽度按键数算（`AIServices.tileWidth`），
    /// 实际给的宽度不够时按 `keyCapacity` 少画几块。
    private func wide(_ shown: [AIService], currentID: String?, defaultID: String?,
                      phase: AIQuickResultPhase?) -> some View {
        GeometryReader { proxy in
            let capacity = AIServices.keyCapacity(contentWidth: Double(proxy.size.width))
            let visible = AIServices.shelfKeys(shown, currentID: currentID, capacity: capacity)
            HStack(spacing: 6) {
                pandaButton(size: 38, phase: phase)
                divider(vertical: true)
                if shown.isEmpty {
                    addButton
                } else {
                    HStack(spacing: keySpacing) {
                        ForEach(visible) {
                            key($0, size: keySide, isCurrent: $0.id == currentID,
                                isDefault: $0.id == defaultID)
                        }
                        plusButton(size: keySide)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: 竖版：状态陪伴卡

    /// 竖版横放（108×62）：左边对着笔记本的小熊猫（比横版占比大），右边一块读得清的玻璃
    /// 上写「问 AI」和一行提示或状态。整块点一下开始提问；右键里有「截图提问」
    /// （扩展栏菜单）。模型字母和 chevron 是横版的事，这里不画。
    private func compact(_ current: AIService?, phase: AIQuickResultPhase?) -> some View {
        let now = status(phase)
        return askButton(current, status: now) {
            HStack(spacing: 3) {
                pandaArt(size: 40, phase: phase, pose: PandaStateResolver.aiDockPose(phase), status: now)
                companionText(now, titleSize: 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 竖版在侧边栏（76×112）：小熊猫在上占大半，下面同一块玻璃写「问 AI」和提示或状态。
    private func tallSquare(_ current: AIService?, phase: AIQuickResultPhase?) -> some View {
        let now = status(phase)
        return askButton(current, status: now) {
            VStack(spacing: 2) {
                pandaArt(size: 50, phase: phase, pose: PandaStateResolver.aiDockPose(phase), status: now)
                companionText(now, titleSize: 15)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 「问 AI」加一行提示或状态，垫一层读得清的玻璃。「问 AI」总留着；提示行先试整句
    /// （「可以试试：截图提问」），放不下用短的（「截图提问」），最多两行，再放不下截断。
    /// 空闲时每 `AIDockTips.interval` 秒换一条，减弱动态效果时只显示第一条不轮换；
    /// 生成中、完成、出错显示真实状态（只有 API 方式有）。
    private func companionText(_ status: AIDockStatus, titleSize: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let rotates = status == .idle && hints.count > 1 && !reduceMotion
        return VStack(alignment: .leading, spacing: 1) {
            askTitle(size: titleSize)
            if rotates {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: AIDockTips.interval)) { timeline in
                    hintLine(AIDockTips.hint(for: status, hints: hints,
                                             index: AIDockTips.index(at: timeline.date, count: hints.count,
                                                                     reduceMotion: reduceMotion)),
                             status: status)
                }
            } else {
                hintLine(AIDockTips.hint(for: status, hints: hints, index: 0), status: status)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .readableGlass(in: shape)
    }

    private func hintLine(_ hint: AIDockHint, status: AIDockStatus) -> some View {
        ViewThatFits(in: .horizontal) {
            hintText(hint.full, status: status, lines: 1)
            hintText(hint.short, status: status, lines: 2)
        }
        .id(hint)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: hint)
    }

    private func hintText(_ text: String, status: AIDockStatus, lines: Int) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(status == .idle ? WidgetStyle.secondary : WidgetStyle.primary)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: lines == 1, vertical: lines > 1)
    }

    private func askTitle(size: CGFloat) -> some View {
        Text("问 AI")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(WidgetStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(13 / size)
            .layoutPriority(1)
    }

    /// 设置里勾选的快捷操作名（和面板玻璃块同名），轮换着当提示。
    private var hints: [AIDockHint] {
        AIDockTips.hints(AIDockChips.resolved(center.settings.panelChips).map(\.gridTitle))
    }

    /// 整块都是打开助手的按钮，和横版的小熊猫做同一件事。
    private func askButton<Label: View>(_ current: AIService?, status: AIDockStatus,
                                        @ViewBuilder _ label: () -> Label) -> some View {
        Button {
            ask()
        } label: {
            label().contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(current.map { tr("用 \($0.title) 打开助手") } ?? tr("问问 AI"))
        .accessibilityLabel("打开 AI 助手")
        .accessibilityValue(AIDockTips.hint(for: status, hints: hints, index: 0).full)
    }

    /// 打开助手：当前服务是网页或 API 时打开刘海里的同一个对话；是跳转（或没解锁刘海对话）
    /// 时照旧打开原来的提问面板。
    private func ask() {
        guard !context.isPreview else { return }
        if AINotchController.shared.openFromShelf(instance) { return }
        AIPanelState.shared.requestPanel(instance.id, mode: .ask, toggle: true)
    }

    /// 点模型键：用这个模型打开助手。它是网页或 API 方式时打开刘海对话并切到它；
    /// 是跳转（或没解锁刘海对话）时直接打开它的 App 或网页。都会记成当前模型。
    private func open(_ service: AIService) {
        guard !context.isPreview else { return }
        center.select(service.id)
        if AINotchController.shared.openFromShelf(instance, preferring: service.id) { return }
        AIServiceOpener.open(service)
    }

    private func column(_ shown: [AIService], currentID: String?, defaultID: String?,
                        phase: AIQuickResultPhase?) -> some View {
        let count = AIServices.visibleCount(shown.count, square: square, vertical: true)
        let visible = AIServices.shelfKeys(shown, currentID: currentID, capacity: count)
        return VStack(spacing: 6) {
            pandaButton(size: 34, phase: phase)
            LazyVGrid(columns: [GridItem(.fixed(keySide), spacing: keySpacing),
                                GridItem(.fixed(keySide), spacing: keySpacing)],
                      spacing: keySpacing) {
                ForEach(visible) {
                    key($0, size: keySide, isCurrent: $0.id == currentID, isDefault: $0.id == defaultID)
                }
                plusButton(size: keySide)
            }
        }
    }

    private func divider(vertical: Bool) -> some View {
        Rectangle()
            .fill(WidgetStyle.primary.opacity(0.14))
            .frame(width: vertical ? 1 : 30, height: vertical ? 34 : 1)
            .accessibilityHidden(true)
    }

    // MARK: Pieces

    /// 小熊猫：用六状态的素材，生成中换「等回答」那张，答完、出错短暂表态。
    /// 竖版传进来笔记本场景（`aiDockPose`）和状态，右上角画状态点（待命不画）。
    private func pandaArt(size: CGFloat, phase: AIQuickResultPhase?, pose: PandaPose? = nil,
                          status: AIDockStatus? = nil) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear.contentShape(.rect)
            PandaStateView(pose: pose ?? PandaStateResolver.aiPose(phase, typing: false), pulse: pulse, size: size,
                           fallbackSymbol: "bubble.left.and.text.bubble.right.fill")
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if let status, status != .idle {
                Circle()
                    .fill(Color(hex: status.dotHex))
                    .frame(width: 7, height: 7)
                    .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                    .accessibilityHidden(true)
            }
        }
    }

    /// 横版和侧边栏的小熊猫按钮：打开助手（当前模型）。
    private func pandaButton(size: CGFloat, phase: AIQuickResultPhase?) -> some View {
        Button {
            ask()
        } label: {
            pandaArt(size: size, phase: phase)
        }
        .buttonStyle(.plain)
        .help("问问 AI")
        .accessibilityLabel("打开 AI 助手")
        .accessibilityValue(status(phase).title)
    }

    private func key(_ service: AIService, size: CGFloat, isCurrent: Bool, isDefault: Bool) -> some View {
        Button {
            open(service)
        } label: {
            AIShelfKey(label: AIServices.keyLabel(service), size: size, isCurrent: isCurrent)
        }
        .buttonStyle(.plain)
        .help(isDefault ? tr("用 \(service.title) 打开助手（默认）") : tr("用 \(service.title) 打开助手"))
        .accessibilityLabel(tr("用 \(service.title) 打开助手"))
        .accessibilityValue(isCurrent ? tr("当前模型") : "")
        .contextMenu {
            Button(isDefault ? tr("已是默认") : tr("设为默认")) { change { AIServices.setDefault(service.id, in: &$0) } }
                .disabled(isDefault)
            Button("左移") { change { AIServices.move(service.id, by: -1, in: &$0) } }
                .disabled(!AIServices.canMove(service.id, by: -1, in: config))
            Button("右移") { change { AIServices.move(service.id, by: 1, in: &$0) } }
                .disabled(!AIServices.canMove(service.id, by: 1, in: config))
            Divider()
            Button(tr("隐藏", context: "verb"), role: .destructive) { change { AIServices.hide(service.id, in: &$0) } }
        }
    }

    private func plusButton(size: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            AIServiceMenu.popUp(for: instance)
        } label: {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(WidgetStyle.primary.opacity(0.32),
                              style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary.opacity(0.8))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("管理更多模型")
        .accessibilityLabel("管理更多模型")
    }

    /// 一块模型键都没有时：明明白白的“添加”。
    private var addButton: some View {
        Button {
            guard !context.isPreview else { return }
            AIServiceMenu.popUp(for: instance)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text("添加").font(WidgetStyle.label(13))
            }
            .foregroundStyle(WidgetStyle.primary)
            .frame(width: 52, height: 26)
            .background {
                Capsule().strokeBorder(WidgetStyle.primary.opacity(0.38),
                                       style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("还没有 AI 字牌，点这里添加")
        .accessibilityLabel("添加 AI 字牌")
    }

    private func change(_ edit: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance, edit)
    }
}

// MARK: - Shelf key

/// 扩展栏上的模型键：一块读得清的玻璃方键上一个字。当前模型暖橙描边、浅橙底，右上一个小橙点。
struct AIShelfKey: View {
    var label: String
    var size: CGFloat
    var isCurrent: Bool

    @Environment(\.colorScheme) private var scheme

    /// 浅色下压深一点，字和描边在浅底上读得清；深色下提亮。
    private var accent: Color { Color(hex: scheme == .dark ? "#F39A6B" : "#C9572B") }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Text(label)
            .font(.system(size: size * (label.count > 1 ? 0.4 : 0.5), weight: .bold, design: .rounded))
            .foregroundStyle(isCurrent ? accent : WidgetStyle.primary.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background {
                if isCurrent { shape.fill(accent.opacity(scheme == .dark ? 0.2 : 0.12)) }
            }
            .readableGlass(in: shape)
            .overlay {
                shape.strokeBorder(isCurrent ? accent.opacity(0.85) : WidgetStyle.primary.opacity(0.14),
                                   lineWidth: isCurrent ? 1.25 : 0.75)
            }
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .offset(x: 1.5, y: -1.5)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
            .accessibilityHidden(true)
    }
}

// MARK: - Glyph

/// 单色玻璃字牌：半透明方块上一个字。
struct AIGlyph: View {
    enum Style { case shelf, panel }

    var initial: String
    var size: CGFloat
    var isDefault = false
    var style: Style = .shelf

    private var ink: Color { style == .panel ? .panelPrimary : WidgetStyle.primary }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(ink.opacity(style == .panel ? 0.12 : 0.09))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [ink.opacity(0.32), ink.opacity(0.06)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.75)
            }
            .overlay {
                Text(initial)
                    .font(.system(size: size * (initial.count > 1 ? 0.36 : 0.46), weight: .semibold,
                                  design: .rounded))
                    .foregroundStyle(ink.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if isDefault {
                    Circle()
                        .fill(Color(hex: AIGlyph.dotHex))
                        .frame(width: max(5, size * 0.24), height: max(5, size * 0.24))
                        .offset(x: size * 0.1, y: -size * 0.1)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    static let dotHex = "#4C9BFF"
}

/// 小熊猫头像，用电子宠物的那张。读不到图（截图工具里）时画个符号。
struct AIPandaAvatar: View {
    var size: CGFloat
    /// 哪一张：平时是站着的，竖版用举手欢呼的那张。
    var pose: String = AIPandaArt.name

    var body: some View {
        Group {
            if let image = AIPandaArt.image(pose) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color(hex: ShelfColor.redPanda.hex))
            }
        }
        .frame(width: size, height: size)
        .contentShape(.rect)
        .accessibilityHidden(true)
    }
}

@MainActor
enum AIPandaArt {
    static let name = "pet-panda-idle"
    static let cheer = "pet-panda-cheer"
    private static var cached: [String: NSImage?] = [:]

    static var image: NSImage? { image(name) }

    /// 站着、欢呼这两张先找六状态的正式素材（待机、完成），全局同一套外观；缺图用原来的。
    static func image(_ pose: String) -> NSImage? {
        if let known = cached[pose] { return known }
        let migrated = PandaStateResolver.migratedName(pose, exists: { PandaStateArt.exists($0) })
        let loaded = migrated != pose ? PandaStateArt.image(migrated)
            : Bundle.main.url(forResource: pose, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        cached[pose] = loaded
        return loaded
    }
}

// MARK: - The plus menu

/// “＋”弹出的菜单：国内、国外两组，打勾的显示在卡片上，最后是“自定义…”。
///
/// 系统菜单点一项就收起，而设计要能连着勾几个，所以勾完一项后在原地再弹
/// 一次，直到用户点到菜单外面或选了“自定义…”。每次都按刚写下的设置重画。
@MainActor
final class AIServiceMenu: NSObject {
    private enum Choice { case toggle(String), custom }

    private var choice: Choice?
    private let config: WidgetConfig

    private init(config: WidgetConfig) {
        self.config = config
    }

    static func popUp(for instance: WidgetInstance) {
        var current = instance
        let origin = NSEvent.mouseLocation
        // 有上限，免得哪里出了岔子停不下来。
        for _ in 0 ..< 40 {
            let picker = AIServiceMenu(config: current.config)
            let menu = picker.build()
            _ = menu.popUp(positioning: nil, at: origin, in: nil)
            switch picker.choice {
            case .toggle(let id)?:
                AIServices.toggle(id, in: &current.config)
                WidgetWriter.update(current)
            case .custom?:
                AIPanelState.shared.requestPanel(current.id, mode: .manage, customForm: true)
                return
            case nil:
                return
            }
        }
    }

    private func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let enabled = Set(AIServices.enabled(in: config).map(\.id))
        let full = enabled.count >= AIServices.maxCount
        for region in AIService.Region.allCases {
            menu.addItem(.sectionHeader(title: region.title))
            for service in AIServices.builtIn where service.region == region {
                menu.addItem(item(service, on: enabled.contains(service.id), full: full))
            }
            menu.addItem(.separator())
        }
        let custom = AIServices.custom(in: config)
        if !custom.isEmpty {
            menu.addItem(.sectionHeader(title: tr("自定义")))
            for service in custom {
                menu.addItem(item(service, on: enabled.contains(service.id), full: full))
            }
            menu.addItem(.separator())
        }
        let add = NSMenuItem(title: tr("自定义…"), action: #selector(pickCustom), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        return menu
    }

    private func item(_ service: AIService, on: Bool, full: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: service.title, action: #selector(pick(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = service.id
        item.state = on ? .on : .off
        item.isEnabled = on || !full
        item.image = Self.glyph(service.initial)
        item.setAccessibilityLabel(on ? tr("隐藏 \(service.title)") : tr("显示 \(service.title)"))
        return item
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        choice = .toggle(id)
    }

    @objc private func pickCustom() {
        choice = .custom
    }

    /// 菜单里的小字牌，模板图，跟着菜单的明暗变色。
    private static func glyph(_ initial: String) -> NSImage? {
        let renderer = ImageRenderer(content:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                .frame(width: 16, height: 16)
                .overlay {
                    Text(initial)
                        .font(.system(size: initial.count > 1 ? 7 : 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                }
        )
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}
