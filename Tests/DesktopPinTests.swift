import Foundation
import XCTest

/// 钉在桌面：尺寸、网格吸附、屏幕坐标换算、断屏回收、找空位、免费上限、便签单页标识。
final class DesktopPinTests: XCTestCase {

    /// 1440×900 的主屏，菜单栏 25、程序坞不占（AppKit 坐标，y 向上）。
    private let main = DesktopScreen(id: 1, visible: CGRect(x: 0, y: 0, width: 1440, height: 875))
    /// 接在右边的外接屏。
    private let side = DesktopScreen(id: 7, visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055))

    // MARK: 尺寸

    func testThreeSizes() {
        XCTAssertEqual(DesktopPinSize.small.size, CGSize(width: 160, height: 160))
        XCTAssertEqual(DesktopPinSize.medium.size, CGSize(width: 340, height: 160))
        XCTAssertEqual(DesktopPinSize.large.size, CGSize(width: 340, height: 340))
        XCTAssertEqual(DesktopPinSize.allCases.filter(\.isPro), [.large])
        XCTAssertEqual(DesktopPinSize.medium.label, "中 340×160")
    }

    func testSizesSitOnTheGridWithTheGap() {
        // 两张小卡并排加中间 20pt 正好是一张中卡宽，两张中卡叠起来加 20pt 是一张大卡高。
        let grid = DesktopPinLayout.grid
        XCTAssertEqual(DesktopPinSize.small.width * 2 + DesktopPinLayout.gap, DesktopPinSize.medium.width)
        XCTAssertEqual(DesktopPinSize.medium.height * 2 + DesktopPinLayout.gap, DesktopPinSize.large.height)
        for size in DesktopPinSize.allCases {
            XCTAssertEqual(size.width.truncatingRemainder(dividingBy: grid), 0)
            XCTAssertEqual(size.height.truncatingRemainder(dividingBy: grid), 0)
        }
    }

    // MARK: 网格吸附

    func testSnapRoundsToTheTwentyPointGrid() {
        let size = DesktopPinSize.small.size
        let snapped = DesktopPinLayout.snap(CGPoint(x: 109, y: 503), size: size, in: main.visible)
        XCTAssertEqual(snapped.x, 100)
        // 顶边从可用区域顶往下 20pt 起算：875 - 20 = 855，503 + 160 = 663 → 离 855 差 192，吸到 200。
        XCTAssertEqual(snapped.y + size.height, 655)
    }

    func testSnapKeepsTheCardOnScreenWithAMargin() {
        let size = DesktopPinSize.large.size
        let farRight = DesktopPinLayout.snap(CGPoint(x: 5000, y: -900), size: size, in: main.visible)
        XCTAssertLessThanOrEqual(farRight.x + size.width, main.visible.maxX - DesktopPinLayout.margin)
        XCTAssertGreaterThanOrEqual(farRight.y, main.visible.minY + DesktopPinLayout.margin - 0.01)
        let farLeft = DesktopPinLayout.snap(CGPoint(x: -300, y: 5000), size: size, in: main.visible)
        XCTAssertEqual(farLeft.x, DesktopPinLayout.margin)
        XCTAssertEqual(farLeft.y + size.height, main.visible.maxY - DesktopPinLayout.margin)
    }

    func testClampedPositionsStayOnTheGrid() {
        let size = DesktopPinSize.medium.size
        let snapped = DesktopPinLayout.snap(CGPoint(x: 5000, y: -900), size: size, in: main.visible)
        let fromLeft = snapped.x - (main.visible.minX + DesktopPinLayout.margin)
        let fromTop = (main.visible.maxY - DesktopPinLayout.margin) - (snapped.y + size.height)
        XCTAssertEqual(fromLeft.truncatingRemainder(dividingBy: DesktopPinLayout.grid), 0)
        XCTAssertEqual(fromTop.truncatingRemainder(dividingBy: DesktopPinLayout.grid), 0)
    }

    // MARK: 相对坐标

    func testRelativeRoundTrip() {
        for size in DesktopPinSize.allCases {
            let origin = DesktopPinLayout.snap(CGPoint(x: 620, y: 300), size: size.size, in: main.visible)
            let rel = DesktopPinLayout.relative(origin, size: size.size, in: main.visible)
            let back = DesktopPinLayout.origin(x: rel.x, y: rel.y, size: size.size, in: main.visible)
            XCTAssertEqual(back, origin, "\(size)")
        }
    }

    func testRelativeCornersAreZeroAndOne() {
        let size = DesktopPinSize.small.size
        let topLeft = DesktopPinLayout.origin(x: 0, y: 0, size: size, in: main.visible)
        XCTAssertEqual(topLeft.x, 20)
        XCTAssertEqual(topLeft.y + size.height, 855)
        let rel = DesktopPinLayout.relative(topLeft, size: size, in: main.visible)
        XCTAssertEqual(rel.x, 0)
        XCTAssertEqual(rel.y, 0)
        let bottomRight = DesktopPinLayout.origin(x: 1, y: 1, size: size, in: main.visible)
        XCTAssertLessThanOrEqual(bottomRight.x + size.width, 1420)
        XCTAssertGreaterThanOrEqual(bottomRight.y, 20)
    }

    func testRelativeIsClampedAndSurvivesBadValues() {
        let pin = DesktopPin(widgetID: UUID(), size: .small, x: 7, y: .nan)
        XCTAssertEqual(pin.x, 1)
        XCTAssertEqual(pin.y, 0)
    }

    func testAResolutionChangeKeepsRoughlyTheSamePlace() {
        let size = DesktopPinSize.medium.size
        let origin = DesktopPinLayout.snap(CGPoint(x: 1000, y: 100), size: size, in: main.visible)
        let rel = DesktopPinLayout.relative(origin, size: size, in: main.visible)
        let bigger = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        let moved = DesktopPinLayout.origin(x: rel.x, y: rel.y, size: size, in: bigger)
        XCTAssertGreaterThan(moved.x, 1500, "还在右边")
        XCTAssertLessThan(moved.y, 400, "还在下面")
    }

    // MARK: 屏幕

    func testPinGoesToItsOwnScreen() {
        let pin = DesktopPin(widgetID: UUID(), size: .small, displayID: 7, x: 0, y: 0)
        let frame = DesktopPinLayout.frame(for: pin, screens: [main, side])
        XCTAssertEqual(frame?.minX, 1460)
    }

    func testDisconnectedScreenFallsBackToMainAndComesBack() {
        let pin = DesktopPin(widgetID: UUID(), size: .small, displayID: 7, x: 0.5, y: 0.5)
        let alone = DesktopPinLayout.frame(for: pin, screens: [main])
        XCTAssertNotNil(alone)
        XCTAssertTrue(main.visible.contains(alone!), "收回主屏")
        XCTAssertEqual(pin.displayID, 7, "存着的屏幕不改")
        let back = DesktopPinLayout.frame(for: pin, screens: [main, side])
        XCTAssertTrue(side.visible.contains(back!), "接回去回到原处")
    }

    func testNoScreensMeansNoFrame() {
        let pin = DesktopPin(widgetID: UUID(), size: .small)
        XCTAssertNil(DesktopPinLayout.frame(for: pin, screens: []))
    }

    func testFrameUsesTheDrawnSize() {
        let pin = DesktopPin(widgetID: UUID(), size: .large, displayID: 1)
        XCTAssertEqual(DesktopPinLayout.frame(for: pin, size: .medium, screens: [main])?.size,
                       DesktopPinSize.medium.size)
    }

    func testScreenContainingAPoint() {
        XCTAssertEqual(DesktopPinLayout.screen(containing: CGPoint(x: 2000, y: 500), screens: [main, side])?.id, 7)
        XCTAssertEqual(DesktopPinLayout.screen(containing: CGPoint(x: 100, y: 500), screens: [main, side])?.id, 1)
        // 落在菜单栏上（不在可用区域里）取最近的一块。
        XCTAssertEqual(DesktopPinLayout.screen(containing: CGPoint(x: 100, y: 890), screens: [main, side])?.id, 1)
    }

    // MARK: 空位

    func testFirstFreeStartsTopLeft() {
        let size = DesktopPinSize.small.size
        let first = DesktopPinLayout.firstFree(size: size, occupied: [], in: main.visible)
        XCTAssertEqual(first, CGPoint(x: 20, y: 855 - 160))
    }

    func testFirstFreeSkipsTakenPlacesAndKeepsTheGap() {
        let size = DesktopPinSize.small.size
        let taken = CGRect(origin: CGPoint(x: 20, y: 695), size: size)
        let next = DesktopPinLayout.firstFree(size: size, occupied: [taken], in: main.visible)
        XCTAssertEqual(next.x, 200, "隔 20pt 放在右边")
        XCTAssertEqual(next.y, 695)
        XCTAssertTrue(DesktopPinLayout.isFree(CGRect(origin: next, size: size), occupied: [taken]))
        XCTAssertFalse(DesktopPinLayout.isFree(CGRect(origin: CGPoint(x: 180, y: 695), size: size),
                                               occupied: [taken]), "贴着不留缝不算空")
    }

    func testNearestFreeUsesTheWantedPlaceWhenEmpty() {
        let size = DesktopPinSize.medium.size
        let spot = DesktopPinLayout.nearestFree(to: CGPoint(x: 405, y: 402), size: size,
                                                occupied: [], in: main.visible)
        XCTAssertEqual(spot, DesktopPinLayout.snap(CGPoint(x: 405, y: 402), size: size, in: main.visible))
    }

    func testNearestFreeStepsAside() {
        let size = DesktopPinSize.small.size
        let taken = CGRect(x: 400, y: 395, width: 160, height: 160)
        let spot = DesktopPinLayout.nearestFree(to: CGPoint(x: 400, y: 395), size: size,
                                                occupied: [taken], in: main.visible)
        XCTAssertTrue(DesktopPinLayout.isFree(CGRect(origin: spot, size: size), occupied: [taken]))
        XCTAssertLessThan(hypot(spot.x - 400, spot.y - 395), 220, "就在旁边")
    }

    func testNearestFreeWhenTheScreenIsFull() {
        let size = DesktopPinSize.large.size
        let wall = main.visible
        let spot = DesktopPinLayout.nearestFree(to: CGPoint(x: 300, y: 300), size: size,
                                                occupied: [wall], in: main.visible)
        XCTAssertEqual(spot, DesktopPinLayout.snap(CGPoint(x: 300, y: 300), size: size, in: main.visible))
    }

    // MARK: 免费 / Pro

    func testFreePinsOneSmallOrMedium() {
        XCTAssertEqual(DesktopPinGate.canPin(existing: 0, size: .small, unlocked: false), .allowed)
        XCTAssertEqual(DesktopPinGate.canPin(existing: 0, size: .medium, unlocked: false), .allowed)
        XCTAssertEqual(DesktopPinGate.canPin(existing: 0, size: .large, unlocked: false), .needsProForSize)
        XCTAssertEqual(DesktopPinGate.canPin(existing: 1, size: .small, unlocked: false), .needsProForCount)
        XCTAssertEqual(DesktopPinGate.canPin(existing: 1, size: .large, unlocked: false), .needsProForCount)
    }

    func testProHasNoLimit() {
        for size in DesktopPinSize.allCases {
            XCTAssertEqual(DesktopPinGate.canPin(existing: 12, size: size, unlocked: true), .allowed)
            XCTAssertEqual(DesktopPinGate.canResize(to: size, unlocked: true), .allowed)
        }
        XCTAssertEqual(DesktopPinGate.canResize(to: .large, unlocked: false), .needsProForSize)
        XCTAssertEqual(DesktopPinGate.canResize(to: .small, unlocked: false), .allowed)
    }

    func testLockedShowsTheFirstAndDrawsLargeAsMedium() {
        let pins = (0..<3).map { _ in DesktopPin(widgetID: UUID(), size: .large) }
        XCTAssertEqual(DesktopPinGate.shown(pins, unlocked: false), [pins[0]])
        XCTAssertEqual(DesktopPinGate.shown(pins, unlocked: true), pins)
        XCTAssertEqual(DesktopPinGate.effectiveSize(.large, unlocked: false), .medium)
        XCTAssertEqual(DesktopPinGate.effectiveSize(.large, unlocked: true), .large)
        XCTAssertEqual(DesktopPinGate.effectiveSize(.small, unlocked: false), .small)
        XCTAssertEqual(DesktopPinGate.lockedSizes(unlocked: false), [.large])
        XCTAssertTrue(DesktopPinGate.lockedSizes(unlocked: true).isEmpty)
    }

    func testProSettingListed() {
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.desktopPins))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.desktopPins)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.desktopPins)), "桌面卡片")
    }

    // MARK: 哪些能钉

    func testFirstBatchIsDedicated() {
        for kind in [WidgetKind.calculator, .notes, .todo, .clock, .weather, .timer, .countdown, .stopwatch] {
            XCTAssertEqual(DesktopPinSupport.mode(kind, hasDetail: true, panelWidth: 320), .dedicated)
        }
        XCTAssertEqual(DesktopPinSupport.sizes(.dedicated), [.small, .medium, .large])
    }

    func testGenericOnlyForPanelsThatFit() {
        XCTAssertEqual(DesktopPinSupport.mode(.battery, hasDetail: true, panelWidth: 330), .generic)
        XCTAssertEqual(DesktopPinSupport.mode(.slacker, hasDetail: true, panelWidth: 400), .none, "太宽")
        XCTAssertEqual(DesktopPinSupport.mode(.volume, hasDetail: false, panelWidth: 300), .none, "没有面板")
        XCTAssertEqual(DesktopPinSupport.mode(.aiAssistant, hasDetail: true, panelWidth: 320), .none)
        XCTAssertEqual(DesktopPinSupport.sizes(.generic), [.medium, .large])
        XCTAssertTrue(DesktopPinSupport.sizes(.none).isEmpty)
        XCTAssertEqual(DesktopPinSupport.defaultSize(.generic), .medium)
    }

    // MARK: 刷新节奏

    func testCadence() {
        XCTAssertEqual(DesktopPinCadence.interval(.clock), 60)
        XCTAssertEqual(DesktopPinCadence.interval(.clock, secondHand: true), 1)
        XCTAssertEqual(DesktopPinCadence.interval(.timer), 60)
        XCTAssertEqual(DesktopPinCadence.interval(.timer, running: true), 1)
        XCTAssertEqual(DesktopPinCadence.interval(.notes), 60)
        XCTAssertEqual(DesktopPinCadence.interval(.stopwatch), 1)
    }

    // MARK: 设置和已钉的卡片

    func testAddDoesNotDuplicateTheSameWidget() {
        var settings = DesktopPinSettings()
        let widget = UUID()
        settings.add(DesktopPin(widgetID: widget, size: .small))
        let firstID = settings.pins[0].id
        settings.add(DesktopPin(widgetID: widget, size: .medium, x: 0.5))
        XCTAssertEqual(settings.pins.count, 1)
        XCTAssertEqual(settings.pins[0].id, firstID, "还是那一张")
        XCTAssertEqual(settings.pins[0].size, .medium)
        // 同一张便签的不同两页是两张卡片。
        settings.add(DesktopPin(widgetID: widget, sheetID: "a", size: .medium))
        settings.add(DesktopPin(widgetID: widget, sheetID: "b", size: .medium))
        XCTAssertEqual(settings.pins.count, 3)
        XCTAssertNotNil(settings.pin(widget: widget, sheet: "b"))
        XCTAssertTrue(settings.hasPins(widget: widget))
    }

    func testRemoveAndUpdate() {
        var settings = DesktopPinSettings()
        let pin = DesktopPin(widgetID: UUID(), size: .small)
        settings.add(pin)
        settings.update(pin.id) { $0.size = .large }
        XCTAssertEqual(settings.pin(pin.id)?.size, .large)
        settings.remove(pin.id)
        XCTAssertTrue(settings.pins.isEmpty)
        settings.add(pin)
        settings.add(DesktopPin(widgetID: UUID(), size: .small))
        settings.removeAll()
        XCTAssertTrue(settings.pins.isEmpty)
    }

    func testOrphansAreUnpinned() {
        var settings = DesktopPinSettings()
        let kept = UUID(), gone = UUID(), note = UUID()
        settings.add(DesktopPin(widgetID: kept, size: .small))
        settings.add(DesktopPin(widgetID: gone, size: .small))
        settings.add(DesktopPin(widgetID: note, sheetID: "live", size: .medium))
        settings.add(DesktopPin(widgetID: note, sheetID: "torn", size: .medium))
        let changed = settings.removeOrphans(widgets: [kept, note]) { _, sheet in sheet == "live" }
        XCTAssertTrue(changed)
        XCTAssertEqual(settings.pins.map(\.widgetID), [kept, note])
        XCTAssertEqual(settings.pins.last?.sheetID, "live")
        XCTAssertFalse(settings.removeOrphans(widgets: [kept, note]) { _, _ in true })
    }

    func testSummary() {
        var settings = DesktopPinSettings()
        settings.add(DesktopPin(widgetID: UUID(), size: .large))
        settings.add(DesktopPin(widgetID: UUID(), size: .small))
        let names = ["算", "时钟"]
        var index = 0
        let text = settings.summary { _ in defer { index += 1 }; return names[index] }
        XCTAssertEqual(text, "算（大）、时钟（小）")
    }

    func testSettingsDecodeWithDefaultsAndSkipBrokenPins() throws {
        let empty = try JSONDecoder().decode(DesktopPinSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, DesktopPinSettings())
        XCTAssertTrue(empty.enabled)
        XCTAssertEqual(empty.spaces, .all)
        XCTAssertEqual(empty.covered, .stay)
        XCTAssertEqual(empty.appearance, .system)
        let id = UUID().uuidString
        let json = """
        {"enabled": false, "spaces": "current", "covered": "autoHide", "appearance": "dark",
         "pins": [{"widgetID": "\(id)", "size": "large", "displayID": 3, "x": 0.25, "y": 2},
                  {"size": "small"}, {"widgetID": "\(id)", "size": "huge", "sheetID": "s1"}]}
        """
        let decoded = try JSONDecoder().decode(DesktopPinSettings.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.spaces, .current)
        XCTAssertEqual(decoded.covered, .autoHide)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.pins.count, 2, "缺 widgetID 的那张跳过")
        XCTAssertEqual(decoded.pins[0].size, .large)
        XCTAssertEqual(decoded.pins[0].displayID, 3)
        XCTAssertEqual(decoded.pins[0].y, 1, "夹到 0 到 1")
        XCTAssertEqual(decoded.pins[1].size, .medium, "认不出的尺寸按中号")
        XCTAssertEqual(decoded.pins[1].sheetID, "s1")
        let round = try JSONDecoder().decode(DesktopPinSettings.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(round, decoded)
    }

    func testPersistedStateCarriesThePins() throws {
        var state = PersistedState()
        state.desktopPins.add(DesktopPin(widgetID: UUID(), size: .small, displayID: 9, x: 0.1, y: 0.2))
        let round = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round.desktopPins, state.desktopPins)
    }

    // MARK: 便签单页

    private func notes(_ texts: [String], page: Int = 0) -> WidgetConfig {
        var config = WidgetConfig()
        StickyStack.store(StickyStack.Pile(sheets: texts.map { StickySheet(text: $0) }, page: page), in: &config)
        return config
    }

    func testSheetIdentityIsAssignedOnceAndStored() throws {
        var config = notes(["一", "二", "三"])
        let pile = StickyStack.pile(config)
        let named = try XCTUnwrap(pile.identifying(at: 1, newID: "B"))
        XCTAssertEqual(named.id, "B")
        let again = try XCTUnwrap(named.pile.identifying(at: 1, newID: "other"))
        XCTAssertEqual(again.id, "B", "已有标识就用原来的")
        StickyStack.store(named.pile, in: &config)
        let read = StickyStack.pile(config)
        XCTAssertEqual(read.index(ofSheet: "B"), 1)
        XCTAssertEqual(read.sheets[1].text, "二")
        XCTAssertNil(read.index(ofSheet: ""))
        XCTAssertNil(pile.identifying(at: 9, newID: "x"))
    }

    func testSheetIdentityFollowsFlipsTearsAndAdds() throws {
        var config = notes(["一", "二", "三"])
        var pile = try XCTUnwrap(StickyStack.pile(config).identifying(at: 2, newID: "C")).pile
        // 前面那张也有标识，存在 sheetID 键里。
        pile = try XCTUnwrap(pile.identifying(at: 0, newID: "A")).pile
        StickyStack.store(pile, in: &config)
        XCTAssertEqual(config.string(StickyStack.sheetIDKey), "A")

        var read = StickyStack.pile(config).flipped(by: 2)
        StickyStack.store(read, in: &config)
        read = StickyStack.pile(config)
        XCTAssertEqual(read.front.id, "C", "翻到它，它在最上面")
        XCTAssertEqual(read.sheets[read.index(ofSheet: "A")!].text, "一")

        // 撕掉最上面那张（就是 C）：C 没了。
        StickyStack.store(read.removingFront(), in: &config)
        read = StickyStack.pile(config)
        XCTAssertNil(read.index(ofSheet: "C"))
        XCTAssertNotNil(read.index(ofSheet: "A"))

        // 加新一张不动 A。
        StickyStack.store(read.adding(color: PaperColor.mint.rawValue), in: &config)
        read = StickyStack.pile(config)
        XCTAssertEqual(read.sheets[read.index(ofSheet: "A")!].text, "一")
    }

    func testWritingASheetInPlaceDoesNotFlip() {
        let pile = StickyStack.pile(notes(["一", "二", "三"], page: 0))
        let written = pile.writing("改了", at: 2)
        XCTAssertEqual(written.page, 0)
        XCTAssertEqual(written.sheets[2].text, "改了")
        XCTAssertEqual(written.sheets[0].text, "一")
        XCTAssertEqual(pile.writing("x", at: 7), pile, "越界不动")
    }

    func testOldNotesWithoutIdentitiesReadTheSame() {
        let config = notes(["一", "二"])
        XCTAssertNil(config[StickyStack.sheetIDKey], "没有标识时不写这个键")
        if case .list(let items) = config[StickyStack.stackKey], case .list(let pair) = items.first {
            XCTAssertEqual(pair.count, 2, "旧的两项写法不变")
        } else {
            XCTFail("stack missing")
        }
        XCTAssertTrue(StickyStack.pile(config).sheets.allSatisfy { $0.id.isEmpty })
    }

    func testSheetLabel() {
        XCTAssertEqual(DesktopPinSheet.label(index: 1, text: "给妈妈回个电话\n第二行"), "第 2 张 · 给妈妈回个电话")
        XCTAssertEqual(DesktopPinSheet.label(index: 0, text: "\n[ ] 买猫粮和抽纸"), "第 1 张 · 买猫粮和抽纸")
        XCTAssertEqual(DesktopPinSheet.label(index: 2, text: "  "), "第 3 张 · 空白")
        XCTAssertEqual(DesktopPinSheet.label(index: 0, text: "一二三四五六七八九十十一十二十三"),
                       "第 1 张 · 一二三四五六七八九十十一…")
    }
}
