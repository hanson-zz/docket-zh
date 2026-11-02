import CoreGraphics
import Foundation
import XCTest

/// 窗口切换器的样式（缩略图、图标、标题列表）和选中窗口的全尺寸预览。
final class WindowSwitcherStyleTests: XCTestCase {

    private let screen = CGSize(width: 1440, height: 900)

    // MARK: 设置

    func testDefaultsAndOldData() throws {
        let s = WindowSwitcherSettings()
        XCTAssertTrue(s.largePreview)
        XCTAssertEqual(s.style, .thumbnails)
        let old = try JSONDecoder().decode(WindowSwitcherSettings.self,
                                           from: Data(#"{"groupByApp":true,"commandTab":true}"#.utf8))
        XCTAssertTrue(old.largePreview, "旧数据没有这个键时大预览是开的")
        XCTAssertEqual(old.style, .thumbnails)
        XCTAssertTrue(old.commandTab)
        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(state.windowSwitcher.style, .thumbnails)
        XCTAssertTrue(state.windowSwitcher.largePreview)
    }

    func testUnknownStyleReadsThumbnails() throws {
        let s = try JSONDecoder().decode(WindowSwitcherSettings.self,
                                         from: Data(#"{"style":"carousel","largePreview":"no"}"#.utf8))
        XCTAssertEqual(s.style, .thumbnails)
        XCTAssertTrue(s.largePreview)
    }

    func testRoundTrip() throws {
        for style in WindowSwitcherStyle.allCases {
            var s = WindowSwitcherSettings()
            s.style = style
            s.largePreview = false
            let back = try JSONDecoder().decode(WindowSwitcherSettings.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(back, s)
        }
        XCTAssertEqual(WindowSwitcherStyle.allCases, [.thumbnails, .icons, .list])
        XCTAssertTrue(WindowSwitcherStyle.thumbnails.showsThumbnails)
        XCTAssertFalse(WindowSwitcherStyle.icons.showsThumbnails)
        XCTAssertFalse(WindowSwitcherStyle.list.showsThumbnails)
    }

    // MARK: 布局

    func testThumbnailStyleUnchanged() {
        XCTAssertEqual(WindowSwitcherLayout.layout(count: 6, visible: screen, style: .thumbnails),
                       WindowSwitcherLayout.layout(count: 6, visible: screen))
        XCTAssertEqual(WindowSwitcherLayout.cardSize(scale: 1, style: .thumbnails), WindowSwitcherLayout.cardSize(scale: 1))
    }

    func testIconCardsAreSmallerThanThumbnails() {
        let icon = WindowSwitcherLayout.cardSize(scale: 1, style: .icons)
        let thumb = WindowSwitcherLayout.cardSize(scale: 1, style: .thumbnails)
        XCTAssertLessThan(icon.width, thumb.width)
        XCTAssertLessThan(icon.height, thumb.height)
        let box = WindowSwitcherLayout.thumbnailSize(scale: 1, style: .icons)
        XCTAssertGreaterThanOrEqual(box.height, WindowSwitcherLayout.iconSize, "大图标放得下")
        XCTAssertEqual(icon.height - box.height, 3 * WindowSwitcherLayout.cardInset + WindowSwitcherLayout.captionHeight)

        let l = WindowSwitcherLayout.layout(count: 8, visible: screen, style: .icons)
        XCTAssertEqual(l.style, .icons)
        XCTAssertEqual(l.columns, 8, "8 个图标一行放得下")
        XCTAssertEqual(l.rows, 1)
        XCTAssertFalse(l.scrolls)
        XCTAssertLessThanOrEqual(l.panelSize.width, screen.width * WindowSwitcherLayout.maxWidthFraction)
    }

    func testListIsOneColumnAndScrollsWhenLong() {
        let short = WindowSwitcherLayout.layout(count: 5, visible: screen, style: .list)
        XCTAssertEqual(short.style, .list)
        XCTAssertEqual(short.columns, 1)
        XCTAssertEqual(short.rows, 5)
        XCTAssertFalse(short.scrolls)
        XCTAssertEqual(short.cardSize.height, WindowSwitcherLayout.listRowHeight)
        XCTAssertEqual(short.gridSize.height, 5 * WindowSwitcherLayout.listRowHeight + 4 * WindowSwitcherLayout.listGap)
        XCTAssertEqual(short.panelSize.width, WindowSwitcherLayout.minPanelWidth)
        XCTAssertEqual(short.gap, WindowSwitcherLayout.listGap)
        XCTAssertEqual(short.thumbnailSize.width, WindowSwitcherLayout.listIconSize)

        let long = WindowSwitcherLayout.layout(count: 60, visible: screen, style: .list)
        XCTAssertTrue(long.scrolls)
        XCTAssertEqual(long.rows, 60)
        XCTAssertLessThanOrEqual(long.panelSize.height, screen.height * WindowSwitcherLayout.maxHeightFraction + 1)

        XCTAssertEqual(WindowSwitcherLayout.layout(count: 0, visible: screen, style: .list).gridSize.height,
                       WindowSwitcherLayout.listRowHeight, "空列表按一行留出空状态")
        // 一列时上下键一次一行。
        XCTAssertEqual(WindowSwitcher.vertical(2, rows: 1, columns: short.columns, count: 5), 3)
        XCTAssertEqual(WindowSwitcher.vertical(2, rows: -1, columns: short.columns, count: 5), 1)
    }

    // MARK: 全尺寸预览

    private func entry(minimized: Bool = false, hidden: Bool = false,
                       desktop: WindowSwitcher.Desktop = .current) -> WindowSwitcher.Entry {
        WindowSwitcher.Entry(id: 1, appName: "App", title: "w", minimized: minimized, hidden: hidden, desktop: desktop)
    }

    func testPreviewOnlyForVisibleWindowsOnThisDesktop() {
        XCTAssertTrue(WindowSwitcherPreview.shows(entry(), enabled: true, canCapture: true))
        XCTAssertFalse(WindowSwitcherPreview.shows(entry(), enabled: false, canCapture: true))
        XCTAssertFalse(WindowSwitcherPreview.shows(entry(), enabled: true, canCapture: false), "没屏幕录制权限不显示")
        XCTAssertFalse(WindowSwitcherPreview.shows(entry(minimized: true), enabled: true, canCapture: true))
        XCTAssertFalse(WindowSwitcherPreview.shows(entry(hidden: true), enabled: true, canCapture: true))
        XCTAssertFalse(WindowSwitcherPreview.shows(entry(desktop: .other(2)), enabled: true, canCapture: true))
        XCTAssertFalse(WindowSwitcherPreview.shows(entry(desktop: .other(nil)), enabled: true, canCapture: true))
        XCTAssertEqual(WindowSwitcherPreview.delay, 0.15, accuracy: 0.001)
    }

    func testFrameFlipsToAppKitCoordinates() {
        let ax = CGRect(x: 100, y: 50, width: 800, height: 600)
        XCTAssertEqual(WindowSwitcherPreview.appKitFrame(ax, primaryHeight: 900),
                       CGRect(x: 100, y: 250, width: 800, height: 600))
        // 主屏上方的副屏：AX 的 y 是负的。
        let above = CGRect(x: 0, y: -1000, width: 400, height: 300)
        XCTAssertEqual(WindowSwitcherPreview.appKitFrame(above, primaryHeight: 900).minY, 1600)
    }

    func testPreviewPixelSize() {
        XCTAssertEqual(WindowSwitcherPreview.pixelSize(window: CGSize(width: 800, height: 600), scale: 2),
                       CGSize(width: 1600, height: 1200))
        let big = WindowSwitcherPreview.pixelSize(window: CGSize(width: 3000, height: 1500), scale: 2)
        XCTAssertEqual(big.width, WindowSwitcherPreview.maxPixels)
        XCTAssertEqual(big.height, WindowSwitcherPreview.maxPixels / 2)
        XCTAssertEqual(WindowSwitcherPreview.pixelSize(window: .zero, scale: 0), CGSize(width: 1, height: 1))
    }
}
