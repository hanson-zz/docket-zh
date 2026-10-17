import Foundation
import XCTest

/// 关于页里的许可文字和仓库里的文件保持一致，更新源的配置读错时退回原来的仓库。
final class LicensingTests: XCTestCase {

    /// 仓库根目录：Tests/ 的上一层。
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testUpstreamMITMatchesLicenseFile() throws {
        XCTAssertEqual(Licensing.upstreamMIT, try read("LICENSE"),
                       "LICENSE 改了，Sources/Core/Licensing.swift 的 upstreamMIT 也要一起改。")
        XCTAssertTrue(Licensing.upstreamMIT.contains("Copyright (c) 2026 Naman Parashar"))
    }

    func testEULAMatchesFile() throws {
        XCTAssertEqual(Licensing.eula, try read("EULA.md"),
                       "EULA.md 改了，Sources/Core/Licensing.swift 的 eula 也要一起改。")
    }

    func testOriginalAuthorComesFirst() {
        XCTAssertEqual(Licensing.credits.first?.id, "docket")
        XCTAssertEqual(Licensing.credits.first?.text, Licensing.upstreamMIT)
        XCTAssertEqual(Set(Licensing.credits.map(\.id)).count, Licensing.credits.count)
    }

    /// NOTICE.md 里引用的每份许可原文，关于页都要有一份，否则安装包里就缺了声明。
    func testEveryNoticeLicenseIsCredited() throws {
        let notice = try read("NOTICE.md")
        for credit in Licensing.credits.dropFirst() {
            let quoted = credit.text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
            XCTAssertTrue(notice.contains(quoted), "\(credit.project) 的许可原文和 NOTICE.md 里的不一致。")
        }
    }

    func testUpdateFeedFallsBackToCurrentRepository() {
        XCTAssertEqual(UpdateFeed.fallback, "hanson-zz/docket-zh")
        XCTAssertEqual(UpdateFeed.repository(from: nil), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: ""), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: "$(DOCKLING_UPDATE_REPOSITORY)"), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: "docket-release"), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: "a/b/c"), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: "hanson-zz/../x"), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: "hanson zz/docket"), UpdateFeed.fallback)
        XCTAssertEqual(UpdateFeed.repository(from: 42), UpdateFeed.fallback)
    }

    func testUpdateFeedAcceptsARepository() {
        XCTAssertEqual(UpdateFeed.repository(from: "hanson-zz/docket-release"), "hanson-zz/docket-release")
        XCTAssertEqual(UpdateFeed.repository(from: " hanson-zz/docket-zh\n"), "hanson-zz/docket-zh")
        XCTAssertEqual(UpdateFeed.repository(from: "a_b/c.d"), "a_b/c.d")
    }
}
