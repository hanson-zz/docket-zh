import XCTest

/// 隔空投送卡片：普通态、拖入态、拖来的不是文件、系统不支持，以及何时竖排。
final class AirDropDropTests: XCTestCase {

    func testStates() {
        XCTAssertEqual(AirDropDrop.state(available: true, dragging: false, files: 0), .idle)
        XCTAssertEqual(AirDropDrop.state(available: true, dragging: true, files: 2), .targeted(files: 2))
        XCTAssertEqual(AirDropDrop.state(available: true, dragging: true, files: 0), .noFiles)
        XCTAssertEqual(AirDropDrop.state(available: false, dragging: true, files: 3), .unavailable)
    }

    func testCopy() {
        XCTAssertEqual(AirDropDrop.State.idle.title, "隔空投送")
        XCTAssertEqual(AirDropDrop.State.idle.caption, "拖文件到这里")
        XCTAssertEqual(AirDropDrop.State.targeted(files: 2).title, "发送给附近设备")
        XCTAssertEqual(AirDropDrop.State.targeted(files: 2).caption, "2 个文件 · 松手选设备")
        XCTAssertTrue(AirDropDrop.State.targeted(files: 1).highlighted)
        XCTAssertFalse(AirDropDrop.State.idle.highlighted)
        XCTAssertTrue(AirDropDrop.State.unavailable.disabled)
        XCTAssertTrue(AirDropDrop.State.noFiles.disabled)
        XCTAssertFalse(AirDropDrop.State.targeted(files: 1).disabled)
    }

    func testColumnOnlyWhenTight() {
        XCTAssertFalse(AirDropDrop.usesColumn(vertical: false, width: 176))
        XCTAssertTrue(AirDropDrop.usesColumn(vertical: true, width: 176))
        XCTAssertTrue(AirDropDrop.usesColumn(vertical: false, width: 76))
        XCTAssertEqual(AirDropDrop.columnTitle.split(separator: "\n").count, 2)
    }

    func testCardIsWideEnoughForTheRow() {
        if let card = WidgetCatalog.make(.airdrop) {
            XCTAssertFalse(AirDropDrop.usesColumn(vertical: false, width: WidgetCatalog.naturalSize(card).width))
        } else {
            XCTFail("隔空投送应在目录里")
        }
    }
}
