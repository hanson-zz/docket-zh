import CoreGraphics
import Foundation

// 截图编辑工具条（截完后在选区旁边出现的那一排）的纯逻辑，都有测试（ShotEditorTests）：
// - 标注模型：工具、6 个预设颜色、3 档粗细，一笔标注怎么记（0...1 的比例，左上角为原点），
//   拖得太短的不算；
// - 撤销栈：每加一笔记一份快照，⌘Z 一步步退回；
// - 工具条放在哪：优先选区下方右对齐，放不下放上方，再放不下贴在选区里面底部；
// - 截图翻译：识别出的文字行并成段落、按原文块的大小挑字号、按底色挑深浅字；
// - 键盘：Esc、回车、⌘Z 在“正在输入文字”和平时分别做什么；
// - Pro：标注、取字、存文件、拷贝免费，截图翻译覆盖和贴图是 Pro；
// - 贴图的缩放、透明度范围；
// - 截图编辑、截图翻译两个全局快捷键（默认不设）和冲突提醒。
// 画图、识别、翻译、窗口在 Services/ShotEditor*.swift 和 Widgets/ShotEditor/。

// MARK: - 工具

public enum ShotTool: String, CaseIterable, Sendable, Identifiable {
    case rectangle, ellipse, arrow, pen, mosaic, text

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .rectangle: tr("矩形")
        case .ellipse: tr("椭圆")
        case .arrow: tr("箭头")
        case .pen: tr("画笔")
        case .mosaic: tr("马赛克")
        case .text: tr("文字")
        }
    }

    public var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "scribble"
        case .mosaic: "checkerboard.rectangle"
        case .text: "textformat"
        }
    }

    /// 马赛克不用颜色，只挑格子大小。
    public var usesColor: Bool { self != .mosaic }
    /// 拖一下画出来的（文字是点一下再输入）。
    public var isDragged: Bool { self != .text }
}

// MARK: - 颜色和粗细

/// 6 个预设颜色。红色在前，是默认。
public enum ShotColor: String, CaseIterable, Sendable, Identifiable {
    case red, yellow, green, blue, black, white

    public static let fallback: ShotColor = .red

    public var id: String { rawValue }

    public var hex: String {
        switch self {
        case .red: "#FF3B30"
        case .yellow: "#FFCC00"
        case .green: "#34C759"
        case .blue: "#0A84FF"
        case .black: "#1C1C1E"
        case .white: "#FFFFFF"
        }
    }

    public var title: String {
        switch self {
        case .red: tr("红色")
        case .yellow: tr("黄色")
        case .green: tr("绿色")
        case .blue: tr("蓝色")
        case .black: tr("黑色")
        case .white: tr("白色")
        }
    }

    /// 0...1 的 RGB。
    public var rgb: (r: Double, g: Double, b: Double) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

/// 3 档粗细。线宽、文字字号、马赛克格子都按这一档走，单位是屏幕上的点；
/// 存出去的原尺寸图按“像素 / 点”放大，所以看到的就是得到的。
public enum ShotStroke: String, CaseIterable, Sendable, Identifiable {
    case thin, medium, thick

    public static let fallback: ShotStroke = .medium

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thin: tr("较细")
        case .medium: tr("适中")
        case .thick: tr("较粗")
        }
    }

    /// 线宽（点）。
    public var lineWidth: CGFloat {
        switch self {
        case .thin: 2
        case .medium: 4
        case .thick: 7
        }
    }

    /// 文字字号（点），最小 14。
    public var textSize: CGFloat {
        switch self {
        case .thin: 14
        case .medium: 18
        case .thick: 26
        }
    }

    /// 马赛克一格多大（点）。
    public var mosaicCell: CGFloat {
        switch self {
        case .thin: 5
        case .medium: 9
        case .thick: 15
        }
    }

    /// 工具条上表示这一档的小圆点直径。
    public var dot: CGFloat {
        switch self {
        case .thin: 5
        case .medium: 8
        case .thick: 12
        }
    }
}

// MARK: - 一笔标注

/// 点都用 0...1 的比例记（左上角是 0,0，向下为正），屏幕上的预览和存出去的原图位置一样。
/// 矩形、椭圆、箭头、马赛克用头尾两个点；画笔是一串点；文字是一个点（左上角）加文字。
public struct ShotMark: Equatable, Sendable, Identifiable {
    public var id: Int
    public var tool: ShotTool
    public var color: ShotColor
    public var stroke: ShotStroke
    public var points: [CGPoint]
    public var text: String

    public init(id: Int, tool: ShotTool, color: ShotColor, stroke: ShotStroke, points: [CGPoint], text: String = "") {
        self.id = id
        self.tool = tool
        self.color = color
        self.stroke = stroke
        self.points = points
        self.text = text
    }

    public var start: CGPoint { points.first ?? .zero }
    public var end: CGPoint { points.last ?? .zero }
    /// 矩形、椭圆、马赛克的范围（比例）。
    public var rect: CGRect { ShotGeometry.rect(from: start, to: end) }
}

public enum ShotGeometry {
    /// 拖不到这么长（点）不算一笔：手抖点了一下。
    public static let minimumDrag: CGFloat = 4
    /// 画笔两点之间至少隔这么远（点），多余的点丢掉，存得少、画得顺。
    public static let penStep: CGFloat = 1.5

    public static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// 选区里的一个点（左上角为原点，单位点）换成比例，夹在图里。
    public static func normalized(_ p: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return clamp(CGPoint(x: p.x / size.width, y: p.y / size.height))
    }

    /// 比例换回一块区域里的点。
    public static func point(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    /// 一串比例点在这块大小上的总长（点）。
    public static func length(_ points: [CGPoint], in size: CGSize) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            let a = point(pair.0, in: size), b = point(pair.1, in: size)
            return total + hypot(b.x - a.x, b.y - a.y)
        }
    }

    /// 画笔的点：离上一个留下的点不到 `step` 的丢掉，最后一个点总留着。
    public static func thinned(_ points: [CGPoint], in size: CGSize, step: CGFloat = penStep) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var kept = [points[0]]
        for p in points.dropFirst().dropLast() {
            let a = point(kept[kept.count - 1], in: size), b = point(p, in: size)
            if hypot(b.x - a.x, b.y - a.y) >= step { kept.append(p) }
        }
        kept.append(points[points.count - 1])
        return kept
    }

    /// 箭头两翼的端点。翼长跟线宽走，短箭头不超过全长的 40%。
    public static func arrowHead(from a: CGPoint, to b: CGPoint, lineWidth: CGFloat,
                                 spread: CGFloat = 0.45) -> (CGPoint, CGPoint) {
        let total = hypot(b.x - a.x, b.y - a.y)
        let length = min(max(10, lineWidth * 4.5), total * 0.4)
        let angle = atan2(b.y - a.y, b.x - a.x)
        let left = CGPoint(x: b.x - length * cos(angle + spread), y: b.y - length * sin(angle + spread))
        let right = CGPoint(x: b.x - length * cos(angle - spread), y: b.y - length * sin(angle - spread))
        return (left, right)
    }
}

// MARK: - 标注和撤销栈

/// 这次截图上画了哪几笔，以及撤销。每次改动前把当时的标注存一份快照，⌘Z 取回上一份，
/// 所以“清空”这类一次改很多笔的操作也能一步撤回。
public struct ShotDocument: Equatable, Sendable {
    public private(set) var marks: [ShotMark] = []
    private var history: [[ShotMark]] = []
    private var nextID = 1
    /// 撤销栈最多记几步，够用又不会无限涨。
    public static let historyLimit = 100

    public init() {}

    public var isEmpty: Bool { marks.isEmpty }
    public var canUndo: Bool { !history.isEmpty }
    public var undoDepth: Int { history.count }

    /// 加一笔。`size` 是选区在屏幕上的大小（点），用来判断拖得够不够长。
    /// 拖得太短的形状、只有一个点的画笔和空文字不算，返回 false，撤销栈不变。
    @discardableResult
    public mutating func add(_ tool: ShotTool, color: ShotColor, stroke: ShotStroke, points raw: [CGPoint],
                             text: String = "", size: CGSize) -> Bool {
        let points = raw.map(ShotGeometry.clamp)
        guard let first = points.first, let last = points.last else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var kept = points
        switch tool {
        case .text:
            guard !trimmed.isEmpty else { return false }
            kept = [first]
        case .pen:
            guard points.count >= 2, ShotGeometry.length(points, in: size) >= ShotGeometry.minimumDrag else { return false }
            kept = ShotGeometry.thinned(points, in: size)
        case .arrow:
            let a = ShotGeometry.point(first, in: size), b = ShotGeometry.point(last, in: size)
            guard hypot(b.x - a.x, b.y - a.y) >= ShotGeometry.minimumDrag else { return false }
            kept = [first, last]
        case .rectangle, .ellipse, .mosaic:
            let r = ShotGeometry.rect(from: ShotGeometry.point(first, in: size), to: ShotGeometry.point(last, in: size))
            guard r.width >= ShotGeometry.minimumDrag, r.height >= ShotGeometry.minimumDrag else { return false }
            kept = [first, last]
        }
        remember()
        marks.append(ShotMark(id: nextID, tool: tool, color: color, stroke: stroke, points: kept,
                              text: tool == .text ? trimmed : ""))
        nextID += 1
        return true
    }

    /// 去掉所有标注（可以撤销）。本来就空时什么都不做。
    public mutating func clear() {
        guard !marks.isEmpty else { return }
        remember()
        marks.removeAll()
    }

    /// 退回上一步。没有可撤销的时返回 false。
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        marks = previous
        return true
    }

    private mutating func remember() {
        history.append(marks)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }
}

// MARK: - 工具条放在哪

public enum ShotToolbarPlacement {
    /// 工具条（连同下面的颜色粗细、取字小面板那一整块）的左上角。坐标都是窗口里的点，
    /// 左上角为原点、向下为正；`bounds` 是这块屏幕能放的范围。
    ///
    /// 优先放在选区正下方、右边和选区右边对齐（和系统、聊天软件的截图一样，鼠标刚松开
    /// 就在附近）；下面放不下放上方；上下都放不下（选区几乎占满屏幕）时贴在选区里面的
    /// 底部。左右超出屏幕时往里挪。
    public static func origin(selection: CGRect, block: CGSize, bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
        let sel = selection.standardized
        var x = sel.maxX - block.width
        x = min(max(x, bounds.minX + gap), bounds.maxX - block.width - gap)
        if block.width + gap * 2 > bounds.width { x = bounds.minX }
        let below = sel.maxY + gap
        if below + block.height <= bounds.maxY - gap { return CGPoint(x: x, y: below) }
        let above = sel.minY - gap - block.height
        if above >= bounds.minY + gap { return CGPoint(x: x, y: above) }
        let inside = min(sel.maxY, bounds.maxY) - gap - block.height
        return CGPoint(x: x, y: max(bounds.minY + gap, inside))
    }

    /// 放在选区上方时，颜色粗细那一行要在工具条上面（靠近选区的一侧是工具条本身）。
    public static func isAbove(origin: CGPoint, selection: CGRect) -> Bool {
        origin.y < selection.standardized.minY
    }
}

// MARK: - 截图翻译：识别出的文字块

/// 识别出的一块文字。`rect` 是 0...1 的比例，左上角为原点（Vision 给的是左下角，
/// 进来时已经翻过来）。
public struct ShotTextBlock: Equatable, Sendable {
    public var text: String
    public var rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

/// 一块译文盖在图上的样子。`rect` 是选区里的点，左上角为原点。
public struct ShotOverlayItem: Equatable, Sendable {
    public var source: String
    public var translation: String
    public var rect: CGRect
    public var fontSize: CGFloat

    public init(source: String, translation: String, rect: CGRect, fontSize: CGFloat) {
        self.source = source
        self.translation = translation
        self.rect = rect
        self.fontSize = fontSize
    }
}

public enum ShotTranslationLayout {
    /// 译文最小、最大字号（点）。盖在图上的是图的内容，跟着原文的大小走，
    /// 太小看不清，所以最小 11；放不下时块往下长，不再缩。
    public static let minimumFont: CGFloat = 11
    public static let maximumFont: CGFloat = 40
    public static let lineSpacing: CGFloat = 1.22

    /// 把一行行文字并成段落，再一段一段翻译，译文读起来才通顺。`imageSize` 用来把
    /// 比例换成同一个尺度（横竖的比例单位不一样长）。
    ///
    /// 下一行接上一段的条件：上下间距不超过行高的 0.8 倍，左边缘差不超过行高的 1.5 倍，
    /// 行高相近（0.6 到 1.6 倍）。先按从上到下、从左到右排。
    public static func paragraphs(_ lines: [ShotTextBlock], imageSize: CGSize) -> [ShotTextBlock] {
        let w = max(imageSize.width, 1), h = max(imageSize.height, 1)
        let usable = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let sorted = usable.sorted { a, b in
            abs(a.rect.minY - b.rect.minY) * h < min(a.rect.height, b.rect.height) * h * 0.5
                ? a.rect.minX < b.rect.minX : a.rect.minY < b.rect.minY
        }
        var result: [ShotTextBlock] = []
        // 每段最后并进来的那一行；分栏时新的一行找它上面那一段接，不只看最后一段。
        var lastLines: [CGRect] = []
        for line in sorted {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = result.indices.reversed().first { index in
                let previous = lastLines[index]
                let lineHeight = previous.height * h
                let gap = (line.rect.minY - previous.maxY) * h
                let indent = abs(line.rect.minX - result[index].rect.minX) * w
                let ratio = line.rect.height / max(previous.height, 0.0001)
                return gap >= -lineHeight * 0.3 && gap <= lineHeight * 0.8 && indent <= lineHeight * 1.5
                    && ratio >= 0.6 && ratio <= 1.6
            }
            if let target {
                result[target].text = join(result[target].text, text)
                result[target].rect = result[target].rect.union(line.rect)
                lastLines[target] = line.rect
            } else {
                result.append(ShotTextBlock(text: text, rect: line.rect))
                lastLines.append(line.rect)
            }
        }
        return result
    }

    /// 两行接成一段：中日韩文字之间不加空格；英文行尾的连字符去掉直接接上；其余加一个空格。
    public static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        if last == "-", head.count > 1, let before = head.dropLast().last, before.isLetter, first.isLowercase {
            return String(head.dropLast()) + tail
        }
        if isWide(last) || isWide(first) { return head + tail }
        return head + " " + tail
    }

    /// 全角字符：汉字、假名、谚文、全角标点。
    public static func isWide(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x1100...0x11FF, 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFE30...0xFE4F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFF:
            return true
        default:
            return false
        }
    }

    /// 估算一段文字排成一行有多宽（点）：全角字 1 个字号宽，大写 0.64，空格 0.28，
    /// 其余半角 0.54。用来挑字号，不需要精确，放不下时块会往下长。
    public static func estimatedWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        var em: CGFloat = 0
        for c in text {
            if isWide(c) { em += 1 } else if c == " " { em += 0.28 } else if c.isUppercase { em += 0.64 } else { em += 0.54 }
        }
        return em * fontSize
    }

    public struct Fit: Equatable, Sendable {
        public var fontSize: CGFloat
        public var lines: Int
        /// 排下这些行要多高（点）。
        public var height: CGFloat
    }

    /// 在 `box`（原文块的大小，点）里放下 `text` 的最大字号：从原文的行高开始往下试，
    /// 每次小 0.5。到最小字号还放不下时用最小字号，`height` 比块高，叫的人往下长。
    public static func fit(_ text: String, in box: CGSize, lineHint: CGFloat? = nil) -> Fit {
        let width = max(box.width, 1)
        let start = min(maximumFont, max(minimumFont, (lineHint ?? box.height) / lineSpacing))
        var size = start
        while true {
            let lines = max(1, Int((estimatedWidth(text, fontSize: size) / width).rounded(.up)))
            let height = CGFloat(lines) * size * lineSpacing
            if height <= box.height + 0.5 || size <= minimumFont {
                return Fit(fontSize: size, lines: lines, height: height)
            }
            size = max(minimumFont, size - 0.5)
        }
    }

    /// 把段落和译文排成盖在图上的块。`lineHeights` 是每段原文单行的高度（比例），用来
    /// 定起始字号；块左右各留 2 点、上下各留 1 点，放不下往下长（不超过选区底部）。
    public static func overlay(_ paragraphs: [ShotTextBlock], translations: [String], lineHeights: [CGFloat],
                               in size: CGSize) -> [ShotOverlayItem] {
        zip(paragraphs.indices, paragraphs).compactMap { index, paragraph in
            guard index < translations.count else { return nil }
            let translated = translations[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else { return nil }
            var rect = CGRect(x: paragraph.rect.minX * size.width, y: paragraph.rect.minY * size.height,
                              width: paragraph.rect.width * size.width, height: paragraph.rect.height * size.height)
                .insetBy(dx: -2, dy: -1)
            let hint = index < lineHeights.count ? lineHeights[index] * size.height : nil
            let fit = fit(translated, in: CGSize(width: rect.width - 4, height: rect.height - 2), lineHint: hint)
            if fit.height + 2 > rect.height {
                rect.size.height = min(fit.height + 2, max(rect.height, size.height - rect.minY))
            }
            return ShotOverlayItem(source: paragraph.text, translation: translated, rect: rect, fontSize: fit.fontSize)
        }
    }

    /// 段落里单行的高度（比例）：并进来的那些原文行里最高的一行。
    public static func lineHeight(of paragraph: ShotTextBlock, lines: [ShotTextBlock]) -> CGFloat {
        let inside = lines.filter { paragraph.rect.insetBy(dx: -0.0001, dy: -0.0001).contains($0.rect) }
        return inside.map(\.rect.height).max() ?? paragraph.rect.height
    }

    /// 相对亮度（sRGB，0...1）。
    public static func luminance(r: Double, g: Double, b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// 底色亮就用深字，暗就用白字：取对比度大的那个（亮度约 0.18 是两边相等的点）。
    public static func usesDarkInk(backgroundLuminance l: Double) -> Bool {
        (l + 0.05) / 0.05 >= 1.05 / (l + 0.05)
    }

    /// 拷贝译文：一段一行。
    public static func joinedTranslation(_ items: [ShotOverlayItem]) -> String {
        items.map(\.translation).joined(separator: "\n")
    }
}

/// 截图翻译往哪种语言翻：和翻译小组件的智能方向一样，中文译成英语，其他译成简体中文。
public enum ShotTranslateDirection {
    public static func pair(for text: String) -> (source: String?, target: String) {
        let source = Translate.detect(text)
        return (source, Translate.target(source: source, text: text, chosen: "", smart: true))
    }
}

// MARK: - 键盘

public enum ShotKeyCommand: Equatable, Sendable {
    case cancel, done, undo, copy
    /// 正在输入文字时：Esc 放弃这段字，回车放进图里。
    case cancelText, commitText
    /// 不归工具条管，交给输入框或系统。
    case passThrough

    public static let escape: UInt16 = 53
    public static let returnKey: UInt16 = 36
    public static let enter: UInt16 = 76
    public static let z: UInt16 = 6
    public static let c: UInt16 = 8

    /// Esc 取消、回车完成、⌘Z 撤销、⌘C 拷贝。正在输入文字时 Esc 和回车只管那段字，
    /// ⌘Z、⌘C 交给输入框（撤销输入框里打的字）。⌘⇧Z 不处理。
    public static func resolve(keyCode: UInt16, command: Bool, shift: Bool, editingText: Bool) -> ShotKeyCommand {
        switch keyCode {
        case escape:
            return editingText ? .cancelText : .cancel
        case returnKey, enter:
            if editingText { return shift ? .passThrough : .commitText }
            return command || shift ? .passThrough : .done
        case z where command && !shift:
            return editingText ? .passThrough : .undo
        case c where command && !shift:
            return editingText ? .passThrough : .copy
        default:
            return .passThrough
        }
    }
}

// MARK: - Pro

/// 工具条上要分免费和 Pro 的几样。标注（六个工具和撤销）、取字、存文件、拷贝免费；
/// 截图翻译（译文盖在截图上）和贴图是 Pro，未解锁点了弹付费墙，不改任何设置。
public enum ShotFeature: String, CaseIterable, Sendable {
    case annotate, recognize, save, copy, translate, pin

    /// 对应的 Pro 设置项，nil 是免费。
    public var proSetting: ProFeatures.Setting? {
        switch self {
        case .translate: .shotTranslate
        case .pin: .shotPin
        case .annotate, .recognize, .save, .copy: nil
        }
    }

    public var isPro: Bool { proSetting != nil }
}

// MARK: - 贴图

public enum ShotPinMath {
    public static let scaleRange: ClosedRange<CGFloat> = 0.2...4
    public static let opacityRange: ClosedRange<Double> = 0.2...1
    /// 右键菜单里的透明度。
    public static let opacityChoices: [Double] = [1, 0.8, 0.6, 0.4]

    /// 滚轮缩放：向上滚放大，每格约 5%，夹在 0.2 到 4 倍。
    public static func zoomed(_ scale: CGFloat, scrollDelta: CGFloat) -> CGFloat {
        let factor = pow(1.05, max(-10, min(10, scrollDelta)))
        return min(max(scale * factor, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// ⌥ + 滚轮调透明度：每格 5%，夹在 20% 到 100%（全透明就找不到了）。
    public static func faded(_ opacity: Double, scrollDelta: CGFloat) -> Double {
        let next = opacity + Double(max(-10, min(10, scrollDelta))) * 0.05
        return min(max(next, opacityRange.lowerBound), opacityRange.upperBound)
    }

    /// 缩放后窗口的大小，中心不动时的新位置由调用方算。`base` 是 1 倍时的大小（点）。
    public static func size(base: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(24, (base.width * scale).rounded()), height: max(24, (base.height * scale).rounded()))
    }

    /// 透明度菜单项的字：“80%”。
    public static func percent(_ opacity: Double) -> String { "\(Int((opacity * 100).rounded()))%" }
}

// MARK: - 全局快捷键

/// 截图编辑、截图翻译两个全局快捷键，默认都不设（系统 ⇧⌘3/4/5 和聊天软件的截图键已经
/// 很拥挤，给默认值容易抢）。在设置 ▸ 快捷键里录制。
public struct ShotHotKeys: Codable, Hashable, Sendable {
    public var edit: KeyCombo?
    public var translate: KeyCombo?

    public init(edit: KeyCombo? = nil, translate: KeyCombo? = nil) {
        self.edit = edit
        self.translate = translate
    }

    /// 少了键、认不出的值都当没设，不让整个设置文件读不进来。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edit = try? c.decodeIfPresent(KeyCombo.self, forKey: .edit)
        translate = try? c.decodeIfPresent(KeyCombo.self, forKey: .translate)
    }

    private enum CodingKeys: String, CodingKey { case edit, translate }

    /// 真正要注册的两个：没设的、缺修饰键的不注册；两个设成一样时只留截图编辑。
    public var registrable: (edit: KeyCombo?, translate: KeyCombo?) {
        let e = edit.flatMap { $0.hasRequiredModifier ? $0 : nil }
        var t = translate.flatMap { $0.hasRequiredModifier ? $0 : nil }
        if let e, t == e { t = nil }
        return (e, t)
    }
}

public enum ShotHotKeyAdvice {
    /// 系统截图的四个键（3、4、5、6 的键码）。
    static let systemKeys: Set<UInt32> = [20, 21, 23, 22]

    /// 录到常见冲突时在设置里提醒一句，不拒收。`others` 是码头里别的全局快捷键
    /// （展开 AI 对话、快速待办、另一个截图快捷键）。
    public static func warning(for combo: KeyCombo?, others: [KeyCombo?] = []) -> String? {
        guard let combo else { return nil }
        typealias M = KeyCombo.Modifier
        let m = combo.modifiers
        if systemKeys.contains(combo.keyCode), m & M.command != 0, m & M.shift != 0, m & M.option == 0 {
            return tr("这是系统截图的快捷键，建议换一个，免得两边抢。")
        }
        if others.contains(where: { $0 == combo }) {
            return tr("和码头里另一个快捷键一样，只有一个会生效。")
        }
        return nil
    }
}
