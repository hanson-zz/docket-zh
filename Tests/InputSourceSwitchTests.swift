import XCTest
@testable import Docket

final class InputSourceSwitchTests: XCTestCase {
    private let abc = InputSourceInfo(id: "com.apple.keylayout.ABC", name: "ABC", languages: ["en"])
    private let pinyin = InputSourceInfo(id: "com.apple.inputmethod.SCIM.ITABC", name: "简体拼音",
                                         languages: ["zh-Hans"], type: InputSourceInfo.inputModeType)
    private let kana = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", name: "日语假名",
                                       languages: ["ja"], type: InputSourceInfo.inputModeType)
    private let korean = InputSourceInfo(id: "com.apple.inputmethod.Korean.2SetKorean", name: "2-Set Korean",
                                         languages: ["ko"], type: InputSourceInfo.inputModeType)
    private let us = InputSourceInfo(id: "com.apple.keylayout.US", name: "美国", languages: ["en"])

    private var all: [InputSourceInfo] { [abc, pinyin, kana, korean] }

    private func settings(_ edit: (inout InputSourceSettings) -> Void = { _ in }) -> InputSourceSettings {
        var value = InputSourceSettings()
        value.enabled = true
        edit(&value)
        return value
    }

    // MARK: 设置

    func testDefaultsAreOffWithDefaultSourceAndNotchHint() {
        let value = InputSourceSettings()
        XCTAssertFalse(value.enabled, "总开关默认关")
        XCTAssertEqual(value.fallback, .defaultSource)
        XCTAssertEqual(value.defaultSourceID, InputSourceCatalog.abcID)
        XCTAssertEqual(value.hint, .notch)
        XCTAssertEqual(value.hintSeconds, 1)
        XCTAssertTrue(value.rules.isEmpty)
        XCTAssertEqual(PersistedState().inputSource, value)
    }

    func testRoundTripAndLenientDecoding() throws {
        var state = PersistedState()
        state.inputSource = settings {
            $0.fallback = .remember
            $0.hint = .cursor
            $0.seconds = 2
            $0.setRule(bundleID: "com.tencent.xinWeChat", appName: "微信", sourceID: pinyin.id)
        }
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(back.inputSource, state.inputSource)

        let legacy = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.inputSource, InputSourceSettings())

        let odd = Data(#"{"enabled":true,"fallback":"later","hint":"everywhere","seconds":7,"defaultSourceID":"","rules":[{"bundleID":"a.b","appName":"A","sourceID":"x"},{"bundleID":"A.B","appName":"A2","sourceID":"y"},{"bundleID":"c.d","appName":"C","sourceID":""}]}"#.utf8)
        let decoded = try JSONDecoder().decode(InputSourceSettings.self, from: odd)
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.fallback, .defaultSource, "认不出的值按默认读")
        XCTAssertEqual(decoded.hint, .notch)
        XCTAssertEqual(decoded.hintSeconds, 1, "不在选项里的秒数按默认读")
        XCTAssertEqual(decoded.defaultSourceID, InputSourceCatalog.abcID)
        XCTAssertEqual(decoded.rules.map(\.sourceID), ["x"], "同一个 App 只留第一条，空输入法丢掉")
    }

    func testOneRulePerAppAndNeverForDockling() {
        var value = settings()
        value.setRule(bundleID: "com.apple.Safari", appName: "Safari", sourceID: pinyin.id)
        value.setRule(bundleID: "com.apple.dt.Xcode", appName: "Xcode", sourceID: abc.id)
        value.setRule(bundleID: "COM.APPLE.SAFARI", appName: "", sourceID: abc.id)
        XCTAssertEqual(value.rules.map(\.bundleID), ["com.apple.Safari", "com.apple.dt.Xcode"], "改一条不换位置")
        XCTAssertEqual(value.rule(for: "com.apple.safari")?.sourceID, abc.id)
        XCTAssertEqual(value.rule(for: "com.apple.Safari")?.appName, "Safari", "空名字不覆盖")
        value.setRule(bundleID: "com.docket-zh.app", appName: "码头", sourceID: abc.id)
        XCTAssertNil(value.rule(for: "com.docket-zh.app"), "码头自己不加规则")
        value.removeRule(bundleID: "com.apple.SAFARI")
        XCTAssertEqual(value.rules.map(\.bundleID), ["com.apple.dt.Xcode"])
    }

    // MARK: 输入法列表

    func testSelectableKeepsKeyboardSourcesOnly() {
        let list = [
            abc,
            InputSourceInfo(id: "com.apple.inputmethod.SCIM", name: "简体中文", languages: ["zh-Hans"],
                            type: "TISTypeKeyboardInputMethodWithModes", selectable: false),
            pinyin,
            InputSourceInfo(id: "com.apple.CharacterPaletteIM", name: "表情与符号",
                            type: InputSourceInfo.methodWithoutModesType),
            InputSourceInfo(id: "com.apple.PressAndHold", name: "PressAndHold", type: InputSourceInfo.methodWithoutModesType),
            InputSourceInfo(id: "com.apple.keylayout.US", name: "美国", enabled: false),
            abc,
            InputSourceInfo(id: "com.sogou.inputmethod.sogou.pinyin", name: "搜狗拼音", languages: ["zh-Hans"],
                            type: InputSourceInfo.inputModeType),
        ]
        XCTAssertEqual(InputSourceCatalog.selectable(list).map(\.id),
                       [abc.id, pinyin.id, "com.sogou.inputmethod.sogou.pinyin"])
    }

    // MARK: 回退顺序

    func testRuleWinsWhenUnlocked() {
        let value = settings { $0.setRule(bundleID: "com.tencent.xinWeChat", appName: "微信", sourceID: pinyin.id) }
        let target = InputSourceResolver.target(for: "com.tencent.xinWeChat", settings: value, rulesActive: true,
                                                memory: InputSourceMemory(), available: all)
        XCTAssertEqual(target, .init(sourceID: pinyin.id, reason: .rule))
    }

    func testRulesIgnoredWhenLockedButKept() {
        let value = settings { $0.setRule(bundleID: "com.tencent.xinWeChat", appName: "微信", sourceID: pinyin.id) }
        XCTAssertFalse(ProLicenseGate.inputSourceRulesActive(unlocked: false))
        XCTAssertTrue(ProLicenseGate.inputSourceRulesActive(unlocked: true))
        let target = InputSourceResolver.target(for: "com.tencent.xinWeChat", settings: value,
                                                rulesActive: ProLicenseGate.inputSourceRulesActive(unlocked: false),
                                                memory: InputSourceMemory(), available: all)
        XCTAssertEqual(target, .init(sourceID: abc.id, reason: .defaultSource), "没解锁时按没有规则处理")
        XCTAssertEqual(value.rules.count, 1, "规则不改写")
    }

    func testDeletedRuleSourceFallsBackToDefaultThenFirst() {
        var value = settings { $0.setRule(bundleID: "com.apple.mail", appName: "邮件", sourceID: korean.id) }
        let withoutKorean = [abc, pinyin, kana]
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.mail", settings: value, rulesActive: true,
                                                  memory: InputSourceMemory(), available: withoutKorean),
                       .init(sourceID: abc.id, reason: .ruleMissing))
        XCTAssertEqual(value.rule(for: "com.apple.mail")?.sourceID, korean.id, "规则保留")
        // 装回来后自动恢复。
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.mail", settings: value, rulesActive: true,
                                                  memory: InputSourceMemory(), available: all)?.reason, .rule)
        // 默认输入法也没了：系统第一个键盘输入法。
        value.defaultSourceID = "com.example.gone"
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.mail", settings: value, rulesActive: true,
                                                  memory: InputSourceMemory(), available: [pinyin, kana]),
                       .init(sourceID: pinyin.id, reason: .ruleMissing))
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.finder", settings: value, rulesActive: true,
                                                  memory: InputSourceMemory(), available: [pinyin, kana]),
                       .init(sourceID: pinyin.id, reason: .firstAvailable))
    }

    func testRememberUsesLastSourceOrDefaultFirstTime() {
        let value = settings { $0.fallback = .remember }
        var memory = InputSourceMemory()
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.Notes", settings: value, rulesActive: true,
                                                  memory: memory, available: all),
                       .init(sourceID: abc.id, reason: .defaultSource), "第一次没有记录用默认输入法")
        memory.record(kana.id, for: "com.apple.Notes")
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.notes", settings: value, rulesActive: true,
                                                  memory: memory, available: all),
                       .init(sourceID: kana.id, reason: .remembered))
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.Notes", settings: value, rulesActive: true,
                                                  memory: memory, available: [abc, pinyin])?.reason, .defaultSource,
                       "记的那个被删了用默认输入法")
        // 用默认输入法时不看记录。
        let plain = settings()
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.Notes", settings: plain, rulesActive: true,
                                                  memory: memory, available: all)?.sourceID, abc.id)
    }

    func testRuleBeatsRemember() {
        let value = settings {
            $0.fallback = .remember
            $0.setRule(bundleID: "com.apple.Notes", appName: "备忘录", sourceID: pinyin.id)
        }
        var memory = InputSourceMemory()
        memory.record(kana.id, for: "com.apple.Notes")
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.Notes", settings: value, rulesActive: true,
                                                  memory: memory, available: all)?.sourceID, pinyin.id)
        XCTAssertEqual(InputSourceResolver.target(for: "com.apple.Notes", settings: value, rulesActive: false,
                                                  memory: memory, available: all)?.sourceID, kana.id)
    }

    func testNoSwitchWhenOffForDocklingOrNothingInstalled() {
        XCTAssertNil(InputSourceResolver.target(for: "com.apple.Safari", settings: InputSourceSettings(),
                                                rulesActive: true, memory: InputSourceMemory(), available: all),
                     "总开关关着不切")
        XCTAssertNil(InputSourceResolver.target(for: "com.docket-zh.app", settings: settings(), rulesActive: true,
                                                memory: InputSourceMemory(), available: all), "码头自己被激活时不切")
        XCTAssertNil(InputSourceResolver.target(for: "com.apple.Safari", settings: settings(), rulesActive: true,
                                                memory: InputSourceMemory(), available: []))
    }

    func testShouldSwitchOnlyWhenDifferent() {
        let target = InputSourceResolver.Target(sourceID: pinyin.id, reason: .rule)
        XCTAssertTrue(InputSourceResolver.shouldSwitch(current: abc.id, target: target))
        XCTAssertTrue(InputSourceResolver.shouldSwitch(current: nil, target: target))
        XCTAssertFalse(InputSourceResolver.shouldSwitch(current: pinyin.id, target: target), "已经是目标时不切")
        XCTAssertFalse(InputSourceResolver.shouldSwitch(current: abc.id, target: nil))
    }

    func testMemoryCapsAndSkipsDockling() {
        var memory = InputSourceMemory()
        memory.record(abc.id, for: "com.docket-zh.app")
        XCTAssertNil(memory.source(for: "com.docket-zh.app"))
        memory.record(nil, for: "a.b")
        memory.record(abc.id, for: nil)
        XCTAssertTrue(memory.sources.isEmpty)
        for index in 0..<(InputSourceMemory.limit + 5) { memory.record(abc.id, for: "app.\(index)") }
        XCTAssertEqual(memory.sources.count, InputSourceMemory.limit)
        XCTAssertNil(memory.source(for: "app.0"), "最久没用的先丢")
        memory.record(pinyin.id, for: "app.6")
        memory.record(kana.id, for: "app.new")
        XCTAssertEqual(memory.source(for: "app.6"), pinyin.id, "刚用过的不丢")
    }

    func testRecordingSameSourceStillRefreshesOrder() {
        // 常用的 App 输入法一直没变，也得算「最近用过」，满了不先丢它。
        var memory = InputSourceMemory()
        for index in 0..<InputSourceMemory.limit { memory.record(abc.id, for: "app.\(index)") }
        let before = memory
        memory.record(abc.id, for: "app.0")
        XCTAssertNotEqual(memory, before, "同一个输入法再记一次要挪到最近")
        XCTAssertEqual(memory.order.last, "app.0")
        memory.record(kana.id, for: "app.new")
        XCTAssertEqual(memory.source(for: "app.0"), abc.id)
        XCTAssertNil(memory.source(for: "app.1"))
        // 已经在最近、值也没变：记录不变（不写盘）。
        let settled = memory
        memory.record(kana.id, for: "app.new")
        XCTAssertEqual(memory, settled)
    }

    // MARK: 规则卡片

    func testRuleStatusCaption() {
        let value = settings()
        let rule = InputSourceRule(bundleID: "com.apple.mail", appName: "邮件", sourceID: korean.id)
        XCTAssertEqual(InputSourceRuleStatus.of(rule, settings: value, available: all), .ok(korean))
        let missing = InputSourceRuleStatus.of(rule, settings: value, available: [abc, pinyin])
        XCTAssertTrue(missing.isMissing)
        XCTAssertEqual(missing.caption, "已删除，暂用 ABC")
        XCTAssertEqual(InputSourceRuleStatus.of(rule, settings: value, available: []).caption, "已删除")
    }

    // MARK: 字形徽章

    func testGlyphs() {
        XCTAssertEqual(InputSourceGlyph.of(abc), .init("A", .latin))
        XCTAssertEqual(InputSourceGlyph.of(us), .init("A", .latin))
        XCTAssertEqual(InputSourceGlyph.of(pinyin), .init("拼", .chinese))
        XCTAssertEqual(InputSourceGlyph.of(kana), .init("あ", .japanese))
        XCTAssertEqual(InputSourceGlyph.of(korean), .init("한", .korean))
        let roman = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", name: "罗马字",
                                    languages: ["ja"], type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(roman).text, "A")
        let katakana = InputSourceInfo(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana",
                                       name: "片假名", languages: ["ja"], type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(katakana).text, "ア")
        let wubi = InputSourceInfo(id: "com.apple.inputmethod.SCIM.WBX", name: "五笔型", languages: ["zh-Hans"],
                                   type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(wubi), .init("五", .chinese))
        let unknownChinese = InputSourceInfo(id: "com.example.zh.im", name: "某输入法", languages: ["zh-Hans"],
                                             type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(unknownChinese), .init("中", .chinese), "认不出输入方式的中文写「中」")
        let wubiNamed = InputSourceInfo(id: "com.example.wubi86", name: "五笔", languages: ["zh-Hans"],
                                        type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(wubiNamed).text, "五")
        let zhuyin = InputSourceInfo(id: "com.apple.inputmethod.TCIM.Zhuyin", name: "注音", languages: ["zh-Hant"],
                                     type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(zhuyin).text, "注")
        let shuangpin = InputSourceInfo(id: "com.apple.inputmethod.SCIM.Shuangpin", name: "双拼",
                                        languages: ["zh-Hans"], type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(shuangpin).text, "双")
        let sogou = InputSourceInfo(id: "com.sogou.inputmethod.sogou.pinyin", name: "搜狗拼音",
                                    languages: ["zh-Hans"], type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(sogou).text, "拼")
        let russian = InputSourceInfo(id: "com.apple.keylayout.Russian", name: "俄语", languages: ["ru"])
        XCTAssertEqual(InputSourceGlyph.of(russian), .init("Я", .other))
        let french = InputSourceInfo(id: "com.apple.keylayout.French", name: "法语", languages: ["fr"])
        XCTAssertEqual(InputSourceGlyph.of(french).text, "A")
        let odd = InputSourceInfo(id: "org.example.im", name: "xyz", languages: ["zz"], type: InputSourceInfo.inputModeType)
        XCTAssertEqual(InputSourceGlyph.of(odd), .init("X", .other), "说不出时用名字的第一个字")
    }

    // MARK: 要不要提示

    func testHintOnlyWhenSwitchedAndFree() {
        let free = InputSourceHint.Occupancy()
        XCTAssertTrue(InputSourceHint.shouldShow(switched: true, position: .notch, occupancy: free))
        XCTAssertTrue(InputSourceHint.shouldShow(switched: true, position: .cursor, occupancy: free))
        XCTAssertFalse(InputSourceHint.shouldShow(switched: false, position: .notch, occupancy: free), "没切不提示")
        XCTAssertFalse(InputSourceHint.shouldShow(switched: true, position: .off, occupancy: free))
        let busy: [InputSourceHint.Occupancy] = [
            .init(fullscreen: true), .init(aiPanelOpen: true), .init(reminderShowing: true),
            .init(messageCardExpanded: true), .init(islandShowing: true),
        ]
        for occupancy in busy {
            XCTAssertFalse(InputSourceHint.shouldShow(switched: true, position: .notch, occupancy: occupancy),
                           "刘海区被占着时直接不显示：\(occupancy)")
        }
    }

    func testCursorFallsBackToNotchWithoutPermissionOrCaret() {
        let caret = CGRect(x: 100, y: 300, width: 2, height: 18)
        XCTAssertEqual(InputSourceHint.effectivePosition(.cursor, trusted: true, caret: caret), .cursor)
        XCTAssertEqual(InputSourceHint.effectivePosition(.cursor, trusted: false, caret: caret), .notch)
        XCTAssertEqual(InputSourceHint.effectivePosition(.cursor, trusted: true, caret: nil), .notch)
        XCTAssertEqual(InputSourceHint.effectivePosition(.notch, trusted: false, caret: nil), .notch)
        XCTAssertEqual(InputSourceHint.effectivePosition(.off, trusted: true, caret: caret), .off)
        XCTAssertTrue(InputSourceHintPosition.cursor.needsAccessibility)
        XCTAssertFalse(InputSourceHintPosition.notch.needsAccessibility)
    }

    // MARK: 放哪

    private let notchScreen = AINotchScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                            notch: CGRect(x: 656, y: 950, width: 200, height: 32),
                                            menuBarHeight: 32, isMain: true)
    private let plainScreen = AINotchScreen(id: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                            notch: nil, menuBarHeight: 25, isMain: true)

    func testHangsFromNotchAtLeastNotchWide() {
        let width = InputSourceHint.capsuleWidth(nameWidth: 60)
        guard case .hang(let frame, let fromNotch) = InputSourceHint.placement(
            .notch, screen: notchScreen, windows: [], caret: nil, width: width) else { return XCTFail() }
        XCTAssertTrue(fromNotch)
        XCTAssertEqual(frame.maxY, 950, "顶边接在刘海下沿")
        XCTAssertEqual(frame.midX, 756, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(frame.width, 200 + InputSourceHint.notchOverhang)
        XCTAssertEqual(frame.height, InputSourceHint.height + AINotchLayout.notchBlendHeight, "顶上留黑色过渡")
    }

    func testSecondsText() {
        XCTAssertEqual(InputSourceSettings.secondsText(1), "1")
        XCTAssertEqual(InputSourceSettings.secondsText(0.5), "0.5")
        XCTAssertEqual(InputSourceSettings.secondsText(1.5), "1.5")
        XCTAssertEqual(InputSourceSettings.secondChoices.first, 0.5)
    }

    func testExternalScreenUsesSmallCapsuleBelowMenuBar() {
        guard case .hang(let frame, let fromNotch) = InputSourceHint.placement(
            .notch, screen: plainScreen, windows: [], caret: nil, width: 160) else { return XCTFail() }
        XCTAssertFalse(fromNotch)
        XCTAssertEqual(frame.height, InputSourceHint.smallHeight)
        XCTAssertLessThan(frame.maxY, 1080 - 25, "在菜单栏下方")
        XCTAssertEqual(frame.width, 160)
    }

    func testYieldsToShiduoShelf() {
        // 收纳架展开：从顶上挂下来约 200pt。
        let shelf = NotchForeignWindow(ownerName: "拾掇", bundleID: "io.github.hanson-zz.shiduo",
                                       frame: CGRect(x: 556, y: 750, width: 400, height: 232))
        guard case .compact(let frame) = InputSourceHint.placement(
            .notch, screen: notchScreen, windows: [shelf], caret: nil, width: 220) else { return XCTFail() }
        XCTAssertEqual(frame.minX, 856, "贴着刘海右边")
        XCTAssertEqual(frame.width, InputSourceHint.compactWidth)
        XCTAssertEqual(frame.minY, 950)
        XCTAssertEqual(frame.height, 32, "和菜单栏一样高")

        // 只伸下来一点（提示条）：落在它下面。
        let strip = NotchForeignWindow(ownerName: "Shiduo", frame: CGRect(x: 640, y: 930, width: 232, height: 52))
        guard case .hang(let below, let fromNotch) = InputSourceHint.placement(
            .notch, screen: notchScreen, windows: [strip], caret: nil, width: 220) else { return XCTFail() }
        XCTAssertFalse(fromNotch)
        XCTAssertEqual(below.maxY, 930 - NotchMessagePlacement.gap)

        // 别的 App 的窗口不算。
        let other = NotchForeignWindow(ownerName: "Safari", frame: shelf.frame)
        guard case .hang(_, true) = InputSourceHint.placement(
            .notch, screen: notchScreen, windows: [other], caret: nil, width: 220) else { return XCTFail() }
    }

    func testCompactMovesPastNotchAppInMenuBar() {
        let indicator = NotchForeignWindow(ownerName: "拾掇", frame: CGRect(x: 856, y: 950, width: 80, height: 32))
        let frame = InputSourceHint.compactFrame(screen: notchScreen, windows: [indicator])
        XCTAssertEqual(frame.minX, 936 + NotchMessagePlacement.capsuleGap)
    }

    func testCursorFrameStaysOnScreen() {
        let caret = CGRect(x: 400, y: 500, width: 2, height: 18)
        guard case .cursor(let frame) = InputSourceHint.placement(
            .cursor, screen: notchScreen, windows: [], caret: caret, width: 150) else { return XCTFail() }
        XCTAssertEqual(frame.maxY, 494, "在光标下面空 6pt")
        XCTAssertEqual(frame.minX, 386)
        let low = InputSourceHint.cursorFrame(caret: CGRect(x: 1500, y: 10, width: 2, height: 18),
                                              screen: notchScreen.frame, width: 150)
        XCTAssertEqual(low.minY, 34, "下面放不下放到光标上面")
        XCTAssertLessThanOrEqual(low.maxX, 1512 - NotchMessagePlacement.margin)
        // 光标旁读不到光标时落回刘海下。
        guard case .hang = InputSourceHint.placement(.cursor, screen: notchScreen, windows: [], caret: nil,
                                                     width: 150) else { return XCTFail() }
        XCTAssertNil(InputSourceHint.placement(.off, screen: notchScreen, windows: [], caret: nil, width: 150))
    }

    func testCapsuleWidthClampsName() {
        XCTAssertEqual(InputSourceHint.capsuleWidth(nameWidth: 0), InputSourceHint.capsuleWidth(nameWidth: 24))
        XCTAssertEqual(InputSourceHint.capsuleWidth(nameWidth: 999), InputSourceHint.capsuleWidth(nameWidth: 220))
    }

    func testProListed() {
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.inputSourceRules))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.inputSourceRules)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.inputSourceRules)), "输入法规则")
    }
}
