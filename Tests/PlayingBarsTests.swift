import XCTest

/// 正在播放的跳动小竖条。
final class PlayingBarsTests: XCTestCase {

    func testHeightsStayInRange() {
        for index in 0..<PlayingBars.count {
            for step in 0..<500 {
                let h = PlayingBars.height(index: index, t: Double(step) * 0.037)
                XCTAssertGreaterThanOrEqual(h, PlayingBars.rest)
                XCTAssertLessThanOrEqual(h, 1)
            }
        }
    }

    func testBarsActuallyMoveAndDiffer() {
        let a = PlayingBars.height(index: 0, t: 10)
        XCTAssertNotEqual(a, PlayingBars.height(index: 0, t: 10.3), "同一根条会动")
        XCTAssertNotEqual(a, PlayingBars.height(index: 1, t: 10), "相邻的条不一起跳")
    }

    func testStillOnlyWhenPausedHiddenOrReduced() {
        XCTAssertEqual(PlayingBars.framesPerSecond(playing: true, visible: true, reduceMotion: false), 12)
        XCTAssertNil(PlayingBars.framesPerSecond(playing: false, visible: true, reduceMotion: false))
        XCTAssertNil(PlayingBars.framesPerSecond(playing: true, visible: false, reduceMotion: false))
        XCTAssertNil(PlayingBars.framesPerSecond(playing: true, visible: true, reduceMotion: true))
    }

    func testStillHeightsAreStaggered() {
        let heights = (0..<4).map(PlayingBars.stillHeight(index:))
        XCTAssertEqual(Set(heights).count, 4)
        XCTAssertEqual(PlayingBars.stillHeight(index: -1), PlayingBars.stillHeight(index: 3))
    }
}
