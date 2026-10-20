import Foundation

// 废纸篓面板的「最近扔的」和「放回原处」（第三批 L3）。
//
// 访达把每个扔进废纸篓的东西原来在哪记在 ~/.Trash/.DS_Store 里：`ptbL` 是原来所在
// 文件夹（相对卷根目录的路径，比如 "Users/han/Desktop/"），`ptbN` 是原来的名字
// （废纸篓里重名时会被改名，放回时要用回原名）。访达菜单里的「放回原处」读的就是
// 这两条。这里只读不写：解析 .DS_Store、排出最近 5 个、判断能不能放回去。
// 读 ~/.Trash 本身要「完全磁盘访问权限」，和废纸篓卡片读大小是同一个权限。

// MARK: - .DS_Store（Buddy Allocator + B 树）

/// 只读的 .DS_Store 解析，够取出每个文件名下的 `ptbL`、`ptbN` 这类字符串记录。
/// 格式：4 字节 1，"Bud1"，根块偏移和大小；根块里是块地址表和目录（"DSDB"
/// 指向 B 树的头）；B 树的节点里是一条条记录（文件名、四字代码、类型、值）。
/// 坏文件、截断的文件都不崩，只返回读到的部分（通常是空）。
public enum DSStore {
    public struct Record: Equatable, Sendable {
        public var name: String
        public var code: String
        public var value: Value
    }

    public enum Value: Equatable, Sendable {
        case string(String)
        case number(Int64)
        case bool(Bool)
        case blob(Data)
        case other
    }

    public static func records(_ data: Data) -> [Record] {
        var reader = Reader(bytes: [UInt8](data))
        return reader.parse() ?? []
    }

    private struct Reader {
        let bytes: [UInt8]
        var blocks: [UInt32] = []
        var visited = Set<UInt32>()
        var out: [Record] = []

        init(bytes: [UInt8]) { self.bytes = bytes }

        func u32(_ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
        }

        func u8(_ at: Int) -> UInt8? { at >= 0 && at < bytes.count ? bytes[at] : nil }

        func ascii(_ at: Int, _ count: Int) -> String? {
            guard at >= 0, count >= 0, at + count <= bytes.count else { return nil }
            return String(bytes: bytes[at..<(at + count)], encoding: .ascii)
        }

        func utf16(_ at: Int, units: Int) -> String? {
            guard units >= 0, units < 1 << 20, at >= 0, at + units * 2 <= bytes.count else { return nil }
            var chars: [UInt16] = []
            chars.reserveCapacity(units)
            for i in 0..<units {
                chars.append(UInt16(bytes[at + i * 2]) << 8 | UInt16(bytes[at + i * 2 + 1]))
            }
            return String(decoding: chars, as: UTF16.self)
        }

        /// 块号换成文件里的偏移。地址低 5 位是大小的对数，其余是偏移；偏移从第 4 字节算起。
        func offset(ofBlock id: UInt32) -> Int? {
            guard Int(id) < blocks.count else { return nil }
            let address = blocks[Int(id)]
            return Int(address & ~UInt32(0x1f)) + 4
        }

        mutating func parse() -> [Record]? {
            guard u32(0) == 1, ascii(4, 4) == "Bud1", let rootOffset = u32(8) else { return nil }
            var at = Int(rootOffset) + 4
            guard let count = u32(at), count < 1 << 20 else { return nil }
            at += 8
            for i in 0..<Int(count) {
                guard let address = u32(at + i * 4) else { return nil }
                blocks.append(address)
            }
            // 地址表按 256 个一组补齐。
            let padded = (Int(count) + 255) / 256 * 256
            at += padded * 4
            guard let tocCount = u32(at), tocCount < 1024 else { return nil }
            at += 4
            var header: UInt32?
            for _ in 0..<Int(tocCount) {
                guard let length = u8(at), let name = ascii(at + 1, Int(length)),
                      let value = u32(at + 1 + Int(length)) else { return nil }
                if name == "DSDB" { header = value }
                at += 1 + Int(length) + 4
            }
            guard let header, let headerAt = offset(ofBlock: header), let root = u32(headerAt) else { return nil }
            node(root, depth: 0)
            return out
        }

        mutating func node(_ id: UInt32, depth: Int) {
            guard depth < 32, visited.insert(id).inserted, var at = offset(ofBlock: id),
                  let rightmost = u32(at), let count = u32(at + 4), count < 1 << 16 else { return }
            at += 8
            for _ in 0..<Int(count) {
                if rightmost != 0 {
                    guard let child = u32(at) else { return }
                    at += 4
                    node(child, depth: depth + 1)
                }
                guard let next = record(at) else { return }
                at = next
            }
            if rightmost != 0 { node(rightmost, depth: depth + 1) }
        }

        /// 读一条记录，返回下一条的偏移。
        mutating func record(_ start: Int) -> Int? {
            guard let units = u32(start), let name = utf16(start + 4, units: Int(units)) else { return nil }
            var at = start + 4 + Int(units) * 2
            guard let code = ascii(at, 4), let type = ascii(at + 4, 4) else { return nil }
            at += 8
            let value: Value
            switch type {
            case "long", "shor", "type":
                guard let v = u32(at) else { return nil }
                value = type == "type" ? .other : .number(Int64(v))
                at += 4
            case "bool":
                guard let v = u8(at) else { return nil }
                value = .bool(v != 0)
                at += 1
            case "blob":
                guard let length = u32(at), at + 4 + Int(length) <= bytes.count else { return nil }
                value = .blob(Data(bytes[(at + 4)..<(at + 4 + Int(length))]))
                at += 4 + Int(length)
            case "ustr":
                guard let length = u32(at), let text = utf16(at + 4, units: Int(length)) else { return nil }
                value = .string(text)
                at += 4 + Int(length) * 2
            case "comp", "dutc":
                guard at + 8 <= bytes.count, let high = u32(at), let low = u32(at + 4) else { return nil }
                value = .number(Int64(bitPattern: UInt64(high) << 32 | UInt64(low)))
                at += 8
            default:
                // 不认识的类型不知道多长，后面的读不下去了。
                return nil
            }
            out.append(Record(name: name, code: code, value: value))
            return at
        }
    }
}

// MARK: - 放回原处

public enum TrashPutBack {
    /// 访达记下的原位置：原来所在的文件夹（绝对路径）和原来的名字。
    public struct Origin: Equatable, Sendable {
        public var folder: String
        public var name: String

        public init(folder: String, name: String) {
            self.folder = folder
            self.name = name
        }

        public var path: String {
            (folder.hasSuffix("/") ? folder : folder + "/") + name
        }
    }

    /// 从 .DS_Store 的记录里取出废纸篓里每一项（按它在废纸篓里的名字）的原位置。
    /// `ptbL` 是相对卷根目录的路径，主卷的根目录是 "/"；没有 `ptbN` 时原名就是
    /// 现在的名字。
    public static func origins(_ records: [DSStore.Record], volumeRoot: String = "/") -> [String: Origin] {
        var folders: [String: String] = [:]
        var names: [String: String] = [:]
        for record in records {
            guard case .string(let text) = record.value else { continue }
            switch record.code {
            case "ptbL": folders[record.name] = text
            case "ptbN": names[record.name] = text
            default: continue
            }
        }
        var result: [String: Origin] = [:]
        let root = volumeRoot.hasSuffix("/") ? volumeRoot : volumeRoot + "/"
        for (item, folder) in folders where !folder.isEmpty {
            let relative = folder.hasPrefix("/") ? String(folder.dropFirst()) : folder
            let name = names[item].flatMap { $0.isEmpty ? nil : $0 } ?? item
            result[item] = Origin(folder: root + relative, name: name)
        }
        return result
    }

    /// 放回之前的判断，界面按它给出明确的一句话。
    public enum Plan: Equatable, Sendable {
        /// 可以放回：移到这个完整路径。
        case move(to: String)
        /// 访达没记它原来在哪（用别的方式扔进来的、或从外置磁盘来的）。
        case unknown
        /// 原来的文件夹已经不在了。
        case folderGone(String)
        /// 原位置已经有同名的东西，不覆盖。
        case nameTaken(String)
    }

    public static func plan(origin: Origin?, folderExists: Bool, targetExists: Bool) -> Plan {
        guard let origin else { return .unknown }
        guard folderExists else { return .folderGone(origin.folder) }
        guard !targetExists else { return .nameTaken(origin.path) }
        return .move(to: origin.path)
    }

    /// 计划或移动失败时给用户看的一句话。`item` 是显示的名字。
    public static func message(_ plan: Plan, item: String) -> String? {
        switch plan {
        case .move: nil
        case .unknown: tr("不知道「\(item)」原来在哪，点「显示」在访达里手动拖出来")
        case .folderGone(let folder):
            tr("「\(item)」原来的文件夹已经不在了（\(displayFolder(folder))），点「显示」手动拖出来")
        case .nameTaken: tr("原位置已经有同名的「\(item)」，没有覆盖")
        }
    }

    /// 移动时被系统拒绝（没有写入权限）。
    public static func deniedMessage(item: String) -> String {
        tr("没有权限把「\(item)」放回原处，点「显示」在访达里放回")
    }

    /// 「/Users/han/Desktop/」显示成「~/Desktop」，太长时只留最后两级。
    public static func displayFolder(_ folder: String, home: String = NSHomeDirectory()) -> String {
        var path = folder.hasSuffix("/") && folder.count > 1 ? String(folder.dropLast()) : folder
        if !home.isEmpty, path == home || path.hasPrefix(home + "/") {
            path = "~" + path.dropFirst(home.count)
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count > 3 { return "…/" + parts.suffix(2).joined(separator: "/") }
        return path
    }
}

// MARK: - 最近扔的

/// 废纸篓里的一项，面板的一行。
public struct TrashedItem: Equatable, Sendable, Identifiable {
    /// 在废纸篓里的名字（可能因重名被改过）。
    public var trashName: String
    /// 什么时候扔进来的（加入废纸篓的时间，读不到时用修改时间）。
    public var date: Date
    public var isDirectory: Bool
    /// 访达记下的原位置，没记时是 nil。
    public var origin: TrashPutBack.Origin?

    public var id: String { trashName }
    /// 显示用的名字：有原名用原名。
    public var displayName: String { origin?.name ?? trashName }

    public init(trashName: String, date: Date, isDirectory: Bool = false, origin: TrashPutBack.Origin? = nil) {
        self.trashName = trashName
        self.date = date
        self.isDirectory = isDirectory
        self.origin = origin
    }

    /// 面板列几个。
    public static let shownLimit = 5

    /// 系统的隐藏文件不算。
    public static func isListed(_ name: String) -> Bool {
        !name.hasPrefix(".")
    }

    /// 最新的在前，同一时间按名字排免得来回跳；只留前 `limit` 个。
    public static func recent(_ items: [TrashedItem], limit: Int = shownLimit) -> [TrashedItem] {
        let sorted = items.filter { isListed($0.trashName) }.sorted {
            $0.date != $1.date ? $0.date > $1.date
                : $0.trashName.localizedStandardCompare($1.trashName) == .orderedAscending
        }
        return Array(sorted.prefix(max(0, limit)))
    }
}
