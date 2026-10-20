import Foundation
import XCTest

/// 邮件面板：解析脚本返回、挑出要显示的几封、Pro 筛选、时间和跳转链接。
final class MailInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_462_980) // 2026-10-20 10:23 +08:00
    private let RS = "\u{1E}", US = "\u{1F}"

    private func record(_ fields: String...) -> String { fields.joined(separator: US) + RS }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func sample() -> MailSnapshot {
        let text = record("A", "工作", "zhou@work.example", "3")
            + record("A", "个人", "me@home.example", "2")
            + record("A", "旧邮箱", "", "41")
            + record("M", "工作", "11", "<a1@x>", "周岚 <zhou@x>", "第二批面板评审", "660", "周四下午\n可以吗？")
            + record("M", "个人", "21", "<b1@x>", "物业服务中心 <wy@x>", "停水通知", "2580", "")
            + record("M", "工作", "12", "<a2@x>", "\"Chen, Yifan\" <c@x>", "合同第二版", "93600", "改了付款节点")
            + record("M", "旧邮箱", "31", "<c1@x>", "old@x", "很久以前", "999999", "")
        return MailInbox.parse(text, now: now)
    }

    // MARK: 解析

    func testParseReadsAccountsAndMessages() {
        let s = sample()
        XCTAssertEqual(s.accounts.map(\.name), ["工作", "个人", "旧邮箱"])
        XCTAssertEqual(s.accounts.map(\.unread), [3, 2, 41])
        XCTAssertEqual(s.accounts[0].address, "zhou@work.example")
        XCTAssertEqual(s.messages.count, 4)
        let first = s.messages[0]
        XCTAssertEqual(first.mailID, 11)
        XCTAssertEqual(first.messageID, "<a1@x>")
        XCTAssertEqual(first.summary, "周四下午 可以吗？")
        XCTAssertEqual(first.received, now.addingTimeInterval(-660))
    }

    func testParseSkipsBrokenRecordsAndDuplicates() {
        let text = record("M", "工作", "abc", "", "x", "y", "1", "")      // 编号不是数字
            + record("M", "", "3", "", "x", "y", "1", "")                // 没有账户
            + record("A", "", "", "4")                                    // 没有名字
            + record("Z", "?")
            + record("M", "工作", "5", "", "x", "y", "1,0", "")
            + record("M", "工作", "5", "", "x", "y", "1", "")            // 重复
            + record("A", "工作", "", "2") + record("A", "工作", "w@x", "1")
        let s = MailInbox.parse(text, now: now)
        XCTAssertEqual(s.messages.count, 1)
        XCTAssertEqual(s.messages[0].received, now.addingTimeInterval(-1))
        XCTAssertEqual(s.accounts, [MailAccount(name: "工作", address: "w@x", unread: 3)])
        XCTAssertEqual(MailInbox.parse("", now: now), MailSnapshot())
    }

    func testSummaryIsOneShortLine() {
        let long = String(repeating: "字", count: 300)
        XCTAssertEqual(MailInbox.summary(long).count, MailInbox.summaryLength)
        XCTAssertEqual(MailInbox.summary("  a \n\n b\t c  "), "a b c")
    }

    // MARK: 设置

    func testLimitFallsBackToFive() {
        XCTAssertEqual(MailInbox.limit(WidgetConfig()), 5)
        XCTAssertEqual(MailInbox.limit(WidgetConfig([MailInbox.limitKey: .string("10")])), 10)
        XCTAssertEqual(MailInbox.limit(WidgetConfig([MailInbox.limitKey: .string("3")])), 3)
        XCTAssertEqual(MailInbox.limit(WidgetConfig([MailInbox.limitKey: .string("7")])), 5)
        XCTAssertEqual(MailInbox.limit(WidgetConfig([MailInbox.limitKey: .string("")])), 5)
    }

    func testDefaultsMatchTheCatalog() {
        let entry = WidgetCatalog.entry(.mail)
        XCTAssertEqual(entry?.defaults.values[MailInbox.limitKey], .string("5"))
        XCTAssertEqual(entry?.defaults.values[MailInbox.summaryKey], .bool(true))
        XCTAssertEqual(entry?.defaults.values[MailInbox.markReadKey], .bool(false))
        XCTAssertTrue(MailInbox.showsSummary(WidgetConfig()))
        XCTAssertFalse(MailInbox.marksReadOnOpen(WidgetConfig()))
        // 面板自己写的两个键不进设置页。
        let keys = WidgetCatalog.configurableKeys(.mail)
        XCTAssertFalse(keys.contains(MailInbox.hiddenKey))
        XCTAssertFalse(keys.contains(MailInbox.filterKey))
    }

    func testTogglingAccountsIsSortedAndReversible() {
        var hidden: Set<String> = []
        hidden = Set(MailInbox.toggling("旧邮箱", shown: false, hidden: hidden))
        XCTAssertEqual(MailInbox.toggling("A", shown: false, hidden: hidden), ["A", "旧邮箱"])
        XCTAssertEqual(MailInbox.toggling("旧邮箱", shown: true, hidden: hidden), [])
        // 存着的配置重读后还在。
        let config = WidgetConfig([MailInbox.hiddenKey: .list([.string("旧邮箱")])])
        XCTAssertEqual(MailInbox.hidden(config), ["旧邮箱"])
    }

    // MARK: 挑哪几封

    func testVisibleSortsNewestFirstAndRespectsLimit() {
        let s = sample()
        let all = MailInbox.visible(s, hidden: [], filter: nil, unlocked: false, limit: 10)
        XCTAssertEqual(all.map(\.mailID), [11, 21, 12, 31])
        XCTAssertEqual(MailInbox.visible(s, hidden: [], filter: nil, unlocked: false, limit: 3).count, 3)
        XCTAssertEqual(MailInbox.visible(s, hidden: [], filter: nil, unlocked: false, limit: 0), [])
    }

    func testHiddenAccountsDropOut() {
        let s = sample()
        let shown = MailInbox.visible(s, hidden: ["旧邮箱"], filter: nil, unlocked: false, limit: 10)
        XCTAssertFalse(shown.contains { $0.account == "旧邮箱" })
        XCTAssertEqual(MailInbox.unreadTotal(s, hidden: ["旧邮箱"], filter: nil, unlocked: false), 5)
        XCTAssertEqual(MailInbox.unreadTotal(s, hidden: [], filter: nil, unlocked: false), 46)
    }

    func testFilterIsProAndFallsBackToAll() {
        let s = sample()
        // 没解锁：存着「工作」也按全部显示。
        XCTAssertNil(MailInbox.effectiveFilter("工作", accounts: s.accounts, hidden: [], unlocked: false))
        XCTAssertEqual(MailInbox.visible(s, hidden: [], filter: "工作", unlocked: false, limit: 10).count, 4)
        XCTAssertFalse(MailInbox.canFilter(unlocked: false))
        XCTAssertFalse(ProLicenseGate.canFilterMailAccounts(unlocked: false))
        // 解锁：只看「工作」。
        let work = MailInbox.visible(s, hidden: [], filter: "工作", unlocked: true, limit: 10)
        XCTAssertEqual(work.map(\.mailID), [11, 12])
        XCTAssertEqual(MailInbox.unreadTotal(s, hidden: [], filter: "工作", unlocked: true), 3)
        // 选的账户被关掉或不在了：退回全部。
        XCTAssertNil(MailInbox.effectiveFilter("工作", accounts: s.accounts, hidden: ["工作"], unlocked: true))
        XCTAssertNil(MailInbox.effectiveFilter("不存在", accounts: s.accounts, hidden: [], unlocked: true))
        XCTAssertNil(MailInbox.effectiveFilter("", accounts: s.accounts, hidden: [], unlocked: true))
    }

    func testAllAccountsHidden() {
        let s = sample()
        XCTAssertTrue(MailInbox.allAccountsHidden(s.accounts, hidden: ["工作", "个人", "旧邮箱"]))
        XCTAssertFalse(MailInbox.allAccountsHidden(s.accounts, hidden: ["工作"]))
        XCTAssertFalse(MailInbox.allAccountsHidden([], hidden: ["工作"]))
    }

    func testFilterChipsNeedTwoAccounts() {
        let s = sample()
        XCTAssertTrue(MailInbox.showsFilterChips(s.accounts, hidden: ["旧邮箱"]))
        XCTAssertFalse(MailInbox.showsFilterChips(s.accounts, hidden: ["旧邮箱", "个人"]))
        XCTAssertFalse(MailInbox.showsFilterChips([], hidden: []))
    }

    func testMarkAllTargetsShownAccountsWithUnread() {
        var s = sample()
        s.accounts[1].unread = 0
        XCTAssertEqual(MailInbox.accountsToMarkAll(s, hidden: ["旧邮箱"], filter: nil, unlocked: false), ["工作"])
        XCTAssertEqual(MailInbox.accountsToMarkAll(s, hidden: [], filter: "旧邮箱", unlocked: true), ["旧邮箱"])
        XCTAssertEqual(MailInbox.accountsToMarkAll(MailSnapshot(), hidden: [], filter: nil, unlocked: true), [])
    }

    func testRemovingTheLastMessageLeavesAnEmptyList() {
        var s = sample()
        for message in s.messages { s = MailInbox.removing(message, from: s) }
        XCTAssertTrue(s.messages.isEmpty)
        XCTAssertEqual(s.accounts.map(\.unread), [1, 1, 40])
        XCTAssertEqual(MailInbox.visible(s, hidden: [], filter: nil, unlocked: true, limit: 5), [])
        // 拿掉不存在的那封不出错，未读数也不会减到负数。
        let ghost = MailMessage(account: "工作", mailID: 99, messageID: "", sender: "", subject: "",
                                summary: "", received: now)
        XCTAssertEqual(MailInbox.removing(ghost, from: s), s)
        let cleared = MailInbox.clearing(["工作", "个人", "旧邮箱"], from: sample())
        XCTAssertEqual(cleared.accounts.map(\.unread), [0, 0, 0])
        XCTAssertTrue(cleared.messages.isEmpty)
    }

    // MARK: 显示

    func testSenderName() {
        XCTAssertEqual(MailInbox.senderName("周岚 <zhou@x>"), "周岚")
        XCTAssertEqual(MailInbox.senderName("\"Chen, Yifan\" <c@x>"), "Chen, Yifan")
        XCTAssertEqual(MailInbox.senderName("<c@x>"), "c@x")
        XCTAssertEqual(MailInbox.senderName("c@x"), "c@x")
        XCTAssertEqual(MailInbox.senderName("  "), "未知发件人")
    }

    func testInitialAndColoursAreStable() {
        XCTAssertEqual(MailInbox.initial("周岚"), "周")
        XCTAssertEqual(MailInbox.initial("chen"), "C")
        XCTAssertEqual(MailInbox.initial("\"!"), "?")
        XCTAssertEqual(MailInbox.avatarHex("周岚"), MailInbox.avatarHex("周岚"))
        XCTAssertTrue(MailInbox.avatarHexes.contains(MailInbox.avatarHex("")))
        let accounts = sample().accounts
        XCTAssertEqual(MailInbox.accountHex("工作", in: accounts), "#6FD6C0")
        XCTAssertEqual(MailInbox.accountHex("个人", in: accounts), "#FFB86B")
        XCTAssertEqual(MailInbox.accountHex("没有", in: accounts), "#9AA0AA")
    }

    func testTimeLabel() {
        let c = calendar
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
            c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
        }
        let now = at(2026, 10, 20, 10, 23)
        XCTAssertEqual(MailInbox.timeLabel(at(2026, 10, 20, 9, 5), now: now, calendar: c), "09:05")
        XCTAssertEqual(MailInbox.timeLabel(at(2026, 10, 19, 23, 59), now: now, calendar: c), "昨天")
        XCTAssertEqual(MailInbox.timeLabel(at(2026, 10, 18, 8, 0), now: now, calendar: c), "周日")
        XCTAssertEqual(MailInbox.timeLabel(at(2026, 10, 3, 8, 0), now: now, calendar: c), "10月3日")
        XCTAssertEqual(MailInbox.timeLabel(at(2025, 12, 31, 8, 0), now: now, calendar: c), "2025/12/31")
        // 时钟不准、信比现在还新：照样写钟点。
        XCTAssertEqual(MailInbox.timeLabel(at(2026, 10, 21, 1, 0), now: now, calendar: c), "01:00")
    }

    // MARK: 跳转和脚本

    func testMessageURL() {
        XCTAssertEqual(MailInbox.messageURL("<abc.123@mail.example>")?.absoluteString,
                       "message://%3Cabc.123@mail.example%3E")
        XCTAssertEqual(MailInbox.messageURL("a b/c@x")?.absoluteString, "message://%3Ca%20b%2Fc@x%3E")
        XCTAssertNil(MailInbox.messageURL(""))
        XCTAssertNil(MailInbox.messageURL("<>"))
    }

    func testQuotedEscapesForAppleScript() {
        XCTAssertEqual(MailInbox.quoted("iCloud"), "\"iCloud\"")
        XCTAssertEqual(MailInbox.quoted("a\"b\\c\nd"), "\"a\\\"b\\\\c d\"")
    }

    func testScriptsCarryTheirArguments() {
        let fetch = MailInbox.fetchScript(perAccount: 10, summary: false)
        XCTAssertTrue(fetch.contains("if lim > 10 then set lim to 10"))
        XCTAssertTrue(fetch.contains("if false then"))
        XCTAssertTrue(MailInbox.fetchScript(perAccount: 0, summary: true).contains("if lim > 1 then"))
        let one = MailInbox.markReadScript(account: "工作 \"A\"", mailID: 42)
        XCTAssertTrue(one.contains("whose id is 42"))
        XCTAssertTrue(one.contains("\"工作 \\\"A\\\"\""))
        let all = MailInbox.markAllReadScript(accounts: ["工作", "个人"])
        XCTAssertTrue(all.contains("set wanted to {\"工作\", \"个人\"}"))
        XCTAssertFalse(fetch.contains("\u{2014}"))
    }
}
