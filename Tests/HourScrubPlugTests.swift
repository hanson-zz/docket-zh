import Foundation
import XCTest

/// 天气面板拖动逐小时预报的计算，以及断网插头动画的阶段和帧率。
final class HourScrubPlugTests: XCTestCase {

    // MARK: 拖动位置

    func testNowIndexSkipsHoursThatAlreadyEnded() {
        let starts: [Double] = [3600, 7200, 10800]
        // 刚刷新：第一列是下一个整点。
        XCTAssertEqual(HourScrub.nowIndex(starts: starts, now: 3000), 0)
        // 第一列这一小时正在进行，仍停在它。
        XCTAssertEqual(HourScrub.nowIndex(starts: starts, now: 5000), 0)
        // 第一列刚好过完，跳到第二列。
        XCTAssertEqual(HourScrub.nowIndex(starts: starts, now: 7200), 1)
        XCTAssertEqual(HourScrub.nowIndex(starts: starts, now: 11000), 2)
        // 全都过去了停在最后一列，没有数据是 0。
        XCTAssertEqual(HourScrub.nowIndex(starts: starts, now: 99_999), 2)
        XCTAssertEqual(HourScrub.nowIndex(starts: [], now: 0), 0)
    }

    func testColumnCentresMapToWholeIndices() {
        // 8 列，每列 30 宽：第 0 列中心 15，第 7 列中心 225。
        XCTAssertEqual(HourScrub.position(x: 15, width: 240, count: 8), 0, accuracy: 1e-9)
        XCTAssertEqual(HourScrub.position(x: 105, width: 240, count: 8), 3, accuracy: 1e-9)
        XCTAssertEqual(HourScrub.position(x: 225, width: 240, count: 8), 7, accuracy: 1e-9)
        // 两列中间是半格。
        XCTAssertEqual(HourScrub.position(x: 120, width: 240, count: 8), 3.5, accuracy: 1e-9)
    }

    func testPositionIsClampedAtBothEnds() {
        XCTAssertEqual(HourScrub.position(x: -50, width: 240, count: 8), 0)
        XCTAssertEqual(HourScrub.position(x: 999, width: 240, count: 8), 7)
        XCTAssertEqual(HourScrub.position(x: 50, width: 0, count: 8), 0)
        XCTAssertEqual(HourScrub.position(x: 50, width: 240, count: 1), 0)
    }

    func testNearestIndex() {
        XCTAssertEqual(HourScrub.index(position: 2.4, count: 8), 2)
        XCTAssertEqual(HourScrub.index(position: 2.6, count: 8), 3)
        XCTAssertEqual(HourScrub.index(position: 12, count: 8), 7)
        XCTAssertEqual(HourScrub.index(position: -1, count: 8), 0)
        XCTAssertEqual(HourScrub.index(position: 3, count: 0), 0)
    }

    func testInterpolatesBetweenNeighbours() {
        let temps: [Double] = [10, 14, 12]
        XCTAssertEqual(HourScrub.interpolate(temps, at: 0), 10)
        XCTAssertEqual(HourScrub.interpolate(temps, at: 0.5) ?? 0, 12, accuracy: 1e-9)
        XCTAssertEqual(HourScrub.interpolate(temps, at: 1.25) ?? 0, 13.5, accuracy: 1e-9)
        XCTAssertEqual(HourScrub.interpolate(temps, at: 2), 12)
        XCTAssertEqual(HourScrub.interpolate(temps, at: 9), 12)
        XCTAssertEqual(HourScrub.interpolate([7], at: 3), 7)
        XCTAssertNil(HourScrub.interpolate([], at: 0))
    }

    // MARK: 天色

    private let rise = Date(timeIntervalSinceReferenceDate: 6 * 3600)
    private let set = Date(timeIntervalSinceReferenceDate: 18 * 3600)

    private func at(_ hours: Double) -> Date { Date(timeIntervalSinceReferenceDate: hours * 3600) }

    func testNoonIsDayAndMidnightIsNight() {
        XCTAssertEqual(HourScrub.night(at: at(12), rise: rise, set: set), 0)
        XCTAssertEqual(HourScrub.night(at: at(2), rise: rise, set: set), 1)
        XCTAssertEqual(HourScrub.night(at: at(22), rise: rise, set: set), 1)
    }

    func testTwilightIsHalfwayAtSunriseAndSunset() {
        XCTAssertEqual(HourScrub.night(at: rise, rise: rise, set: set), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HourScrub.night(at: set, rise: rise, set: set), 0.5, accuracy: 1e-9)
        // 日落后变暗，日出后变亮。
        XCTAssertGreaterThan(HourScrub.night(at: at(18.2), rise: rise, set: set),
                             HourScrub.night(at: at(17.8), rise: rise, set: set))
        XCTAssertLessThan(HourScrub.night(at: at(6.2), rise: rise, set: set),
                          HourScrub.night(at: at(5.8), rise: rise, set: set))
    }

    func testGlowPeaksAtSunsetAndFades() {
        XCTAssertEqual(HourScrub.glow(at: set, rise: rise, set: set), 1, accuracy: 1e-9)
        XCTAssertEqual(HourScrub.glow(at: at(12), rise: rise, set: set), 0)
        XCTAssertEqual(HourScrub.glow(at: at(19.5), rise: rise, set: set), 0)
        let half = HourScrub.glow(at: at(17.5), rise: rise, set: set)
        XCTAssertGreaterThan(half, 0)
        XCTAssertLessThan(half, 1)
    }

    // MARK: 插头

    func testPhaseFollowsLoadingOrHold() {
        XCTAssertEqual(PlugReconnect.phase(loading: false, holding: false), .unplugged)
        XCTAssertEqual(PlugReconnect.phase(loading: true, holding: false), .reconnecting)
        XCTAssertEqual(PlugReconnect.phase(loading: false, holding: true), .reconnecting)
    }

    func testPlugIsInWhileReconnectingAndOutOtherwise() {
        for t in stride(from: 0.0, to: 10, by: 0.37) {
            XCTAssertEqual(PlugReconnect.gap(.reconnecting, t: t, reduceMotion: false), 0)
            let gap = PlugReconnect.gap(.unplugged, t: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(gap, 0.82 - 1e-9)
            XCTAssertLessThanOrEqual(gap, 1 + 1e-9)
            let sag = PlugReconnect.sag(gap: gap, t: t, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(sag, 0)
            XCTAssertLessThanOrEqual(sag, 1)
        }
        XCTAssertEqual(PlugReconnect.gap(.unplugged, t: 3, reduceMotion: true), 1)
    }

    func testSwaysOnlyWhenUnpluggedAndMotionAllowed() {
        XCTAssertEqual(PlugReconnect.framesPerSecond(.unplugged, reduceMotion: false), PlugReconnect.swayFPS)
        XCTAssertNil(PlugReconnect.framesPerSecond(.unplugged, reduceMotion: true))
        XCTAssertNil(PlugReconnect.framesPerSecond(.reconnecting, reduceMotion: false))
    }
}
