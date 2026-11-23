import XCTest

/// 第一阶段稳定性：AI 连续提问时发给接口的上下文、刘海上六种活动同时出现时的先后、
/// AI 对话面板开着时小岛不展开、快捷结果卡片在刘海和备用浮窗之间来回换不丢。
final class AINotchStabilityTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: 发给接口的上下文

    func testSupersededQuestionIsNotSentAgain() {
        // 小组件连续提问：上一条还没出字就被顶掉（标为已停止、空白），只问新的。
        let messages = [AIChatMessage(role: .user, text: "旧问题"),
                        AIChatMessage(role: .assistant, text: "", status: .stopped),
                        AIChatMessage(role: .user, text: "新问题")]
        let sent = AIChatContext.outgoing(messages)
        XCTAssertEqual(sent.map(\.text), ["新问题"])
        XCTAssertEqual(sent.map(\.role), [.user])
    }

    func testStoppedWithTextKeepsTheExchange() {
        // 已经流出来的半句留着，一问一答照常带上。
        let messages = [AIChatMessage(role: .user, text: "一"),
                        AIChatMessage(role: .assistant, text: "半句", status: .stopped),
                        AIChatMessage(role: .user, text: "二")]
        XCTAssertEqual(AIChatContext.outgoing(messages).map(\.text), ["一", "半句", "二"])
    }

    func testUnansweredQuestionsMergeIntoOne() {
        // 前一个出错没答上：不连发两条用户消息，合成一条。
        let messages = [AIChatMessage(role: .user, text: "一"),
                        AIChatMessage(role: .assistant, text: "", status: .failed("401")),
                        AIChatMessage(role: .user, text: "二")]
        let sent = AIChatContext.outgoing(messages)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.role, .user)
        XCTAssertEqual(sent.first?.text, "一\n\n二")
    }

    func testOutgoingNeverSendsSuccessiveRoles() {
        let messages = [AIChatMessage(role: .assistant, text: "开场白"),
                        AIChatMessage(role: .user, text: "一"),
                        AIChatMessage(role: .assistant, text: "答一"),
                        AIChatMessage(role: .user, text: "二"),
                        AIChatMessage(role: .assistant, text: "", status: .stopped),
                        AIChatMessage(role: .user, text: "三"),
                        AIChatMessage(role: .assistant, text: "  ", status: .failed("超时")),
                        AIChatMessage(role: .user, text: "四")]
        let sent = AIChatContext.outgoing(messages)
        XCTAssertEqual(sent.first?.role, .user, "第一条总是问题")
        XCTAssertEqual(sent.last?.role, .user, "最后一条是这次要问的")
        for (a, b) in zip(sent, sent.dropFirst()) {
            XCTAssertNotEqual(a.role, b.role, "不出现连续两条同一角色")
        }
        XCTAssertEqual(sent.map(\.text), ["一", "答一", "三\n\n四"], "被换掉的「二」不带，出错没答的「三」并进「四」")
    }

    func testLastQuestionIsAlwaysSent() {
        XCTAssertEqual(AIChatContext.outgoing([AIChatMessage(role: .user, text: "只有一问")]).map(\.text), ["只有一问"])
        let normal = [AIChatMessage(role: .user, text: "一"), AIChatMessage(role: .assistant, text: "答"),
                      AIChatMessage(role: .user, text: "二")]
        XCTAssertEqual(AIChatContext.outgoing(normal), AIChatContext.history(normal), "正常一问一答和原来一样")
    }

    // MARK: 刘海小岛：六种同时出现

    private var everything: NotchIslandSettings {
        var settings = NotchIslandSettings()
        settings.enabled = true
        for kind in NotchIslandKind.allCases { settings.set(kind, true) }
        return settings
    }

    private var music: NotchIslandActivity {
        .music(NotchIslandMusic(title: "晨光里的码头", artist: "海风乐队", playing: true,
                                tint: ArtworkTint(hue: 0.9, saturation: 0.5), source: .appleMusic))
    }
    private var radio: NotchIslandActivity { .radio(station: "Lo-fi 电台", playing: true) }
    private var meeting: NotchIslandActivity { .meeting(title: "周会", start: now.addingTimeInterval(300)) }
    private var timer: NotchIslandActivity {
        .timer(deadline: now.addingTimeInterval(1498), pausedLeft: nil, total: 1500, focus: true)
    }
    private var download: NotchIslandActivity { .download(fraction: 0.4, done: false) }
    private var charging: NotchIslandActivity { .charging(percent: 63) }

    func testAllSixAtOnceFollowThePriority() {
        // 到达顺序故意反过来。
        let arrived = [music, radio, meeting, timer, download, charging]
        let ordered = NotchIslandStack.ordered(arrived, settings: everything)
        XCTAssertEqual(ordered.map(\.kind), [.charging, .download, .timer, .meeting, .radio, .music])
        XCTAssertEqual(NotchIslandStack.form(ordered, hovering: false), .split(charging, download),
                       "主岛是充电，小圆岛是下载")
    }

    func testLowerActivitiesComeBackWhenHigherOnesEnd() {
        // 充电提示收起、下载完成后，后面的不丢，依次补上来。
        var arrived = [music, radio, meeting, timer, download, charging]
        arrived.removeAll { $0.kind == .charging }
        XCTAssertEqual(NotchIslandStack.form(arrived, settings: everything, hovering: false), .split(download, timer))
        arrived.removeAll { $0.kind == .download }
        XCTAssertEqual(NotchIslandStack.form(arrived, settings: everything, hovering: false), .split(timer, meeting))
        arrived.removeAll { $0.kind == .timer || $0.kind == .meeting }
        XCTAssertEqual(NotchIslandStack.form(arrived, settings: everything, hovering: false), .split(radio, music))
        arrived.removeAll { $0.kind == .radio }
        XCTAssertEqual(NotchIslandStack.form(arrived, settings: everything, hovering: false), .compact(music))
    }

    func testOrderDoesNotDependOnArrival() {
        let a = NotchIslandStack.ordered([charging, download, timer, meeting, radio, music], settings: everything)
        let b = NotchIslandStack.ordered([meeting, music, charging, radio, timer, download], settings: everything)
        XCTAssertEqual(a, b)
    }

    // MARK: AI 对话面板开着时

    func testIslandStaysCompactWhileTheAIPanelIsOpen() {
        XCTAssertTrue(NotchIslandGate.expands(hovering: true, aiPanelOpen: false))
        XCTAssertFalse(NotchIslandGate.expands(hovering: true, aiPanelOpen: true), "面板开着不往下长")
        XCTAssertFalse(NotchIslandGate.expands(hovering: false, aiPanelOpen: false))
        let ordered = NotchIslandStack.ordered([music, timer], settings: everything)
        let hovering = NotchIslandGate.expands(hovering: true, aiPanelOpen: true)
        XCTAssertEqual(NotchIslandStack.form(ordered, hovering: hovering), .split(timer, music), "仍然显示，只是不展开")
    }

    // MARK: 快捷结果卡片

    func testQuickCardRoundTripsWithoutLosingTheResult() {
        // 刘海卡片显示着，小岛来了又走：去备用浮窗再回来，始终是卡片（不变成 nil、不跳到完整对话）。
        var target = AIQuickResult.target(mode: .api, unlocked: true, placement: .notch, autoShow: true,
                                          notchOccupied: false)
        XCTAssertEqual(target, .notchCard)
        for occupied in [true, true, false, true, false, false] {
            target = AIQuickResult.relocated(target, notchOccupied: occupied)
            XCTAssertEqual(target, occupied ? .floating : .notchCard)
        }
        XCTAssertEqual(AIQuickResult.relocated(.quiet, notchOccupied: true), .quiet)
        XCTAssertEqual(AIQuickResult.relocated(.none, notchOccupied: false), .none)
    }

    func testSupersededReplyReadsAsStoppedNotDone() {
        // 被新问题顶掉、一个字都没出的旧回答：卡片上是失败「已停止生成」，给「重试」，不会冒充已完成。
        if case .failed = AIQuickResult.phase(status: .stopped, text: "") {} else { XCTFail("没出字就被顶掉算失败") }
        XCTAssertEqual(AIQuickResult.phase(status: .stopped, text: "半句"), .done)
        XCTAssertNil(AIQuickResult.collapseDelay(.after15, phase: .thinking, pinned: false, hovering: false),
                     "新问题还在思考时不倒计时收起")
        XCTAssertFalse(AIQuickResult.closesOnOutsideClick(phase: .answering, pinned: false), "回答中点外面不收")
    }
}
