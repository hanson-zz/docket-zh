import AppKit
import Observation
import SwiftUI
@preconcurrency import Translation

// MARK: - 状态

/// 一次截图编辑的全部状态。窗口关掉就丢，图只在内存里。
@MainActor
@Observable
final class ShotEditorModel {
    /// 上次挑的颜色和粗细，这次运行里下一张截图接着用。
    static var lastColor: ShotColor = .fallback
    static var lastStroke: ShotStroke = .fallback

    struct TextEntry: Equatable {
        /// 比例，左上角为原点。
        var point: CGPoint
        var text = ""
        var color: ShotColor
        var stroke: ShotStroke
    }

    enum TranslationState: Equatable {
        case idle
        case working(String)
        case ready
        case failed(String)
    }

    let image: CGImage
    /// 选区在窗口里的位置（点，左上角为原点）。
    let selection: CGRect
    /// 窗口（整块屏幕）的范围，工具条不出这块。
    let bounds: CGRect
    let format: CaptureFormat
    /// 这块屏幕在 AppKit 坐标里的位置，贴图换算用。
    let screenFrame: CGRect

    var document = ShotDocument()
    var tool: ShotTool?
    var color: ShotColor
    var stroke: ShotStroke
    /// 正在拖的这一笔（比例）。
    var draft: [CGPoint] = []
    var textEntry: TextEntry?
    var pixelated: CGImage?
    private var pixelatedCell: CGFloat = 0

    /// 识别出的每一行；nil 是还没识别过。
    var lines: [ShotTextBlock]?
    var paragraphs: [ShotTextBlock] = []
    var recognizing = false
    var textPanel = false

    var translation: TranslationState = .idle
    var isTranslating: Bool {
        if case .working = translation { return true }
        return false
    }
    var translationConfig: TranslationSession.Configuration?
    var overlay: [ShotImaging.OverlayPaint] = []
    var showTranslated = true

    /// Pro 没解锁：翻译、贴图按钮带小锁。
    var locked = false
    /// 工具条旁边一闪而过的一句话。
    var note: String?
    private var noteTask: Task<Void, Never>?

    init(image: CGImage, selection: CGRect, bounds: CGRect, format: CaptureFormat, screenFrame: CGRect) {
        self.image = image
        self.selection = selection
        self.bounds = bounds
        self.format = format
        self.screenFrame = screenFrame
        self.color = ShotEditorModel.lastColor
        self.stroke = ShotEditorModel.lastStroke
    }

    var size: CGSize { selection.size }
    /// 一个点等于几个像素。
    var pixelScale: CGFloat { CGFloat(image.width) / max(selection.width, 1) }

    var recognizedText: String { paragraphs.map(\.text).joined(separator: "\n") }

    var showsOverlay: Bool { translation == .ready && showTranslated }

    func flash(_ text: String) {
        note = text
        noteTask?.cancel()
        noteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.note = nil
        }
    }

    func preparePixelated() {
        let cell = stroke.mosaicCell * pixelScale
        guard pixelated == nil || pixelatedCell != cell else { return }
        pixelated = ShotImaging.pixelated(image, cell: cell)
        pixelatedCell = cell
    }

    /// 文字放进图里；空的就当没写。
    func commitText() {
        guard let entry = textEntry else { return }
        textEntry = nil
        document.add(.text, color: entry.color, stroke: entry.stroke, points: [entry.point], text: entry.text, size: size)
    }

    func finishDrag() {
        defer { draft = [] }
        guard let tool, tool.isDragged else { return }
        if tool == .mosaic { preparePixelated() }
        document.add(tool, color: color, stroke: stroke, points: draft, size: size)
    }

    func ensureLines() async {
        guard lines == nil, !recognizing else { return }
        recognizing = true
        let found = await ShotImaging.recognize(ShotImaging.Box(image: image))
        recognizing = false
        lines = found
        paragraphs = ShotTranslationLayout.paragraphs(found, imageSize: CGSize(width: image.width, height: image.height))
    }

    func applyTranslations(_ translations: [String]) {
        let heights = paragraphs.map { ShotTranslationLayout.lineHeight(of: $0, lines: lines ?? []) }
        let items = ShotTranslationLayout.overlay(paragraphs, translations: translations, lineHeights: heights, in: size)
        overlay = items.map { item in
            let normalized = CGRect(x: item.rect.minX / size.width, y: item.rect.minY / size.height,
                                    width: item.rect.width / size.width, height: item.rect.height / size.height)
            let color = ShotImaging.averageColor(image, in: normalized)
            let dark = ShotTranslationLayout.usesDarkInk(
                backgroundLuminance: ShotTranslationLayout.luminance(r: color.r, g: color.g, b: color.b))
            return ShotImaging.OverlayPaint(item: item, background: color, darkInk: dark)
        }
        if overlay.isEmpty {
            translation = .failed(tr("没有可以翻译的文字"))
        } else {
            translation = .ready
            showTranslated = true
        }
    }

    /// 存、拷贝、贴图用的原尺寸图：底图、（显示译文时）译文块、标注。
    func rendered() -> CGImage? {
        if document.marks.contains(where: { $0.tool == .mosaic }) { preparePixelated() }
        return ShotImaging.render(image, pixelated: pixelated, marks: document.marks,
                                  overlay: showsOverlay ? overlay : [], pointSize: size)
    }
}

// MARK: - 整个编辑区

struct ShotEditorView: View {
    @Bindable var model: ShotEditorModel
    var send: (ShotAction) -> Void

    @State private var blockSize: CGSize = .zero

    var body: some View {
        let origin = ShotToolbarPlacement.origin(selection: model.selection, block: blockSize, bounds: model.bounds)
        let above = ShotToolbarPlacement.isAbove(origin: origin, selection: model.selection)
        ZStack(alignment: .topLeading) {
            dim
            ShotCanvas(model: model)
                .frame(width: model.selection.width, height: model.selection.height)
                .offset(x: model.selection.minX, y: model.selection.minY)
            Rectangle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: model.selection.width + 2, height: model.selection.height + 2)
                .offset(x: model.selection.minX - 1, y: model.selection.minY - 1)
                .allowsHitTesting(false)
            ShotToolbarBlock(model: model, above: above, send: send)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { blockSize = $0 }
                .offset(x: origin.x, y: origin.y)
                .opacity(blockSize == .zero ? 0 : 1)
        }
        .frame(width: model.bounds.width, height: model.bounds.height, alignment: .topLeading)
        .translationTask(model.translationConfig) { session in
            await ShotEditor.shared.runTranslation(session, model: model)
        }
    }

    /// 选区外压暗一层。
    private var dim: some View {
        Path { path in
            path.addRect(model.bounds)
            path.addRect(model.selection)
        }
        .fill(Color.black.opacity(0.32), style: FillStyle(eoFill: true))
        .contentShape(Rectangle())
        .onTapGesture { model.commitText() }
    }
}

// MARK: - 画布

private struct ShotCanvas: View {
    @Bindable var model: ShotEditorModel
    @FocusState private var typing: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: model.image, scale: model.pixelScale)
                .resizable()
                .interpolation(.high)
            Canvas { context, size in
                if model.showsOverlay {
                    for paint in model.overlay { ShotPainter.overlay(paint, in: &context) }
                }
                for mark in model.document.marks {
                    ShotPainter.mark(mark, in: &context, size: size, pixelated: model.pixelated, scale: model.pixelScale)
                }
                if let tool = model.tool, tool.isDragged, model.draft.count > 1 {
                    let mark = ShotMark(id: 0, tool: tool, color: model.color, stroke: model.stroke, points: model.draft)
                    ShotPainter.mark(mark, in: &context, size: size, pixelated: model.pixelated, scale: model.pixelScale)
                }
            }
            .allowsHitTesting(false)
            if let entry = model.textEntry {
                textField(entry)
            }
            if case .working(let text) = model.translation {
                statusPill(text, symbol: "translate")
            } else if case .failed(let text) = model.translation {
                statusPill(text, symbol: "exclamationmark.triangle.fill")
            } else if model.recognizing {
                statusPill(tr("正在识别文字…"), symbol: "text.viewfinder")
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(drawing, including: model.tool == nil ? .subviews : .all)
        .pointerStyle(model.tool == nil ? nil : .rectSelection)
    }

    private var drawing: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let tool = model.tool else { return }
                let point = ShotGeometry.normalized(value.location, in: model.size)
                switch tool {
                case .text:
                    break
                case .pen:
                    if model.draft.isEmpty { model.draft = [ShotGeometry.normalized(value.startLocation, in: model.size)] }
                    model.draft.append(point)
                default:
                    model.draft = [ShotGeometry.normalized(value.startLocation, in: model.size), point]
                }
            }
            .onEnded { value in
                guard let tool = model.tool else { return }
                if tool == .text {
                    model.commitText()
                    model.textEntry = .init(point: ShotGeometry.normalized(value.location, in: model.size),
                                            color: model.color, stroke: model.stroke)
                    typing = true
                } else {
                    model.finishDrag()
                }
            }
    }

    private func textField(_ entry: ShotEditorModel.TextEntry) -> some View {
        let at = ShotGeometry.point(entry.point, in: model.size)
        let binding = Binding(get: { model.textEntry?.text ?? "" },
                              set: { model.textEntry?.text = $0 })
        let rgb = entry.color.rgb
        return TextField("", text: binding, prompt: Text(tr("输入文字，回车放好")).foregroundStyle(Color.white.opacity(0.7)))
            .textFieldStyle(.plain)
            .font(.system(size: entry.stroke.textSize, weight: .bold))
            .foregroundStyle(Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b))
            .focused($typing)
            .frame(minWidth: 160, maxWidth: max(160, model.size.width - at.x - 4), alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.8),
                                                                       style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .offset(x: at.x - 3, y: at.y)
            .onAppear { typing = true }
    }

    private func statusPill(_ text: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(verbatim: text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.panelPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: max(120, model.size.width - 16))
        .padding(8)
        .allowsHitTesting(false)
    }
}

/// 屏幕上的预览和 `ShotImaging.render` 画法一样：线宽、字号按点，马赛克从同一张底图裁。
enum ShotPainter {
    static func color(_ c: ShotColor) -> Color {
        let rgb = c.rgb
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static func mark(_ mark: ShotMark, in context: inout GraphicsContext, size: CGSize, pixelated: CGImage?,
                     scale: CGFloat) {
        let width = mark.stroke.lineWidth
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let shade = color(mark.color)
        let r = mark.rect
        let rect = CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width,
                          height: r.height * size.height)
        switch mark.tool {
        case .rectangle:
            context.stroke(Path(rect), with: .color(shade), style: style)
        case .ellipse:
            context.stroke(Path(ellipseIn: rect), with: .color(shade), style: style)
        case .arrow:
            let a = ShotGeometry.point(mark.start, in: size), b = ShotGeometry.point(mark.end, in: size)
            let (l, rr) = ShotGeometry.arrowHead(from: a, to: b, lineWidth: width)
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            context.stroke(line, with: .color(shade), style: style)
            var head = Path()
            head.move(to: l)
            head.addLine(to: b)
            head.addLine(to: rr)
            head.closeSubpath()
            context.fill(head, with: .color(shade))
            context.stroke(head, with: .color(shade), style: StrokeStyle(lineWidth: width, lineJoin: .round))
        case .pen:
            var path = Path()
            let points = mark.points.map { ShotGeometry.point($0, in: size) }
            guard let first = points.first else { return }
            path.move(to: first)
            for p in points.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(shade), style: style)
        case .mosaic:
            guard let pixelated else {
                context.fill(Path(rect), with: .color(.gray.opacity(0.6)))
                return
            }
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                layer.draw(Image(decorative: pixelated, scale: scale).interpolation(.none),
                           in: CGRect(origin: .zero, size: size))
            }
        case .text:
            let at = ShotGeometry.point(mark.start, in: size)
            let outline: Color = mark.color == .white ? .black : .white
            let text = Text(verbatim: mark.text)
                .font(.system(size: mark.stroke.textSize, weight: .bold))
                .foregroundStyle(shade)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: outline.opacity(0.85), radius: 0.8))
                layer.draw(text, in: CGRect(x: at.x, y: at.y, width: max(20, size.width - at.x), height: size.height))
            }
        }
    }

    static func overlay(_ paint: ShotImaging.OverlayPaint, in context: inout GraphicsContext) {
        let rect = paint.item.rect
        let bg = Color(.sRGB, red: paint.background.r, green: paint.background.g, blue: paint.background.b, opacity: 0.96)
        context.fill(Path(roundedRect: rect, cornerRadius: min(3, rect.height / 2)), with: .color(bg))
        let text = Text(verbatim: paint.item.translation)
            .font(.system(size: paint.item.fontSize, weight: .medium))
            .foregroundStyle(paint.darkInk ? Color(white: 0.08) : .white)
        context.draw(text, in: rect.insetBy(dx: 2, dy: 1))
    }
}

// MARK: - 工具条

private struct ShotToolbarBlock: View {
    @Bindable var model: ShotEditorModel
    var above: Bool
    var send: (ShotAction) -> Void

    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if above {
                panels
                options
                toolbar
            } else {
                toolbar
                options
                panels
            }
        }
    }

    // MARK: 第一排

    private var toolbar: some View {
        HStack(spacing: 2) {
            ForEach(ShotTool.allCases) { tool in
                item(tool.symbol, label: tool.title, selected: model.tool == tool) { send(.tool(tool)) }
            }
            divider
            item("text.viewfinder", label: tr("取字：识别文字，可拷贝、送翻译、问 AI"),
                 selected: model.textPanel, busy: model.recognizing) { send(.recognize) }
            item("translate", label: tr("翻译：识别后把译文盖在原文的位置"), selected: model.showsOverlay,
                 busy: model.isTranslating,
                 locked: model.locked) { send(.translate) }
            divider
            item("arrow.uturn.backward", label: tr("撤销（⌘Z）"), disabled: !model.document.canUndo && model.textEntry == nil) {
                send(.undo)
            }
            item("square.and.arrow.down", label: tr("存到截图文件夹")) { send(.save) }
            item("pin", label: tr("贴图：钉在屏幕最上层"), locked: model.locked) { send(.pin) }
            item("doc.on.doc", label: tr("拷贝（⌘C），可以接着画")) { send(.copy) }
            item("xmark", label: tr("取消（Esc）")) { send(.cancel) }
            Button { send(.done) } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 30)
                    .background(Capsule().fill(Color(hex: "#2563EB")))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? tr("完成：拷贝并关闭（回车）") : nil }
            .accessibilityLabel(tr("完成：拷贝并关闭（回车）"))
            .padding(.leading, 2)
        }
        .padding(.horizontal, 6)
        .frame(height: 42)
        .glassEffect(.regular, in: Capsule())
        .overlay(alignment: above ? .bottom : .top) {
            if let tip = hovered ?? model.note {
                Text(verbatim: tip)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .glassEffect(.regular, in: Capsule())
                    .offset(y: above ? 34 : -34)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.panelSeparator)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func item(_ symbol: String, label: String, selected: Bool = false, busy: Bool = false,
                      disabled: Bool = false, locked: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selected ? Color.panelPrimary : Color.panelPrimary.opacity(disabled ? 0.3 : 0.85))
                }
            }
            .frame(width: 32, height: 30)
            .background {
                if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.panelSelected) }
            }
            .overlay(alignment: .bottomTrailing) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 12, height: 12)
                        .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
                        .offset(x: -1, y: -1)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovered = $0 ? (locked ? tr("\(label)（\(ProFeatures.label)）") : label) : nil }
        .accessibilityLabel(label)
        .accessibilityValue(locked ? ProFeatures.label : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: 第二排：颜色粗细、原文译文

    @ViewBuilder
    private var options: some View {
        if model.tool != nil || model.translation == .ready {
            HStack(spacing: 10) {
                if let tool = model.tool {
                    if tool.usesColor {
                        ForEach(ShotColor.allCases) { color in colorDot(color) }
                        divider
                    }
                    ForEach(ShotStroke.allCases) { stroke in strokeDot(stroke, tool: tool) }
                }
                if model.translation == .ready {
                    if model.tool != nil { divider }
                    segment(tr("原文"), on: !model.showTranslated) { send(.showTranslated(false)) }
                    segment(tr("译文"), on: model.showTranslated) { send(.showTranslated(true)) }
                    smallButton(tr("拷贝译文"), symbol: "doc.on.doc") { send(.copyTranslation) }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .glassEffect(.regular, in: Capsule())
        }
    }

    private func colorDot(_ color: ShotColor) -> some View {
        let on = model.color == color
        return Button { send(.color(color)) } label: {
            Circle()
                .fill(ShotPainter.color(color))
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 1))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(on ? Color.panelPrimary : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? color.title : nil }
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func strokeDot(_ stroke: ShotStroke, tool: ShotTool) -> some View {
        let on = model.stroke == stroke
        let label = tool == .text ? tr("字号：\(stroke.title)") : (tool == .mosaic ? tr("格子：\(stroke.title)") : tr("粗细：\(stroke.title)"))
        return Button { send(.stroke(stroke)) } label: {
            Circle()
                .fill(Color.panelPrimary)
                .frame(width: stroke.dot, height: stroke.dot)
                .frame(width: 24, height: 24)
                .background(Circle().fill(on ? Color.panelSelected : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? label : nil }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: on ? .bold : .medium))
                .foregroundStyle(Color.panelPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(on ? Color.panelSelected : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.panelFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 取字小面板

    @ViewBuilder
    private var panels: some View {
        if model.textPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("识别到的文字"), systemImage: "text.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                    Spacer(minLength: 8)
                    Button { send(.closePanel) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("收起"))
                }
                ScrollView {
                    Text(verbatim: model.recognizedText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.panelPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    smallButton(tr("拷贝"), symbol: "doc.on.doc") { send(.copyText) }
                    smallButton(tr("送翻译"), symbol: "translate") { send(.sendToTranslate) }
                    smallButton(tr("问 AI"), symbol: "sparkles") { send(.askAI) }
                }
            }
            .padding(14)
            .frame(width: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
