import AppKit
import SwiftUI

/// AI 助手：最左边是小熊猫（点它打开提问面板），一道细分隔线，后面是勾选
/// 的 AI 服务字牌（单色玻璃字牌，首字或短缩写，不用官方图标），末尾一块
/// 虚线“＋”。默认服务的字牌右上角有一个小蓝点。
///
/// 点字牌：装了它的 Mac App 就开 App，否则开网页。右键字牌：设为默认、
/// 左移、右移、隐藏。点“＋”：按国内、国外列出全部服务，打勾的显示在卡片
/// 上，最后一项“自定义…”。右键卡片别处是扩展栏自己的菜单，里面加了
/// “打开提问面板”和“管理字牌…”。
struct AIAssistantTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var config: WidgetConfig { instance.config }
    private var services: [AIService] { AIServices.enabled(in: config) }
    private var square: Bool { AIServices.isSquare(config) }

    var body: some View {
        let shown = services
        let defaultID = AIServices.defaultService(in: config, enabled: shown)?.id
        return WidgetSurface {
            if context.position.isVertical {
                column(shown, defaultID: defaultID)
            } else if square {
                compact(shown, defaultID: defaultID)
            } else {
                wide(shown, defaultID: defaultID)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI 助手")
    }

    // MARK: Layouts

    private func wide(_ shown: [AIService], defaultID: String?) -> some View {
        let visible = Array(shown.prefix(AIServices.visibleCount(shown.count, square: false, vertical: false)))
        return HStack(spacing: 6) {
            pandaButton(size: 38)
            divider(vertical: true)
            if visible.isEmpty {
                addButton
            } else {
                HStack(spacing: 5) {
                    ForEach(visible) { letter($0, size: 24, isDefault: $0.id == defaultID) }
                    plusButton(size: 24)
                }
            }
        }
    }

    private func compact(_ shown: [AIService], defaultID: String?) -> some View {
        let visible = Array(shown.prefix(AIServices.visibleCount(shown.count, square: true, vertical: false)))
        return HStack(spacing: 6) {
            pandaButton(size: 34)
            if visible.isEmpty {
                plusButton(size: 26)
            } else {
                LazyVGrid(columns: [GridItem(.fixed(22), spacing: 4), GridItem(.fixed(22), spacing: 4)],
                          spacing: 4) {
                    ForEach(visible) { letter($0, size: 22, isDefault: $0.id == defaultID) }
                    plusButton(size: 22)
                }
                .frame(width: 48)
            }
        }
    }

    private func column(_ shown: [AIService], defaultID: String?) -> some View {
        let visible = Array(shown.prefix(AIServices.visibleCount(shown.count, square: square, vertical: true)))
        return VStack(spacing: 6) {
            pandaButton(size: 34)
            LazyVGrid(columns: [GridItem(.fixed(24), spacing: 5), GridItem(.fixed(24), spacing: 5)],
                      spacing: 5) {
                ForEach(visible) { letter($0, size: 24, isDefault: $0.id == defaultID) }
                plusButton(size: 24)
            }
        }
    }

    private func divider(vertical: Bool) -> some View {
        Rectangle()
            .fill(WidgetStyle.primary.opacity(0.14))
            .frame(width: vertical ? 1 : 30, height: vertical ? 30 : 1)
            .accessibilityHidden(true)
    }

    // MARK: Pieces

    /// 小熊猫：点开提问面板，再点一次关上（面板开着时扩展栏照常切换）。
    private func pandaButton(size: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            AIPanelState.shared.requestPanel(instance.id, mode: .ask, toggle: true)
        } label: {
            AIPandaAvatar(size: size)
        }
        .buttonStyle(.plain)
        .help("问问 AI")
        .accessibilityLabel("打开提问面板")
    }

    private func letter(_ service: AIService, size: CGFloat, isDefault: Bool) -> some View {
        Button {
            guard !context.isPreview else { return }
            AIServiceOpener.open(service)
        } label: {
            AIGlyph(initial: service.initial, size: size, isDefault: isDefault, style: .shelf)
        }
        .buttonStyle(.plain)
        .help(isDefault ? "\(service.title)（默认）" : service.title)
        .accessibilityLabel("打开 \(service.title)")
        .accessibilityHint(isDefault ? "默认的提问服务" : "")
        .contextMenu {
            Button(isDefault ? "已是默认" : "设为默认") { change { AIServices.setDefault(service.id, in: &$0) } }
                .disabled(isDefault)
            Button("左移") { change { AIServices.move(service.id, by: -1, in: &$0) } }
                .disabled(!AIServices.canMove(service.id, by: -1, in: config))
            Button("右移") { change { AIServices.move(service.id, by: 1, in: &$0) } }
                .disabled(!AIServices.canMove(service.id, by: 1, in: config))
            Divider()
            Button("隐藏", role: .destructive) { change { AIServices.hide(service.id, in: &$0) } }
        }
    }

    private func plusButton(size: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            AIServiceMenu.popUp(for: instance)
        } label: {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(WidgetStyle.primary.opacity(0.38),
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
        .help("显示或隐藏 AI 字牌")
        .accessibilityLabel("添加或隐藏 AI 字牌")
    }

    /// 一块字牌都没有时：明明白白的“添加”。
    private var addButton: some View {
        Button {
            guard !context.isPreview else { return }
            AIServiceMenu.popUp(for: instance)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text("添加").font(WidgetStyle.label(11))
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

// MARK: - Glyph

/// 单色玻璃字牌：半透明方块上一个字。
struct AIGlyph: View {
    enum Style { case shelf, panel }

    var initial: String
    var size: CGFloat
    var isDefault = false
    var style: Style = .shelf

    private var ink: Color { style == .panel ? .white : WidgetStyle.primary }

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

    var body: some View {
        Group {
            if let image = AIPandaArt.image {
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
    private static var loaded = false
    private static var cached: NSImage?

    static var image: NSImage? {
        if !loaded {
            loaded = true
            if let url = Bundle.main.url(forResource: name, withExtension: "png") {
                cached = NSImage(contentsOf: url)
            }
        }
        return cached
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
            menu.addItem(.sectionHeader(title: "自定义"))
            for service in custom {
                menu.addItem(item(service, on: enabled.contains(service.id), full: full))
            }
            menu.addItem(.separator())
        }
        let add = NSMenuItem(title: "自定义…", action: #selector(pickCustom), keyEquivalent: "")
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
        item.setAccessibilityLabel(on ? "隐藏 \(service.title)" : "显示 \(service.title)")
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
