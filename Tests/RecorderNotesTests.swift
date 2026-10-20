import XCTest
@testable import Docket

final class RecorderNotesTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: 免费和 Pro

    func testRecorderIsFreeAndOnlyToolsArePro() {
        XCTAssertFalse(ProFeatures.isProKind(.recorder))
        XCTAssertFalse(ProFeatures.isPro(.recorder, overrides: [:]))
        XCTAssertTrue(ProLicenseGate.canAdd(.recorder, overrides: [:], unlocked: false))
        let placed = WidgetInstance(kind: .recorder, config: WidgetConfig(["folder": .string("")]))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false), "免费用户的录音卡片不盖锁")
        XCTAssertFalse(ProLicenseGate.canUseRecorderTools(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseRecorderTools(unlocked: true))
        XCTAssertTrue(ProUnlockStyle.allCases.contains(.recorderTools))
    }

    // MARK: 时长

    func testClockIsTwoDigits() {
        XCTAssertEqual(RecorderClock.text(0), "00:00")
        XCTAssertEqual(RecorderClock.text(372.9), "06:12")
        XCTAssertEqual(RecorderClock.text(1122), "18:42")
        XCTAssertEqual(RecorderClock.text(3723), "1:02:03")
        XCTAssertEqual(RecorderClock.text(-5), "00:00")
        XCTAssertEqual(RecorderClock.text(.nan), "00:00")
        XCTAssertEqual(RecorderClock.text(.infinity), "00:00")
    }

    func testCaptionTodayAndEarlier() {
        let now = date(2026, 10, 20, 10, 23)
        XCTAssertEqual(RecorderClock.caption(date: date(2026, 10, 20, 9, 30), duration: 1122, now: now, calendar: utc),
                       "09:30 · 18:42")
        XCTAssertEqual(RecorderClock.caption(date: date(2026, 10, 20, 9, 30), duration: nil, now: now, calendar: utc),
                       "09:30")
        XCTAssertEqual(RecorderClock.caption(date: date(2026, 10, 18, 8, 5), duration: 190, now: now, calendar: utc),
                       "10月18日 08:05 · 03:10")
    }

    // MARK: 名字

    func testDefaultNameShowsTime() {
        XCTAssertTrue(RecorderTitle.isDefault("录音 2026-10-20 09.30.05.m4a"))
        XCTAssertTrue(RecorderTitle.isDefault("录音 2026-10-20 09.30.05 2.m4a"))
        XCTAssertEqual(RecorderTitle.display(fileName: "录音 2026-10-20 09.30.05.m4a"), "录音 09:30")
        XCTAssertEqual(RecorderTitle.display(fileName: "录音 2026-10-20 10.20.00 3.M4A"), "录音 10:20")
        XCTAssertEqual(RecorderTitle.editable(fileName: "录音 2026-10-20 09.30.05.m4a"), "")
    }

    func testCustomNameDropsPrefix() {
        XCTAssertFalse(RecorderTitle.isDefault("录音 需求会：第二批面板.m4a"))
        XCTAssertEqual(RecorderTitle.display(fileName: "录音 需求会：第二批面板.m4a"), "需求会：第二批面板")
        XCTAssertEqual(RecorderTitle.editable(fileName: "录音 需求会.m4a"), "需求会")
        // 名字本身像日期但不完整，不当成默认名。
        XCTAssertEqual(RecorderTitle.display(fileName: "录音 2026-10-20.m4a"), "2026-10-20")
        XCTAssertEqual(RecorderTitle.display(fileName: "录音 2026-10-20 09.30.05 草稿.m4a"), "2026-10-20 09.30.05 草稿")
    }

    func testCleanName() {
        XCTAssertNil(RecorderTitle.clean("   "))
        XCTAssertNil(RecorderTitle.clean("..."))
        XCTAssertEqual(RecorderTitle.clean("  会议 / 纪要: 1 \n"), "会议 ／ 纪要： 1")
        XCTAssertEqual(RecorderTitle.clean(".隐藏"), "隐藏")
        let long = String(repeating: "长", count: 100)
        XCTAssertEqual(RecorderTitle.clean(long)?.count, RecorderTitle.maxLength)
    }

    func testRenameKeepsPrefixAndAvoidsClashes() {
        let current = "录音 2026-10-20 09.30.05.m4a"
        XCTAssertEqual(RecorderTitle.renamed(current, to: "需求会", taken: [current]), "录音 需求会.m4a")
        XCTAssertEqual(RecorderTitle.renamed(current, to: "需求会", taken: [current, "录音 需求会.m4a"]),
                       "录音 需求会 2.m4a")
        XCTAssertNil(RecorderTitle.renamed("录音 需求会.m4a", to: " 需求会 ", taken: ["录音 需求会.m4a"]), "没变不改")
        XCTAssertNil(RecorderTitle.renamed(current, to: "  ", taken: [current]), "空名字不改")
        let renamed = RecorderTitle.renamed(current, to: "a:b", taken: [])!
        XCTAssertTrue(RecordingNaming.isRecording(renamed), "改名后列表还认得出")
    }

    func testExcerptTitle() {
        XCTAssertEqual(RecorderTitle.excerptTitle("需求会"), "需求会 选段")
    }

    // MARK: 转写

    func testWordsBecomeParagraphs() {
        let words = [
            TranscriptWord(text: "先过", start: 0.5, duration: 0.4),
            TranscriptWord(text: "第二批", start: 0.9, duration: 0.5),
            TranscriptWord(text: "面板。", start: 1.4, duration: 0.4),
            TranscriptWord(text: "麦克风", start: 4.0, duration: 0.5),
            TranscriptWord(text: "", start: 4.5, duration: 0.1),
            TranscriptWord(text: "Codex", start: 4.6, duration: 0.4),
            TranscriptWord(text: "app", start: 5.0, duration: 0.3),
        ]
        let paras = Transcript.paragraphs(words)
        XCTAssertEqual(paras, [
            TranscriptSegment(start: 0.5, text: "先过第二批面板。"),
            TranscriptSegment(start: 4.0, text: "麦克风Codex app"),
        ])
        XCTAssertEqual(Transcript.paragraphs([]), [])
    }

    func testLongParagraphSplitsAtSentenceEnd() {
        var words: [TranscriptWord] = []
        for i in 0..<30 { words.append(TranscriptWord(text: "字字。", start: Double(i) * 0.3, duration: 0.2)) }
        let paras = Transcript.paragraphs(words)
        XCTAssertGreaterThan(paras.count, 1)
        XCTAssertTrue(paras.allSatisfy { $0.text.count <= Transcript.paragraphLength + 3 })
    }

    func testJoinTextAndPreview() {
        XCTAssertEqual(Transcript.join("hello", "world"), "hello world")
        XCTAssertEqual(Transcript.join("你好", "world"), "你好world")
        XCTAssertEqual(Transcript.join("", "a"), "a")
        let segs = [TranscriptSegment(start: 0, text: "第一段。"), TranscriptSegment(start: 3, text: "  "),
                    TranscriptSegment(start: 5, text: "第二段")]
        XCTAssertEqual(Transcript.fullText(segs), "第一段。\n第二段")
        XCTAssertEqual(Transcript.preview(segs), "第一段。第二段")
        XCTAssertTrue(Transcript.hasText(segs))
        XCTAssertFalse(Transcript.hasText([TranscriptSegment(start: 0, text: " ")]))
        XCTAssertFalse(Transcript.hasText([]))
    }

    func testTrimmedTranscriptShiftsTimes() {
        let segs = [TranscriptSegment(start: 0, text: "A"), TranscriptSegment(start: 30, text: "B"),
                    TranscriptSegment(start: 60, text: "C"), TranscriptSegment(start: 100, text: "D")]
        XCTAssertEqual(Transcript.trimmed(segs, start: 42, end: 90), [
            TranscriptSegment(start: 0, text: "B"),
            TranscriptSegment(start: 18, text: "C"),
        ])
        XCTAssertEqual(Transcript.trimmed(segs, start: 0, end: 200).count, 4)
        XCTAssertEqual(Transcript.trimmed(segs, start: 50, end: 50), [])
        XCTAssertEqual(Transcript.trimmed([], start: 0, end: 10), [])
    }

    func testProgressNeverReachesOneEarly() {
        XCTAssertEqual(Transcript.progress(heard: 30, duration: 60), 0.5)
        XCTAssertEqual(Transcript.progress(heard: 90, duration: 60), 0.99)
        XCTAssertEqual(Transcript.progress(heard: 10, duration: nil), 0)
        XCTAssertEqual(Transcript.progress(heard: 10, duration: 0), 0)
    }

    func testLocaleCandidates() {
        XCTAssertEqual(TranscribeLocales.candidates(preferred: ["zh_CN"]), ["zh-CN", "en-US"])
        XCTAssertEqual(TranscribeLocales.candidates(preferred: ["ja-JP", ""]), ["ja-JP", "zh-CN", "en-US"])
    }

    // MARK: 裁剪

    func testTrimClampsAndKeepsMinimum() {
        var trim = RecordingTrim(duration: 1122)
        XCTAssertTrue(trim.isFull)
        XCTAssertEqual(trim.rangeLabel, "00:00 至 18:42")
        trim.setStart(fraction: 42.0 / 1122)
        trim.setEnd(fraction: 1030.0 / 1122)
        XCTAssertFalse(trim.isFull)
        XCTAssertEqual(trim.rangeLabel, "00:42 至 17:10")
        XCTAssertEqual(trim.remainingLabel, "剩 16:28")
        // 把开头拖过结尾：停在结尾前 1 秒。
        trim.setStart(fraction: 1.5)
        XCTAssertEqual(trim.start, trim.end - RecordingTrim.minimumLength, accuracy: 0.001)
        // 把结尾拖到开头前：停在开头后 1 秒。
        trim.setEnd(fraction: -1)
        XCTAssertEqual(trim.end, trim.start + RecordingTrim.minimumLength, accuracy: 0.001)
        trim.reset()
        XCTAssertTrue(trim.isFull)
        trim.setStart(fraction: .nan)
        XCTAssertEqual(trim.start, 0)
    }

    func testTrimOfVeryShortAndEmptyRecordings() {
        var short = RecordingTrim(duration: 0.5)
        short.setStart(fraction: 0.9)
        XCTAssertEqual(short.start, 0, accuracy: 0.001, "比 1 秒还短的录音不能再裁")
        var empty = RecordingTrim(duration: 0)
        empty.setEnd(fraction: 0.5)
        XCTAssertEqual(empty.length, 0)
        XCTAssertEqual(empty.startFraction, 0)
        XCTAssertEqual(empty.endFraction, 1)
        XCTAssertEqual(RecordingTrim(duration: .nan).duration, 0)
    }

    // MARK: 波形

    func testWaveformBars() {
        let bars = Waveform.bars([0, 0.5, 1, 0.25], count: 2)
        XCTAssertEqual(bars, [0.5, 1])
        XCTAssertEqual(Waveform.bars([], count: 3), [Waveform.floor, Waveform.floor, Waveform.floor])
        XCTAssertEqual(Waveform.bars([0, 0], count: 2), [Waveform.floor, Waveform.floor])
        XCTAssertEqual(Waveform.bars([1], count: 4).count, 4, "采样比条少也画满")
        XCTAssertEqual(Waveform.bars([.nan, 1], count: 2), [Waveform.floor, 1])
        XCTAssertEqual(Waveform.bars([1, 2], count: 0), [])
        XCTAssertEqual(Waveform.fraction(x: 50, width: 200), 0.25)
        XCTAssertEqual(Waveform.fraction(x: -10, width: 200), 0)
        XCTAssertEqual(Waveform.fraction(x: 300, width: 200), 1)
        XCTAssertEqual(Waveform.fraction(x: 10, width: 0), 0)
    }

    // MARK: 分组

    func testDayGroups() {
        let now = date(2026, 10, 20, 10, 23)
        let dates = [date(2026, 10, 20, 9, 30), date(2026, 10, 20, 8, 5), date(2026, 10, 19, 22, 0),
                     date(2026, 10, 1, 9, 0)]
        let groups = RecorderDay.groups(dates, date: { $0 }, now: now, calendar: utc)
        XCTAssertEqual(groups.map(\.day), [.today, .yesterday, .earlier])
        XCTAssertEqual(groups.map(\.items.count), [2, 1, 1])
        XCTAssertEqual(RecorderDay.header(.today, count: 2), "今天 · 2 条")
        XCTAssertTrue(RecorderDay.groups([Date](), date: { $0 }, now: now).isEmpty)
    }

    // MARK: 存文字的小表

    func testNotesFollowRenameAndDelete() {
        var notes = RecordingNotes()
        let a = URL(fileURLWithPath: "/tmp/rec/录音 2026-10-20 09.30.05.m4a")
        let b = URL(fileURLWithPath: "/tmp/rec/录音 需求会.m4a")
        notes.set([TranscriptSegment(start: 0, text: "你好")], for: a)
        notes.move(from: a, to: b)
        XCTAssertNil(notes.segments(for: a))
        XCTAssertEqual(notes.segments(for: b)?.first?.text, "你好")
        notes.move(from: a, to: b)  // 旧的已经不在，什么也不做。
        XCTAssertEqual(notes.segments(for: b)?.count, 1)
        notes.remove(b)
        XCTAssertNil(notes.segments(for: b))
    }

    func testNotesRoundTripAndPrune() {
        var notes = RecordingNotes()
        let folder = URL(fileURLWithPath: "/tmp/rec", isDirectory: true)
        let kept = folder.appendingPathComponent("录音 甲.m4a")
        let gone = folder.appendingPathComponent("录音 乙.m4a")
        let elsewhere = URL(fileURLWithPath: "/tmp/other/录音 丙.m4a")
        for url in [kept, gone, elsewhere] { notes.set([TranscriptSegment(start: 1, text: "字")], for: url) }
        notes.prune(folder: folder, existing: ["录音 甲.m4a"])
        XCTAssertNotNil(notes.segments(for: kept))
        XCTAssertNil(notes.segments(for: gone))
        XCTAssertNotNil(notes.segments(for: elsewhere), "别的文件夹的不动")
        let back = RecordingNotes.decode(notes.encoded())
        XCTAssertEqual(back, notes)
        XCTAssertEqual(RecordingNotes.decode(nil), RecordingNotes())
        XCTAssertEqual(RecordingNotes.decode(Data("坏的".utf8)), RecordingNotes())
    }
}
