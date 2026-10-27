import XCTest
import Foundation

/// 钉在桌面 · Files 组专属布局的纯判断（`DesktopCardsFilesPlan`）。
final class DesktopCardsFilesTests: XCTestCase {
    private let group: [WidgetKind] = [
        .downloads, .fileShelf, .clipboard, .bookmarks, .capture,
        .photos, .screenshots, .wallpaper, .slacker, .volume,
    ]

    func testGroupKindsAreDedicatedWithAllThreeSizes() {
        XCTAssertEqual(DesktopCardsFilesPlan.kinds, Set(group))
        for kind in group {
            // 面板宽、有没有面板都不影响：摸鱼时钟面板 400 宽、音量没有面板，也走专属布局。
            XCTAssertEqual(DesktopPinSupport.mode(kind, hasDetail: kind != .volume, panelWidth: 400), .dedicated,
                           kind.rawValue)
            XCTAssertEqual(DesktopCardsFilesPlan.sizes(kind), [.small, .medium, .large], kind.rawValue)
        }
    }

    func testAIAssistantStaysUnpinnable() {
        XCTAssertFalse(DesktopCardsFilesPlan.handles(.aiAssistant))
        XCTAssertEqual(DesktopPinSupport.mode(.aiAssistant, hasDetail: true, panelWidth: 320), .none)
        XCTAssertTrue(DesktopCardsFilesPlan.sizes(.aiAssistant).isEmpty)
        XCTAssertEqual(DesktopPinSupport.excludedKinds, [.aiAssistant])
    }

    func testPhotosWallpaperCaptureNoLongerExcluded() {
        for kind in [WidgetKind.photos, .wallpaper, .capture, .volume, .screenshots, .slacker] {
            XCTAssertFalse(DesktopPinSupport.excludedKinds.contains(kind), kind.rawValue)
        }
    }

    func testListRowsPerSize() {
        for kind in group {
            XCTAssertEqual(DesktopCardsFilesPlan.rows(kind, size: .small), 0, "小号只有主角：\(kind.rawValue)")
        }
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.downloads, size: .medium), 3)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.downloads, size: .large), 5)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.downloads, size: .large, downloading: 1), 4)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.downloads, size: .large, downloading: 2), 3)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.downloads, size: .large, downloading: 9), 3, "最多 2 张下载卡，至少留 3 行")
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.clipboard, size: .medium), 3)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.clipboard, size: .large), 6)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.volume, size: .medium), 4)
        XCTAssertEqual(DesktopCardsFilesPlan.rows(.volume, size: .large), 5)
    }

    func testClipboardSplitKeepsPinsOnTopAndFillsTheRest() {
        let split = DesktopCardsFilesPlan.clipboardSplit
        XCTAssertTrue(split(0, 10, .large) == (0, 6), "没有星标，全是最近")
        XCTAssertTrue(split(2, 10, .large) == (2, 4))
        XCTAssertTrue(split(8, 10, .large) == (3, 3), "星标最多 3 条")
        XCTAssertTrue(split(8, 1, .large) == (5, 1), "最近的不够，星标补满空位")
        XCTAssertTrue(split(0, 0, .large) == (0, 0))
        XCTAssertTrue(split(5, 10, .medium) == (0, 3), "中号只列最近 3 条")
        XCTAssertTrue(split(5, 2, .medium) == (0, 2))
    }

    func testGrids() {
        typealias G = DesktopCardsFilesPlan.Grid
        XCTAssertEqual(DesktopCardsFilesPlan.bookmarkGrid(.small), G(columns: 2, rows: 2))
        XCTAssertEqual(DesktopCardsFilesPlan.bookmarkGrid(.medium).capacity, Bookmark.tileLimit,
                       "中号和扩展栏卡片一样最多 8 个")
        XCTAssertEqual(DesktopCardsFilesPlan.bookmarkGrid(.large), G(columns: 1, rows: 6))
        XCTAssertEqual(DesktopCardsFilesPlan.shelfGrid(.medium), G(columns: 4, rows: 1))
        XCTAssertEqual(DesktopCardsFilesPlan.shelfGrid(.large).capacity, 12)
        XCTAssertEqual(DesktopCardsFilesPlan.shotGrid(.small).capacity, 0)
        XCTAssertEqual(DesktopCardsFilesPlan.shotGrid(.medium), G(columns: 2, rows: 2))
        XCTAssertEqual(DesktopCardsFilesPlan.shotGrid(.large), G(columns: 3, rows: 2))
        XCTAssertEqual(DesktopCardsFilesPlan.wallpaperGrid.capacity, 8)
    }

    func testCaptureButtonsGrid() {
        typealias G = DesktopCardsFilesPlan.Grid
        XCTAssertEqual(DesktopCardsFilesPlan.captureGrid(count: 4, size: .small), G(columns: 1, rows: 1), "小号一个大按钮")
        XCTAssertEqual(DesktopCardsFilesPlan.captureGrid(count: 1, size: .small), G(columns: 1, rows: 1))
        XCTAssertEqual(DesktopCardsFilesPlan.captureGrid(count: 3, size: .medium), G(columns: 3, rows: 1))
        XCTAssertEqual(DesktopCardsFilesPlan.captureGrid(count: 4, size: .medium), G(columns: 4, rows: 1))
        XCTAssertEqual(DesktopCardsFilesPlan.captureGrid(count: 6, size: .large), G(columns: 4, rows: 1), "最多 4 个")
        XCTAssertEqual(DesktopCardsFilesPlan.captureGrid(count: 0, size: .large).capacity, 0)
    }

    func testSlotsPutPlusNInTheLastCell() {
        XCTAssertTrue(DesktopCardsFilesPlan.slots(total: 3, capacity: 4) == (3, 0))
        XCTAssertTrue(DesktopCardsFilesPlan.slots(total: 4, capacity: 4) == (4, 0), "正好放下不写 +N")
        XCTAssertTrue(DesktopCardsFilesPlan.slots(total: 5, capacity: 4) == (3, 2))
        XCTAssertTrue(DesktopCardsFilesPlan.slots(total: 20, capacity: 12) == (11, 9))
        XCTAssertTrue(DesktopCardsFilesPlan.slots(total: -1, capacity: 4) == (0, 0))
        XCTAssertTrue(DesktopCardsFilesPlan.slots(total: 2, capacity: 0) == (0, 2))
    }

    func testSlackerCellsAndPhotoTick() {
        XCTAssertEqual(DesktopCardsFilesPlan.slackerCells(.small, available: 4), 0)
        XCTAssertEqual(DesktopCardsFilesPlan.slackerCells(.medium, available: 3), 3)
        XCTAssertEqual(DesktopCardsFilesPlan.slackerCells(.large, available: 9), 4)
        XCTAssertEqual(DesktopCardsFilesPlan.photoTick(interval: 30, count: 5, paused: false), 1)
        XCTAssertEqual(DesktopCardsFilesPlan.photoTick(interval: 30, count: 5, paused: true), 60)
        XCTAssertEqual(DesktopCardsFilesPlan.photoTick(interval: 30, count: 1, paused: false), 60)
    }
}
