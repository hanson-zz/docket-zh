import Foundation
import XCTest
@testable import Docket

/// 「Codex 用量」升级：会话列表、正在做什么、统计、去终端、卡片两种。
/// 会话记录都是手写的样例，形状照 Codex 写进 rollout-*.jsonl 的样子。
final class CodexSessionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    private func line(_ kind: String, _ payload: [String: Any], at: Date? = nil) -> String {
        let record: [String: Any] = ["timestamp": iso(at ?? now), "type": kind, "payload": payload]
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func log(_ lines: [String]) -> Data { Data(lines.joined(separator: "\n").utf8) }

    private func call(_ name: String, _ args: [String: Any], id: String) -> String {
        let text = String(data: try! JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        return line("response_item", ["type": "function_call", "name": name, "arguments": text, "call_id": id])
    }

    // MARK: 会话头

    func testMetaReadsIdCwdOriginatorAndStart() {
        let head = log([line("session_meta", ["id": "abc", "cwd": "/Users/me/code/docket",
                                              "originator": "codex_cli_rs", "timestamp": iso(now)])])
        let meta = CodexRollout.meta(inHead: head)
        XCTAssertEqual(meta?.id, "abc")
        XCTAssertEqual(meta?.project, "docket")
        XCTAssertEqual(meta?.originator, "codex_cli_rs")
        XCTAssertEqual(meta?.startedAt?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(meta?.isSubagent, false)
    }

    func testMetaFallsBackWhenTheFirstLineIsCutOff() {
        // 第一行带着很长的系统提示，读进来的开头不是完整的一行。
        let text = #"{"timestamp":"2026-10-22T00:00:00.000Z","type":"session_meta","payload":{"id":"x1","cwd":"\/tmp\/bake-cost","originator":"codex_vscode","instructions":"aaaa"#
        let meta = CodexRollout.meta(inHead: Data(text.utf8))
        XCTAssertEqual(meta?.id, "x1")
        XCTAssertEqual(meta?.project, "bake-cost")
        XCTAssertEqual(meta?.originator, "codex_vscode")
    }

    func testSubagentSessionsAreMarked() {
        let head = log([line("session_meta", ["id": "c", "cwd": "/a", "parent_thread_id": "p"])])
        XCTAssertEqual(CodexRollout.meta(inHead: head)?.isSubagent, true)
        let session = CodexSession.make(id: "f", meta: CodexRollout.meta(inHead: head),
                                        tail: CodexTailSummary(lastEvent: .working), modified: now, now: now)
        XCTAssertNil(session)
    }

    func testMetaIsNilForSomethingElse() {
        XCTAssertNil(CodexRollout.meta(inHead: Data("hello".utf8)))
        XCTAssertNil(CodexRollout.meta(inHead: Data()))
    }

    // MARK: 正在做什么

    func testRunningCommandIsTheLastUnansweredCall() {
        let tail = log([
            line("event_msg", ["type": "task_started"], at: now.addingTimeInterval(-600)),
            call("shell", ["command": ["bash", "-lc", "npm test"]], id: "c1"),
        ])
        let s = CodexRollout.summary(inTail: tail)
        XCTAssertEqual(s.lastEvent, .working)
        XCTAssertEqual(s.doing, .running("npm test"))
        XCTAssertEqual(s.turnStartedAt?.timeIntervalSince1970 ?? 0, now.addingTimeInterval(-600).timeIntervalSince1970, accuracy: 0.01)
    }

    func testEscalatedCallWithoutOutputIsWaiting() {
        let tail = log([
            line("event_msg", ["type": "task_started"]),
            call("shell_command", ["command": "git push", "sandbox_permissions": "require_escalated"], id: "c2"),
        ])
        let s = CodexRollout.summary(inTail: tail)
        XCTAssertEqual(s.lastEvent, .waiting)
        XCTAssertEqual(s.doing, .askingToRun("git push"))
        XCTAssertEqual(s.doing?.text, "想执行 git push，等你批准")
    }

    func testEscalatedCallWithOutputIsNoLongerWaiting() {
        let tail = log([
            line("event_msg", ["type": "task_started"]),
            call("exec_command", ["cmd": "git push", "with_escalated_permissions": true], id: "c3"),
            line("response_item", ["type": "function_call_output", "call_id": "c3", "output": "ok"]),
        ])
        let s = CodexRollout.summary(inTail: tail)
        XCTAssertEqual(s.lastEvent, .working)
        XCTAssertEqual(s.doing, .running("git push"))
    }

    func testOldApprovalEventsStillRead() {
        let tail = log([
            line("event_msg", ["type": "task_started"]),
            line("event_msg", ["type": "exec_approval_request", "command": ["git", "push"]]),
        ])
        let s = CodexRollout.summary(inTail: tail)
        XCTAssertEqual(s.lastEvent, .waiting)
        XCTAssertEqual(s.doing, .askingToRun("git push"))
    }

    func testFinishedTurnAndTokens() {
        let end = now.addingTimeInterval(-30)
        let tail = log([
            line("event_msg", ["type": "task_started"], at: now.addingTimeInterval(-300)),
            line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 123_456]]]),
            line("event_msg", ["type": "task_complete"], at: end),
        ])
        let s = CodexRollout.summary(inTail: tail)
        XCTAssertEqual(s.lastEvent, .done)
        XCTAssertEqual(s.doing, .finished)
        XCTAssertEqual(s.totalTokens, 123_456)
        XCTAssertEqual(s.turnEndedAt?.timeIntervalSince1970 ?? 0, end.timeIntervalSince1970, accuracy: 0.01)
    }

    func testReasoningTitleWhenNothingElse() {
        let tail = log([
            line("event_msg", ["type": "task_started"]),
            line("event_msg", ["type": "agent_reasoning", "text": "**Planning the refactor**\n\nmore"]),
        ])
        XCTAssertEqual(CodexRollout.summary(inTail: tail).doing, .thinking("Planning the refactor"))
    }

    func testPatchIsEditing() {
        let tail = log([
            line("event_msg", ["type": "task_started"]),
            line("response_item", ["type": "custom_tool_call", "name": "apply_patch", "input": "*** Begin Patch", "call_id": "p"]),
        ])
        XCTAssertEqual(CodexRollout.summary(inTail: tail).doing, .editing)
    }

    func testCommandTextIsShortAndOneLine() {
        XCTAssertEqual(CodexRollout.commandText(["bash", "-lc", "npm test"]), "npm test")
        XCTAssertEqual(CodexRollout.commandText(["git", "status"]), "git status")
        XCTAssertEqual(CodexRollout.commandText("echo a\necho b"), "echo a")
        XCTAssertNil(CodexRollout.commandText(""))
        XCTAssertNil(CodexRollout.commandText(nil))
        let long = CodexRollout.commandText(String(repeating: "x", count: 100))
        XCTAssertEqual(long?.count, 48)
        XCTAssertTrue(long?.hasSuffix("…") ?? false)
    }

    // MARK: 会话行

    func testIdleSessionsAreNotListed() {
        let tail = CodexTailSummary(lastEvent: .done)
        XCTAssertNil(CodexSession.make(id: "a", meta: nil, tail: tail, modified: now.addingTimeInterval(-3600), now: now))
    }

    func testWorkingSessionShowsTurnTime() {
        let tail = CodexTailSummary(lastEvent: .working, doing: .running("npm test"),
                                    turnStartedAt: now.addingTimeInterval(-23 * 60))
        let s = CodexSession.make(id: "a", meta: CodexSessionMeta(cwd: "/x/bake-cost"), tail: tail, modified: now, now: now)
        XCTAssertEqual(s?.state, .working)
        XCTAssertEqual(s?.project, "bake-cost")
        XCTAssertEqual(s?.elapsedText(now: now), "23 分钟")
    }

    func testDoneSessionSaysJustNowThenMinutesAgo() {
        let tail = CodexTailSummary(lastEvent: .done, turnEndedAt: now.addingTimeInterval(-20))
        let s = CodexSession.make(id: "a", meta: nil, tail: tail, modified: now.addingTimeInterval(-20), now: now)
        XCTAssertEqual(s?.doing, .finished)
        XCTAssertEqual(s?.elapsedText(now: now), "刚刚")
        XCTAssertEqual(s?.elapsedText(now: now.addingTimeInterval(6 * 60)), "6 分钟前")
    }

    func testHoursAreWrittenOut() {
        let s = CodexSession(id: "a", project: nil, state: .working, since: now.addingTimeInterval(-63 * 60), modified: now)
        XCTAssertEqual(s.elapsedText(now: now), "1 小时 3 分")
    }

    func testWaitingSortsFirstAndDecidesTheCard() {
        let list = [
            CodexSession(id: "d", project: "c", state: .done, modified: now),
            CodexSession(id: "w", project: "b", state: .working, modified: now),
            CodexSession(id: "q", project: "a", state: .waiting, modified: now.addingTimeInterval(-100)),
        ]
        XCTAssertEqual(CodexSessionList.sorted(list).map(\.id), ["q", "w", "d"])
        XCTAssertEqual(CodexSessionList.overall(list), .waiting)
        XCTAssertEqual(CodexSessionList.lead(list)?.project, "a")
        XCTAssertEqual(CodexSessionList.overall([]), .idle)
        XCTAssertNil(CodexSessionList.lead([]))
    }

    func testOddNumbersInTheLogDoNotCrash() {
        // "nan"、"inf"、超大的数：读成没有，而不是在 Int(_:) 里崩掉。
        XCTAssertNil(CodexUsageParser.number("nan"))
        XCTAssertNil(CodexUsageParser.number("inf"))
        XCTAssertNil(CodexUsageParser.number("1e400"))
        XCTAssertEqual(CodexUsageParser.number("374.92"), 374.92)
        let tail = log([
            line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["total_tokens": "nan"]]]),
            line("event_msg", ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 1e300]]]),
        ])
        XCTAssertNil(CodexRollout.summary(inTail: tail).totalTokens)
        let t0 = now.addingTimeInterval(-600)
        let data = log([
            line("event_msg", ["type": "task_started"], at: t0),
            line("event_msg", ["type": "task_complete", "duration_ms": "inf"], at: t0.addingTimeInterval(60)),
            line("event_msg", ["type": "task_started"], at: t0.addingTimeInterval(100)),
            line("event_msg", ["type": "task_complete", "duration_ms": 1e300], at: t0.addingTimeInterval(130)),
        ])
        XCTAssertEqual(CodexRollout.activeSeconds(inLog: data) ?? 0, 90, accuracy: 0.01)
    }

    // MARK: 统计

    func testActiveSecondsAddsTurnsAndSkipsTheOpenOne() {
        let t0 = now.addingTimeInterval(-3600)
        let data = log([
            line("session_meta", ["id": "a", "cwd": "/a"], at: t0),
            line("event_msg", ["type": "task_started"], at: t0),
            line("event_msg", ["type": "task_complete"], at: t0.addingTimeInterval(600)),
            line("event_msg", ["type": "task_started"], at: t0.addingTimeInterval(1000)),
            line("event_msg", ["type": "task_complete", "duration_ms": 120_000], at: t0.addingTimeInterval(1200)),
            line("event_msg", ["type": "task_started"], at: t0.addingTimeInterval(2000)),
        ])
        XCTAssertEqual(CodexRollout.activeSeconds(inLog: data) ?? 0, 720, accuracy: 0.01)
    }

    func testActiveSecondsIsNilWithoutTurns() {
        XCTAssertNil(CodexRollout.activeSeconds(inLog: log([line("session_meta", ["id": "a"])])))
    }

    func testBucketsSplitTodayAndWeekAndHideUnknownTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        // 2026-10-22 是周四。
        let thursday = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15))!
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10))!
        let lastSunday = cal.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10))!
        let records = [
            CodexSessionRecord(startedAt: thursday.addingTimeInterval(-3600), activeSeconds: 600, tokens: 1000),
            CodexSessionRecord(startedAt: monday, activeSeconds: 1200, tokens: 2000),
            CodexSessionRecord(startedAt: lastSunday, activeSeconds: 99, tokens: 99),
        ]
        let b = CodexStats.buckets(records, now: thursday, calendar: cal)
        XCTAssertEqual(b.today, CodexStatBucket(sessions: 1, seconds: 600, tokens: 1000))
        XCTAssertEqual(b.week, CodexStatBucket(sessions: 2, seconds: 1800, tokens: 3000))

        let unknown = records + [CodexSessionRecord(startedAt: thursday.addingTimeInterval(-60), activeSeconds: nil, tokens: nil)]
        let c = CodexStats.buckets(unknown, now: thursday, calendar: cal)
        XCTAssertEqual(c.today.sessions, 2)
        XCTAssertNil(c.today.seconds, "有一个会话读不出时长，就不报时长")
        XCTAssertEqual(c.today.tokens, 1000)

        let empty = CodexStats.buckets([], now: thursday, calendar: cal)
        XCTAssertEqual(empty.today, CodexStatBucket(sessions: 0, seconds: 0, tokens: nil))
    }

    func testWeekStartsOnMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        cal.firstWeekday = 1
        let sunday = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
        let start = CodexStats.weekStart(now: sunday, calendar: cal)
        let parts = cal.dateComponents([.month, .day, .hour], from: start)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 19)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(CodexStats.weekFolders(now: sunday, calendar: cal).count, 7)
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9))!
        XCTAssertEqual(CodexStats.weekFolders(now: monday, calendar: cal), ["2026/10/19"])
    }

    func testServerTokensTodayAndWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        let daily = [CodexDailyTokens(day: "2026-10-18", tokens: 50),
                     CodexDailyTokens(day: "2026-10-19", tokens: 10),
                     CodexDailyTokens(day: "2026-10-20", tokens: 20),
                     CodexDailyTokens(day: "2026-10-21", tokens: 30)]
        let t = CodexStats.serverTokens(daily, now: wednesday, calendar: cal)
        XCTAssertEqual(t?.today, 30)
        XCTAssertEqual(t?.week, 60)
        XCTAssertNil(CodexStats.serverTokens([], now: wednesday, calendar: cal))
    }

    func testTokenParts() {
        XCTAssertEqual(CodexStats.tokenParts(12_400_000, english: false).number, "1,240")
        XCTAssertEqual(CodexStats.tokenParts(12_400_000, english: false).unit, "万 tokens")
        XCTAssertEqual(CodexStats.tokenParts(820, english: false).unit, "tokens")
        XCTAssertEqual(CodexStats.tokenParts(250_000_000, english: false).unit, "亿 tokens")
        XCTAssertEqual(CodexStats.tokenParts(12_400_000, english: true).number, "12M")
    }

    func testDurationText() {
        XCTAssertEqual(CodexStats.durationText(2 * 3600 + 35 * 60), "2 小时 35 分")
        XCTAssertEqual(CodexStats.durationText(14 * 3600 + 5 * 60), "14 小时")
        XCTAssertEqual(CodexStats.durationText(18 * 60), "18 分钟")
    }

    // MARK: 去终端

    func testTerminalTarget() {
        XCTAssertEqual(CodexTerminal.host(originator: "codex_cli_rs"), .terminal)
        XCTAssertEqual(CodexTerminal.host(originator: "codex_vscode"), .editor)
        XCTAssertEqual(CodexTerminal.host(originator: nil), .terminal)
        XCTAssertEqual(CodexTerminal.target(host: .terminal, running: ["com.googlecode.iterm2", "com.apple.Terminal"]),
                       "com.googlecode.iterm2")
        XCTAssertEqual(CodexTerminal.target(host: .terminal, running: []), "com.apple.Terminal")
        XCTAssertEqual(CodexTerminal.target(host: .editor, running: ["com.microsoft.VSCode", "com.apple.Terminal"]),
                       "com.microsoft.VSCode")
        XCTAssertEqual(CodexTerminal.target(host: .editor, running: ["com.apple.Terminal"]), "com.apple.Terminal")
    }

    // MARK: 卡片

    func testCardLayoutAndPanda() {
        XCTAssertFalse(CodexCard.isMedium(WidgetConfig()))
        XCTAssertFalse(CodexCard.isMedium(WidgetCatalog.make(.aiUsage)!.config))
        XCTAssertTrue(CodexCard.isMedium(WidgetConfig(["layout": .string("medium")])))
        XCTAssertEqual(CodexCard.pandaImage(.waiting), "pet-panda-hungry")
        XCTAssertEqual(CodexCard.pandaImage(.idle), "pet-panda-rest")
        let small = WidgetCatalog.make(.aiUsage)!
        let medium = WidgetCatalog.make(.aiUsage, overrides: ["layout": .string("medium")])!
        XCTAssertGreaterThan(WidgetCatalog.naturalSize(medium).width, WidgetCatalog.naturalSize(small).width)
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: medium.config, kind: .aiUsage), "精版")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: small.config, kind: .aiUsage), "简版")
    }

    func testLiquidLookOnlyOnTheSmallCardAndSoundKeysStayOutOfTheList() {
        XCTAssertTrue(WidgetCatalog.applies("look", to: WidgetConfig(), kind: .aiUsage))
        XCTAssertFalse(WidgetCatalog.applies("look", to: WidgetConfig(["layout": .string("medium")]), kind: .aiUsage))
        for key in ["soundWaiting", "soundDone", "soundQuota", "tone"] {
            XCTAssertFalse(WidgetCatalog.applies(key, to: WidgetConfig(), kind: .aiUsage), key)
        }
    }

    func testCardLabelsAndShortReset() {
        let week = CodexLimitWindow(id: "secondary", label: "每周额度", usedFraction: 0.6, duration: 604_800)
        let five = CodexLimitWindow(id: "primary", label: "5 小时额度", usedFraction: 0.3, duration: 18_000)
        XCTAssertEqual(CodexCard.label(week), "本周")
        XCTAssertEqual(CodexCard.label(five), "5 小时")
        XCTAssertEqual(CodexCard.resetShort(2 * 3600 + 14 * 60), "2:14")
        XCTAssertEqual(CodexCard.resetShort(46 * 3600 + 5 * 60), "1天22时")
        XCTAssertEqual(CodexCard.resetShort(-5), "0:00")
    }
}
