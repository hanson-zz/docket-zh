import XCTest
@testable import Docket

final class ClaudeUsageTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 凭据

    func testAccessTokenFromCredentials() throws {
        let expires = Int((t0.timeIntervalSince1970 + 3600) * 1000)
        let json = #"{"claudeAiOauth":{"accessToken":" tok-123 ","refreshToken":"r","expiresAt":\#(expires),"scopes":["user:inference"]}}"#
        XCTAssertEqual(try ClaudeCredentials.accessToken(from: json, now: t0), "tok-123")
    }

    func testExpiredTokenIsUnknown() {
        let expires = Int((t0.timeIntervalSince1970 - 10) * 1000)
        let json = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":\#(expires)}}"#
        XCTAssertThrowsError(try ClaudeCredentials.accessToken(from: json, now: t0)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .expired)
        }
        // 只剩不到一分钟也当过期，免得请求发出去时正好失效。
        let soon = Int((t0.timeIntervalSince1970 + 30) * 1000)
        XCTAssertThrowsError(try ClaudeCredentials.accessToken(
            from: #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":\#(soon)}}"#, now: t0))
    }

    func testMissingExpiryIsLeftToTheServer() throws {
        XCTAssertEqual(try ClaudeCredentials.accessToken(from: #"{"claudeAiOauth":{"accessToken":"tok"}}"#, now: t0), "tok")
    }

    func testNoCredentialsIsNotSignedIn() {
        for text in ["", "{}", #"{"claudeAiOauth":{}}"#, #"{"claudeAiOauth":{"accessToken":"  "}}"#, "not json"] {
            XCTAssertThrowsError(try ClaudeCredentials.accessToken(from: text, now: t0)) {
                XCTAssertEqual($0 as? ClaudeUsageError, .notSignedIn)
            }
        }
    }

    func testKeychainServiceName() {
        XCTAssertEqual(ClaudeCredentials.keychainService, "Claude" + " " + "Code-credentials")
    }

    // MARK: 用量接口

    func testParsesWindows() throws {
        let json = """
        {"five_hour":{"utilization":37.0,"resets_at":"2026-11-19T15:00:00.123456+00:00"},
         "seven_day":{"utilization":82,"resets_at":"2026-11-23T08:00:00Z"},
         "seven_day_opus":{"utilization":null,"resets_at":null}}
        """
        let report = try ClaudeUsageParser.report(from: Data(json.utf8), now: t0)
        XCTAssertEqual(report.fetchedAt, t0)
        let primary = try XCTUnwrap(report.primary)
        XCTAssertEqual(primary.usedFraction, 0.37, accuracy: 1e-9)
        XCTAssertEqual(primary.duration, 5 * 3600)
        XCTAssertEqual(primary.resetsAt?.timeIntervalSince1970 ?? 0,
                       ISO8601DateFormatter().date(from: "2026-11-19T15:00:00Z")!.timeIntervalSince1970 + 0.123,
                       accuracy: 0.001)
        let weekly = try XCTUnwrap(report.weekly)
        XCTAssertEqual(weekly.usedFraction, 0.82, accuracy: 1e-9)
        XCTAssertEqual(weekly.duration, 7 * 86_400)
        XCTAssertEqual(weekly.resetsAt, ISO8601DateFormatter().date(from: "2026-11-23T08:00:00Z"))
        XCTAssertTrue(report.extras.isEmpty)

        // 水位：剩余，取更紧的每周窗口。
        let now = ISO8601DateFormatter().date(from: "2026-11-19T12:00:00Z")!
        var fresh = report
        fresh.fetchedAt = now
        let q = LiveIconUsage.quota(fresh, now: now)
        XCTAssertEqual(q?.window, .weekly)
        XCTAssertEqual(q?.remaining ?? -1, 0.18, accuracy: 1e-9)
    }

    func testNullUtilizationSkipsOnlyThatWindow() throws {
        let json = #"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":{"utilization":10.5,"resets_at":"2026-11-23T08:00:00.5Z"},"seven_day_opus":{"utilization":4,"resets_at":null}}"#
        let windows = try ClaudeUsageParser.windows(from: Data(json.utf8))
        XCTAssertEqual(windows.map(\.id), ["secondary", "opus"])
        XCTAssertEqual(windows.last?.group, "Opus")
        XCTAssertNotNil(windows.first?.resetsAt)
    }

    func testUnreadableAndEmpty() {
        XCTAssertThrowsError(try ClaudeUsageParser.windows(from: Data("[]".utf8))) {
            XCTAssertEqual($0 as? ClaudeUsageError, .unreadable)
        }
        XCTAssertThrowsError(try ClaudeUsageParser.windows(from: Data(#"{"five_hour":null}"#.utf8))) {
            XCTAssertEqual($0 as? ClaudeUsageError, .nothingMetered)
        }
    }

    func testDates() {
        XCTAssertNotNil(ClaudeUsageParser.date("2026-11-19T15:00:00+00:00"))
        XCTAssertNotNil(ClaudeUsageParser.date("2026-11-19T15:00:00.123Z"))
        XCTAssertEqual(ClaudeUsageParser.date("2026-11-19T15:00:00.999999+08:00")?.timeIntervalSince1970 ?? 0,
                       ISO8601DateFormatter().date(from: "2026-11-19T07:00:00Z")!.timeIntervalSince1970 + 0.999,
                       accuracy: 0.001)
        XCTAssertNil(ClaudeUsageParser.date(""))
        XCTAssertNil(ClaudeUsageParser.date("tomorrow"))
    }
}
