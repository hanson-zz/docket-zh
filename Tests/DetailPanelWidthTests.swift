import XCTest

/// 详情面板内容区宽度和撑宽检查（beta.27 正在播放面板右侧被裁）。
final class DetailPanelWidthTests: XCTestCase {

    func testContentWidthOnTopOrBottomShelf() {
        XCTAssertEqual(DetailPanelWidth.content(panel: 320, tailDepth: 10, tailOnSide: false), 288)
        XCTAssertEqual(DetailPanelWidth.content(panel: 360, tailDepth: 10, tailOnSide: false), 328)
    }

    func testContentWidthWithSideTail() {
        XCTAssertEqual(DetailPanelWidth.content(panel: 320, tailDepth: 10, tailOnSide: true), 278)
    }

    func testContentWidthNeverNegative() {
        XCTAssertEqual(DetailPanelWidth.content(panel: 20, tailDepth: 10, tailOnSide: true), 0)
    }

    func testOverflowIgnoresRounding() {
        XCTAssertEqual(DetailPanelWidth.overflow(content: 288, available: 288), 0)
        XCTAssertEqual(DetailPanelWidth.overflow(content: 288.3, available: 288), 0)
        XCTAssertEqual(DetailPanelWidth.overflow(content: 200, available: 288), 0)
    }

    /// 原来正在播放的封面光晕按 1.64 倍封面边长参与排版，320 面板里撑宽 46pt 多。
    func testOldMusicCoverGlowOverflowedTheMusicPanel() {
        let available = DetailPanelWidth.content(panel: 320, tailDepth: 10, tailOnSide: false)
        let glow: CGFloat = 204 * 1.64
        XCTAssertGreaterThan(DetailPanelWidth.overflow(content: glow, available: available), 40)
        // 现在只有封面本身参与排版。
        XCTAssertEqual(DetailPanelWidth.overflow(content: 204, available: available), 0)
    }
}
