import Foundation
import XCTest

/// The pure halves of the file and tool widgets: conversion maths, colour
/// codes, recent lists, where screenshots go and which picture a slideshow
/// shows. The halves that touch AppKit cannot run here, since the test
/// target compiles the core rather than hosting the app.
final class UnitConversionTests: XCTestCase {
    private func assertConverts(_ value: Double, _ from: ConversionUnit, _ to: ConversionUnit,
                                _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let result = UnitConverter.convert(value, from: from, to: to) else {
            return XCTFail("\(from) -> \(to) returned nil", file: file, line: line)
        }
        XCTAssertEqual(result, expected, accuracy: abs(expected) * 1e-9 + 1e-9, file: file, line: line)
    }

    func testLength() {
        assertConverts(1, .mile, .kilometre, 1.609344)
        assertConverts(12, .inch, .foot, 1)
        assertConverts(1, .yard, .centimetre, 91.44)
        assertConverts(2500, .millimetre, .metre, 2.5)
    }

    func testWeight() {
        assertConverts(1, .pound, .kilogram, 0.45359237)
        assertConverts(16, .ounce, .pound, 1)
        assertConverts(1, .kilogram, .jin, 2)
        assertConverts(1, .tonne, .kilogram, 1000)
    }

    func testTemperatureIsAffine() {
        assertConverts(32, .fahrenheit, .celsius, 0)
        assertConverts(100, .celsius, .fahrenheit, 212)
        assertConverts(0, .kelvin, .celsius, -273.15)
        assertConverts(-40, .celsius, .fahrenheit, -40)
        assertConverts(300, .kelvin, .fahrenheit, 80.33)
    }

    func testARoundTripReturnsTheValue() {
        for category in UnitCategory.allCases {
            for a in category.units {
                for b in category.units {
                    let there = UnitConverter.convert(42.5, from: a, to: b)!
                    let back = UnitConverter.convert(there, from: b, to: a)!
                    XCTAssertEqual(back, 42.5, accuracy: 1e-9, "\(a) -> \(b)")
                }
            }
        }
    }

    func testAcrossCategoriesIsNil() {
        XCTAssertNil(UnitConverter.convert(1, from: .metre, to: .gram))
        XCTAssertNil(UnitConverter.convert(1, from: .celsius, to: .mile))
    }

    func testEveryCategoryHasItsDefaultPairAndUnits() {
        for category in UnitCategory.allCases {
            XCTAssertGreaterThanOrEqual(category.units.count, 3, "\(category)")
            XCTAssertEqual(category.defaultPair.from.category, category)
            XCTAssertEqual(category.defaultPair.to.category, category)
            XCTAssertNotEqual(category.defaultPair.from, category.defaultPair.to)
        }
    }

    func testFormatting() {
        XCTAssertEqual(UnitConverter.format(1609.344), "1609.34")
        XCTAssertEqual(UnitConverter.format(2), "2")
        XCTAssertEqual(UnitConverter.format(0.5), "0.5")
        XCTAssertEqual(UnitConverter.format(0), "0")
        XCTAssertEqual(UnitConverter.format(-40), "-40")
        XCTAssertEqual(UnitConverter.format(0.000123), "0.000123")
        XCTAssertEqual(UnitConverter.format(.nan), "-")
    }

    func testParsingIsForgiving() {
        XCTAssertEqual(UnitConverter.parse("12.5"), 12.5)
        XCTAssertEqual(UnitConverter.parse(" 12,5 "), 12.5)
        XCTAssertEqual(UnitConverter.parse("１２３"), 123)
        XCTAssertEqual(UnitConverter.parse("-3"), -3)
        XCTAssertNil(UnitConverter.parse(""))
        XCTAssertNil(UnitConverter.parse("abc"))
    }
}

final class ColorCodeTests: XCTestCase {
    func testHexRoundTrip() {
        let code = ColorCode(hex: "#1C1C1E")
        XCTAssertEqual(code?.hex, "#1C1C1E")
        XCTAssertEqual(ColorCode(hex: "ff9f0a")?.hex, "#FF9F0A")
        XCTAssertNil(ColorCode(hex: "#12345"))
        XCTAssertNil(ColorCode(hex: "zzzzzz"))
    }

    func testRGBAndHSL() {
        let red = ColorCode(red: 1, green: 0, blue: 0)
        XCTAssertEqual(red.rgb, "rgb(255, 0, 0)")
        XCTAssertEqual(red.hsl, "hsl(0, 100%, 50%)")
        let grey = ColorCode(red: 0.5, green: 0.5, blue: 0.5)
        XCTAssertEqual(grey.hsl, "hsl(0, 0%, 50%)")
        XCTAssertEqual(ColorCode(hex: "#0000FF")?.hsl, "hsl(240, 100%, 50%)")
    }

    func testComponentsAreClamped() {
        let wild = ColorCode(red: 2, green: -1, blue: .nan)
        XCTAssertEqual(wild.hex, "#FF0000")
    }

    func testLightness() {
        XCTAssertTrue(ColorCode(red: 1, green: 1, blue: 1).isLight)
        XCTAssertFalse(ColorCode(red: 0, green: 0, blue: 0).isLight)
    }
}

final class RecentListTests: XCTestCase {
    func testNewestFirstWithoutDuplicates() {
        var list: [String] = []
        for item in ["a", "b", "c", "a"] { list = RecentList.inserting(item, into: list, limit: 10) }
        XCTAssertEqual(list, ["a", "c", "b"])
    }

    func testCapped() {
        var list: [Int] = []
        for item in 1...30 { list = RecentList.inserting(item, into: list, limit: 20) }
        XCTAssertEqual(list.count, 20)
        XCTAssertEqual(list.first, 30)
        XCTAssertEqual(list.last, 11)
    }

    func testCustomSameness() {
        let list = RecentList.inserting("ABC", into: ["abc", "x"], limit: 5) {
            $0.lowercased() == $1.lowercased()
        }
        XCTAssertEqual(list, ["ABC", "x"])
    }
}

final class FileListingTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    func testScreenshotLocationFallsBackToTheDesktop() {
        XCTAssertEqual(ScreenshotLocation.resolve(nil, home: home).path, "/Users/tester/Desktop")
        XCTAssertEqual(ScreenshotLocation.resolve("  ", home: home).path, "/Users/tester/Desktop")
        XCTAssertEqual(ScreenshotLocation.resolve("relative/path", home: home).path, "/Users/tester/Desktop")
    }

    func testScreenshotLocationExpandsATilde() {
        XCTAssertEqual(ScreenshotLocation.resolve("~/Pictures/Shots/", home: home).path,
                       "/Users/tester/Pictures/Shots")
        XCTAssertEqual(ScreenshotLocation.resolve("/Volumes/Work/Caps", home: home).path,
                       "/Volumes/Work/Caps")
    }

    func testCaptureNames() {
        XCTAssertTrue(ScreenshotNaming.looksLikeCapture("截屏2026-10-11 22.04.01.png"))
        XCTAssertTrue(ScreenshotNaming.looksLikeCapture("Screenshot 2026-10-11 at 22.04.01.png"))
        XCTAssertTrue(ScreenshotNaming.looksLikeCapture("Shot 1.png", customPrefix: "Shot"))
        XCTAssertFalse(ScreenshotNaming.looksLikeCapture("Holiday.jpg"))
    }

    func testNewestFirstIsStable() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let files = [
            ListedFile(url: URL(fileURLWithPath: "/a/b.png"), date: now),
            ListedFile(url: URL(fileURLWithPath: "/a/a.png"), date: now),
            ListedFile(url: URL(fileURLWithPath: "/a/c.png"), date: now.addingTimeInterval(10)),
        ]
        XCTAssertEqual(ListedFile.newestFirst(files, limit: 10).map(\.name), ["c.png", "a.png", "b.png"])
        XCTAssertEqual(ListedFile.newestFirst(files, limit: 1).map(\.name), ["c.png"])
    }

    func testImagesAndPartialDownloads() {
        let now = Date()
        XCTAssertTrue(ListedFile(url: URL(fileURLWithPath: "/x/IMG.HEIC"), date: now).isImage)
        XCTAssertFalse(ListedFile(url: URL(fileURLWithPath: "/x/notes.txt"), date: now).isImage)
        XCTAssertTrue(ListedFile(url: URL(fileURLWithPath: "/x/movie.mp4.crdownload"), date: now).isPartialDownload)
    }

    func testRelativeAge() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        XCTAssertEqual(RelativeAge.caption(now.addingTimeInterval(-10), now: now), "刚刚")
        XCTAssertEqual(RelativeAge.caption(now.addingTimeInterval(-180), now: now), "3 分钟前")
        XCTAssertEqual(RelativeAge.caption(now.addingTimeInterval(-7200), now: now), "2 小时前")
        XCTAssertEqual(RelativeAge.caption(now.addingTimeInterval(-86_400 * 3), now: now), "3 天前")
    }

    func testSlideshowCyclesInOrder() {
        let start = Date(timeIntervalSinceReferenceDate: 300)
        let indices = (0..<6).map {
            Slideshow.index(at: start.addingTimeInterval(Double($0) * 30), interval: 30, count: 4, shuffle: false)
        }
        XCTAssertEqual(indices, [2, 3, 0, 1, 2, 3])
        XCTAssertEqual(Slideshow.index(at: start, interval: 30, count: 0, shuffle: false), 0)
    }

    func testShuffleStaysInRangeAndNeverRepeatsBackToBack() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var previous: Int?
        for step in 1..<200 {
            let i = Slideshow.index(at: start.addingTimeInterval(Double(step) * 10),
                                    interval: 10, count: 5, shuffle: true)
            XCTAssertTrue((0..<5).contains(i))
            if let previous { XCTAssertNotEqual(i, previous, "step \(step)") }
            previous = i
        }
    }
}
