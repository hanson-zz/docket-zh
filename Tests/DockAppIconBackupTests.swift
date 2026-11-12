import Foundation
import XCTest

/// 程序坞自定义图标：设置备份里的映射和图片、旧备份兼容、更换和恢复默认的先后（只认
/// 最后一次）、大图抽样倍数。
final class DockAppIconBackupTests: XCTestCase {

    /// 一个最小的“PNG”：文件头对就行，这里不解码。
    private func png(_ tail: UInt8 = 1) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, tail])
    }

    // MARK: 导出

    func testExportReadsEveryMappedIcon() {
        let map = ["com.apple.finder": "com.apple.finder.png", "com.apple.safari": "com.apple.safari.png"]
        let disk = ["com.apple.finder.png": png(1), "com.apple.safari.png": png(2)]
        let icons = DockAppIconBackup.encode(map: map) { disk[$0] }
        XCTAssertEqual(Set(icons.keys), ["com.apple.finder", "com.apple.safari"])
        XCTAssertEqual(icons["com.apple.safari"], png(2).base64EncodedString())
    }

    /// 文件丢了、坏了、不是这个功能的文件名的项，画不出来，也不往备份里写。
    func testExportSkipsMissingBrokenAndForeignFiles() {
        let map = ["com.a": "com.a.png", "com.b": "com.b.png", "com.c": "../evil.png"]
        let disk = ["com.a.png": png(), "com.b.png": Data("not a png".utf8), "../evil.png": png()]
        let icons = DockAppIconBackup.encode(map: map) { disk[$0] }
        XCTAssertEqual(Set(icons.keys), ["com.a"])
        XCTAssertTrue(DockAppIconBackup.encode(map: ["com.d": "com.d.png"]) { _ in nil }.isEmpty)
    }

    // MARK: 恢复

    func testRestoreDecodesValidEntriesSortedByBundleID() {
        let icons = ["com.b": png(2).base64EncodedString(), "com.a": png(1).base64EncodedString()]
        let entries = DockAppIconBackup.entries(from: icons)
        XCTAssertEqual(entries, [.init(bundleID: "com.a", png: png(1)), .init(bundleID: "com.b", png: png(2))])
    }

    func testRestoreSkipsBadEntries() {
        let icons = [
            "com.ok": png().base64EncodedString(),
            "../../etc": png().base64EncodedString(),
            "com.notbase64": "%%%",
            "com.notpng": Data("hello world".utf8).base64EncodedString(),
            "": png().base64EncodedString(),
        ]
        XCTAssertEqual(DockAppIconBackup.entries(from: icons).map(\.bundleID), ["com.ok"])
    }

    /// 只差大小写的同一个 App（手改过的备份）只写回一张，键统一成小写。
    func testRestoreKeepsOneEntryPerApp() {
        let icons = ["Com.Apple.Finder": png(1).base64EncodedString(),
                     "com.apple.finder": png(2).base64EncodedString()]
        let entries = DockAppIconBackup.entries(from: icons)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.bundleID, "com.apple.finder")
    }

    func testExportThenRestoreRoundTrips() {
        let map = ["com.tencent.xinwechat": "com.tencent.xinwechat.png"]
        let icons = DockAppIconBackup.encode(map: map) { _ in self.png(7) }
        XCTAssertEqual(DockAppIconBackup.entries(from: icons), [.init(bundleID: "com.tencent.xinwechat", png: png(7))])
    }

    // MARK: 备份文件

    func testBackupFileCarriesIcons() throws {
        var state = PersistedState()
        state.profiles = [DockProfile(id: UUID(), kind: .customDock, name: "Everyday")]
        let icons = ["com.apple.finder": png().base64EncodedString()]
        let payload = try Backup.decode(try Backup.encode(state, dockAppIcons: icons))
        XCTAssertEqual(payload.dockAppIcons, icons)
        XCTAssertEqual(payload.version, 1)
    }

    /// 没有自定义图标时不写这个键，备份和以前一模一样。
    func testBackupWithoutIconsLeavesTheKeyOut() throws {
        var state = PersistedState()
        state.profiles = [DockProfile(id: UUID(), kind: .customDock, name: "Everyday")]
        let json = String(data: try Backup.encode(state), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("dockAppIcons"))
    }

    /// 加这个功能之前导出的备份：没有 `dockAppIcons`，照样能读，恢复时不碰图标。
    func testOldBackupWithoutIconsStillDecodes() throws {
        let id = UUID()
        let json = """
        {"version":1,"exported":"2026-09-27T08:00:00Z","profiles":[],"customProfileID":"\(id.uuidString)"}
        """
        let payload = try Backup.decode(Data(json.utf8))
        XCTAssertNil(payload.dockAppIcons)
        XCTAssertEqual(payload.customProfileID, id)
        XCTAssertTrue(DockAppIconBackup.entries(from: payload.dockAppIcons).isEmpty)
    }

    // MARK: 先后

    /// 「恢复默认」后马上又换一张：恢复之前那次没做完的更换作废，新换的那次生效。
    func testLaterOperationWins() {
        var tickets = DockAppIconTickets()
        let first = tickets.begin("com.apple.finder")
        let reset = tickets.begin("com.apple.finder")
        XCTAssertFalse(tickets.isCurrent(first, for: "com.apple.finder"))
        XCTAssertTrue(tickets.isCurrent(reset, for: "com.apple.finder"))
        let again = tickets.begin("com.apple.finder")
        XCTAssertFalse(tickets.isCurrent(reset, for: "com.apple.finder"))
        XCTAssertTrue(tickets.isCurrent(again, for: "com.apple.finder"))
    }

    func testTicketsAreSeparatePerAppAndIgnoreCase() {
        var tickets = DockAppIconTickets()
        let finder = tickets.begin("com.apple.Finder")
        let safari = tickets.begin("com.apple.safari")
        XCTAssertTrue(tickets.isCurrent(finder, for: "COM.APPLE.FINDER"))
        XCTAssertTrue(tickets.isCurrent(safari, for: "com.apple.safari"))
        XCTAssertFalse(tickets.isCurrent(finder, for: "com.apple.safari"))
        XCTAssertFalse(tickets.isCurrent(finder, for: ""))
    }

    // MARK: 大图抽样

    func testSubsampleFactorKeepsAtLeastTheStoredSize() {
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 512, pixelHeight: 512), 1)
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 1023, pixelHeight: 300), 1)
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 1024, pixelHeight: 1024), 2)
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 300, pixelHeight: 2048), 4)
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 4096, pixelHeight: 4096), 8)
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 30000, pixelHeight: 20000), 8)
        XCTAssertEqual(DockAppIcons.subsampleFactor(pixelWidth: 0, pixelHeight: 100), 1)
    }
}
