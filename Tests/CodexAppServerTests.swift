import Foundation
import XCTest
@testable import Docket

// The app-server half of the Codex usage widget: the messages Docket writes
// to `codex app-server` and how it reads the replies. Every payload is a
// hand-written sample in the protocol's shape, never a real account's.

final class CodexAppServerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: Building

    func testInitializeCarriesClientInfoAndEndsTheLine() {
        let data = CodexAppServer.initializeRequest(version: "0.5.3")
        XCTAssertEqual(data.last, UInt8(ascii: "\n"))
        XCTAssertEqual(data.filter { $0 == UInt8(ascii: "\n") }.count, 1)
        let root = object(data)
        XCTAssertEqual(root["method"] as? String, "initialize")
        XCTAssertEqual(root["id"] as? Int, CodexAppServer.initializeID)
        XCTAssertNil(root["jsonrpc"], "the app-server neither sends nor expects the jsonrpc field")
        let info = (root["params"] as? [String: Any])?["clientInfo"] as? [String: Any]
        XCTAssertEqual(info?["name"] as? String, "docket")
        XCTAssertEqual(info?["version"] as? String, "0.5.3")
    }

    func testInitializedIsANotificationWithoutParams() {
        let root = object(CodexAppServer.initializedNotification())
        XCTAssertEqual(root["method"] as? String, "initialized")
        XCTAssertNil(root["id"])
        XCTAssertNil(root["params"])
    }

    func testRateLimitsRequestUsesTheProtocolMethodName() {
        let root = object(CodexAppServer.rateLimitsRequest())
        XCTAssertEqual(root["method"] as? String, "account/rateLimits/read")
        XCTAssertEqual(root["id"] as? Int, CodexAppServer.rateLimitsID)
        XCTAssertNil(root["params"])
    }

    // MARK: Parsing lines

    func testResponsesErrorsAndNoiseAreToldApart() {
        if case .response(let id, let result) = CodexAppServer.parse(line: Data(#"{"id":1,"result":{"userAgent":"codex/1"}}"#.utf8)) {
            XCTAssertEqual(id, 1)
            XCTAssertEqual(object(result)["userAgent"] as? String, "codex/1")
        } else {
            XCTFail("expected a response")
        }
        XCTAssertEqual(CodexAppServer.parse(line: Data(#"{"id":2,"error":{"code":-32600,"message":"Not initialized"}}"#.utf8)),
                       .error(id: 2, code: -32600, message: "Not initialized"))
        XCTAssertEqual(CodexAppServer.parse(line: Data(#"{"method":"account/updated","params":{}}"#.utf8)), .other)
        XCTAssertEqual(CodexAppServer.parse(line: Data(#"{"id":7,"method":"item/tool/requestUserInput","params":{}}"#.utf8)), .other)
        XCTAssertEqual(CodexAppServer.parse(line: Data("WARN something happened".utf8)), .other)
    }

    func testLinesAreSplitAndTheUnfinishedTailKept() {
        var buffer = Data("{\"id\":1,\"result\":{}}\n\n{\"id\":2,".utf8)
        let lines = CodexAppServer.takeLines(&buffer)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "{\"id\":2,")
        buffer.append(Data("\"result\":{}}\n".utf8))
        XCTAssertEqual(CodexAppServer.takeLines(&buffer).count, 1)
        XCTAssertTrue(buffer.isEmpty)
    }

    // MARK: Mapping the response

    private let sample = Data("""
    {"ordinaryUsageAllowed":true,
     "rateLimits":{"limitId":"codex","limitName":null,
       "primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1800003600},
       "secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1800400000},
       "credits":{"hasCredits":false,"unlimited":false,"balance":null},
       "planType":"plus","rateLimitReachedType":null},
     "rateLimitsByLimitId":{
       "codex":{"limitId":"codex","primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1800003600}},
       "codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark",
         "primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":1800003600},"secondary":null}},
     "rateLimitResetCredits":{"availableCount":2,"credits":null},
     "accountId":null}
    """.utf8)

    func testMainWindowsAreReadInMinutesAndSeconds() throws {
        let report = try CodexAppServer.report(fromResult: sample, now: now, includeExtras: false)
        XCTAssertEqual(report.source, .appServer)
        XCTAssertEqual(report.windows.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(report.primary?.usedFraction ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(report.primary?.duration, 18000)
        XCTAssertEqual(report.primary?.label, "5 小时额度")
        XCTAssertEqual(report.primary?.resetsAt, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(report.weekly?.label, "每周额度")
        XCTAssertEqual(report.plan, "plus")
        XCTAssertEqual(report.resetCredits, 2)
        XCTAssertEqual(report.fetchedAt, now)
    }

    func testOtherLimitBucketsBecomeExtrasWithoutRepeatingTheMainOne() throws {
        let report = try CodexAppServer.report(fromResult: sample, now: now, includeExtras: true)
        XCTAssertEqual(report.windows.map(\.id), ["primary", "secondary", "codex_bengalfox"])
        XCTAssertEqual(report.extras.first?.group, "Spark")
        XCTAssertEqual(report.extras.first?.usedFraction ?? 0, 0.05, accuracy: 0.0001)
        XCTAssertEqual(report.ringWindows.map(\.id), ["primary", "secondary"])
    }

    func testANullWindowIsSkippedNotFatal() throws {
        let data = Data("""
        {"rateLimits":{"primary":null,"secondary":{"usedPercent":70,"windowDurationMins":10080,"resetsAt":null}}}
        """.utf8)
        let report = try CodexAppServer.report(fromResult: data, now: now)
        XCTAssertEqual(report.windows.map(\.id), ["secondary"])
        XCTAssertNil(report.weekly?.resetsAt)
        XCTAssertNil(report.plan)
        XCTAssertNil(report.resetCredits)
    }

    func testASpendCapStandsInWhenThereAreNoWindows() throws {
        let data = Data("""
        {"rateLimits":{"primary":null,"secondary":null,"planType":"business",
          "individualLimit":{"limit":"100","used":"25","remainingPercent":75,"resetsAt":1800100000}}}
        """.utf8)
        let report = try CodexAppServer.report(fromResult: data, now: now)
        XCTAssertEqual(report.primary?.id, "credits")
        XCTAssertEqual(report.primary?.usedFraction ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(report.primary?.resetsAt, Date(timeIntervalSince1970: 1_800_100_000))
    }

    func testNothingMeteredAndGarbageThrow() {
        XCTAssertThrowsError(try CodexAppServer.report(fromResult: Data(#"{"rateLimits":{"primary":null}}"#.utf8))) {
            XCTAssertEqual($0 as? CodexUsageError, .nothingMetered)
        }
        XCTAssertThrowsError(try CodexAppServer.report(fromResult: Data("null".utf8))) {
            XCTAssertEqual($0 as? CodexUsageError, .unreadable)
        }
    }

    // MARK: Source and cache

    func testACacheWrittenBeforeTheSourceFieldStillDecodes() throws {
        let old = Data(#"{"windows":[],"daily":[],"fetchedAt":0}"#.utf8)
        let report = try JSONDecoder().decode(CodexUsageReport.self, from: old)
        XCTAssertNil(report.source)
        var fresh = report
        fresh.source = .web
        let round = try JSONDecoder().decode(CodexUsageReport.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(round.source, .web)
        XCTAssertEqual(CodexUsageSource.appServer.title, "官方接口")
        XCTAssertEqual(CodexUsageSource.web.title, "备用接口")
    }

    // MARK: Finding and launching the binary

    func testCandidatesPutOverrideAndShellPathFirstAndDropRepeats() {
        let paths = CodexAppServer.candidatePaths(home: "/Users/u", shellPath: "/opt/homebrew/bin:/Users/u/.nvm/versions/node/v22/bin",
                                                  override: "/custom/codex")
        XCTAssertEqual(paths.first, "/custom/codex")
        XCTAssertEqual(paths[1], "/opt/homebrew/bin/codex")
        XCTAssertEqual(paths[2], "/Users/u/.nvm/versions/node/v22/bin/codex")
        XCTAssertEqual(paths.filter { $0 == "/opt/homebrew/bin/codex" }.count, 1)
        XCTAssertTrue(paths.contains("/Users/u/.npm-global/bin/codex"))
        XCTAssertTrue(paths.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        XCTAssertTrue(paths.contains("/Applications/Codex.app/Contents/Resources/codex"))
    }

    func testChildPathStartsWithTheBinaryFolderSoEnvCanFindNode() {
        let path = CodexAppServer.childPath(binary: "/Users/u/.nvm/versions/node/v22/bin/codex",
                                            shellPath: nil, inherited: "/usr/bin:/bin")
        let dirs = path.split(separator: ":").map(String.init)
        XCTAssertEqual(dirs.first, "/Users/u/.nvm/versions/node/v22/bin")
        XCTAssertTrue(dirs.contains("/opt/homebrew/bin"))
        XCTAssertEqual(dirs.filter { $0 == "/usr/bin" }.count, 1)
    }

    func testProxyIsPassedToTheChild() {
        XCTAssertEqual(CodexAppServer.proxyEnvironment(nil), [:])
        let http = CodexAppServer.proxyEnvironment(CodexProxy.parse("127.0.0.1:7890"))
        XCTAssertEqual(http["HTTPS_PROXY"], "http://127.0.0.1:7890")
        XCTAssertEqual(http["ALL_PROXY"], "http://127.0.0.1:7890")
        let socks = CodexAppServer.proxyEnvironment(CodexProxy.parse("socks5://localhost:1080"))
        XCTAssertEqual(socks["ALL_PROXY"], "socks5h://localhost:1080")
        XCTAssertNil(socks["HTTPS_PROXY"])
    }
}
