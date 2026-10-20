import Foundation
import XCTest

/// 废纸篓面板的「最近扔的」和「放回原处」（第三批 L3）：.DS_Store 解析、原位置、
/// 放不回去时的说法、最近 5 个怎么排。
final class TrashPutBackTests: XCTestCase {
    // MARK: 造一个 .DS_Store

    private enum Field {
        case ustr(String)
        case long(UInt32)
        case bool(Bool)
        case blob([UInt8])
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
    }

    private static func utf16(_ s: String) -> [UInt8] {
        s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] }
    }

    private static func record(_ name: String, _ code: String, _ field: Field) -> [UInt8] {
        var out = be32(UInt32(name.utf16.count)) + utf16(name) + Array(code.utf8)
        switch field {
        case .ustr(let s): out += Array("ustr".utf8) + be32(UInt32(s.utf16.count)) + utf16(s)
        case .long(let v): out += Array("long".utf8) + be32(v)
        case .bool(let b): out += Array("bool".utf8) + [b ? 1 : 0]
        case .blob(let bytes): out += Array("blob".utf8) + be32(UInt32(bytes.count)) + bytes
        }
        return out
    }

    /// 按 Buddy Allocator 的格式拼一个文件。`nodes[0]` 是根节点；每个节点是
    /// (最右子节点块号或 0, [(子节点块号或 nil, 记录字节)])。块号：0 根块，1 DSDB 头，
    /// 2 起是节点。
    private static func store(nodes: [(rightmost: UInt32, entries: [(child: UInt32?, record: [UInt8])])]) -> Data {
        let blockSize: UInt32 = 4096
        let rootOffset: UInt32 = 0x1000
        let headerOffset: UInt32 = 0x2000
        func nodeOffset(_ i: Int) -> UInt32 { 0x3000 + UInt32(i) * blockSize }
        var addresses: [UInt32] = [rootOffset | 12, headerOffset | 5]
        for i in nodes.indices { addresses.append(nodeOffset(i) | 12) }

        var root = be32(UInt32(addresses.count)) + be32(0)
        var table = addresses
        while table.count % 256 != 0 { table.append(0) }
        root += table.flatMap(be32)
        root += be32(1) + [4] + Array("DSDB".utf8) + be32(1)

        let header = be32(2) + be32(UInt32(nodes.count > 1 ? 1 : 0)) + be32(0) + be32(UInt32(nodes.count)) + be32(blockSize)

        let total = Int(nodeOffset(nodes.count)) + 4
        var file = [UInt8](repeating: 0, count: total)
        func put(_ bytes: [UInt8], at offset: UInt32) {
            let start = Int(offset) + 4
            file.replaceSubrange(start..<(start + bytes.count), with: bytes)
        }
        let prefix = be32(1) + Array("Bud1".utf8) + be32(rootOffset) + be32(UInt32(root.count)) + be32(rootOffset)
        file.replaceSubrange(0..<prefix.count, with: prefix)
        put(root, at: rootOffset)
        put(header, at: headerOffset)
        for (i, node) in nodes.enumerated() {
            var bytes = be32(node.rightmost) + be32(UInt32(node.entries.count))
            for entry in node.entries {
                if let child = entry.child { bytes += be32(child) }
                bytes += entry.record
            }
            put(bytes, at: nodeOffset(i))
        }
        return Data(file)
    }

    // MARK: 解析

    func testLeafRecordsAreRead() {
        let data = Self.store(nodes: [(0, [
            (nil, Self.record("旧稿.key", "ptbL", .ustr("Users/han/Desktop/"))),
            (nil, Self.record("旧稿.key", "ptbN", .ustr("旧稿.key"))),
            (nil, Self.record("报告 2.pdf", "Iloc", .blob([0, 0, 0, 1, 0, 0, 0, 2]))),
            (nil, Self.record("报告 2.pdf", "dilc", .bool(true))),
            (nil, Self.record("报告 2.pdf", "logS", .long(1234))),
            (nil, Self.record("报告 2.pdf", "ptbL", .ustr("Users/han/Documents/"))),
            (nil, Self.record("报告 2.pdf", "ptbN", .ustr("报告.pdf"))),
        ])])
        let records = DSStore.records(data)
        XCTAssertEqual(records.count, 7)
        XCTAssertEqual(records[0], DSStore.Record(name: "旧稿.key", code: "ptbL", value: .string("Users/han/Desktop/")))
        XCTAssertEqual(records[3].value, .bool(true))
        XCTAssertEqual(records[4].value, .number(1234))

        let origins = TrashPutBack.origins(records)
        XCTAssertEqual(origins["旧稿.key"], TrashPutBack.Origin(folder: "/Users/han/Desktop/", name: "旧稿.key"))
        // 在废纸篓里重名被改成「报告 2.pdf」，放回时用原名。
        XCTAssertEqual(origins["报告 2.pdf"]?.path, "/Users/han/Documents/报告.pdf")
    }

    func testInternalNodesAreWalked() {
        // 根节点（块 2）有两条记录，左边子节点是块 3，最右子节点是块 4。
        let data = Self.store(nodes: [
            (4, [(3, Self.record("b.txt", "ptbL", .ustr("Users/han/")))]),
            (0, [(nil, Self.record("a.txt", "ptbL", .ustr("Users/han/Downloads/")))]),
            (0, [(nil, Self.record("c.txt", "ptbL", .ustr("Volumes/Data/x/")))]),
        ])
        let names = DSStore.records(data).map(\.name)
        XCTAssertEqual(names, ["a.txt", "b.txt", "c.txt"])
        let origins = TrashPutBack.origins(DSStore.records(data))
        XCTAssertEqual(origins["a.txt"]?.path, "/Users/han/Downloads/a.txt")
        XCTAssertEqual(origins["b.txt"]?.path, "/Users/han/b.txt")
    }

    func testJunkNeverCrashes() {
        XCTAssertEqual(DSStore.records(Data()), [])
        XCTAssertEqual(DSStore.records(Data("hello world, not a store".utf8)), [])
        let good = Self.store(nodes: [(0, [(nil, Self.record("a", "ptbL", .ustr("Users/")))])])
        // 每一种截断都只返回读到的部分，不崩。
        for length in stride(from: 0, to: good.count, by: 97) {
            _ = DSStore.records(good.prefix(length))
        }
        // 节点指向自己也不会死循环。
        let loop = Self.store(nodes: [(2, [(2, Self.record("a", "ptbL", .ustr("Users/")))])])
        _ = DSStore.records(loop)
    }

    func testOriginsWithoutNameUseTrashName() {
        let records = [DSStore.Record(name: "x.png", code: "ptbL", value: .string("/Users/han/Pictures"))]
        XCTAssertEqual(TrashPutBack.origins(records)["x.png"]?.path, "/Users/han/Pictures/x.png")
        // 只有原名、没有原文件夹：不知道原位置。
        let nameOnly = [DSStore.Record(name: "y", code: "ptbN", value: .string("y"))]
        XCTAssertNil(TrashPutBack.origins(nameOnly)["y"])
    }

    // MARK: 放回的判断

    func testPlan() {
        let origin = TrashPutBack.Origin(folder: "/Users/han/Desktop/", name: "a.txt")
        XCTAssertEqual(TrashPutBack.plan(origin: nil, folderExists: true, targetExists: false), .unknown)
        XCTAssertEqual(TrashPutBack.plan(origin: origin, folderExists: false, targetExists: false),
                       .folderGone("/Users/han/Desktop/"))
        XCTAssertEqual(TrashPutBack.plan(origin: origin, folderExists: true, targetExists: true),
                       .nameTaken("/Users/han/Desktop/a.txt"))
        XCTAssertEqual(TrashPutBack.plan(origin: origin, folderExists: true, targetExists: false),
                       .move(to: "/Users/han/Desktop/a.txt"))
    }

    func testEveryFailureSaysSomething() {
        XCTAssertNil(TrashPutBack.message(.move(to: "/a"), item: "a"))
        for plan in [TrashPutBack.Plan.unknown, .folderGone("/Users/han/Old/"), .nameTaken("/a")] {
            let text = TrashPutBack.message(plan, item: "a.txt")
            XCTAssertNotNil(text)
            XCTAssertTrue(text?.contains("a.txt") == true, "\(plan)")
        }
        XCTAssertTrue(TrashPutBack.deniedMessage(item: "a.txt").contains("权限"))
    }

    func testDisplayFolder() {
        XCTAssertEqual(TrashPutBack.displayFolder("/Users/han/Desktop/", home: "/Users/han"), "~/Desktop")
        XCTAssertEqual(TrashPutBack.displayFolder("/Users/han", home: "/Users/han"), "~")
        XCTAssertEqual(TrashPutBack.displayFolder("/Volumes/Data/a/b/c/", home: "/Users/han"), "…/b/c")
        XCTAssertEqual(TrashPutBack.displayFolder("/Users/hanson/x", home: "/Users/han"), "/Users/hanson/x")
    }

    // MARK: 最近扔的

    func testRecentFiveNewestFirst() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        var items = (0..<8).map { TrashedItem(trashName: "f\($0)", date: base.addingTimeInterval(Double($0))) }
        items.append(TrashedItem(trashName: ".hidden", date: base.addingTimeInterval(100)))
        let recent = TrashedItem.recent(items)
        XCTAssertEqual(recent.map(\.trashName), ["f7", "f6", "f5", "f4", "f3"])
        XCTAssertEqual(TrashedItem.recent([]), [])
        // 同一时间按名字排，不来回跳。
        let tie = TrashedItem.recent([TrashedItem(trashName: "b", date: base), TrashedItem(trashName: "a", date: base)])
        XCTAssertEqual(tie.map(\.trashName), ["a", "b"])
    }

    func testDisplayNamePrefersOriginalName() {
        let renamed = TrashedItem(trashName: "报告 2.pdf", date: .now,
                                  origin: TrashPutBack.Origin(folder: "/Users/han/", name: "报告.pdf"))
        XCTAssertEqual(renamed.displayName, "报告.pdf")
        XCTAssertEqual(TrashedItem(trashName: "x", date: .now).displayName, "x")
    }
}
