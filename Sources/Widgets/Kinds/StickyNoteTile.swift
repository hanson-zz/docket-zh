import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 便签：一张长期贴着的纸（160×100，始终展开；底栏上实际 58pt 高）。
///
/// 纸感卡片：小圆角、顶上一条半透明胶带、右下角卷起，手写字。可以叠几张
/// （最多 10 张，见 `StickyStack`），每张一种颜色，后面的露出纸边；右下角的
/// “1/3”点一下翻到下一张；指针停在便签上用滚轮或触控板滚动也能前后翻（往下
/// 是下一张，往上是上一张，一下手势翻一张）。减少动态效果时直接换，不做动画。
/// 不会自动清空，一直贴着直到自己撕掉。字体字号按面板里选的；清单项在卡片上
/// 只画成 ☐ / ☑，勾在面板里点。
///
/// The words are only shown here; they are written in the note's detail panel,
/// on paper the size of something you write on rather than glance at. A field
/// on the tile cannot coexist with that: the caret would swallow the click that
/// opens the panel, and the shelf is a non-activating panel, so a click on the
/// paper had to beg for key status before a single letter could land.
struct StickyNoteTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 拖着文字停在便签上。
    @State private var targeted = false

    private var unlocked: Bool { ProAccess.isUnlocked || context.isPreview }

    private var pile: StickyStack.Pile {
        if context.isPreview {
            // 添加面板里的样例：三张叠着，看得出能放几张。
            return StickyStack.Pile(sheets: [StickySheet(text: tr("买咖啡\n给小王回电话"), color: PaperColor.cream.rawValue),
                                             StickySheet(color: PaperColor.pink.rawValue),
                                             StickySheet(color: PaperColor.mint.rawValue)])
        }
        return StickyStack.pile(instance.config)
    }

    var body: some View {
        // A column is the same paper card, just narrower and taller: smaller
        // ink, one more line, and the text shrinks a little rather than
        // trailing off in an ellipsis inside 56pt of usable width.
        let column = context.position.isVertical
        let pile = self.pile
        let front = pile.front.paper(unlocked: unlocked)
        // 纸自己就是卡片：底板透明，纸铺在卡片里，四边留一点让叠着的纸边露出来。
        return WidgetSurface(fill: .clear) {
            ZStack {
                ForEach(Array(pile.behind.prefix(2).enumerated().reversed()), id: \.offset) { index, sheet in
                    StickyPaper(color: sheet.paper(unlocked: unlocked), tape: false, curl: false)
                        .rotationEffect(.degrees(index == 0 ? 2.2 : 4))
                        .offset(x: CGFloat(index + 1) * 2, y: -CGFloat(index + 1) * 1.5)
                }
                StickyPaper(color: front, tape: true, curl: true)
                    .overlay { words(pile.front.text, ink: Color(hex: front.inkHex), column: column) }
                    .rotationEffect(.degrees(-0.8))
                    .id(pile.page)
                    .transition(reduceMotion ? AnyTransition.identity
                                : AnyTransition.asymmetric(insertion: .opacity,
                                                           removal: AnyTransition.offset(x: -18, y: 0).combined(with: .opacity)))
            }
            .padding(.horizontal, -WidgetStyle.inset + (column ? 5 : 6))
            .padding(.top, 6)
            .padding(.bottom, 5)
            .overlay(alignment: .bottomTrailing) {
                if let marker = pile.marker { flipButton(marker, ink: Color(hex: front.inkHex)) }
            }
            // 只接滚动，点击照样穿过去（打开面板、点“1/3”）。
            .overlay {
                StickyScrollPager(enabled: pile.count > 1 && !context.isPreview) { step in flip(by: step) }
            }
            .dropHidden(targeted)
        }
        // 拖文字或链接过来：橙色虚线框写“贴到便签上 / 在最后追加一行”，松手接在最上面那张末尾。
        .dropTargetOutline(targeted, prompt: .stickyNote, compact: column)
        .onDrop(of: [.plainText, .url], delegate: ContentDropDelegate(
            types: [.plainText, .url],
            enabled: !context.isPreview,
            targeted: { targeted = $0 },
            receive: { things in StickyDrop.append(things, to: instance) }))
    }

    /// 字：手写体，最上面那张的。空白的纸画两条横线和一支铅笔。
    @ViewBuilder
    private func words(_ text: String, ink: Color, column: Bool) -> some View {
        if text.isEmpty {
            blankPaper(ink: ink, column: column)
        } else {
            // 字号放大、最多只缩到 0.9 倍：原来 14pt 缩到 0.75 倍，58pt 高的卡上
            // 只剩 10pt 出头，手札体笔画又细，看不清。宁可少一行、尾巴省略。
            let noteFont = StickyNoteFont.of(instance.config)
            let noteSize = StickyNoteSize.of(instance.config)
            Text(verbatim: StickyChecklist.display(text))
                .font(StickyFont.font(noteFont, size: CGFloat(StickyNoteType.card(noteFont, noteSize, column: column))))
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .lineSpacing(-1)
                .lineLimit(column ? 4 : 3)
                .minimumScaleFactor(StickyFont.minimumScale)
                .truncationMode(.tail)
                .padding(.horizontal, column ? 6 : 9)
                .padding(.top, column ? 7 : 8)
                .padding(.bottom, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // No button trait: the note itself is read, not activated -
                // writing is its own control and the card belongs to the shelf.
                .accessibilityLabel(tr("便签：\(text)"))
        }
    }

    /// 翻下一张：右下角的“1/3”。只有一张时没有。
    private func flipButton(_ marker: String, ink: Color) -> some View {
        Button {
            flip()
        } label: {
            Text(marker)
                .font(.system(size: 9, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.5)))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .padding(.trailing, 9)
        .padding(.bottom, 8)
        .help(tr("翻到下一张便签"))
        .accessibilityLabel(tr("第 \(pile.page + 1) 张，共 \(pile.count) 张，翻到下一张"))
    }

    private func flip(by step: Int = 1) {
        guard !context.isPreview else { return }
        // 减少动态效果时直接换成那一张。
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        withAnimation(animation) { StickyLog.flip(instance, by: step) }
    }

    /// Ruled lines under a pencil, at the weight of a watermark.
    ///
    /// Drawn in the ink colour rather than grey: every paper swatch is light
    /// in both appearances, so a semantic grey would go white in the dark and
    /// disappear. Opacity does the work instead, which keeps it a hint at any
    /// paper colour.
    private func blankPaper(ink: Color, column: Bool) -> some View {
        VStack(alignment: .leading, spacing: column ? 5 : 6) {
            Image(systemName: "pencil.line")
                .font(.system(size: column ? 11 : 12, weight: .semibold))
                .foregroundStyle(ink.opacity(0.28))
            ForEach(0..<2, id: \.self) { line in
                Capsule()
                    .fill(ink.opacity(0.14))
                    // The second line is shorter, the way a written one runs
                    // out. Equal lines read as a loading skeleton.
                    .frame(width: line == 0 ? nil : 34, height: 2)
            }
        }
        .padding(.horizontal, column ? 6 : 9)
        .padding(.top, column ? 8 : 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(tr("空白便签"))
    }
}

/// 一张纸：小圆角、一点投影；最上面那张顶上一条胶带、右下角卷起。
struct StickyPaper: View {
    var color: PaperColor
    var tape: Bool
    var curl: Bool
    /// 面板里的大纸角卷得大一些。
    var curlSize: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        shape
            .fill(Color(hex: color.hex))
            .shadow(color: .black.opacity(0.28), radius: 1.5, x: 1, y: 1.5)
            .overlay(alignment: .bottomTrailing) {
                if curl { StickyCurl(dark: color.isDark).frame(width: curlSize, height: curlSize) }
            }
            .overlay(alignment: .top) {
                if tape {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.white.opacity(color.isDark ? 0.28 : 0.45))
                        .frame(width: 30, height: 9)
                        .rotationEffect(.degrees(-4))
                        .offset(y: -3)
                }
            }
    }
}

/// 右下角卷起的纸角：一块阴影加一块翻过来的浅色三角。
private struct StickyCurl: View {
    var dark: Bool

    var body: some View {
        Canvas { canvas, size in
            let w = size.width, h = size.height
            var shadow = Path()
            shadow.move(to: CGPoint(x: w, y: 0))
            shadow.addLine(to: CGPoint(x: 0, y: h))
            shadow.addLine(to: CGPoint(x: w * 0.6, y: h))
            shadow.addQuadCurve(to: CGPoint(x: w, y: h * 0.6), control: CGPoint(x: w, y: h))
            shadow.closeSubpath()
            canvas.fill(shadow, with: .color(.black.opacity(0.12)))
            var flap = Path()
            flap.move(to: CGPoint(x: w, y: 0))
            flap.addLine(to: CGPoint(x: 0, y: h))
            flap.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w * 0.25, y: h * 0.25))
            flap.closeSubpath()
            canvas.fill(flap, with: .color(.white.opacity(dark ? 0.25 : 0.5)))
        }
        .allowsHitTesting(false)
    }
}

/// 便签的手写字：优先系统的“手札体”（Hannotate SC），没有就回退系统圆体。
///
/// 先试 W7（更粗），细的 W5 放后面：卡片上字只有 15pt，W5 的笔画在中间色纸上
/// 发虚。手札体是按需下载的字体，很多 Mac 没装，回退时用圆体 semibold，
/// 和手写的气质最接近，又比默认字体粗一档。
enum StickyFont {
    /// 卡片（横排）和竖排时的字号。
    static let cardSize: CGFloat = 15
    static let columnSize: CGFloat = 12
    /// 最多缩到 0.9 倍，放不下就少一行。
    static let minimumScale: CGFloat = 0.9

    /// 手札体的几种字重，按想要的先后试。
    private static let names = ["HannotateSC-W7", "HannotateSC-W5"]

    @MainActor private static var resolved: String?? = nil

    /// 按便签设置的字体：手写、普通（系统字体）、等宽。
    @MainActor
    static func font(_ kind: StickyNoteFont, size: CGFloat) -> Font {
        switch kind {
        case .hand: hand(size: size)
        case .regular: .system(size: size, weight: .medium)
        case .mono: .system(size: size, weight: .medium, design: .monospaced)
        }
    }

    /// 面板编辑器（AppKit）用的同一套字体。
    @MainActor
    static func nsFont(_ kind: StickyNoteFont, size: CGFloat) -> NSFont {
        switch kind {
        case .hand:
            if let name = handName, let font = NSFont(name: name, size: size) { return font }
            let base = NSFont.systemFont(ofSize: size, weight: .semibold)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case .regular: return .systemFont(ofSize: size, weight: .medium)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .medium)
        }
    }

    @MainActor private static var handName: String? {
        if resolved == nil {
            let installed = Set(NSFontManager.shared.availableFonts)
            resolved = .some(names.first { installed.contains($0) })
        }
        return resolved ?? nil
    }

    @MainActor
    static func hand(size: CGFloat) -> Font {
        if resolved == nil {
            // 只探测已安装字体。直接按名称解析缺失的按需字体会等待系统字体服务，
            // 无人值守的 runner 上可能长时间没有响应。
            let installed = Set(NSFontManager.shared.availableFonts)
            resolved = .some(names.first { installed.contains($0) })
        }
        if let name = resolved ?? nil {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }
}

/// 卡片和面板对便签的几种写法，都从现在保存着的那份改，两边不会打架。
@MainActor
enum StickyLog {
    private static func latest(_ instance: WidgetInstance) -> WidgetInstance {
        WidgetWriter.current(instance.id) ?? instance
    }

    static func change(_ instance: WidgetInstance, _ edit: (StickyStack.Pile) -> StickyStack.Pile) {
        WidgetWriter.write(latest(instance)) { config in
            StickyStack.store(edit(StickyStack.pile(config)), in: &config)
        }
    }

    static func flip(_ instance: WidgetInstance, by step: Int = 1) { change(instance) { $0.flipped(by: step) } }

    static func write(_ text: String, in instance: WidgetInstance) { change(instance) { $0.writing(text) } }

    static func color(_ color: PaperColor, in instance: WidgetInstance) {
        change(instance) { $0.coloring(color.rawValue) }
    }

    static func addSheet(_ instance: WidgetInstance) {
        change(instance) { $0.adding(color: StickyStack.nextColor(after: $0)) }
    }

    static func tearOff(_ instance: WidgetInstance) { change(instance) { $0.removingFront() } }

    /// 直接改配置：撕掉、撤销、垃圾桶这些要同时动叠放和垃圾桶的。
    static func mutate(_ instance: WidgetInstance, _ edit: (inout WidgetConfig) -> Void) {
        WidgetWriter.write(latest(instance), edit)
    }

    /// 「已完成沉到底部」。
    static func setSink(_ on: Bool, in instance: WidgetInstance) {
        WidgetWriter.write(latest(instance)) { config in config.set(StickyChecklist.sinkKey, .bool(on)) }
    }

    /// 打开垃圾桶时把过期的真的清掉；没有过期的不写。
    static func purgeTrash(_ instance: WidgetInstance) {
        var probe = latest(instance).config
        guard StickyTrash.purge(&probe, now: Date()) else { return }
        mutate(instance) { config in _ = StickyTrash.purge(&config, now: Date()) }
    }

    static func restore(_ id: String, in instance: WidgetInstance) {
        mutate(instance) { config in _ = StickyTrash.restore(id, in: &config, now: Date()) }
    }

    static func deleteForever(_ id: String, in instance: WidgetInstance) {
        mutate(instance) { config in StickyTrash.delete(id, in: &config, now: Date()) }
    }

    static func emptyTrash(_ instance: WidgetInstance) {
        mutate(instance) { config in StickyTrash.empty(&config) }
    }

    /// 字体、字号：整张便签一起改，不动纸和字。
    static func style(_ key: String, _ value: String, in instance: WidgetInstance) {
        WidgetWriter.write(latest(instance)) { config in config.set(key, .string(value)) }
    }
}

/// 便签上的滚轮和触控板翻页。
///
/// 扩展栏的滚动是整个承载视图自己接的（`ScrollingHostingView`），卡片上的 SwiftUI
/// 拿不到。这里垫一层只在“当前事件是滚动”时才应答命中测试的视图：滚动落到它，
/// 点击和悬停照样穿过去交给下面的便签和“1/3”。只有一张时不接，滚动照旧滚扩展栏；
/// 按着 Command 的滚动（切换布局）也交回去。一下手势翻一张，滚轮一格翻一张，
/// 节奏和切换布局的手势一样（`LayoutGesture`）。
struct StickyScrollPager: NSViewRepresentable {
    var enabled: Bool
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> PagerView {
        let view = PagerView()
        view.enabled = enabled
        view.onStep = onStep
        return view
    }

    func updateNSView(_ view: PagerView, context: Context) {
        view.enabled = enabled
        view.onStep = onStep
    }

    final class PagerView: NSView {
        var enabled = false
        var onStep: ((Int) -> Void)?
        private var gesture = LayoutGesture()

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard enabled, NSApp.currentEvent?.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            guard enabled, !event.modifierFlags.contains(.command) else {
                super.scrollWheel(with: event)
                return
            }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { gesture.begin() }
            // 惯性的尾巴吞掉但不算数，手指已经决定了翻不翻。
            guard event.momentumPhase.isEmpty else { return }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let delta = abs(dx) > abs(dy) ? dx : dy
            if let step = gesture.feed(Double(delta), precise: event.hasPreciseScrollingDeltas,
                                       at: event.timestamp) {
                onStep?(step)
            }
        }
    }
}
