import Foundation
import XCTest

/// 文件暂存的清单（放进来的时间、自动移出）和隔空投送的「最近发过」。
final class FileShelfListTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    // MARK: 读写

    /// 旧版本只存了路径：读出来都在，时间是 nil。
    func testLegacyPathsReadWithoutDates() {
        let config = WidgetConfig(["files": .list([.string("/a.pdf"), .string("/b.png")])])
        let items = FileShelfList.read(config)
        XCTAssertEqual(items.map(\.path), ["/a.pdf", "/b.png"])
        XCTAssertEqual(items.map(\.added), [nil, nil])
    }

    func testWriteThenReadKeepsPathsAndDates() {
        var config = WidgetConfig()
        let items = [FileShelfList.Item(path: "/a", added: t0), .init(path: "/b", added: nil)]
        FileShelfList.write(items, into: &config)
        XCTAssertEqual(FileShelfList.read(config), items)
        XCTAssertEqual(config.strings("files"), ["/a", "/b"], "路径仍在旧的键里，旧版本也读得到")
    }

    /// 时间列表比路径短（被别的版本截断过）时，少的那几个当作不知道时间。
    func testShortDateListPadsWithNil() {
        let config = WidgetConfig(["files": .list([.string("/a"), .string("/b")]),
                                   "added": .list([.number(t0.timeIntervalSince1970)])])
        XCTAssertEqual(FileShelfList.read(config).map(\.added), [t0, nil])
    }

    func testEmptyConfigIsAnEmptyList() {
        XCTAssertTrue(FileShelfList.read(WidgetConfig()).isEmpty)
        XCTAssertEqual(FileShelfList.expiry(WidgetConfig()), .never)
    }

    // MARK: 增删

    func testAddingPutsNewOnTopInDropOrderAndRestartsTheClock() {
        let old = [FileShelfList.Item(path: "/x", added: t0), .init(path: "/y", added: t0)]
        let later = t0.addingTimeInterval(100)
        let next = FileShelfList.adding(["/a", "/y", "/a", ""], to: old, now: later)
        XCTAssertEqual(next.map(\.path), ["/a", "/y", "/x"])
        XCTAssertEqual(next.map(\.added), [later, later, t0])
    }

    func testAddingRespectsTheLimit() {
        let old = (0..<50).map { FileShelfList.Item(path: "/\($0)", added: t0) }
        let next = FileShelfList.adding(["/new"], to: old, now: t0)
        XCTAssertEqual(next.count, FileShelfList.limit)
        XCTAssertEqual(next.first?.path, "/new")
        XCTAssertEqual(next.last?.path, "/48", "挤掉最早的那个")
    }

    func testAddingNothingChangesNothing() {
        let old = [FileShelfList.Item(path: "/x", added: t0)]
        XCTAssertEqual(FileShelfList.adding([], to: old, now: t0), old)
    }

    func testRemovingTheLastOneLeavesAnEmptyList() {
        let old = [FileShelfList.Item(path: "/x", added: t0)]
        XCTAssertTrue(FileShelfList.removing(["/x"], from: old).isEmpty)
        XCTAssertEqual(FileShelfList.removing(["/nope"], from: old), old)
    }

    // MARK: 自动移出

    func testExpiryChoicesInPanelOrder() {
        XCTAssertEqual(FileShelfList.Expiry.allCases.map(\.title), ["1 天", "3 天", "7 天", "不移出"])
        XCTAssertEqual(FileShelfList.Expiry.allCases.map(\.days), [1, 3, 7, nil])
        XCTAssertEqual(FileShelfList.expiry(WidgetConfig(["expire": .string("3")])), .three)
        XCTAssertEqual(FileShelfList.expiry(WidgetConfig(["expire": .string("banana")])), .never,
                       "认不出的值退回不移出，不会误清")
    }

    func testNeverDoesNothing() {
        let items = [FileShelfList.Item(path: "/a", added: t0.addingTimeInterval(-100 * day))]
        let result = FileShelfList.sweep(items, expiry: .never, now: t0)
        XCTAssertEqual(result.kept, items)
        XCTAssertFalse(result.changed)
    }

    func testSweepRemovesOnlyExpiredAtTheExactBoundary() {
        let items = [FileShelfList.Item(path: "/fresh", added: t0.addingTimeInterval(-3 * day + 1)),
                     .init(path: "/edge", added: t0.addingTimeInterval(-3 * day)),
                     .init(path: "/old", added: t0.addingTimeInterval(-10 * day))]
        let result = FileShelfList.sweep(items, expiry: .three, now: t0)
        XCTAssertEqual(result.kept.map(\.path), ["/fresh"])
        XCTAssertEqual(result.removed, ["/edge", "/old"])
        XCTAssertTrue(result.changed)
    }

    /// 旧条目不知道时间：开了自动移出从现在算，不会一打开就清空。
    func testUnknownDatesStartCountingNow() {
        let items = [FileShelfList.Item(path: "/legacy", added: nil)]
        let result = FileShelfList.sweep(items, expiry: .one, now: t0)
        XCTAssertEqual(result.kept, [FileShelfList.Item(path: "/legacy", added: t0)])
        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertTrue(result.changed, "补上的时间要写回，下次才接着算")
        // 补好以后再看一次没有变化，不会反复写。
        XCTAssertFalse(FileShelfList.sweep(result.kept, expiry: .one, now: t0.addingTimeInterval(60)).changed)
        XCTAssertEqual(FileShelfList.sweep(result.kept, expiry: .one, now: t0.addingTimeInterval(day)).removed,
                       ["/legacy"])
    }

    func testSweepOnEmptyListIsQuiet() {
        let result = FileShelfList.sweep([], expiry: .seven, now: t0)
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertFalse(result.changed)
    }

    func testNextExpiryIsTheSoonest() {
        let items = [FileShelfList.Item(path: "/a", added: t0),
                     .init(path: "/b", added: t0.addingTimeInterval(-day)),
                     .init(path: "/c", added: nil)]
        XCTAssertEqual(FileShelfList.nextExpiry(items, expiry: .seven), t0.addingTimeInterval(6 * day))
        XCTAssertNil(FileShelfList.nextExpiry(items, expiry: .never))
        XCTAssertNil(FileShelfList.nextExpiry([], expiry: .one))
    }

    // MARK: 文字

    func testCopy() {
        XCTAssertEqual(FileShelfList.clearMissingTitle(2), "清掉找不到的 2 个")
        XCTAssertEqual(FileShelfList.subtitle(count: 0, missing: 0, selecting: false), "把文件拖到这里")
        XCTAssertEqual(FileShelfList.subtitle(count: 4, missing: 0, selecting: false), "4 个文件 · 拖出即可使用")
        XCTAssertEqual(FileShelfList.subtitle(count: 4, missing: 1, selecting: false), "4 个文件 · 1 个找不到了")
    }

    // MARK: 隔空投送：最近发过

    func testRecordingKeepsFiveNewestFirstWithoutDuplicates() {
        var entries: [AirDropHistory.Entry] = []
        for i in 0..<6 {
            entries = AirDropHistory.recording(["/\(i)"], at: t0.addingTimeInterval(Double(i)), into: entries)
        }
        XCTAssertEqual(entries.map(\.path), ["/5", "/4", "/3", "/2", "/1"])
        entries = AirDropHistory.recording(["/3", "/9"], at: t0.addingTimeInterval(100), into: entries)
        XCTAssertEqual(entries.map(\.path), ["/3", "/9", "/5", "/4", "/2"])
        XCTAssertEqual(entries.first?.sent, t0.addingTimeInterval(100), "再发一次更新时间")
    }

    func testHistoryRoundTripAndRemoveLast() {
        var config = WidgetConfig()
        let entries = AirDropHistory.recording(["/tmp/合同终版.pdf"], at: t0, into: [])
        AirDropHistory.write(entries, into: &config)
        XCTAssertEqual(AirDropHistory.read(config), entries)
        XCTAssertEqual(AirDropHistory.read(config).first?.name, "合同终版.pdf")
        let empty = AirDropHistory.removing("/tmp/合同终版.pdf", from: entries)
        XCTAssertTrue(empty.isEmpty)
        AirDropHistory.write(empty, into: &config)
        XCTAssertTrue(AirDropHistory.read(config).isEmpty)
    }

    func testHistoryCaption() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let entry = AirDropHistory.Entry(path: "/a", sent: t0)
        XCTAssertEqual(AirDropHistory.caption(entry, exists: false, now: t0, calendar: calendar), "找不到了")
        XCTAssertEqual(AirDropHistory.caption(entry, exists: true, now: t0.addingTimeInterval(day), calendar: calendar),
                       "昨天")
        XCTAssertEqual(AirDropHistory.goneNotice("a.pdf"), "「a.pdf」找不到了，可能被移走或删掉了")
    }
}
