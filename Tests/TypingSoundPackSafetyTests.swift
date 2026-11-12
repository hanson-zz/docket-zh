import XCTest
@testable import Docket

final class TypingSoundPackSafetyTests: XCTestCase {

    // MARK: 造 zip

    /// 只造中央目录和末尾记录（检查只读这两块），大小随便写，用来模拟 zip 炸弹。
    private struct FakeEntry {
        var name: String
        var size: UInt64
        /// Unix 文件模式（带类型位），nil 表示不是 Unix 建的。
        var mode: UInt32? = nil
    }

    private func le16(_ v: Int, into d: inout Data) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
    private func le32(_ v: UInt32, into d: inout Data) {
        d.append(contentsOf: (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) })
    }
    private func le64(_ v: UInt64, into d: inout Data) {
        d.append(contentsOf: (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xFF) })
    }

    private func makeZip(_ entries: [FakeEntry], zip64: Bool = false, comment: String = "",
                         declaredCount: Int? = nil) -> Data {
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            le32(0x0201_4B50, into: &directory)
            le16(entry.mode == nil ? 0x0014 : 0x0314, into: &directory)
            le16(20, into: &directory)
            le16(0, into: &directory)   // flags
            le16(8, into: &directory)   // deflate
            le16(0, into: &directory)
            le16(0, into: &directory)
            le32(0, into: &directory)   // crc
            le32(zip64 ? 0xFFFF_FFFF : UInt32(min(entry.size / 100, 0xFFFF_FFFE)), into: &directory)
            le32(zip64 ? 0xFFFF_FFFF : UInt32(min(entry.size, 0xFFFF_FFFE)), into: &directory)
            le16(name.count, into: &directory)
            le16(zip64 ? 20 : 0, into: &directory)
            le16(0, into: &directory)   // comment
            le16(0, into: &directory)   // disk
            le16(0, into: &directory)   // internal
            le32((entry.mode ?? 0) << 16, into: &directory)
            le32(0, into: &directory)   // local header offset
            directory.append(name)
            if zip64 {
                le16(0x0001, into: &directory)
                le16(16, into: &directory)
                le64(entry.size, into: &directory)
                le64(entry.size / 100, into: &directory)
            }
        }
        var data = Data("PK-fake-local-headers".utf8)
        let directoryOffset = data.count
        data.append(directory)
        let count = declaredCount ?? entries.count
        if zip64 {
            let record = data.count
            le32(0x0606_4B50, into: &data)
            le64(44, into: &data)
            le16(45, into: &data)
            le16(45, into: &data)
            le32(0, into: &data)
            le32(0, into: &data)
            le64(UInt64(count), into: &data)
            le64(UInt64(count), into: &data)
            le64(UInt64(directory.count), into: &data)
            le64(UInt64(directoryOffset), into: &data)
            le32(0x0706_4B50, into: &data)
            le32(0, into: &data)
            le64(UInt64(record), into: &data)
            le32(1, into: &data)
        }
        le32(0x0605_4B50, into: &data)
        le16(0, into: &data)
        le16(0, into: &data)
        le16(zip64 ? 0xFFFF : count, into: &data)
        le16(zip64 ? 0xFFFF : count, into: &data)
        le32(zip64 ? 0xFFFF_FFFF : UInt32(directory.count), into: &data)
        le32(zip64 ? 0xFFFF_FFFF : UInt32(directoryOffset), into: &data)
        let commentData = Data(comment.utf8)
        le16(commentData.count, into: &data)
        data.append(commentData)
        return data
    }

    private let mb: UInt64 = 1024 * 1024

    // MARK: 中央目录

    /// Python zipfile 造的真 zip：pack/、pack/config.json、pack/sound.wav（1004 字节）。
    func testReadsRealZip() throws {
        let base64 = "UEsDBBQAAAAIADlHYl0AAAAAAgAAAAAAAAAFAAAAcGFjay8DAFBLAwQUAAAACAA5R2JdabOBng4AAAAMAAAAEAAAAHBhY2svY29uZmlnLmpzb26rVspLzE1VslKqUKoFAFBLAwQUAAAACAA5R2Jd65elaA4AAADsAwAADgAAAHBhY2svc291bmQud2F2C/J0c2MYBaNgFAx7AABQSwECFAMUAAAACAA5R2JdAAAAAAIAAAAAAAAABQAAAAAAAAAAABAA/UEAAAAAcGFjay9QSwECFAMUAAAACAA5R2JdabOBng4AAAAMAAAAEAAAAAAAAAAAAAAAgAElAAAAcGFjay9jb25maWcuanNvblBLAQIUAxQAAAAIADlHYl3rl6VoDgAAAOwDAAAOAAAAAAAAAAAAAACAAWEAAABwYWNrL3NvdW5kLndhdlBLBQYAAAAAAwADAK0AAACbAAAAAAA="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        let entries = try ZipCentralDirectory.entries(in: data, maxEntries: 1000)
        XCTAssertEqual(entries.map(\.name), ["pack/", "pack/config.json", "pack/sound.wav"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, false, false])
        XCTAssertEqual(entries[1].uncompressedSize, 12)
        XCTAssertEqual(entries[2].uncompressedSize, 1004)
        XCTAssertFalse(entries.contains(where: \.isSymlink))
        XCTAssertNoThrow(try TypingSoundPackLimits.check(zip: data))
    }

    func testReadsZipWithCommentAndZip64() throws {
        let plain = makeZip([FakeEntry(name: "a.wav", size: 1000)], comment: "hello")
        XCTAssertEqual(try ZipCentralDirectory.entries(in: plain, maxEntries: 10).first?.uncompressedSize, 1000)

        let big = makeZip([FakeEntry(name: "a.wav", size: 5 * 1024 * mb)], zip64: true)
        let entries = try ZipCentralDirectory.entries(in: big, maxEntries: 10)
        XCTAssertEqual(entries.first?.uncompressedSize, 5 * 1024 * mb, "ZIP64 里的真实大小")
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: big)) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .entryTooLarge("a.wav"))
        }
    }

    func testDamagedZip() {
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: Data("not a zip at all, nope".utf8))) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .damaged)
        }
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: Data())) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .damaged)
        }
        // 末尾记录说有 3 个条目，中央目录里只有 1 个。
        let short = makeZip([FakeEntry(name: "a.wav", size: 10)], declaredCount: 3)
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: short)) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .damaged)
        }
        // 截掉一半。
        let whole = makeZip([FakeEntry(name: "a.wav", size: 10), FakeEntry(name: "b.wav", size: 10)])
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: whole.prefix(whole.count / 2)))
    }

    // MARK: 大小上限（zip 炸弹）

    func testRejectsZipBombs() {
        // 总量超过 200 MB：每个 19 MB，11 个。
        let many = (0..<11).map { FakeEntry(name: "s\($0).wav", size: 19 * mb) }
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: makeZip(many))) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .totalTooLarge)
        }
        // 单个超过 20 MB。
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: makeZip([FakeEntry(name: "huge.wav", size: 21 * mb)]))) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .entryTooLarge("huge.wav"))
        }
        // 刚好在上限内的能过。
        let fine = (0..<10).map { FakeEntry(name: "s\($0).wav", size: 20 * mb) }
        XCTAssertNoThrow(try TypingSoundPackLimits.check(zip: makeZip(fine)))
        // 条目太多。
        let crowd = (0...TypingSoundPackLimits.maxEntries).map { FakeEntry(name: "f\($0).wav", size: 1) }
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: makeZip(crowd))) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .tooManyEntries)
        }
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: makeZip([], declaredCount: 60_000))) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .tooManyEntries, "声明的条目数超了就不往下读")
        }
    }

    func testLimitsMatchMessages() {
        XCTAssertEqual(TypingSoundPackLimits.maxTotalBytes, 200 * mb)
        XCTAssertEqual(TypingSoundPackLimits.maxEntryBytes, 20 * mb)
        XCTAssertTrue(TypingSoundPackLimits.Failure.totalTooLarge.message.contains("200 MB"))
        XCTAssertTrue(TypingSoundPackLimits.Failure.entryTooLarge("x.wav").message.contains("20 MB"))
        XCTAssertTrue(TypingSoundPackLimits.Failure.tooManyEntries.message.contains("\(TypingSoundPackLimits.maxEntries)"))
        let long = String(repeating: "a", count: 300) + ".wav"
        XCTAssertLessThan(TypingSoundPackLimits.Failure.unsafePath(long).message.count, 120, "长名字截短")
    }

    // MARK: 路径穿越和符号链接

    func testRejectsPathTraversal() {
        for bad in ["../evil.wav", "pack/../../evil.wav", "/etc/passwd", "\\evil.wav", "pack\\..\\..\\evil.wav",
                    "C:/evil.wav", "c:\\evil.wav", "~/evil.wav", "a/\0b.wav", ""] {
            XCTAssertFalse(TypingSoundPackLimits.isSafeEntryName(bad), bad)
        }
        for good in ["pack/config.json", "pack/sounds/a.wav", "a..b.wav", "..hidden/x.wav", "__MACOSX/pack/._a.wav", "x/"] {
            XCTAssertTrue(TypingSoundPackLimits.isSafeEntryName(good), good)
        }
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: makeZip([FakeEntry(name: "ok.wav", size: 1),
                                                                          FakeEntry(name: "../x.wav", size: 1)]))) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .unsafePath("../x.wav"))
        }
    }

    func testRejectsSymlinks() throws {
        let zip = makeZip([FakeEntry(name: "pack/link.wav", size: 11, mode: 0o120777)])
        XCTAssertEqual(try ZipCentralDirectory.entries(in: zip, maxEntries: 10).first?.isSymlink, true)
        XCTAssertThrowsError(try TypingSoundPackLimits.check(zip: zip)) {
            XCTAssertEqual($0 as? TypingSoundPackLimits.Failure, .symlink("pack/link.wav"))
        }
        let regular = makeZip([FakeEntry(name: "pack/a.wav", size: 11, mode: 0o100644)])
        XCTAssertNoThrow(try TypingSoundPackLimits.check(zip: regular))
    }

    // MARK: 认音频格式

    func testSniffsAudioFormats() {
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("OggS\0\u{2}".utf8)), .ogg)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("RIFF\0\0\0\0WAVE".utf8)), .wav)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("fLaC\0\0\0\"".utf8)), .flac)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("ID3\u{4}".utf8)), .mp3)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data([0xFF, 0xFB, 0x90, 0x00])), .mp3)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("FORM\0\0\0\0AIFF".utf8)), .aiff)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("caff\0\u{1}".utf8)), .caf)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("\0\0\0\u{20}ftypM4A ".utf8)), .mp4)
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data("Ogg".utf8)), .unknown, "太短")
        XCTAssertEqual(TypingSoundAudioFormat.sniff(Data()), .unknown)
    }

    func testDetectsOggPacks() {
        XCTAssertTrue(TypingSoundAudioFormat.isOgg(fileName: "sound.ogg", header: Data()))
        XCTAssertTrue(TypingSoundAudioFormat.isOgg(fileName: "a/B.OGG", header: Data()))
        XCTAssertTrue(TypingSoundAudioFormat.isOgg(fileName: "renamed.wav", header: Data("OggS\0".utf8)), "改了扩展名的 OGG")
        XCTAssertFalse(TypingSoundAudioFormat.isOgg(fileName: "sound.wav", header: Data("RIFF\0\0\0\0WAVE".utf8)))
        XCTAssertFalse(TypingSoundAudioFormat.isOgg(fileName: "sound.flac", header: Data("fLaC".utf8)))
        let message = TypingSoundAudioFormat.oggUnsupportedMessage
        XCTAssertTrue(message.contains("OGG") && message.contains("WAV/MP3"))
    }

    func testUnsupportedFormatMessageNoLongerSuggestsOgg() {
        XCTAssertFalse(MechvibesPack.ParseError.unsupportedFormat("opus").message.contains("ogg"))
    }
}
