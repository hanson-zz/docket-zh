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

final class AppStripTests: XCTestCase {
    func testEverythingShowsWhenItFits() {
        XCTAssertEqual(AppStrip.fit(total: 4, capacity: 6), .init(shown: 4, overflow: 0))
        XCTAssertEqual(AppStrip.fit(total: 6, capacity: 6), .init(shown: 6, overflow: 0))
        XCTAssertEqual(AppStrip.fit(total: 0, capacity: 6), .init(shown: 0, overflow: 0))
    }

    /// The marker takes a slot of its own, so it never covers an icon.
    func testTheLastSlotCountsTheRest() {
        XCTAssertEqual(AppStrip.fit(total: 7, capacity: 6), .init(shown: 5, overflow: 2))
        XCTAssertEqual(AppStrip.fit(total: 30, capacity: 6), .init(shown: 5, overflow: 25))
        let fit = AppStrip.fit(total: 9, capacity: 6)
        XCTAssertEqual(fit.shown + fit.overflow, 9)
    }

    func testTheFrontmostAppLeads() {
        let apps = [("a", false), ("b", true), ("c", false)]
        XCTAssertEqual(AppStrip.ordered(apps, isActive: { $0.1 }).map { $0.0 }, ["b", "a", "c"])
        XCTAssertEqual(AppStrip.ordered([("x", false)], isActive: { $0.1 }).map { $0.0 }, ["x"])
    }
}

final class BookmarkTests: XCTestCase {
    func testATitleAndAnAddress() {
        let link = Bookmark(parsing: "GitHub https://github.com/hanson-zz/docket-zh")
        XCTAssertEqual(link?.title, "GitHub")
        XCTAssertEqual(link?.url.absoluteString, "https://github.com/hanson-zz/docket-zh")
    }

    func testABareHostIsAWebAddressTitledByItsHost() {
        let link = Bookmark(parsing: "  www.bilibili.com ")
        XCTAssertEqual(link?.url.absoluteString, "https://www.bilibili.com")
        XCTAssertEqual(link?.title, "bilibili.com")
    }

    func testATitleOfSeveralWordsAndChinese() {
        XCTAssertEqual(Bookmark(parsing: "我的 项目 主页 example.org/x")?.title, "我的 项目 主页")
        XCTAssertEqual(Bookmark(parsing: "必应 https://cn.bing.com")?.initial, "必")
        XCTAssertEqual(Bookmark(parsing: "github.com")?.initial, "G")
    }

    func testNothingThatReadsAsAnAddressIsDropped() {
        XCTAssertNil(Bookmark(parsing: ""))
        XCTAssertNil(Bookmark(parsing: "just words"))
        XCTAssertNil(Bookmark(parsing: "https://"))
        XCTAssertNil(Bookmark(parsing: ".com"))
        XCTAssertEqual(Bookmark.list(["a b", "知乎 zhihu.com", "", "mailto:hi@example.com"]).count, 2)
    }

    func testTheColourIsStablePerHost() {
        let a = Bookmark(parsing: "A https://www.zhihu.com")!
        let b = Bookmark(parsing: "B zhihu.com/question/1")!
        XCTAssertEqual(a.paletteIndex(count: 8), b.paletteIndex(count: 8), "same host, same colour")
        XCTAssertTrue((0..<8).contains(a.paletteIndex(count: 8)))
        XCTAssertEqual(a.paletteIndex(count: 0), 0)
    }

    func testTheTileGrowsWithItsLinksUpToEight() {
        XCTAssertEqual(Bookmark.tileWidth(count: 0), 100)
        XCTAssertLessThan(Bookmark.tileWidth(count: 3), Bookmark.tileWidth(count: 4))
        XCTAssertEqual(Bookmark.tileWidth(count: 8), Bookmark.tileWidth(count: 20))
        XCTAssertEqual(Bookmark.columnHeight(count: 8), Bookmark.columnHeight(count: 9))
        XCTAssertGreaterThanOrEqual(Bookmark.columnHeight(count: 1), 62)
    }
}

final class RecordingNamingTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testTheNameSortsAndHasNoColon() {
        let date = Date(timeIntervalSince1970: 1_792_000_000) // 2026-10-14 17:46:40 UTC
        let name = RecordingNaming.fileName(for: date, calendar: utc)
        XCTAssertEqual(name, "录音 2026-10-14 17.46.40.m4a")
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(RecordingNaming.isRecording(name))
    }

    func testOnlyOurFilesAreListed() {
        XCTAssertTrue(RecordingNaming.isRecording("录音 2026-01-01 00.00.00 2.M4A"))
        XCTAssertFalse(RecordingNaming.isRecording("会议.m4a"))
        XCTAssertFalse(RecordingNaming.isRecording("录音 草稿.txt"))
    }

    func testASecondPressInTheSameSecondDoesNotOverwrite() {
        let name = "录音 2026-10-15 02.13.20.m4a"
        XCTAssertEqual(RecordingNaming.unique(name, taken: []), name)
        XCTAssertEqual(RecordingNaming.unique(name, taken: [name]), "录音 2026-10-15 02.13.20 2.m4a")
        XCTAssertEqual(RecordingNaming.unique(name, taken: [name, "录音 2026-10-15 02.13.20 2.m4a"]),
                       "录音 2026-10-15 02.13.20 3.m4a")
    }

    func testElapsedTime() {
        XCTAssertEqual(RecordingNaming.elapsed(0), "0:00")
        XCTAssertEqual(RecordingNaming.elapsed(7.9), "0:07")
        XCTAssertEqual(RecordingNaming.elapsed(754), "12:34")
        XCTAssertEqual(RecordingNaming.elapsed(3723), "1:02:03")
        XCTAssertEqual(RecordingNaming.elapsed(-5), "0:00")
        XCTAssertEqual(RecordingNaming.elapsed(.infinity), "0:00")
    }
}
