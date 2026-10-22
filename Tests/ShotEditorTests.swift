import CoreGraphics
import Foundation
import XCTest

/// 截图编辑工具条：标注模型、撤销栈、工具条位置、截图翻译的段落和覆盖排版、键盘、
/// Pro 划分、贴图和快捷键。
final class ShotEditorTests: XCTestCase {
    private let size = CGSize(width: 400, height: 200)

    // MARK: 工具、颜色、粗细

    func testToolsColorsAndStrokes() {
        XCTAssertEqual(ShotTool.allCases.map(\.title), ["矩形", "椭圆", "箭头", "画笔", "马赛克", "文字"])
        XCTAssertEqual(ShotTool.allCases.count, Set(ShotTool.allCases.map(\.symbol)).count, "图标不重复")
        XCTAssertFalse(ShotTool.mosaic.usesColor)
        XCTAssertTrue(ShotTool.allCases.filter { $0 != .mosaic }.allSatisfy(\.usesColor))
        XCTAssertFalse(ShotTool.text.isDragged)
        // 4 到 6 个预设颜色，默认红色。
        XCTAssertTrue((4...6).contains(ShotColor.allCases.count))
        XCTAssertEqual(ShotColor.fallback, .red)
        XCTAssertEqual(Set(ShotColor.allCases.map(\.hex)).count, ShotColor.allCases.count)
        let white = ShotColor.white.rgb
        XCTAssertEqual(white.r, 1, accuracy: 0.001)
        XCTAssertEqual(white.b, 1, accuracy: 0.001)
        // 3 档粗细，越来越粗；文字最小 14 点（不低于 13）。
        XCTAssertEqual(ShotStroke.allCases.count, 3)
        XCTAssertEqual(ShotStroke.fallback, .medium)
        let widths = ShotStroke.allCases.map(\.lineWidth)
        XCTAssertEqual(widths, widths.sorted())
        XCTAssertEqual(Set(widths).count, 3)
        XCTAssertGreaterThanOrEqual(ShotStroke.allCases.map(\.textSize).min()!, 13)
        XCTAssertEqual(ShotStroke.allCases.map(\.mosaicCell), ShotStroke.allCases.map(\.mosaicCell).sorted())
    }

    // MARK: 标注模型

    func testShortDragsAreNotMarks() {
        var doc = ShotDocument()
        // 400 点宽：0.005 是 2 点，不够 4 点。
        XCTAssertFalse(doc.add(.rectangle, color: .red, stroke: .medium,
                               points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.105, y: 0.3)], size: size))
        XCTAssertFalse(doc.add(.arrow, color: .red, stroke: .medium,
                               points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.104, y: 0.1)], size: size))
        XCTAssertFalse(doc.add(.pen, color: .red, stroke: .medium, points: [CGPoint(x: 0.1, y: 0.1)], size: size))
        XCTAssertFalse(doc.add(.text, color: .red, stroke: .medium, points: [CGPoint(x: 0.1, y: 0.1)],
                               text: "   \n", size: size))
        XCTAssertFalse(doc.add(.ellipse, color: .red, stroke: .medium, points: [], size: size))
        XCTAssertTrue(doc.isEmpty)
        XCTAssertFalse(doc.canUndo, "没加上的不进撤销栈")
    }

    func testMarksAreClampedAndKept() throws {
        var doc = ShotDocument()
        XCTAssertTrue(doc.add(.ellipse, color: .blue, stroke: .thick,
                              points: [CGPoint(x: -0.2, y: 0.5), CGPoint(x: 0.4, y: 1.3)], size: size))
        let mark = try XCTUnwrap(doc.marks.first)
        XCTAssertEqual(mark.start, CGPoint(x: 0, y: 0.5))
        XCTAssertEqual(mark.end, CGPoint(x: 0.4, y: 1))
        XCTAssertEqual(mark.rect, CGRect(x: 0, y: 0.5, width: 0.4, height: 0.5))
        XCTAssertEqual(mark.color, .blue)
        XCTAssertEqual(mark.stroke, .thick)
        // 文字只留一个点，去掉首尾空白。
        XCTAssertTrue(doc.add(.text, color: .white, stroke: .thin,
                              points: [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.9, y: 0.9)], text: "  你好 \n", size: size))
        XCTAssertEqual(doc.marks.last?.points, [CGPoint(x: 0.2, y: 0.2)])
        XCTAssertEqual(doc.marks.last?.text, "你好")
        XCTAssertEqual(Set(doc.marks.map(\.id)).count, 2, "id 不重复")
    }

    func testPenIsThinned() throws {
        var doc = ShotDocument()
        // 一条 40 点长的横线，每 0.25 点一个点：留下的点间距至少 1.5 点，首尾都在。
        let points = (0...160).map { CGPoint(x: 0.1 + Double($0) * 0.25 / 400, y: 0.5) }
        XCTAssertTrue(doc.add(.pen, color: .red, stroke: .medium, points: points, size: size))
        let kept = try XCTUnwrap(doc.marks.first?.points)
        XCTAssertLessThan(kept.count, points.count)
        XCTAssertEqual(kept.first, points.first)
        XCTAssertEqual(kept.last, points.last)
        for (a, b) in zip(kept, kept.dropFirst().dropLast()) {
            XCTAssertGreaterThanOrEqual((b.x - a.x) * 400, ShotGeometry.penStep - 0.0001)
        }
        XCTAssertEqual(ShotGeometry.length(kept, in: size), 40, accuracy: 0.01)
    }

    func testArrowHeadStaysShortOnShortArrows() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 20, y: 0)
        let (l, r) = ShotGeometry.arrowHead(from: a, to: b, lineWidth: 7)
        XCTAssertLessThanOrEqual(hypot(b.x - l.x, b.y - l.y), 8.0001, "不超过全长 40%")
        XCTAssertEqual(l.y, -r.y, accuracy: 0.0001, "两翼对称")
        let (long, _) = ShotGeometry.arrowHead(from: a, to: CGPoint(x: 400, y: 0), lineWidth: 4)
        XCTAssertEqual(hypot(400 - long.x, long.y), 18, accuracy: 0.001)
    }

    // MARK: 撤销栈

    func testUndoStepsBackOneAtATimeIncludingClear() {
        var doc = ShotDocument()
        let rect = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)]
        doc.add(.rectangle, color: .red, stroke: .thin, points: rect, size: size)
        doc.add(.mosaic, color: .red, stroke: .thick, points: rect, size: size)
        doc.add(.arrow, color: .green, stroke: .medium, points: rect, size: size)
        XCTAssertEqual(doc.marks.map(\.tool), [.rectangle, .mosaic, .arrow])
        XCTAssertEqual(doc.undoDepth, 3)
        doc.clear()
        XCTAssertTrue(doc.isEmpty)
        XCTAssertTrue(doc.undo(), "清空也能撤回")
        XCTAssertEqual(doc.marks.map(\.tool), [.rectangle, .mosaic, .arrow])
        XCTAssertTrue(doc.undo())
        XCTAssertEqual(doc.marks.map(\.tool), [.rectangle, .mosaic])
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.isEmpty)
        XCTAssertFalse(doc.undo())
        XCTAssertFalse(doc.canUndo)
        // 空的时候清空不进撤销栈。
        doc.clear()
        XCTAssertFalse(doc.canUndo)
        // 撤回后再画，id 接着往后，不和撤掉的重复。
        doc.add(.ellipse, color: .red, stroke: .thin, points: rect, size: size)
        XCTAssertEqual(doc.marks.first?.id, 4)
    }

    func testHistoryIsCapped() {
        var doc = ShotDocument()
        let rect = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5)]
        for _ in 0..<(ShotDocument.historyLimit + 20) {
            doc.add(.rectangle, color: .red, stroke: .thin, points: rect, size: size)
        }
        XCTAssertEqual(doc.undoDepth, ShotDocument.historyLimit)
        XCTAssertEqual(doc.marks.count, ShotDocument.historyLimit + 20)
    }

    // MARK: 工具条位置

    func testToolbarGoesBelowThenAboveThenInside() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let block = CGSize(width: 520, height: 44)
        // 下面放得下：选区下方，右边对齐。
        let below = ShotToolbarPlacement.origin(selection: CGRect(x: 300, y: 200, width: 600, height: 300),
                                                block: block, bounds: bounds)
        XCTAssertEqual(below, CGPoint(x: 900 - 520, y: 508))
        XCTAssertFalse(ShotToolbarPlacement.isAbove(origin: below, selection: CGRect(x: 300, y: 200, width: 600, height: 300)))
        // 选区贴着底：放上方。
        let bottom = CGRect(x: 300, y: 500, width: 600, height: 380)
        let above = ShotToolbarPlacement.origin(selection: bottom, block: block, bounds: bounds)
        XCTAssertEqual(above.y, 500 - 8 - 44)
        XCTAssertTrue(ShotToolbarPlacement.isAbove(origin: above, selection: bottom))
        // 几乎全屏：贴在选区里面的底部。
        let full = CGRect(x: 0, y: 10, width: 1440, height: 885)
        let inside = ShotToolbarPlacement.origin(selection: full, block: block, bounds: bounds)
        XCTAssertEqual(inside.y, 895 - 8 - 44)
        XCTAssertEqual(inside.x, 1440 - 8 - 520)
    }

    func testToolbarStaysOnScreenSideways() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let block = CGSize(width: 520, height: 44)
        // 很窄的选区靠左：右对齐会出屏，往里挪到左边留 8 点。
        let left = ShotToolbarPlacement.origin(selection: CGRect(x: 4, y: 100, width: 60, height: 60),
                                               block: block, bounds: bounds)
        XCTAssertEqual(left.x, 8)
        // 选区右边超出屏幕：不超过屏幕右边。
        let right = ShotToolbarPlacement.origin(selection: CGRect(x: 1300, y: 100, width: 400, height: 60),
                                                block: block, bounds: bounds)
        XCTAssertEqual(right.x, 1440 - 8 - 520)
        // 反着框的选区（宽高为负）一样。
        let flipped = ShotToolbarPlacement.origin(selection: CGRect(x: 900, y: 500, width: -600, height: -300),
                                                  block: block, bounds: bounds)
        XCTAssertEqual(flipped, CGPoint(x: 380, y: 508))
    }

    // MARK: 截图翻译：段落

    func testLinesMergeIntoParagraphs() {
        let image = CGSize(width: 1000, height: 1000)
        let lines = [
            // 第二段在右栏，同一高度，先按 x 排在后面。
            ShotTextBlock(text: "Right column", rect: CGRect(x: 0.6, y: 0.10, width: 0.3, height: 0.02)),
            ShotTextBlock(text: "The quick brown fox jumps over the lazy", rect: CGRect(x: 0.1, y: 0.10, width: 0.4, height: 0.02)),
            ShotTextBlock(text: "dog and keeps run-", rect: CGRect(x: 0.1, y: 0.125, width: 0.3, height: 0.02)),
            ShotTextBlock(text: "ning.", rect: CGRect(x: 0.1, y: 0.15, width: 0.05, height: 0.02)),
            // 隔得远：新的一段。
            ShotTextBlock(text: "标题", rect: CGRect(x: 0.1, y: 0.4, width: 0.1, height: 0.05)),
            ShotTextBlock(text: "  ", rect: CGRect(x: 0.1, y: 0.5, width: 0.1, height: 0.02)),
        ]
        let paragraphs = ShotTranslationLayout.paragraphs(lines, imageSize: image)
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(paragraphs[0].text, "The quick brown fox jumps over the lazy dog and keeps running.")
        XCTAssertEqual(paragraphs[0].rect.minY, 0.10, accuracy: 0.0001)
        XCTAssertEqual(paragraphs[0].rect.maxY, 0.17, accuracy: 0.0001)
        XCTAssertEqual(paragraphs[1].text, "Right column")
        XCTAssertEqual(paragraphs[2].text, "标题")
        XCTAssertEqual(ShotTranslationLayout.lineHeight(of: paragraphs[0], lines: lines), 0.02, accuracy: 0.0001)
    }

    func testDifferentSizedLinesStayApart() {
        let image = CGSize(width: 1000, height: 1000)
        let lines = [
            ShotTextBlock(text: "大标题", rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.06)),
            ShotTextBlock(text: "正文第一行", rect: CGRect(x: 0.1, y: 0.17, width: 0.3, height: 0.02)),
            ShotTextBlock(text: "正文第二行", rect: CGRect(x: 0.1, y: 0.195, width: 0.3, height: 0.02)),
        ]
        let paragraphs = ShotTranslationLayout.paragraphs(lines, imageSize: image)
        XCTAssertEqual(paragraphs.map(\.text), ["大标题", "正文第一行正文第二行"])
    }

    func testJoiningLines() {
        XCTAssertEqual(ShotTranslationLayout.join("你好", "世界"), "你好世界")
        XCTAssertEqual(ShotTranslationLayout.join("hello", "world"), "hello world")
        XCTAssertEqual(ShotTranslationLayout.join("trans-", "lation"), "translation")
        XCTAssertEqual(ShotTranslationLayout.join("COVID-", "19"), "COVID- 19")
        XCTAssertEqual(ShotTranslationLayout.join("价格", "USD"), "价格USD")
        XCTAssertEqual(ShotTranslationLayout.join("", "x"), "x")
    }

    // MARK: 截图翻译：字号和覆盖

    func testFitPicksTheLargestSizeThatFits() {
        // 一行 20 点高、200 点宽的中文块：4 个字，起始字号约 16，一行放得下。
        let fit = ShotTranslationLayout.fit("你好世界", in: CGSize(width: 200, height: 20))
        XCTAssertEqual(fit.lines, 1)
        XCTAssertEqual(fit.fontSize, (20 / ShotTranslationLayout.lineSpacing), accuracy: 0.6)
        XCTAssertLessThanOrEqual(fit.height, 20.5)
        // 长译文放进同样的块：缩到最小字号还放不下，height 比块高。
        let long = ShotTranslationLayout.fit(String(repeating: "很长的译文", count: 20), in: CGSize(width: 200, height: 20))
        XCTAssertEqual(long.fontSize, ShotTranslationLayout.minimumFont)
        XCTAssertGreaterThan(long.height, 20)
        XCTAssertGreaterThan(long.lines, 1)
        // 字号不超过最大值。
        XCTAssertLessThanOrEqual(ShotTranslationLayout.fit("A", in: CGSize(width: 900, height: 600)).fontSize,
                                 ShotTranslationLayout.maximumFont)
        // 宽度估算：全角字一个字号宽。
        XCTAssertEqual(ShotTranslationLayout.estimatedWidth("中文", fontSize: 10), 20)
        XCTAssertEqual(ShotTranslationLayout.estimatedWidth("ab", fontSize: 10), 10.8, accuracy: 0.001)
    }

    func testOverlayLaysTranslationsOverTheirBlocks() throws {
        let paragraphs = [
            ShotTextBlock(text: "Hello", rect: CGRect(x: 0.1, y: 0.1, width: 0.25, height: 0.1)),
            ShotTextBlock(text: "World", rect: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)),
            ShotTextBlock(text: "Skipped", rect: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1)),
        ]
        let items = ShotTranslationLayout.overlay(paragraphs,
                                                  translations: ["你好", String(repeating: "世界", count: 30), "  "],
                                                  lineHeights: [0.1, 0.1], in: size)
        XCTAssertEqual(items.count, 2, "空译文不画")
        let first = try XCTUnwrap(items.first)
        XCTAssertEqual(first.source, "Hello")
        XCTAssertEqual(first.translation, "你好")
        XCTAssertEqual(first.rect, CGRect(x: 38, y: 19, width: 104, height: 22))
        XCTAssertGreaterThanOrEqual(first.fontSize, ShotTranslationLayout.minimumFont)
        // 放不下的往下长，但不超过选区底部。
        let second = items[1]
        XCTAssertLessThanOrEqual(second.rect.maxY, size.height + 0.001)
        XCTAssertGreaterThan(second.rect.height, 22)
        XCTAssertEqual(ShotTranslationLayout.joinedTranslation(items), "你好\n" + String(repeating: "世界", count: 30))
    }

    func testInkFollowsTheBackground() {
        XCTAssertTrue(ShotTranslationLayout.usesDarkInk(backgroundLuminance: 1))
        XCTAssertFalse(ShotTranslationLayout.usesDarkInk(backgroundLuminance: 0))
        XCTAssertTrue(ShotTranslationLayout.usesDarkInk(backgroundLuminance: ShotTranslationLayout.luminance(r: 0.95, g: 0.95, b: 0.9)))
        XCTAssertFalse(ShotTranslationLayout.usesDarkInk(backgroundLuminance: ShotTranslationLayout.luminance(r: 0.1, g: 0.2, b: 0.4)))
        XCTAssertEqual(ShotTranslationLayout.luminance(r: 1, g: 1, b: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(ShotTranslationLayout.luminance(r: 0, g: 0, b: 0), 0, accuracy: 0.0001)
    }

    func testDirectionFollowsTheSmartRule() {
        XCTAssertEqual(ShotTranslateDirection.pair(for: "这是一段中文说明文字").target, "en")
        XCTAssertEqual(ShotTranslateDirection.pair(for: "This is an English sentence about screenshots").target, "zh-Hans")
    }

    // MARK: 键盘

    func testKeys() {
        typealias K = ShotKeyCommand
        XCTAssertEqual(K.resolve(keyCode: K.escape, command: false, shift: false, editingText: false), .cancel)
        XCTAssertEqual(K.resolve(keyCode: K.returnKey, command: false, shift: false, editingText: false), .done)
        XCTAssertEqual(K.resolve(keyCode: K.enter, command: false, shift: false, editingText: false), .done)
        XCTAssertEqual(K.resolve(keyCode: K.z, command: true, shift: false, editingText: false), .undo)
        XCTAssertEqual(K.resolve(keyCode: K.z, command: true, shift: true, editingText: false), .passThrough)
        XCTAssertEqual(K.resolve(keyCode: K.z, command: false, shift: false, editingText: false), .passThrough)
        XCTAssertEqual(K.resolve(keyCode: K.c, command: true, shift: false, editingText: false), .copy)
        // 正在输入文字：Esc、回车只管那段字，⌘Z 交给输入框。
        XCTAssertEqual(K.resolve(keyCode: K.escape, command: false, shift: false, editingText: true), .cancelText)
        XCTAssertEqual(K.resolve(keyCode: K.returnKey, command: false, shift: false, editingText: true), .commitText)
        XCTAssertEqual(K.resolve(keyCode: K.returnKey, command: false, shift: true, editingText: true), .passThrough)
        XCTAssertEqual(K.resolve(keyCode: K.z, command: true, shift: false, editingText: true), .passThrough)
        XCTAssertEqual(K.resolve(keyCode: K.c, command: true, shift: false, editingText: true), .passThrough)
        XCTAssertEqual(K.resolve(keyCode: 0, command: false, shift: false, editingText: false), .passThrough)
    }

    // MARK: Pro

    func testProSplit() {
        let free: [ShotFeature] = [.annotate, .recognize, .save, .copy]
        for feature in free {
            XCTAssertFalse(feature.isPro, feature.rawValue)
            XCTAssertTrue(ProLicenseGate.canUseShotFeature(feature, unlocked: false), feature.rawValue)
        }
        XCTAssertEqual(ShotFeature.translate.proSetting, .shotTranslate)
        XCTAssertEqual(ShotFeature.pin.proSetting, .shotPin)
        for feature in [ShotFeature.translate, .pin] {
            XCTAssertTrue(feature.isPro)
            XCTAssertFalse(ProLicenseGate.canUseShotFeature(feature, unlocked: false))
            XCTAssertTrue(ProLicenseGate.canUseShotFeature(feature, unlocked: true))
        }
        XCTAssertEqual(Set(ShotFeature.allCases.compactMap(\.proSetting)), [.shotTranslate, .shotPin])
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.shotTranslate))
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.shotPin))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.shotTranslate)), "截图翻译")
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.shotPin)), "截图贴图")
    }

    // MARK: 贴图

    func testPinZoomAndOpacityAreClamped() {
        XCTAssertEqual(ShotPinMath.zoomed(1, scrollDelta: 1), 1.05, accuracy: 0.0001)
        XCTAssertEqual(ShotPinMath.zoomed(1, scrollDelta: -1), 1 / 1.05, accuracy: 0.0001)
        XCTAssertEqual(ShotPinMath.zoomed(3.9, scrollDelta: 10), 4)
        XCTAssertEqual(ShotPinMath.zoomed(0.21, scrollDelta: -10), 0.2)
        XCTAssertEqual(ShotPinMath.zoomed(1, scrollDelta: 500), pow(1.05, 10), accuracy: 0.0001, "一次滚太多也只算 10 格")
        XCTAssertEqual(ShotPinMath.faded(1, scrollDelta: -2), 0.9, accuracy: 0.0001)
        XCTAssertEqual(ShotPinMath.faded(0.25, scrollDelta: -5), 0.2)
        XCTAssertEqual(ShotPinMath.faded(0.95, scrollDelta: 4), 1)
        XCTAssertEqual(ShotPinMath.size(base: CGSize(width: 300, height: 200), scale: 0.5), CGSize(width: 150, height: 100))
        XCTAssertEqual(ShotPinMath.size(base: CGSize(width: 30, height: 20), scale: 0.2), CGSize(width: 24, height: 24))
        XCTAssertEqual(ShotPinMath.opacityChoices.map(ShotPinMath.percent), ["100%", "80%", "60%", "40%"])
        XCTAssertTrue(ShotPinMath.opacityChoices.allSatisfy(ShotPinMath.opacityRange.contains))
    }

    // MARK: 快捷键

    func testHotKeysDefaultToNoneAndDecodeLeniently() throws {
        XCTAssertNil(PersistedState().shotHotKeys.edit)
        XCTAssertNil(PersistedState().shotHotKeys.translate)
        // 老的设置文件没有这个键：照常读进来。
        let old = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(old.shotHotKeys, ShotHotKeys())
        // 坏掉的一半不连累另一半。
        let mixed = try JSONDecoder().decode(ShotHotKeys.self,
                                             from: Data(#"{"edit":{"keyCode":0,"modifiers":4352},"translate":"x"}"#.utf8))
        XCTAssertEqual(mixed.edit, KeyCombo(keyCode: 0, modifiers: 4352))
        XCTAssertNil(mixed.translate)
        // 存了再读回来一样。
        var state = PersistedState()
        state.shotHotKeys = ShotHotKeys(edit: KeyCombo(keyCode: 0, modifiers: 4352),
                                        translate: KeyCombo(keyCode: 17, modifiers: 4352))
        let round = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round.shotHotKeys, state.shotHotKeys)
    }

    func testRegistrableDropsBadAndDuplicateCombos() {
        typealias M = KeyCombo.Modifier
        let a = KeyCombo(keyCode: 0, modifiers: M.control | M.shift)
        XCTAssertEqual(ShotHotKeys(edit: a, translate: a).registrable.translate, nil, "一样时只留截图编辑")
        XCTAssertEqual(ShotHotKeys(edit: a, translate: a).registrable.edit, a)
        let shiftOnly = KeyCombo(keyCode: 0, modifiers: M.shift)
        XCTAssertNil(ShotHotKeys(edit: shiftOnly).registrable.edit, "只有 Shift 不注册")
    }

    func testHotKeyWarnings() {
        typealias M = KeyCombo.Modifier
        XCTAssertNotNil(ShotHotKeyAdvice.warning(for: KeyCombo(keyCode: 21, modifiers: M.command | M.shift)), "⇧⌘4")
        XCTAssertNotNil(ShotHotKeyAdvice.warning(for: KeyCombo(keyCode: 21, modifiers: M.command | M.shift | M.control)),
                        "⌃⇧⌘4 截到剪贴板")
        XCTAssertNil(ShotHotKeyAdvice.warning(for: KeyCombo(keyCode: 21, modifiers: M.command | M.option)))
        let mine = KeyCombo(keyCode: 0, modifiers: M.control | M.option)
        XCTAssertNotNil(ShotHotKeyAdvice.warning(for: mine, others: [nil, mine]))
        XCTAssertNil(ShotHotKeyAdvice.warning(for: mine, others: [nil]))
        XCTAssertNil(ShotHotKeyAdvice.warning(for: nil))
    }
}
