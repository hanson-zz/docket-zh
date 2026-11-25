import XCTest

/// 沿边流光：开关和节能判断、绕圈相位、彗尾切段、浅色深色亮度。
final class EdgeBeamTests: XCTestCase {
    // MARK: 开关和节能

    func testDefaultIsOn() {
        XCTAssertTrue(EdgeBeam.defaultEnabled)
        XCTAssertEqual(EdgeBeam.enabledKey, "edgeBeam.enabled")
    }

    func testOffWhenDisabledOrInactive() {
        XCTAssertEqual(EdgeBeam.motion(enabled: false, active: true, reduceMotion: false, lowPower: false), .off)
        XCTAssertEqual(EdgeBeam.motion(enabled: true, active: false, reduceMotion: false, lowPower: false), .off)
        XCTAssertEqual(EdgeBeam.motion(enabled: false, active: false, reduceMotion: true, lowPower: true), .off)
    }

    func testMovesOnlyWithoutReduceMotionAndLowPower() {
        XCTAssertEqual(EdgeBeam.motion(enabled: true, active: true, reduceMotion: false, lowPower: false), .moving)
        XCTAssertEqual(EdgeBeam.motion(enabled: true, active: true, reduceMotion: true, lowPower: false), .still,
                       "减弱动态效果时静止")
        XCTAssertEqual(EdgeBeam.motion(enabled: true, active: true, reduceMotion: false, lowPower: true), .still,
                       "低电量模式时静止")
        XCTAssertEqual(EdgeBeam.motion(enabled: true, active: true, reduceMotion: true, lowPower: true), .still)
    }

    // MARK: 相位

    func testPhaseWrapsEveryLap() {
        let lap = EdgeBeam.lapDuration
        XCTAssertEqual(EdgeBeam.phase(elapsed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(EdgeBeam.phase(elapsed: lap / 4), 0.25, accuracy: 1e-9)
        XCTAssertEqual(EdgeBeam.phase(elapsed: lap * 3 + lap / 2), 0.5, accuracy: 1e-9)
        XCTAssertEqual(EdgeBeam.phase(elapsed: -lap / 4), 0.75, accuracy: 1e-9, "负数也落在 0..<1")
    }

    func testPhaseGuardsBadInput() {
        XCTAssertEqual(EdgeBeam.phase(elapsed: 5, lap: 0), 0)
        XCTAssertEqual(EdgeBeam.phase(elapsed: .infinity), 0)
        XCTAssertEqual(EdgeBeam.phase(elapsed: .nan), 0)
    }

    func testLapIsSlowEnoughNotToLookLikeASpinner() {
        XCTAssertGreaterThanOrEqual(EdgeBeam.lapDuration, 2.5)
        XCTAssertLessThanOrEqual(EdgeBeam.frameRate, 30)
    }

    // MARK: 彗尾

    func testSegmentsEndAtHeadAndBrightenTowardIt() {
        let segments = EdgeBeam.segments(head: 0.6)
        XCTAssertEqual(segments.count, EdgeBeam.segmentCount)
        XCTAssertEqual(segments.last!.to, 0.6, accuracy: 1e-9, "最后一段就是光头")
        XCTAssertEqual(segments.first!.from, 0.6 - EdgeBeam.tailLength, accuracy: 1e-9)
        XCTAssertEqual(segments.last!.strength, 1, accuracy: 1e-9)
        for (a, b) in zip(segments, segments.dropFirst()) {
            XCTAssertLessThan(a.strength, b.strength, "越靠头越亮")
            XCTAssertEqual(a.to, b.from, accuracy: 1e-9, "段和段首尾相接")
        }
    }

    func testSegmentsSplitAcrossPathStart() {
        let segments = EdgeBeam.segments(head: 0.07, length: 0.2, count: 4)
        XCTAssertEqual(segments.count, 5, "跨过起点的那段拆成两段")
        for segment in segments {
            XCTAssertLessThan(segment.from, segment.to)
            XCTAssertGreaterThanOrEqual(segment.from, 0)
            XCTAssertLessThanOrEqual(segment.to, 1)
        }
        let covered = segments.reduce(0) { $0 + ($1.to - $1.from) }
        XCTAssertEqual(covered, 0.2, accuracy: 1e-9, "拆开后总长不变")
    }

    func testSegmentsEndingExactlyAtStart() {
        let segments = EdgeBeam.segments(head: 0, length: 0.2, count: 2)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.last!.to, 1, accuracy: 1e-9)
        XCTAssertEqual(segments.last!.from, 0.9, accuracy: 1e-9)
    }

    func testEmptySegmentsForNothingToDraw() {
        XCTAssertTrue(EdgeBeam.segments(head: 0.3, length: 0.2, count: 0).isEmpty)
        XCTAssertTrue(EdgeBeam.segments(head: 0.3, length: 0, count: 4).isEmpty)
    }

    // MARK: 亮度

    func testThinAndDim() {
        for dark in [true, false] {
            let look = EdgeBeam.look(dark: dark)
            XCTAssertLessThanOrEqual(look.lineWidth, 1.5, "细线")
            XCTAssertLessThanOrEqual(look.lineOpacity, 0.75, "低亮度")
            XCTAssertLessThanOrEqual(look.glowOpacity, 0.25, "柔光很淡，不大面积发光")
            XCTAssertLessThanOrEqual(look.glowBlur, 4)
            XCTAssertEqual(EdgeBeam.inset(dark: dark), look.lineWidth / 2, accuracy: 1e-9)
        }
        XCTAssertLessThan(EdgeBeam.look(dark: false).glowOpacity, EdgeBeam.look(dark: true).glowOpacity,
                          "浅色底上柔光更淡")
    }

    func testNeutralIsSoftWhiteOnDarkAndGrayOnLight() {
        let dark = EdgeBeam.neutral(dark: true)
        let light = EdgeBeam.neutral(dark: false)
        XCTAssertGreaterThan(dark.red, 0.85)
        XCTAssertLessThan(light.red, 0.6)
        // 中性：不偏蓝。
        XCTAssertLessThanOrEqual(dark.blue - dark.red, 0.05)
        XCTAssertLessThanOrEqual(light.blue - light.red, 0.05)
    }
}
