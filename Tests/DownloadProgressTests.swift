import XCTest

/// “下载”里画在文件图标上的进度。
final class DownloadProgressTests: XCTestCase {

    func testParseFraction() {
        XCTAssertEqual(DownloadProgress.parseFraction("0.25"), 0.25)
        XCTAssertEqual(DownloadProgress.parseFraction(" 0.5\n"), 0.5)
        XCTAssertEqual(DownloadProgress.parseFraction("1.7"), 1)
        XCTAssertNil(DownloadProgress.parseFraction("-0.1"))
        XCTAssertNil(DownloadProgress.parseFraction("abc"))
        XCTAssertNil(DownloadProgress.parseFraction("nan"))
    }

    func testSafariInfo() {
        let info: [String: Any] = ["DownloadEntryProgressBytesSoFar": NSNumber(value: 250),
                                   "DownloadEntryProgressTotalToLoad": NSNumber(value: 1000)]
        XCTAssertEqual(DownloadProgress.fraction(safariInfo: info)!, 0.25, accuracy: 0.0001)
        XCTAssertNil(DownloadProgress.fraction(safariInfo: ["DownloadEntryProgressTotalToLoad": NSNumber(value: -1),
                                                            "DownloadEntryProgressBytesSoFar": NSNumber(value: 5)]))
        XCTAssertNil(DownloadProgress.fraction(safariInfo: [:]))
    }

    func testFinalName() {
        XCTAssertEqual(DownloadProgress.finalName("电影.mp4.crdownload"), "电影.mp4")
        XCTAssertEqual(DownloadProgress.finalName("Xcode.xip.download"), "Xcode.xip")
        XCTAssertEqual(DownloadProgress.finalName("发票.pdf"), "发票.pdf")
        XCTAssertEqual(DownloadProgress.finalExtension("a.zip.part"), "zip")
        XCTAssertEqual(DownloadProgress.finalExtension("未确认 123.crdownload"), "")
    }

    func testCaption() {
        XCTAssertEqual(DownloadProgress.caption(nil), "下载中")
        XCTAssertEqual(DownloadProgress.caption(0.456), "45%")
        XCTAssertEqual(DownloadProgress.caption(1), "100%")
        XCTAssertEqual(DownloadProgress.caption(2), "100%")
    }

    func testTileCaptionDoesNotRepeat() {
        XCTAssertEqual(DownloadProgress.tileCaption(nil), "下载中")
        XCTAssertEqual(DownloadProgress.tileCaption(0.456), "下载中 · 45%")
    }

    func testStaleLeftoversAreNotActive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(DownloadProgress.isActive(lastWrite: now.addingTimeInterval(-5), now: now))
        XCTAssertTrue(DownloadProgress.isActive(lastWrite: now.addingTimeInterval(30), now: now))
        XCTAssertFalse(DownloadProgress.isActive(lastWrite: now.addingTimeInterval(-DownloadProgress.staleAfter), now: now))
        XCTAssertFalse(DownloadProgress.isActive(lastWrite: now.addingTimeInterval(-86_400 * 30), now: now))
        XCTAssertFalse(DownloadProgress.isActive(lastWrite: nil, now: now))
    }

    func testLastWriteLooksInsideSafariBundle() throws {
        let fm = FileManager.default
        let bundle = fm.temporaryDirectory.appendingPathComponent("docket-\(UUID().uuidString).zip.download")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: bundle) }
        let old = Date(timeIntervalSince1970: 1_000_000)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: bundle.path)
        let inner = bundle.appendingPathComponent("a.zip")
        try Data("x".utf8).write(to: inner)
        let fresh = Date(timeIntervalSince1970: 2_000_000)
        try fm.setAttributes([.modificationDate: fresh], ofItemAtPath: inner.path)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: bundle.path)
        let seen = try XCTUnwrap(DownloadProgress.lastWrite(bundle))
        XCTAssertEqual(seen.timeIntervalSince1970, fresh.timeIntervalSince1970, accuracy: 1)
    }

    func testPollFasterOnlyWhileDownloading() {
        XCTAssertEqual(DownloadProgress.pollInterval(downloading: true, idle: 5), 1.5)
        XCTAssertEqual(DownloadProgress.pollInterval(downloading: false, idle: 5), 5)
    }

    func testReadsExtendedAttribute() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("docket-progress-\(UUID().uuidString).crdownload")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(DownloadProgress.read(url))
        let value = Array("0.4".utf8)
        let status = url.withUnsafeFileSystemRepresentation { path in
            setxattr(path!, DownloadProgress.attributeName, value, value.count, 0, 0)
        }
        XCTAssertEqual(status, 0)
        XCTAssertEqual(DownloadProgress.read(url), 0.4)
    }
}
