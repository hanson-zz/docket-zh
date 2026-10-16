import XCTest

/// 环境音面板的呼吸引导。
final class BreathPacerTests: XCTestCase {

    func testCalmPatternSkipsHolds() {
        let p = BreathPacer.Pattern.calm
        XCTAssertEqual(BreathPacer.state(elapsed: 0, pattern: p).phase, .inhale)
        XCTAssertEqual(BreathPacer.state(elapsed: 3.9, pattern: p).phase, .inhale)
        XCTAssertEqual(BreathPacer.state(elapsed: 4.1, pattern: p).phase, .exhale, "没有屏息时吸完直接呼气")
        XCTAssertEqual(BreathPacer.state(elapsed: 10.1, pattern: p).phase, .inhale)
        XCTAssertEqual(BreathPacer.state(elapsed: 10.1, pattern: p).cycle, 1)
    }

    func testBoxPatternWalksAllFourSteps() {
        let p = BreathPacer.Pattern.box
        let phases = [1.0, 5, 9, 13].map { BreathPacer.state(elapsed: $0, pattern: p).phase }
        XCTAssertEqual(phases, [.inhale, .holdIn, .exhale, .holdOut])
    }

    func testFullnessRisesHoldsAndFalls() {
        let p = BreathPacer.Pattern.relax
        XCTAssertEqual(BreathPacer.state(elapsed: 0, pattern: p).fullness, 0, accuracy: 0.001)
        XCTAssertEqual(BreathPacer.state(elapsed: 2, pattern: p).fullness, 0.5, accuracy: 0.001)
        XCTAssertEqual(BreathPacer.state(elapsed: 6, pattern: p).fullness, 1, accuracy: 0.001)
        XCTAssertEqual(BreathPacer.state(elapsed: 18.99, pattern: p).fullness, 0, accuracy: 0.01)
    }

    func testFullnessStaysInRange() {
        for pattern in BreathPacer.Pattern.allCases {
            for step in 0..<600 {
                let s = BreathPacer.state(elapsed: Double(step) * 0.11, pattern: pattern)
                XCTAssertGreaterThanOrEqual(s.fullness, 0)
                XCTAssertLessThanOrEqual(s.fullness, 1)
                XCTAssertGreaterThanOrEqual(s.secondsLeft, 1)
            }
        }
    }

    func testSecondsLeftCountsDown() {
        let p = BreathPacer.Pattern.calm
        XCTAssertEqual(BreathPacer.state(elapsed: 0.2, pattern: p).secondsLeft, 4)
        XCTAssertEqual(BreathPacer.state(elapsed: 3.5, pattern: p).secondsLeft, 1)
    }

    func testNegativeElapsedIsStart() {
        XCTAssertEqual(BreathPacer.state(elapsed: -5, pattern: .box).phase, .inhale)
    }

    func testParseFallsBack() {
        XCTAssertEqual(BreathPacer.Pattern.parse("box"), .box)
        XCTAssertEqual(BreathPacer.Pattern.parse("???"), .calm)
    }

    func testFrameRate() {
        XCTAssertEqual(BreathPacer.framesPerSecond(running: true, reduceMotion: false), 30)
        XCTAssertEqual(BreathPacer.framesPerSecond(running: true, reduceMotion: true), 1)
        XCTAssertEqual(BreathPacer.framesPerSecond(running: false, reduceMotion: false), 1)
    }
}
