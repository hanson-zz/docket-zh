import Foundation
import XCTest
@testable import Docket

// The Codex usage widget's parsing and arithmetic. Every payload here is a
// hand-written sample in the shape the backend sends, never a real account's.

final class CodexUsageParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testMainPairIsReadAndLabelledByLength() throws {
        let data = json("""
        {"plan_type":"plus","rate_limit":{
          "primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_after_seconds":3600},
          "secondary_window":{"used_percent":"12.5","limit_window_seconds":604800,"reset_at":1800100000}}}
        """)
        let windows = try CodexUsageParser.windows(from: data, now: now)
        XCTAssertEqual(windows.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(windows[0].label, "5 小时额度")
        XCTAssertEqual(windows[0].usedFraction, 0.42, accuracy: 0.0001)
        XCTAssertEqual(windows[0].resetsAt, now.addingTimeInterval(3600))
        XCTAssertEqual(windows[1].label, "每周额度")
        XCTAssertEqual(windows[1].usedFraction, 0.125, accuracy: 0.0001)
        XCTAssertEqual(windows[1].resetsAt, Date(timeIntervalSince1970: 1_800_100_000))
        XCTAssertEqual(CodexUsageParser.plan(from: data), "plus")
    }

    func testABadWindowDoesNotTakeItsSiblingWithIt() throws {
        let data = json("""
        {"rate_limit":{"primary_window":{"used_percent":null},
          "secondary_window":{"used_percent":30,"limit_window_seconds":604800}}}
        """)
        let windows = try CodexUsageParser.windows(from: data, now: now)
        XCTAssertEqual(windows.map(\.id), ["secondary"])
    }

    func testExtrasComeAfterTheMainPairAndAreNotDuplicated() throws {
        let spark = #"{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000}}}"#
        let data = json("""
        {"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000}},
         "additional_rate_limits":[\(spark),\(spark),{"limit_name":"other","rate_limit":{}}],
         "code_review_rate_limit":{"secondary_window":{"used_percent":50,"limit_window_seconds":604800}}}
        """)
        let windows = try CodexUsageParser.windows(from: data, now: now)
        XCTAssertEqual(windows.map(\.id), ["primary", "spark", "code-review-secondary"])
        XCTAssertEqual(windows[2].group, "代码审查")
        let report = CodexUsageReport(windows: windows, fetchedAt: now)
        XCTAssertEqual(report.primary?.id, "primary")
        XCTAssertNil(report.weekly)
        XCTAssertEqual(report.extras.count, 2)

        let plain = try CodexUsageParser.windows(from: data, now: now, includeExtras: false)
        XCTAssertEqual(plain.map(\.id), ["primary"])
    }

    func testACreditSeatShowsItsCap() throws {
        let data = json(#"{"spend_control":{"individual_limit":{"limit":"400","used":"100","used_percent":25}}}"#)
        let windows = try CodexUsageParser.windows(from: data, now: now)
        XCTAssertEqual(windows.first?.id, "credits")
        XCTAssertEqual(CodexUsageReport(windows: windows, fetchedAt: now).primary?.usedFraction, 0.25)
    }

    func testNothingMeteredAndGarbageAreErrors() {
        XCTAssertThrowsError(try CodexUsageParser.windows(from: json("{}"))) {
            XCTAssertEqual($0 as? CodexUsageError, .nothingMetered)
        }
        XCTAssertThrowsError(try CodexUsageParser.windows(from: json("<html>"))) {
            XCTAssertEqual($0 as? CodexUsageError, .unreadable)
        }
    }

    func testLabels() {
        XCTAssertEqual(CodexUsageParser.label(windowSeconds: 0, fallback: "primary"), "当前会话")
        XCTAssertEqual(CodexUsageParser.label(windowSeconds: 0, fallback: "secondary"), "较长窗口")
        XCTAssertEqual(CodexUsageParser.label(windowSeconds: 1800, fallback: "primary"), "30 分钟额度")
        XCTAssertEqual(CodexUsageParser.label(windowSeconds: 30 * 86400, fallback: "primary"), "每月额度")
        XCTAssertEqual(CodexUsageParser.label(windowSeconds: 3 * 86400, fallback: "primary"), "3 天额度")
        XCTAssertEqual(CodexLimitWindow(id: "a", label: "每周额度", usedFraction: 0).shortLabel, "周")
        XCTAssertEqual(CodexLimitWindow(id: "a", label: "5 小时额度", usedFraction: 0).shortLabel, "5 小时")
        XCTAssertEqual(CodexUsageParser.planTitle("pro"), "Pro")
        XCTAssertNil(CodexUsageParser.planTitle(""))
    }

    func testDailyBucketsAndResetCredits() {
        let profile = json(#"{"stats":{"daily_usage_buckets":[{"start_date":"2026-10-12","tokens":900},{"start_date":"2026-10-11T00:00:00Z","tokens":100}]}}"#)
        let daily = CodexUsageParser.daily(from: profile)
        XCTAssertEqual(daily, [CodexDailyTokens(day: "2026-10-11", tokens: 100),
                               CodexDailyTokens(day: "2026-10-12", tokens: 900)])
        XCTAssertEqual(CodexUsageParser.resetCredits(from: json(#"{"available_count":2,"credits":[]}"#)), 2)
        XCTAssertEqual(CodexUsageParser.resetCredits(from: json(#"{"credits":[{"status":"available"},{"status":"used"}]}"#)), 1)
    }

    func testReportRoundTripsForTheOfflineCache() throws {
        let report = CodexUsageReport(windows: [CodexLimitWindow(id: "primary", label: "5 小时额度", usedFraction: 0.3,
                                                                 resetsAt: now, duration: 18000)],
                                      plan: "plus", resetCredits: 1,
                                      daily: [CodexDailyTokens(day: "2026-10-12", tokens: 5)], fetchedAt: now)
        let back = try JSONDecoder().decode(CodexUsageReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(back, report)
        XCTAssertFalse(report.isStale(now: now.addingTimeInterval(60)))
        XCTAssertTrue(report.isStale(now: now.addingTimeInterval(3600)))
    }
}

final class CodexAuthTests: XCTestCase {
    private func jwt(_ claims: String) -> String {
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).sig"
    }

    func testReadsTokenAccountEmailAndPlan() throws {
        let access = jwt(#"{"exp":1900000000}"#)
        let id = jwt(#"{"email":"me@example.com","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#)
        let data = Data(#"{"tokens":{"access_token":"\#(access)","account_id":"acc-1","id_token":"\#(id)"}}"#.utf8)
        let c = try CodexAuth.credential(from: data, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(c.accountID, "acc-1")
        XCTAssertEqual(c.email, "me@example.com")
        XCTAssertEqual(c.plan, "plus")
    }

    func testExpiredAndMissing() {
        let access = jwt(#"{"exp":100}"#)
        let data = Data(#"{"tokens":{"access_token":"\#(access)","account_id":"acc"}}"#.utf8)
        XCTAssertThrowsError(try CodexAuth.credential(from: data)) { XCTAssertEqual($0 as? CodexUsageError, .expired) }
        // An API-key sign-in has no ChatGPT tokens, so there are no limits to read.
        XCTAssertThrowsError(try CodexAuth.credential(from: Data(#"{"OPENAI_API_KEY":"sk-x"}"#.utf8))) {
            XCTAssertEqual($0 as? CodexUsageError, .notSignedIn)
        }
    }

    func testAccountFallsBackToTheTokensOwnClaim() throws {
        let access = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"from-claim"}}"#)
        let data = Data(#"{"tokens":{"access_token":"\#(access)"}}"#.utf8)
        XCTAssertEqual(try CodexAuth.credential(from: data).accountID, "from-claim")
    }
}

final class CodexActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func log(_ events: [(String, String)]) -> Data {
        Data(events.map { #"{"type":"\#($0.0)","payload":{"type":"\#($0.1)"}}"# }.joined(separator: "\n").utf8)
    }

    func testNewestLifecycleEventWins() {
        XCTAssertEqual(CodexRollout.lastEvent(inTail: log([("event_msg", "task_started"), ("response_item", "message")])), .working)
        XCTAssertEqual(CodexRollout.lastEvent(inTail: log([("event_msg", "task_started"), ("event_msg", "task_complete")])), .done)
        XCTAssertEqual(CodexRollout.lastEvent(inTail: log([("event_msg", "task_started"), ("event_msg", "exec_approval_request")])), .waiting)
        XCTAssertEqual(CodexRollout.lastEvent(inTail: log([("event_msg", "exec_approval_request"), ("event_msg", "exec_command_begin")])), .working)
        XCTAssertEqual(CodexRollout.lastEvent(inTail: log([("event_msg", "task_started"), ("event_msg", "turn_aborted")])), .idle)
        XCTAssertNil(CodexRollout.lastEvent(inTail: log([("event_msg", "item_completed")])))
        // A half line at the start of the tail is skipped, not fatal.
        var cut = Data(#"ad":{"type":"x"}}"#.utf8)
        cut.append(Data("\n".utf8))
        cut.append(log([("event_msg", "task_complete")]))
        XCTAssertEqual(CodexRollout.lastEvent(inTail: cut), .done)
    }

    func testStateAgesOut() {
        func s(_ e: CodexActivity?, _ ago: TimeInterval) -> CodexActivity {
            CodexRollout.state(lastEvent: e, modified: now.addingTimeInterval(-ago), now: now)
        }
        XCTAssertEqual(s(.working, 60), .working)
        XCTAssertEqual(s(.working, 3600), .idle)
        XCTAssertEqual(s(.done, 60), .done)
        XCTAssertEqual(s(.done, 1200), .idle)
        XCTAssertEqual(s(.waiting, 1800), .waiting)
        XCTAssertEqual(s(nil, 2), .working)
        XCTAssertEqual(s(nil, 60), .idle)
        XCTAssertEqual(CodexRollout.state(lastEvent: .working, modified: nil, now: now), .idle)
    }

    func testDayFolders() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 1))!
        XCTAssertEqual(CodexRollout.dayFolders(now: d, calendar: cal), ["2026/10/01", "2026/09/30"])
    }
}

final class CodexPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRunsOutBeforeTheResetAtThisRate() {
        // Half the 5 hours gone, 80% used: out in 37.5 minutes.
        let w = CodexLimitWindow(id: "primary", label: "", usedFraction: 0.8,
                                 resetsAt: now.addingTimeInterval(9000), duration: 18000)
        XCTAssertEqual(CodexPace.elapsedFraction(w, now: now)!, 0.5, accuracy: 0.001)
        XCTAssertEqual(CodexPace.runsOutAt(w, now: now)!.timeIntervalSince(now), 2250, accuracy: 1)
        XCTAssertEqual(CodexPace.delta(w, now: now)!, 0.3, accuracy: 0.001)
    }

    func testLastsWhenUnderPaceOrTooEarlyToTell() {
        let slow = CodexLimitWindow(id: "p", label: "", usedFraction: 0.2,
                                    resetsAt: now.addingTimeInterval(9000), duration: 18000)
        XCTAssertNil(CodexPace.runsOutAt(slow, now: now))
        let early = CodexLimitWindow(id: "p", label: "", usedFraction: 0.1,
                                     resetsAt: now.addingTimeInterval(17_900), duration: 18000)
        XCTAssertNil(CodexPace.runsOutAt(early, now: now))
        let unknown = CodexLimitWindow(id: "p", label: "", usedFraction: 0.9)
        XCTAssertNil(CodexPace.runsOutAt(unknown, now: now))
        XCTAssertNil(CodexPace.elapsedFraction(unknown, now: now))
    }

    func testFormatting() {
        XCTAssertEqual(CodexPace.duration(30), "不到 1 分钟")
        XCTAssertEqual(CodexPace.duration(45 * 60), "45 分钟")
        XCTAssertEqual(CodexPace.duration(2 * 3600 + 14 * 60), "2 小时 14 分")
        XCTAssertEqual(CodexPace.duration(3 * 86400 + 4 * 3600), "3 天 4 小时")
        XCTAssertEqual(CodexPace.compact(2 * 3600 + 5 * 60), "2:05")
        XCTAssertEqual(CodexPace.compact(50 * 3600), "2 天")
        XCTAssertEqual(CodexPace.tokens(512), "512")
        XCTAssertEqual(CodexPace.tokens(1_234), "1.2k")
        XCTAssertEqual(CodexPace.tokens(38_000), "38k")
        XCTAssertEqual(CodexPace.tokens(2_500_000), "2.5M")
    }

    func testSeriesIsGaplessAndEndsToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!
        let s = CodexPace.series([CodexDailyTokens(day: "2026-10-12", tokens: 7),
                                  CodexDailyTokens(day: "2026-10-10", tokens: 3)],
                                 days: 4, now: today, calendar: cal)
        XCTAssertEqual(s, [0, 3, 0, 7])
    }
}

final class CodexAlertTests: XCTestCase {
    func testOnlyARiseWarns() {
        let t = CodexAlert.thresholds(first: 80)
        XCTAssertEqual(t, [0.8, 0.95, 1.0])
        XCTAssertNil(CodexAlert.crossed(previous: nil, current: 0.9, thresholds: t))
        XCTAssertEqual(CodexAlert.crossed(previous: 0.7, current: 0.82, thresholds: t), 0.8)
        XCTAssertEqual(CodexAlert.crossed(previous: 0.7, current: 0.97, thresholds: t), 0.95)
        XCTAssertNil(CodexAlert.crossed(previous: 0.85, current: 0.9, thresholds: t))
        XCTAssertNil(CodexAlert.crossed(previous: 0.9, current: 0.1, thresholds: t))
        XCTAssertEqual(CodexAlert.thresholds(first: 99), [0.95, 1.0])
        XCTAssertEqual(CodexAlert.thresholds(first: 10), [0.5, 0.95, 1.0])
    }

    func testBackoffDoublesHonoursRetryAfterAndCaps() {
        XCTAssertEqual(CodexBackoff.delay(failures: 0), 0)
        XCTAssertEqual(CodexBackoff.delay(failures: 1), 60)
        XCTAssertEqual(CodexBackoff.delay(failures: 3), 240)
        XCTAssertEqual(CodexBackoff.delay(failures: 20), 1800)
        XCTAssertEqual(CodexBackoff.delay(failures: 1, retryAfter: 600), 600)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CodexBackoff.retryAfter("120", now: now), 120)
        XCTAssertNil(CodexBackoff.retryAfter("soon", now: now))
        XCTAssertNil(CodexBackoff.retryAfter(nil, now: now))
    }

    func testProxyParsing() {
        XCTAssertEqual(CodexProxy.parse("127.0.0.1:7890"), CodexProxy(kind: .http, host: "127.0.0.1", port: 7890))
        XCTAssertEqual(CodexProxy.parse(" http://127.0.0.1:7890/ "), CodexProxy(kind: .http, host: "127.0.0.1", port: 7890))
        XCTAssertEqual(CodexProxy.parse("socks5://localhost:1080"), CodexProxy(kind: .socks, host: "localhost", port: 1080))
        XCTAssertEqual(CodexProxy.parse("socks5://localhost:1080")?.display, "socks5://localhost:1080")
        XCTAssertNil(CodexProxy.parse(""))
        XCTAssertNil(CodexProxy.parse("127.0.0.1"))
        XCTAssertNil(CodexProxy.parse("ftp://a:1"))
        XCTAssertNil(CodexProxy.parse("host:99999"))
    }
}

final class CodexWidgetTests: XCTestCase {
    func testTheWidgetIsPlaceableAndShowsOnCodexActivity() {
        let widget = WidgetCatalog.make(.aiUsage)!
        XCTAssertEqual(WidgetCatalog.entry(.aiUsage)?.name, "Codex 用量")
        XCTAssertTrue(WidgetVisibility.supportsCondition(.aiUsage))
        var conditional = widget
        conditional.config.set(WidgetVisibility.modeKey, .string("conditional"))
        XCTAssertFalse(WidgetVisibility.isVisible(conditional, WidgetConditions(codexActive: false)))
        XCTAssertTrue(WidgetVisibility.isVisible(conditional, WidgetConditions(codexActive: true)))
        // Unknown stays visible.
        XCTAssertTrue(WidgetVisibility.isVisible(conditional, .unknown))
        XCTAssertNotNil(WidgetVisibility.conditionTitle(.aiUsage, config: widget.config))
    }
}
