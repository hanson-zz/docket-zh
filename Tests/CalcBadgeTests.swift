import XCTest

/// 「算」卡片字牌：小熊猫脸框拟人计算器的比例、线宽和颜色。
final class CalcBadgeTests: XCTestCase {

    func testEverythingStaysInsideThePlate() {
        let parts = [CalcBadge.face, CalcBadge.screen, CalcBadge.openEye, CalcBadge.keypad]
            + CalcBadge.brows + CalcBadge.cheeks + CalcBadge.keys
        for part in parts {
            XCTAssertTrue(CalcBadge.plate.contains(part), "\(part) 出了方底")
        }
    }

    func testScreenSitsInsideTheFaceWithARimAllRound() {
        let face = CalcBadge.face, screen = CalcBadge.screen
        XCTAssertTrue(face.contains(screen))
        // 上框比左右宽，放得下眉斑；下框留给腮
        XCTAssertGreaterThan(screen.y0 - face.y0, screen.x0 - face.x0)
        XCTAssertGreaterThan(face.y1 - screen.y1, 0.03)
        XCTAssertGreaterThan(screen.x0 - face.x0, 0.03)
        XCTAssertGreaterThan(face.x1 - screen.x1, 0.03)
    }

    func testBrowsSitOnTheTopRimAboveTheEyes() {
        XCTAssertEqual(CalcBadge.brows.count, 2)
        for brow in CalcBadge.brows {
            XCTAssertTrue(CalcBadge.face.contains(brow))
            XCTAssertLessThanOrEqual(brow.y1, CalcBadge.screen.y0, "眉斑压到屏幕上了")
            XCTAssertGreaterThanOrEqual(brow.y0, CalcBadge.face.y0)
        }
        XCTAssertEqual(CalcBadge.brows[0].midX, CalcBadge.openEye.midX, accuracy: 1e-9)
        XCTAssertEqual(CalcBadge.brows[1].midX, CalcBadge.wink.centerX, accuracy: 1e-9)
        XCTAssertFalse(CalcBadge.brows[0].overlaps(CalcBadge.brows[1]))
    }

    func testCheeksAreInTheLowerCornersOfTheFace() {
        let face = CalcBadge.face
        XCTAssertEqual(CalcBadge.cheeks.count, 2)
        for cheek in CalcBadge.cheeks {
            // 和脸框下半部分有交集（画的时候裁进脸框）
            XCTAssertTrue(cheek.overlaps(face))
            XCTAssertGreaterThan(cheek.midY, face.midY)
        }
        // 伸出脸框左右边，裁完角上整块是奶白
        XCTAssertLessThan(CalcBadge.cheeks[0].x0, face.x0)
        XCTAssertGreaterThan(CalcBadge.cheeks[1].x1, face.x1)
        XCTAssertLessThan(CalcBadge.cheeks[0].midX, face.midX)
        XCTAssertGreaterThan(CalcBadge.cheeks[1].midX, face.midX)
        // 左右对称
        XCTAssertEqual(CalcBadge.cheeks[0].x0, 1 - CalcBadge.cheeks[1].x1, accuracy: 1e-9)
    }

    func testEyesAreInsideTheScreenAndSymmetric() {
        XCTAssertTrue(CalcBadge.screen.contains(CalcBadge.openEye))
        XCTAssertEqual(CalcBadge.openEye.midY, CalcBadge.screen.midY, accuracy: 1e-9)
        XCTAssertGreaterThan(CalcBadge.openEye.height, CalcBadge.openEye.width, "睁眼是竖胶囊")
        XCTAssertEqual(CalcBadge.eyeCenters.left + CalcBadge.eyeCenters.right, 1, accuracy: 1e-9)

        let wink = CalcBadge.wink
        let half = wink.lineWidth / 2
        for p in wink.points() {
            XCTAssertTrue(CalcBadge.screen.contains(x: p.x - half, y: p.y - half))
            XCTAssertTrue(CalcBadge.screen.contains(x: p.x + half, y: p.y + half))
        }
    }

    func testWinkArchesUpward() {
        let points = CalcBadge.wink.points(steps: 20)
        let middle = points[points.count / 2]
        // y 向下：中点比两头高（y 更小），是 ^ 形
        XCTAssertLessThan(middle.y, points.first!.y)
        XCTAssertLessThan(middle.y, points.last!.y)
        XCTAssertLessThan(points.first!.x, points.last!.x)
        XCTAssertEqual(points.first!.y, points.last!.y, accuracy: 1e-9, "左右对称")
    }

    func testKeysAreATwoByTwoGridWithGaps() {
        let keys = CalcBadge.keys
        XCTAssertEqual(keys.count, 4)
        XCTAssertEqual(CalcBadge.Key.allCases.count, 4)
        for (i, a) in keys.enumerated() {
            XCTAssertTrue(CalcBadge.keypad.contains(a))
            XCTAssertGreaterThan(a.width, a.height, "胶囊键是横的")
            for b in keys[(i + 1)...] {
                XCTAssertFalse(a.overlaps(b))
            }
        }
        XCTAssertEqual(keys[1].x0 - keys[0].x1, CalcBadge.keyGap, accuracy: 1e-9)
        XCTAssertEqual(keys[2].y0 - keys[0].y1, CalcBadge.keyGap, accuracy: 1e-9)
        XCTAssertEqual(CalcBadge.key(.equals), keys[3], "＝在右下")
        XCTAssertGreaterThan(keys[0].y0, CalcBadge.face.y1, "按键在脸下面")
        XCTAssertTrue(CalcBadge.Key.equals.isAccent)
        XCTAssertFalse(CalcBadge.Key.plus.isAccent)
    }

    func testSymbolStrokesAreAtLeastOnePointAtEverySize() {
        for size in CalcBadge.sizes {
            XCTAssertGreaterThanOrEqual(CalcBadge.symbolStroke(size: size), 1, "\(size)pt")
            XCTAssertGreaterThanOrEqual(CalcBadge.equalsStroke(size: size), 1, "\(size)pt")
            // 竖胶囊眼、眨眼弧也不细过 1pt
            XCTAssertGreaterThanOrEqual(CalcBadge.openEye.width * size, 1)
            XCTAssertGreaterThanOrEqual(CalcBadge.wink.lineWidth * size, 1)
        }
        XCTAssertGreaterThan(CalcBadge.symbolStroke(size: 112), CalcBadge.symbolStroke(size: 26), "大尺寸跟着变粗")
    }

    func testSymbolsStayInsideTheirKeys() {
        for size in CalcBadge.sizes {
            let stroke = CalcBadge.symbolStroke(size: size) / size
            for key in CalcBadge.Key.allCases {
                let box = CalcBadge.key(key)
                for (a, b) in CalcBadge.symbolSegments(key, size: size) {
                    for (x, y) in [a, b] {
                        XCTAssertTrue(box.contains(x: x - stroke / 2, y: y - stroke / 2), "\(key) \(size)pt")
                        XCTAssertTrue(box.contains(x: x + stroke / 2, y: y + stroke / 2), "\(key) \(size)pt")
                    }
                }
            }
        }
        XCTAssertEqual(CalcBadge.symbolSegments(.plus, size: 40).count, 2)
        XCTAssertEqual(CalcBadge.symbolSegments(.minus, size: 40).count, 1)
        XCTAssertEqual(CalcBadge.symbolSegments(.times, size: 40).count, 2)
        XCTAssertEqual(CalcBadge.symbolSegments(.equals, size: 40).count, 2)
        XCTAssertGreaterThan(CalcBadge.symbolArm(size: 26), CalcBadge.symbolArm(size: 40), "小尺寸符号相对大一点")
    }

    func testEqualsKeyIsReadable() {
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(CalcBadge.equalsInk, CalcBadge.panda), 4.5)
        let grad = CalcBadge.keyGradient(CalcBadge.panda)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(CalcBadge.equalsInk, grad.top), 3)
    }

    func testDefaultPurpleKeysKeepWhiteSymbols() {
        let purple = WidgetTint.defaultPalette(.calculator).main
        for dark in [false, true] {
            let fill = CalcBadge.keyFill(main: WidgetTint.readable(purple, dark: dark), dark: dark)
            XCTAssertFalse(CalcBadge.keyInkIsDark(on: fill), dark ? "深色" : "浅色")
        }
        // 浅色外观往深紫压一点，深色外观原样
        let light = CalcBadge.keyFill(main: purple, dark: false)
        XCTAssertLessThan(WidgetTint.luminance(light), WidgetTint.luminance(purple))
        XCTAssertEqual(CalcBadge.keyFill(main: purple, dark: true), purple)
    }

    func testPaleThemeKeysSwitchToDarkSymbols() {
        let yellow = ColorCode(hex: "#FFD60A")!
        XCTAssertTrue(CalcBadge.keyInkIsDark(on: CalcBadge.keyFill(main: yellow, dark: true)))
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(CalcBadge.darkKeyInk, yellow), 3)
    }

    func testScreenIsInkNotBlackInLightAndDarkerInDark() {
        let light = CalcBadge.screenColors(dark: false), dark = CalcBadge.screenColors(dark: true)
        XCTAssertNotEqual(light.top, ColorCode(red: 0, green: 0, blue: 0))
        XCTAssertGreaterThan(light.top.blue, light.top.red, "浅色下是深紫墨色")
        XCTAssertLessThan(WidgetTint.luminance(dark.top), WidgetTint.luminance(light.top))
        XCTAssertLessThan(WidgetTint.luminance(light.bottom), WidgetTint.luminance(light.top), "上亮下暗")
        // 白眼睛在屏幕上清楚
        for scheme in [light, dark] {
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(CalcBadge.eyeWhite, scheme.top), 7)
        }
    }

    func testPandaColorsMatchTheDesign() {
        XCTAssertEqual(CalcBadge.panda, ColorCode(hex: "#E0682C"))
        XCTAssertEqual(CalcBadge.pandaHighlight, ColorCode(hex: "#F28E4E"))
        XCTAssertEqual(CalcBadge.cream, ColorCode(hex: "#FFF6EC"))
        XCTAssertEqual(CalcBadge.sizes, [40, 34, 32, 26])
    }
}
