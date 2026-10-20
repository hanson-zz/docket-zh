import CoreGraphics
import Foundation
import XCTest

/// 「下载」和「最近截图」面板改版：筛选、搜索、分天、多选、改名撞名、
/// 压缩包名字、还剩多久，以及标注的几何和撤销。
final class FilePanelsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    /// 2026-10-20 周二 10:23（上海）。
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10, minute: 23))!
    }

    private func file(_ name: String, daysAgo: Int = 0, hour: Int = 9, folder: Bool = false, size: Int64? = 1000) -> ListedFile {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let date = calendar.date(bySettingHour: hour, minute: 5, second: 0, of: day)!
        return ListedFile(url: URL(fileURLWithPath: "/tmp/dl/\(name)"), date: date, isDirectory: folder, size: size)
    }

    // MARK: 类型筛选

    func testDownloadKinds() {
        XCTAssertEqual(DownloadKind.of(file("海报.PNG")), .image)
        XCTAssertEqual(DownloadKind.of(file("合同.pdf")), .document)
        XCTAssertEqual(DownloadKind.of(file("报价单.xlsx")), .document)
        XCTAssertEqual(DownloadKind.of(file("安装器.dmg")), .installer)
        XCTAssertEqual(DownloadKind.of(file("字体.zip")), .archive)
        XCTAssertNil(DownloadKind.of(file("没有扩展名")))
        XCTAssertNil(DownloadKind.of(file("项目.zip", folder: true)), "名字像压缩包的文件夹不算压缩包")
        XCTAssertTrue(DownloadKind.all.matches(file("随便")))
        XCTAssertFalse(DownloadKind.image.matches(file("合同.pdf")))
    }

    func testShotFilters() {
        let today = file("截屏 今天.png")
        let monday = file("截屏 周一.png", daysAgo: 1)
        let lastWeek = file("截屏 上周.png", daysAgo: 8)
        let movie = file("录屏 2026-10-20.mov")
        XCTAssertTrue(ShotFilter.today.matches(today, now: now, calendar: calendar))
        XCTAssertFalse(ShotFilter.today.matches(monday, now: now, calendar: calendar))
        XCTAssertTrue(ShotFilter.week.matches(monday, now: now, calendar: calendar), "周一和周二同一周")
        XCTAssertFalse(ShotFilter.week.matches(lastWeek, now: now, calendar: calendar))
        XCTAssertTrue(ShotFilter.recording.matches(movie, now: now, calendar: calendar))
        XCTAssertFalse(ShotFilter.recording.matches(today, now: now, calendar: calendar))
        XCTAssertTrue(ShotFilter.all.matches(lastWeek, now: now, calendar: calendar))
    }

    // MARK: 搜索

    func testSearchByNameIgnoresCaseAndWidth() {
        let f = file("Contract第二版.PDF")
        XCTAssertTrue(FileQuery.matches(f, query: "contract", calendar: calendar))
        XCTAssertTrue(FileQuery.matches(f, query: "第二版", calendar: calendar))
        XCTAssertTrue(FileQuery.matches(f, query: "ＰＤＦ", calendar: calendar), "全角也能搜到")
        XCTAssertTrue(FileQuery.matches(f, query: "   ", calendar: calendar), "空搜索全部算")
        XCTAssertFalse(FileQuery.matches(f, query: "报价", calendar: calendar))
    }

    func testSearchByDate() {
        let f = file("截屏.png")
        for q in ["10-20", "10月20日", "10/20", "2026-10-20"] {
            XCTAssertTrue(FileQuery.matches(f, query: q, calendar: calendar), q)
        }
        XCTAssertFalse(FileQuery.matches(f, query: "10-21", calendar: calendar))
    }

    // MARK: 分天

    func testDaySectionsKeepOrderAndSkipEmpty() {
        let files = [file("a", hour: 10), file("b", hour: 9), file("c", daysAgo: 3)]
        let sections = FileDayGroup.sections(files, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.group), [.today, .earlier])
        XCTAssertEqual(sections[0].files.map(\.name), ["a", "b"])
        XCTAssertTrue(FileDayGroup.sections([], now: now, calendar: calendar).isEmpty)
        XCTAssertEqual(FileDayGroup.of(file("y", daysAgo: 1).date, now: now, calendar: calendar), .yesterday)
    }

    func testShortDateForToday() {
        XCTAssertEqual(FileDate.short(file("a", hour: 9).date, now: now, calendar: calendar), "09:05")
    }

    // MARK: 类型小标

    func testBadges() {
        XCTAssertEqual(FileBadge.of(extension: "pdf"), FileBadge(label: "PDF", colorHex: "#E5534B"))
        XCTAssertEqual(FileBadge.of(extension: "docx").label, "DOC")
        XCTAssertEqual(FileBadge.of(extension: "xlsx").label, "XLS")
        XCTAssertEqual(FileBadge.of(extension: "zip").colorHex, "#D9A520")
        XCTAssertEqual(FileBadge.of(extension: "png").colorHex, "#8E6CE0")
        XCTAssertEqual(FileBadge.of(extension: "").label, "FILE")
        XCTAssertLessThanOrEqual(FileBadge.of(extension: "torrent").label.count, 4)
    }

    // MARK: 多选

    func testMultiSelection() {
        var s = MultiSelection<Int>()
        XCTAssertTrue(s.isEmpty)
        s.toggle(1); s.toggle(2)
        XCTAssertEqual(s.count, 2)
        s.toggle(1)
        XCTAssertEqual(s.ids, [2])
        s.toggleAll([1, 2, 3])
        XCTAssertTrue(s.allSelected([1, 2, 3]))
        s.toggleAll([1, 2])
        XCTAssertEqual(s.ids, [3], "全不选只取消看得见的")
        XCTAssertFalse(s.allSelected([]), "空列表不算全选")
        s.toggleAll([4, 5])
        s.prune(keeping: [3, 5])
        XCTAssertEqual(s.ids, [3, 5], "删掉、移走的去掉")
        XCTAssertEqual(s.ordered([5, 4, 3]), [5, 3])
        s.clear()
        XCTAssertTrue(s.isEmpty)
    }

    // MARK: 改名

    func testRenameChecks() {
        let siblings: Set<String> = ["报价单.xlsx", "合同.pdf"]
        XCTAssertEqual(FileRename.check("  ", original: "合同.pdf", siblings: siblings), .failure(.empty))
        XCTAssertEqual(FileRename.check("a/b.pdf", original: "合同.pdf", siblings: siblings), .failure(.invalidCharacter))
        XCTAssertEqual(FileRename.check("a:b.pdf", original: "合同.pdf", siblings: siblings), .failure(.invalidCharacter))
        XCTAssertEqual(FileRename.check(".隐藏", original: "合同.pdf", siblings: siblings), .failure(.hidden))
        XCTAssertEqual(FileRename.check("报价单.XLSX", original: "合同.pdf", siblings: siblings), .failure(.taken))
        XCTAssertEqual(FileRename.check("合同.pdf", original: "合同.pdf", siblings: siblings), .success(nil))
        XCTAssertEqual(FileRename.check("合同签字.pdf", original: "合同.pdf", siblings: siblings), .success("合同签字.pdf"))
        XCTAssertEqual(FileRename.check("合同签字", original: "合同.pdf", siblings: siblings), .success("合同签字.pdf"),
                       "删掉扩展名时补回去")
        XCTAssertEqual(FileRename.check("合同.PDF", original: "合同.pdf", siblings: siblings), .success("合同.PDF"),
                       "只改大小写的自己不算撞名")
        XCTAssertEqual(FileRename.check(String(repeating: "长", count: 100), original: "a.txt", siblings: []),
                       .failure(.tooLong))
    }

    func testUniqueNames() {
        XCTAssertEqual(FileRename.unique("a.pdf", taken: []), "a.pdf")
        XCTAssertEqual(FileRename.unique("a.pdf", taken: ["A.pdf"]), "a 2.pdf")
        XCTAssertEqual(FileRename.unique("a.pdf", taken: ["a.pdf", "a 2.pdf"]), "a 3.pdf")
        XCTAssertEqual(FileRename.unique("文件夹", taken: ["文件夹"]), "文件夹 2")
    }

    func testArchiveNames() {
        XCTAssertEqual(ArchiveNaming.name(for: ["合同.pdf"], taken: []), "合同.pdf.zip")
        XCTAssertEqual(ArchiveNaming.name(for: ["合同.pdf"], taken: ["合同.pdf.zip"]), "合同.pdf 2.zip")
        let several = ArchiveNaming.name(for: ["a", "b"], taken: [])
        XCTAssertTrue(several.hasSuffix(".zip"))
        XCTAssertFalse(several.hasPrefix("a"))
    }

    func testRecentFolders() {
        var list: [String] = []
        list = RecentFolders.adding("/a", to: list)
        list = RecentFolders.adding("/b", to: list)
        list = RecentFolders.adding("/a", to: list)
        XCTAssertEqual(list, ["/a", "/b"], "选过的提到最前，不重复")
        list = RecentFolders.adding("/c", to: list)
        list = RecentFolders.adding("/d", to: list)
        XCTAssertEqual(list, ["/d", "/c", "/a"], "最多 3 个")
        XCTAssertEqual(RecentFolders.adding("  ", to: list), list)
    }

    // MARK: 还剩多久

    func testETA() {
        let t0 = now
        XCTAssertNil(DownloadETA.remaining(firstAt: t0, firstFraction: 0.1, now: t0.addingTimeInterval(1), fraction: 0.2),
                     "看到不到 2 秒不猜")
        XCTAssertNil(DownloadETA.remaining(firstAt: t0, firstFraction: nil, now: t0.addingTimeInterval(10), fraction: 0.5))
        XCTAssertNil(DownloadETA.remaining(firstAt: t0, firstFraction: 0.5, now: t0.addingTimeInterval(10), fraction: 0.5),
                     "没动")
        XCTAssertNil(DownloadETA.remaining(firstAt: t0, firstFraction: 0.5, now: t0.addingTimeInterval(10), fraction: 0.4),
                     "倒退")
        let left = DownloadETA.remaining(firstAt: t0, firstFraction: 0.2, now: t0.addingTimeInterval(10), fraction: 0.4)
        XCTAssertEqual(left ?? 0, 30, accuracy: 0.001)
    }

    func testETALineFallsBackToPercent() {
        XCTAssertEqual(DownloadETA.line(fraction: 0.64, remaining: nil), "64%")
        XCTAssertTrue(DownloadETA.line(fraction: 0.64, remaining: 50).hasPrefix("64% · "))
        XCTAssertEqual(DownloadETA.line(fraction: nil, remaining: 50), DownloadProgress.caption(nil))
    }

    // MARK: 标注

    func testMarkupRejectsTinyStrokesAndEmptyText() {
        var doc = MarkupDocument()
        XCTAssertFalse(doc.add(.arrow, color: .red, from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.501, y: 0.5)))
        XCTAssertFalse(doc.add(.box, color: .red, from: CGPoint(x: 0.1, y: 0.1), to: CGPoint(x: 0.5, y: 0.105)),
                       "压扁成一条线的框不算")
        XCTAssertFalse(doc.add(.text, color: .white, from: .zero, to: .zero, text: "  "))
        XCTAssertTrue(doc.isEmpty)
        XCTAssertFalse(doc.dirty)
        XCTAssertTrue(doc.add(.mosaic, color: .red, from: CGPoint(x: 0.6, y: 0.6), to: CGPoint(x: 0.2, y: 0.3)))
        XCTAssertEqual(doc.marks[0].rect.origin.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(doc.marks[0].rect.width, 0.4, accuracy: 0.0001)
        XCTAssertTrue(doc.dirty)
    }

    func testMarkupClampsUndoAndExport() {
        var doc = MarkupDocument()
        doc.add(.arrow, color: .yellow, from: CGPoint(x: -0.2, y: 0.5), to: CGPoint(x: 1.4, y: 0.5))
        XCTAssertEqual(doc.marks[0].start.x, 0)
        XCTAssertEqual(doc.marks[0].end.x, 1)
        doc.add(.text, color: .green, from: CGPoint(x: 0.3, y: 0.3), to: CGPoint(x: 0.3, y: 0.3), text: " 看这里 ")
        XCTAssertEqual(doc.marks.last?.text, "看这里")
        XCTAssertNotEqual(doc.marks[0].id, doc.marks[1].id)
        doc.markExported()
        XCTAssertFalse(doc.dirty)
        doc.undo()
        XCTAssertEqual(doc.marks.count, 1)
        XCTAssertTrue(doc.dirty, "撤销以后和拷贝出去的不一样了")
        doc.undo()
        XCTAssertFalse(doc.canUndo)
        XCTAssertFalse(doc.dirty, "全撤完就没有要保存的了")
        doc.undo()
        XCTAssertTrue(doc.isEmpty, "空的时候撤销不出错")
    }

    func testFitAndCoordinateRoundTrip() {
        let rect = MarkupGeometry.fit(image: CGSize(width: 1440, height: 900), in: CGSize(width: 288, height: 196))
        XCTAssertEqual(rect.width, 288, accuracy: 0.001)
        XCTAssertEqual(rect.height, 180, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 8, accuracy: 0.001)
        let p = CGPoint(x: 0.25, y: 0.75)
        let back = MarkupGeometry.normalized(MarkupGeometry.point(p, in: rect), in: rect)
        XCTAssertEqual(back.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, p.y, accuracy: 0.0001)
        XCTAssertEqual(MarkupGeometry.normalized(CGPoint(x: -50, y: 500), in: rect), CGPoint(x: 0, y: 1), "拖出图外夹回边上")
        XCTAssertEqual(MarkupGeometry.fit(image: .zero, in: CGSize(width: 10, height: 10)), .zero)
    }

    func testArrowHeadPointsBackFromTheTip() {
        let (l, r) = MarkupGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), length: 10)
        XCTAssertLessThan(l.x, 100)
        XCTAssertLessThan(r.x, 100)
        XCTAssertEqual(l.y, -r.y, accuracy: 0.0001, "两翼对称")
    }

    func testSizesScaleWithImageWidth() {
        XCTAssertEqual(MarkupGeometry.lineWidth(imageWidth: 100), 2, "小图也至少 2")
        XCTAssertGreaterThan(MarkupGeometry.lineWidth(imageWidth: 2880), MarkupGeometry.lineWidth(imageWidth: 1440))
        XCTAssertGreaterThanOrEqual(MarkupGeometry.mosaicCell(imageWidth: 100), 6)
        XCTAssertGreaterThanOrEqual(MarkupGeometry.textSize(imageWidth: 100), 12)
    }

    func testMarkupNewNameNeverOverwrites() {
        let first = MarkupNaming.newName(original: "截屏 10.18.33.png", taken: [])
        XCTAssertTrue(first.hasPrefix("截屏 10.18.33 "))
        XCTAssertTrue(first.hasSuffix(".png"))
        let second = MarkupNaming.newName(original: "截屏 10.18.33.png", taken: [first])
        XCTAssertNotEqual(first, second)
    }

    func testColorsAreTheFourFromTheDesign() {
        XCTAssertEqual(MarkupColor.allCases.map(\.hex), ["#FF6B5A", "#FFC94D", "#5BD98A", "#FFFFFF"])
        XCTAssertEqual(MarkupColor.white.rgb.r, 1, accuracy: 0.0001)
        XCTAssertEqual(MarkupTool.allCases.count, 4)
    }
}
