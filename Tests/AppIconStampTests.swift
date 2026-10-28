import XCTest

final class AppIconStampTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIconStampTests-\(UUID().uuidString)/Test.app")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Contents/Resources"),
                                                withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: dir.appendingPathComponent("Contents/Info.plist"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir.deletingLastPathComponent())
    }

    func testWatchedPathsIncludeCustomIconFile() {
        let paths = AppIconStamp.watchedPaths(for: "/Applications/拾掇.app/")
        XCTAssertEqual(paths, [
            "/Applications/拾掇.app",
            "/Applications/拾掇.app/Icon\r",
            "/Applications/拾掇.app/Contents/Info.plist",
            "/Applications/拾掇.app/Contents/Resources",
        ])
    }

    func testUnchangedBundleStaysFresh() {
        let a = AppIconStamp.read(path: dir.path)
        let b = AppIconStamp.read(path: dir.path)
        XCTAssertTrue(AppIconStamp.isFresh(cached: a, current: b))
    }

    func testWritingCustomIconMakesItStale() throws {
        let before = AppIconStamp.read(path: dir.path)
        XCTAssertNil(before.dates[1])
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("Icon\r"))
        let after = AppIconStamp.read(path: dir.path)
        XCTAssertNotNil(after.dates[1])
        XCTAssertFalse(AppIconStamp.isFresh(cached: before, current: after))
    }

    func testChangingCustomIconAgainMakesItStale() throws {
        let icon = dir.appendingPathComponent("Icon\r")
        try Data([1]).write(to: icon)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                              ofItemAtPath: icon.path)
        let before = AppIconStamp.read(path: dir.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)],
                                              ofItemAtPath: icon.path)
        let after = AppIconStamp.read(path: dir.path)
        XCTAssertFalse(AppIconStamp.isFresh(cached: before, current: after))
    }

    func testTouchingBundleMakesItStale() throws {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                              ofItemAtPath: dir.path)
        let before = AppIconStamp.read(path: dir.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 3_000)],
                                              ofItemAtPath: dir.path)
        XCTAssertFalse(AppIconStamp.isFresh(cached: before, current: AppIconStamp.read(path: dir.path)))
    }

    func testDeletedAppIsStale() throws {
        let before = AppIconStamp.read(path: dir.path)
        try FileManager.default.removeItem(at: dir)
        let after = AppIconStamp.read(path: dir.path)
        XCTAssertTrue(after.dates.allSatisfy { $0 == nil })
        XCTAssertFalse(AppIconStamp.isFresh(cached: before, current: after))
    }
}
