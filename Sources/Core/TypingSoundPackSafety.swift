import Foundation

// MARK: - 导入声音包前的安全检查
//
// 导入 Mechvibes 声音包的 .zip 时，解压前先读 zip 末尾的中央目录，把每个条目的名字、
// 解压后大小和类型过一遍：条目太多、单个文件太大、加起来太大（zip 炸弹），或者路径想
// 跑出解压文件夹（../、绝对路径）、是符号链接，都直接拒绝，不交给 ditto。
// 另外认一下声音文件开头的几个字节，解不开时能说清楚是不是 OGG。
// 解压和解码在 Services 的 TypingSoundPackStore，这里只有能测的判断。

/// zip 中央目录里的一个条目。
public struct ZipEntryInfo: Equatable, Sendable {
    public var name: String
    public var compressedSize: UInt64
    public var uncompressedSize: UInt64
    public var isDirectory: Bool
    public var isSymlink: Bool

    public init(name: String, compressedSize: UInt64 = 0, uncompressedSize: UInt64,
                isDirectory: Bool = false, isSymlink: Bool = false) {
        self.name = name
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }
}

/// 只读 zip 的中央目录（不解压任何内容），支持 ZIP64。分卷 zip 不支持。
public enum ZipCentralDirectory {
    public enum Failure: Error, Equatable, Sendable {
        /// 找不到中央目录、字段越界或条目数对不上：当成坏了的压缩包。
        case damaged
        /// 声明的条目数就超过上限，不用往下读。
        case tooManyEntries
    }

    private static let eocdSignature: UInt32 = 0x0605_4B50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    private static let zip64EOCDSignature: UInt32 = 0x0606_4B50
    private static let centralHeaderSignature: UInt32 = 0x0201_4B50

    /// 读出全部条目。`maxEntries` 是条目数上限，声明的条目数超过它时直接抛 `tooManyEntries`。
    public static func entries(in data: Data, maxEntries: Int) throws -> [ZipEntryInfo] {
        let bytes = [UInt8](data)
        let count = bytes.count
        guard count >= 22 else { throw Failure.damaged }

        // 末尾目录记录（EOCD）：从最后往前找，最多跨过 65535 字节的注释。
        var eocd = -1
        var position = count - 22
        let lowest = max(0, count - 22 - 65_535)
        while position >= lowest {
            if u32(bytes, position) == eocdSignature,
               position + 22 + Int(u16(bytes, position + 20)) <= count {
                eocd = position
                break
            }
            position -= 1
        }
        guard eocd >= 0 else { throw Failure.damaged }

        let diskNumber = u16(bytes, eocd + 4)
        let directoryDisk = u16(bytes, eocd + 6)
        var total = UInt64(u16(bytes, eocd + 10))
        var directorySize = UInt64(u32(bytes, eocd + 12))
        var directoryOffset = UInt64(u32(bytes, eocd + 16))
        guard diskNumber == 0 || diskNumber == 0xFFFF, directoryDisk == 0 || directoryDisk == 0xFFFF else {
            throw Failure.damaged
        }

        // ZIP64：任何一个字段是全 1 时去读 ZIP64 末尾记录。
        if total == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = eocd - 20
            guard locator >= 0, u32(bytes, locator) == zip64LocatorSignature else { throw Failure.damaged }
            let recordOffset = u64(bytes, locator + 8)
            guard count >= 56, recordOffset <= UInt64(count - 56) else { throw Failure.damaged }
            let record = Int(recordOffset)
            guard u32(bytes, record) == zip64EOCDSignature else { throw Failure.damaged }
            total = u64(bytes, record + 32)
            directorySize = u64(bytes, record + 40)
            directoryOffset = u64(bytes, record + 48)
        }

        guard total <= UInt64(maxEntries) else { throw Failure.tooManyEntries }
        guard directoryOffset <= UInt64(count), directorySize <= UInt64(count) - directoryOffset else {
            throw Failure.damaged
        }

        var result: [ZipEntryInfo] = []
        result.reserveCapacity(Int(total))
        var cursor = Int(directoryOffset)
        let end = Int(directoryOffset + directorySize)
        for _ in 0..<Int(total) {
            guard cursor + 46 <= end, u32(bytes, cursor) == centralHeaderSignature else { throw Failure.damaged }
            let madeBy = u16(bytes, cursor + 4)
            var compressed = UInt64(u32(bytes, cursor + 20))
            var uncompressed = UInt64(u32(bytes, cursor + 24))
            let nameLength = Int(u16(bytes, cursor + 28))
            let extraLength = Int(u16(bytes, cursor + 30))
            let commentLength = Int(u16(bytes, cursor + 32))
            let external = u32(bytes, cursor + 38)
            let nameStart = cursor + 46
            let extraStart = nameStart + nameLength
            let next = extraStart + extraLength + commentLength
            guard next <= end else { throw Failure.damaged }

            // ZIP64 扩展字段（0x0001）：只带原本是全 1 的那几项，顺序是解压后、压缩后。
            if uncompressed == 0xFFFF_FFFF || compressed == 0xFFFF_FFFF {
                var extra = extraStart
                var found = false
                while extra + 4 <= extraStart + extraLength {
                    let id = u16(bytes, extra)
                    let size = Int(u16(bytes, extra + 2))
                    let body = extra + 4
                    guard body + size <= extraStart + extraLength else { break }
                    if id == 0x0001 {
                        var field = body
                        if uncompressed == 0xFFFF_FFFF {
                            guard field + 8 <= body + size else { throw Failure.damaged }
                            uncompressed = u64(bytes, field)
                            field += 8
                        }
                        if compressed == 0xFFFF_FFFF {
                            guard field + 8 <= body + size else { throw Failure.damaged }
                            compressed = u64(bytes, field)
                        }
                        found = true
                        break
                    }
                    extra = body + size
                }
                guard found else { throw Failure.damaged }
            }

            let name = String(decoding: bytes[nameStart..<extraStart], as: UTF8.self)
            // 高字节 3 是 Unix 建的，外部属性高 16 位是文件模式。
            let mode = (madeBy >> 8) == 3 ? (external >> 16) & 0o170000 : 0
            let isSymlink = mode == 0o120000
            let isDirectory = mode == 0o040000 || name.hasSuffix("/") || name.hasSuffix("\\")
            result.append(ZipEntryInfo(name: name, compressedSize: compressed, uncompressedSize: uncompressed,
                                       isDirectory: isDirectory, isSymlink: isSymlink))
            cursor = next
        }
        return result
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i >= 0, i + 2 <= b.count else { return 0 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i >= 0, i + 4 <= b.count else { return 0 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    private static func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        guard i >= 0, i + 8 <= b.count else { return 0 }
        return UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32
    }
}

/// 声音包的大小和路径上限。
public enum TypingSoundPackLimits {
    /// 解压后全部加起来最多多少字节。
    public static let maxTotalBytes: UInt64 = 200 * 1024 * 1024
    /// 单个文件解压后最多多少字节。
    public static let maxEntryBytes: UInt64 = 20 * 1024 * 1024
    /// zip 里最多多少个条目（文件夹和 __MACOSX 里的也算）。
    public static let maxEntries = 1000

    public enum Failure: Error, Equatable, Sendable {
        case damaged
        case tooManyEntries
        case entryTooLarge(String)
        case totalTooLarge
        case unsafePath(String)
        case symlink(String)

        public var message: String {
            switch self {
            case .damaged: tr("解压失败，压缩包可能坏了。")
            case .tooManyEntries: tr("压缩包里的文件太多（超过 1000 个），不像声音包。")
            case .entryTooLarge(let name): tr("\(Self.short(name)) 超过 20 MB，不像按键声音。")
            case .totalTooLarge: tr("压缩包解压后超过 200 MB，为了安全没有导入。")
            case .unsafePath(let name): tr("压缩包里有不安全的路径：\(Self.short(name))")
            case .symlink(let name): tr("压缩包里有符号链接（\(Self.short(name))），为了安全没有导入。")
            }
        }

        private static func short(_ name: String) -> String {
            name.count > 60 ? String(name.prefix(57)) + "..." : name
        }
    }

    /// 解压前检查一个 zip 的全部内容。
    public static func check(zip data: Data) throws {
        let entries: [ZipEntryInfo]
        do {
            entries = try ZipCentralDirectory.entries(in: data, maxEntries: maxEntries)
        } catch ZipCentralDirectory.Failure.tooManyEntries {
            throw Failure.tooManyEntries
        } catch {
            throw Failure.damaged
        }
        try check(entries)
    }

    /// 检查条目：数量、单个大小、总大小、路径、符号链接。
    public static func check(_ entries: [ZipEntryInfo]) throws {
        guard entries.count <= maxEntries else { throw Failure.tooManyEntries }
        var total: UInt64 = 0
        for entry in entries {
            guard isSafeEntryName(entry.name) else { throw Failure.unsafePath(entry.name) }
            guard !entry.isSymlink else { throw Failure.symlink(entry.name) }
            guard entry.uncompressedSize <= maxEntryBytes else { throw Failure.entryTooLarge(entry.name) }
            total += entry.uncompressedSize
            guard total <= maxTotalBytes else { throw Failure.totalTooLarge }
        }
    }

    /// zip 条目名安不安全：不能是绝对路径（/、\、C:），不能带 .. 这一层，不能有 NUL。
    public static func isSafeEntryName(_ raw: String) -> Bool {
        guard !raw.isEmpty, !raw.contains("\0") else { return false }
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("/") || path.hasPrefix("~") { return false }
        let scalars = Array(path.unicodeScalars)
        if scalars.count >= 2, scalars[1] == ":", scalars[0].isASCII,
           CharacterSet.letters.contains(scalars[0]) { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }
}

// MARK: - 认音频格式

/// 看文件开头的几个字节认是什么音频。只用来在解不开时说清楚原因，不决定能不能解。
public enum TypingSoundAudioFormat: String, Sendable {
    case ogg
    case wav
    case flac
    case mp3
    case aiff
    case caf
    case mp4
    case unknown

    /// 认格式要的字节数。
    public static let headerLength = 12

    public static func sniff(_ header: Data) -> TypingSoundAudioFormat {
        let b = [UInt8](header.prefix(headerLength))
        func ascii(_ offset: Int, _ text: String) -> Bool {
            let t = Array(text.utf8)
            return b.count >= offset + t.count && Array(b[offset..<offset + t.count]) == t
        }
        if ascii(0, "OggS") { return .ogg }
        if ascii(0, "RIFF"), ascii(8, "WAVE") { return .wav }
        if ascii(0, "fLaC") { return .flac }
        if ascii(0, "FORM"), ascii(8, "AIFF") || ascii(8, "AIFC") { return .aiff }
        if ascii(0, "caff") { return .caf }
        if ascii(4, "ftyp") { return .mp4 }
        if ascii(0, "ID3") { return .mp3 }
        if b.count >= 2, b[0] == 0xFF, b[1] & 0xE0 == 0xE0 { return .mp3 }
        return .unknown
    }

    /// 一个解不开的文件是不是 OGG：扩展名是 .ogg / .oga，或者内容其实是 OGG（改了扩展名的）。
    public static func isOgg(fileName: String, header: Data) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext == "ogg" || ext == "oga" || sniff(header) == .ogg
    }

    /// 声音包用的是 OGG、这台 Mac 又解不开时给用户看的话。
    public static var oggUnsupportedMessage: String {
        tr("此音效包使用 OGG 格式，暂不支持，请用 WAV/MP3 版本。")
    }
}
