import Foundation
import XCTest

/// The pure halves of the v0.4.0 widgets. What touches AppKit, the network or
/// the microphone cannot run here, since the test target compiles the core
/// rather than hosting the app.
final class WallpaperCycleTests: XCTestCase {
    func testNextAndPreviousWrapAround() {
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 3, step: .next, roll: 0), 1)
        XCTAssertEqual(WallpaperCycle.index(after: 2, count: 3, step: .next, roll: 0), 0)
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 3, step: .previous, roll: 0), 2)
        XCTAssertEqual(WallpaperCycle.index(after: 1, count: 3, step: .previous, roll: 0), 0)
    }

    func testAPictureFromOutsideTheFolderStartsAtAnEnd() {
        XCTAssertEqual(WallpaperCycle.index(after: nil, count: 4, step: .next, roll: 0), 0)
        XCTAssertEqual(WallpaperCycle.index(after: nil, count: 4, step: .previous, roll: 0), 3)
        XCTAssertEqual(WallpaperCycle.index(after: 9, count: 4, step: .next, roll: 0), 0,
                       "an index past the end is treated as outside the folder")
    }

    func testAnEmptyFolderHasNothingToShow() {
        for step in WallpaperCycle.Step.allCases {
            XCTAssertNil(WallpaperCycle.index(after: nil, count: 0, step: step, roll: 0.5))
        }
    }

    func testRandomNeverRepeatsTheCurrentPicture() {
        for current in 0..<5 {
            for roll in stride(from: 0.0, through: 1.0, by: 0.05) {
                let pick = WallpaperCycle.index(after: current, count: 5, step: .random, roll: roll)!
                XCTAssertNotEqual(pick, current)
                XCTAssertTrue((0..<5).contains(pick))
            }
        }
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 1, step: .random, roll: 0.7), 0,
                       "one picture is the only choice")
        XCTAssertEqual(WallpaperCycle.index(after: 0, count: 3, step: .random, roll: .nan), 1)
    }
}
