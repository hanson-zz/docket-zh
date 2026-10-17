import XCTest

/// 快速开关第二批工具的纯逻辑：识字结果、取色提示、二维码、演示模式的恢复、
/// 只锁键盘的计时和低电量模式的 pmset 解析。
final class QuickToolsTests: XCTestCase {

    // MARK: 新开关只有三个进默认，旧配置照常读取

    func testNewTogglesAreNotDefaultAndOldConfigStillReads() {
        let added: [QuickToggle] = [.textCapture, .colorPicker, .presentation, .keyboardLock,
                                    .qrCode, .mirror, .lowPower, .restartDock]
        // 截图识字、取色器、演示模式进了新卡片的默认，其余仍要自己勾。
        let inDefaults: Set<QuickToggle> = [.textCapture, .colorPicker, .presentation]
        for toggle in added {
            XCTAssertEqual(QuickToggle.defaults.contains(toggle), inDefaults.contains(toggle), "\(toggle)")
            XCTAssertFalse(QuickToggle.emptyFallback.contains(toggle))
            XCTAssertTrue(QuickToggle.allCases.contains(toggle))
        }
        XCTAssertEqual(Set(QuickToggle.allCases.map(\.rawValue)).count, QuickToggle.allCases.count)

        var config = WidgetConfig()
        config.set(QuickToggle.key, .list([.string("darkMode"), .string("cleanScreen"), .string("quitApps")]))
        XCTAssertEqual(QuickToggle.chosen(config), [.darkMode, .cleanScreen, .quitApps])
        config.set(QuickToggle.key, .list([.string("lock"), .string("qrCode"), .string("mirror")]))
        XCTAssertEqual(QuickToggle.chosen(config), [.lock, .qrCode, .mirror])
    }

    func testOnlyRealSwitchesHaveState() {
        XCTAssertTrue(QuickToggle.presentation.hasState)
        XCTAssertTrue(QuickToggle.lowPower.hasState)
        XCTAssertTrue(QuickToggle.keyboardLock.hasState)
        XCTAssertFalse(QuickToggle.textCapture.hasState)
        XCTAssertFalse(QuickToggle.colorPicker.hasState)
        XCTAssertFalse(QuickToggle.qrCode.hasState)
        XCTAssertFalse(QuickToggle.restartDock.hasState)
    }

    // MARK: 截图识字

    func testRecognizedTextDropsBlankLines() {
        XCTAssertEqual(RecognizedText.joined(["  你好 ", "", "   ", "Hello world"]), "你好\nHello world")
        XCTAssertEqual(RecognizedText.joined([]), "")
    }

    func testPreviewFlattensAndTruncates() {
        XCTAssertEqual(RecognizedText.preview("第一行\n第二行"), "第一行 第二行")
        XCTAssertEqual(RecognizedText.preview("一二三四五六", limit: 4), "一二三四…")
        XCTAssertEqual(RecognizedText.preview("一二三四", limit: 4), "一二三四")
    }

    // MARK: 取色器

    func testColorHintShowsUppercaseHexAndRGB() {
        let code = ColorCode(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        XCTAssertEqual(code.hex, "#1C1C1E")
        XCTAssertEqual(code.copiedHint, "已复制 #1C1C1E（RGB 28, 28, 30）")
        let orange = ColorCode(hex: "ff9f0a")!
        XCTAssertEqual(orange.hex, "#FF9F0A")
        XCTAssertEqual(ColorCode(red: 2, green: -1, blue: .nan).hex, "#FF0000")
    }

    // MARK: 二维码

    func testWebURLDetection() {
        XCTAssertEqual(QRText.webURL("https://example.com/a?b=1")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertEqual(QRText.webURL("www.example.com")?.absoluteString, "https://www.example.com")
        XCTAssertNotNil(QRText.webURL("HTTPS://EXAMPLE.COM"))
        XCTAssertNil(QRText.webURL("WIFI:T:WPA;S:home;P:secret;;"))
        XCTAssertNil(QRText.webURL("javascript:alert(1)"))
        XCTAssertNil(QRText.webURL("mailto:a@example.com"))
        XCTAssertNil(QRText.webURL("ftp://example.com"))
        XCTAssertNil(QRText.webURL("https://user:pass@example.com"))
        XCTAssertNil(QRText.webURL("https://example.com 后面有字"))
        XCTAssertNil(QRText.webURL("https://"))
        XCTAssertNil(QRText.webURL("hello"))
        XCTAssertNil(QRText.webURL(""))
    }

    func testClipboardCheck() {
        XCTAssertEqual(QRText.check(nil), .empty)
        XCTAssertEqual(QRText.check("  \n "), .empty)
        XCTAssertEqual(QRText.check(" 你好 "), .ok("你好"))
        XCTAssertEqual(QRText.check(String(repeating: "a", count: QRText.maxBytes)), .ok(String(repeating: "a", count: QRText.maxBytes)))
        XCTAssertEqual(QRText.check(String(repeating: "a", count: QRText.maxBytes + 1)), .tooLong)
        // 一个汉字 3 字节。
        XCTAssertEqual(QRText.check(String(repeating: "码", count: 700)), .tooLong)
    }

    func testQRScaleIsWholeNumber() {
        XCTAssertEqual(QRText.scale(moduleSide: 23, target: 400), 17)
        XCTAssertEqual(QRText.scale(moduleSide: 400, target: 200), 1)
        XCTAssertEqual(QRText.scale(moduleSide: 0, target: 200), 1)
        XCTAssertEqual(QRText.scale(moduleSide: 25, target: .infinity), 1)
    }

    // MARK: 演示模式

    private func app(_ pid: Int32, regular: Bool = true, hidden: Bool = false, front: Bool = false,
                     me: Bool = false, finder: Bool = false) -> PresentationPlan.App {
        PresentationPlan.App(pid: pid, isRegular: regular, isHidden: hidden, isFrontmost: front,
                             isSelf: me, isFinder: finder)
    }

    func testEnterRemembersAndHidesOnlyVisibleOthers() {
        let apps = [app(1, front: true), app(2), app(3, hidden: true), app(4, regular: false),
                    app(5, me: true), app(6, finder: true)]
        let plan = PresentationPlan.enter(desktopHidden: false, keepAwake: false, apps: apps)
        XCTAssertEqual(plan.snapshot, PresentationSnapshot(desktopHidden: false, keepAwake: false,
                                                          hiddenApps: [2], hidFinder: true))
        XCTAssertEqual(plan.changes.setDesktopHidden, true)
        XCTAssertEqual(plan.changes.setKeepAwake, true)
        XCTAssertEqual(plan.changes.hide, [2])
        XCTAssertTrue(plan.changes.hideFinder)
    }

    func testEnterLeavesAlreadyOnSettingsAlone() {
        let plan = PresentationPlan.enter(desktopHidden: true, keepAwake: true, apps: [app(1, front: true)])
        XCTAssertNil(plan.changes.setDesktopHidden)
        XCTAssertNil(plan.changes.setKeepAwake)
        XCTAssertEqual(plan.changes.hide, [])
        XCTAssertFalse(plan.changes.hideFinder)
    }

    func testExitRestoresWhatItWasBefore() {
        let snapshot = PresentationSnapshot(desktopHidden: false, keepAwake: false, hiddenApps: [2, 7], hidFinder: true)
        // 2 还藏着，7 已经退出了，8 是用户自己藏的不算。
        let changes = PresentationPlan.exit(snapshot, desktopHidden: true, keepAwake: true,
                                            apps: [app(2, hidden: true), app(8, hidden: true)])
        XCTAssertEqual(changes.setDesktopHidden, false)
        XCTAssertEqual(changes.setKeepAwake, false)
        XCTAssertEqual(changes.unhide, [2])
        XCTAssertTrue(changes.unhideFinder)
    }

    func testExitKeepsUserChoicesThatWereAlreadyOn() {
        // 打开前桌面就隐藏、本来就保持唤醒：关掉演示模式后保持原样。
        let snapshot = PresentationSnapshot(desktopHidden: true, keepAwake: true)
        let changes = PresentationPlan.exit(snapshot, desktopHidden: true, keepAwake: true, apps: [])
        XCTAssertNil(changes.setDesktopHidden)
        XCTAssertNil(changes.setKeepAwake)
        XCTAssertEqual(changes.unhide, [])
        XCTAssertFalse(changes.unhideFinder)
    }

    func testExitDoesNotShowFinderTheUserAlreadyShowed() {
        let snapshot = PresentationSnapshot(desktopHidden: true, keepAwake: false, hidFinder: true)
        let changes = PresentationPlan.exit(snapshot, desktopHidden: true, keepAwake: false,
                                            apps: [app(9, finder: true)])
        XCTAssertFalse(changes.unhideFinder)
    }

    func testSnapshotRoundTripsAndReadsOlderData() throws {
        let snapshot = PresentationSnapshot(desktopHidden: true, keepAwake: false, hiddenApps: [3], hidFinder: true)
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(PresentationSnapshot.self, from: data), snapshot)
        let partial = Data(#"{"desktopHidden":true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PresentationSnapshot.self, from: partial),
                       PresentationSnapshot(desktopHidden: true, keepAwake: false))
    }

    // MARK: 只锁键盘

    func testKeyboardLockTiming() {
        XCTAssertEqual(KeyboardLockTiming.holdProgress(elapsed: 0), 0)
        XCTAssertEqual(KeyboardLockTiming.holdProgress(elapsed: 1.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(KeyboardLockTiming.holdProgress(elapsed: 10), 1)
        XCTAssertEqual(KeyboardLockTiming.holdProgress(elapsed: -.infinity), 0)
        XCTAssertEqual(KeyboardLockTiming.remainingText(600), "10:00 后自动解锁")
        XCTAssertEqual(KeyboardLockTiming.remainingText(64.2), "1:05 后自动解锁")
        XCTAssertEqual(KeyboardLockTiming.remainingText(-3), "0:00 后自动解锁")
    }

    // MARK: 低电量模式

    func testParsesPmset() {
        let output = """
        System-wide power settings:
        Currently in use:
         standby              1
         lowpowermode         1
         sleep                1 (sleep prevented by coreaudiod)
        """
        XCTAssertEqual(LowPowerSetting.parse(output), LowPowerSetting.Reading(key: "lowpowermode", isOn: true))
        XCTAssertEqual(LowPowerSetting.parse(" lowpowermode\t0\n"), LowPowerSetting.Reading(key: "lowpowermode", isOn: false))
        XCTAssertEqual(LowPowerSetting.parse(" powermode            1\n"), LowPowerSetting.Reading(key: "powermode", isOn: true))
        XCTAssertEqual(LowPowerSetting.parse(" powermode            2\n"), LowPowerSetting.Reading(key: "powermode", isOn: false))
        XCTAssertEqual(LowPowerSetting.parse(" powermode 0\n lowpowermode 1\n")?.key, "lowpowermode")
        XCTAssertNil(LowPowerSetting.parse(" sleep 1\n displaysleep 10\n"))
        XCTAssertNil(LowPowerSetting.parse(""))
    }

    func testPmsetCommandOnlyForKnownKeys() {
        XCTAssertEqual(LowPowerSetting.command(key: "lowpowermode", on: true), "/usr/bin/pmset -a lowpowermode 1")
        XCTAssertEqual(LowPowerSetting.command(key: "powermode", on: false), "/usr/bin/pmset -a powermode 0")
        XCTAssertNil(LowPowerSetting.command(key: "sleep; rm -rf /", on: true))
    }
}
