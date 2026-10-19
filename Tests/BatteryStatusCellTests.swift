import XCTest

/// 电池“电量”样式（原来叫“状态”）换成电池形状后的纯逻辑。
final class BatteryStatusCellTests: XCTestCase {

    func testClassicAndLiquidDrawTheCellOthersKeepTheirOwn() {
        XCTAssertTrue(BatteryStatusCell.drawsCell(look: BatteryLook.classic.rawValue))
        XCTAssertTrue(BatteryStatusCell.drawsCell(look: BatteryLook.liquid.rawValue))
        XCTAssertFalse(BatteryStatusCell.drawsCell(look: BatteryLook.pixel.rawValue))
        XCTAssertFalse(BatteryStatusCell.drawsCell(look: BatteryLook.particles.rawValue))
        XCTAssertFalse(BatteryStatusCell.drawsCell(look: BatteryLook.panda.rawValue))
        XCTAssertTrue(BatteryStatusCell.drawsCell(look: "something-old"), "认不出的旧值按经典")
    }

    func testOldStatusConfigStillReadsAsTheStatusCard() {
        var config = WidgetConfig()
        config.set("layout", .string("status"))
        config.set("devices", .list([.string("mac")]))
        XCTAssertTrue(BatteryShelf.isStatusCard(config), "存的值不变，旧卡片照样是电量卡片")
    }

    func testLabelNeverInventsALevel() {
        XCTAssertEqual(BatteryStatusCell.label(level: 0.764, present: true), "76")
        XCTAssertEqual(BatteryStatusCell.label(level: 1, present: true), "100")
        XCTAssertEqual(BatteryStatusCell.label(level: 1.4, present: true), "100")
        XCTAssertEqual(BatteryStatusCell.label(level: -0.2, present: true), "0")
        XCTAssertEqual(BatteryStatusCell.label(level: 0.5, present: false), "-")
        XCTAssertEqual(BatteryStatusCell.label(level: .nan, present: true), "-")
    }

    func testCellFitsTheShortCard() {
        let size = BatteryStatusCell.cellSize(cardHeight: 58)
        XCTAssertEqual(size.height, 29)
        XCTAssertEqual(size.width, 61)
        XCTAssertLessThanOrEqual(size.height, 58 - 2 * 12, "扣掉卡片上下边距放得下")
        XCTAssertEqual(BatteryStatusCell.cellSize(cardHeight: 40).height, 26)
        XCTAssertEqual(BatteryStatusCell.cellSize(cardHeight: 132).height, 30)
        XCTAssertEqual(BatteryStatusCell.cellSize(cardHeight: .infinity).height, 29)
    }

    func testLowBatteryTurnsRedLikeTheCell() {
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.08, charging: false, present: true), .critical)
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.18, charging: false, present: true), .low)
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.08, charging: true, present: true), .normal,
                       "充电中不报警")
    }

    func testInkContrastsWithTheFill() {
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .normal, liquid: false), .inverted)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .normal, liquid: true), .white)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .low, liquid: false), .white)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .critical, liquid: true), .white)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .absent, liquid: false), .none)
    }

    func testGeometryMatchesTheDrawnCell() {
        let g = BatteryStatusCell.geometry(long: 61, short: 29)
        XCTAssertEqual(g.nub, 61 * 0.07, accuracy: 0.0001)
        XCTAssertEqual(g.bodyLong, 61 - g.nub - 1, accuracy: 0.0001)
        XCTAssertEqual(g.stroke, 29 * 0.08, accuracy: 0.0001)
        XCTAssertEqual(g.inset, g.stroke + 29 * 0.07, accuracy: 0.0001)
        XCTAssertEqual(g.innerLong, g.bodyLong - 2 * g.inset, accuracy: 0.0001)
        XCTAssertEqual(g.fillEnd(0), g.inset, accuracy: 0.0001)
        XCTAssertEqual(g.fillEnd(1), g.inset + g.innerLong, accuracy: 0.0001)
        XCTAssertEqual(g.fillEnd(2), g.fillEnd(1), accuracy: 0.0001)
        XCTAssertEqual(g.fillEnd(.nan), g.inset, accuracy: 0.0001)

        let tiny = BatteryStatusCell.geometry(long: 10, short: 5)
        XCTAssertEqual(tiny.nub, 2, "凸起至少 2pt")
        XCTAssertEqual(tiny.stroke, 1.4, accuracy: 0.0001, "外框至少 1.4pt")
        XCTAssertGreaterThanOrEqual(tiny.innerLong, 0)
    }
}
