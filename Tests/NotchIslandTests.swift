import XCTest

/// 刘海小岛的纯逻辑：设置、活动栈和优先级、形态、什么时候不显示、下载的空档和打勾、
/// 计时器、文字、几何。
final class NotchIslandTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: 设置

    func testSettingsDefaultsOffWithEveryKind() {
        let settings = NotchIslandSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertEqual(settings.kinds, NotchIslandKind.allCases)
        XCTAssertEqual(NotchIslandKind.allCases, [.charging, .download, .timer, .radio], "顺序就是优先级")
        XCTAssertEqual(Set(NotchIslandKind.settingsOrder), Set(NotchIslandKind.allCases))
        XCTAssertEqual(NotchIslandKind.settingsOrder.count, 4)
    }

    func testSetKeepsFixedOrder() {
        var settings = NotchIslandSettings()
        settings.set(.download, false)
        settings.set(.charging, false)
        XCTAssertEqual(settings.kinds, [.timer, .radio])
        settings.set(.charging, true)
        settings.set(.download, true)
        XCTAssertEqual(settings.kinds, [.charging, .download, .timer, .radio])
        settings.set(.radio, true)
        XCTAssertEqual(settings.kinds.count, 4, "重复打开不重复存")
    }

    func testSettingsDecodeLeniently() throws {
        var settings = NotchIslandSettings()
        settings.enabled = true
        settings.set(.radio, false)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(NotchIslandSettings.self, from: data), settings)

        let future = Data(#"{"enabled":true,"kinds":["radio","weather","timer"]}"#.utf8)
        let decoded = try JSONDecoder().decode(NotchIslandSettings.self, from: future)
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.kinds, [.timer, .radio], "认不出的活动丢掉，其余按固定顺序")

        let empty = try JSONDecoder().decode(NotchIslandSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, NotchIslandSettings())
    }

    func testPersistedStateCarriesSettings() throws {
        var state = PersistedState()
        state.notchIsland.enabled = true
        state.notchIsland.set(.charging, false)
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.notchIsland, state.notchIsland)
        let legacy = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.notchIsland.enabled, "老状态文件没有这一组：默认关")
    }

    func testProGate() {
        var settings = NotchIslandSettings()
        XCTAssertFalse(ProLicenseGate.notchIslandActive(settings, unlocked: true), "默认关")
        settings.enabled = true
        XCTAssertTrue(ProLicenseGate.notchIslandActive(settings, unlocked: true))
        XCTAssertFalse(ProLicenseGate.notchIslandActive(settings, unlocked: false), "没解锁不生效，设置留着")
        XCTAssertTrue(settings.enabled)
        settings.kinds = []
        XCTAssertFalse(ProLicenseGate.notchIslandActive(settings, unlocked: true), "一种都没勾也不显示")
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.notchIsland))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.notchIsland)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.notchIsland)), "刘海小岛")
    }

    // MARK: 活动栈

    private var radio: NotchIslandActivity { .radio(station: "Lo-fi 电台", playing: true) }
    private var timer: NotchIslandActivity {
        .timer(deadline: now.addingTimeInterval(1498), pausedLeft: nil, total: 1500, focus: true)
    }
    private var download: NotchIslandActivity { .download(fraction: 0.6, done: false) }
    private var charging: NotchIslandActivity { .charging(percent: 80) }

    func testPriorityOrder() {
        var settings = NotchIslandSettings()
        settings.enabled = true
        let ordered = NotchIslandStack.ordered([radio, timer, download, charging], settings: settings)
        XCTAssertEqual(ordered.map(\.kind), [.charging, .download, .timer, .radio])
        XCTAssertTrue(NotchIslandKind.charging.priority < NotchIslandKind.download.priority)
        XCTAssertTrue(NotchIslandKind.download.priority < NotchIslandKind.timer.priority)
        XCTAssertTrue(NotchIslandKind.timer.priority < NotchIslandKind.radio.priority)
    }

    func testOrderedFiltersBySettingsAndDedupes() {
        var settings = NotchIslandSettings()
        settings.set(.download, false)
        let ordered = NotchIslandStack.ordered(
            [radio, download, .radio(station: "别的台", playing: true), timer], settings: settings)
        XCTAssertEqual(ordered, [timer, radio], "没勾的不显示，同一种只留先来的")
    }

    func testFormSelection() {
        let settings = NotchIslandSettings()
        XCTAssertNil(NotchIslandStack.form([], settings: settings, hovering: false))
        XCTAssertNil(NotchIslandStack.form([], settings: settings, hovering: true), "没有活动时悬停也不展开")
        XCTAssertEqual(NotchIslandStack.form([radio], settings: settings, hovering: false), .compact(radio))
        XCTAssertEqual(NotchIslandStack.form([radio, timer], settings: settings, hovering: false), .split(timer, radio))
        XCTAssertEqual(NotchIslandStack.form([radio, timer, download], settings: settings, hovering: false),
                       .split(download, timer), "最多两个：主岛加一个小圆岛")
        XCTAssertEqual(NotchIslandStack.form([radio, timer], settings: settings, hovering: true),
                       .expanded(timer, secondary: radio))
        XCTAssertEqual(NotchIslandStack.form([radio], settings: settings, hovering: true),
                       .expanded(radio, secondary: nil))
        XCTAssertEqual(NotchIslandStack.maxShown, 2)
    }

    func testFormAccessors() {
        let split = NotchIslandForm.split(timer, radio)
        XCTAssertEqual(split.primary, timer)
        XCTAssertEqual(split.secondary, radio)
        XCTAssertFalse(split.isExpanded)
        XCTAssertNil(NotchIslandForm.compact(radio).secondary)
        XCTAssertTrue(NotchIslandForm.expanded(radio, secondary: nil).isExpanded)
    }

    // MARK: 什么时候不显示

    func testGate() {
        XCTAssertTrue(NotchIslandGate.visible(.init(active: true)))
        XCTAssertFalse(NotchIslandGate.visible(.init(active: false)))
        XCTAssertFalse(NotchIslandGate.visible(.init(active: true, presenting: true)), "演示模式")
        XCTAssertFalse(NotchIslandGate.visible(.init(active: true, fullscreen: true)), "全屏 App")
        XCTAssertFalse(NotchIslandGate.visible(.init(active: true, messageCard: true)), "消息卡弹出时让位")
        XCTAssertFalse(NotchIslandGate.visible(.init(active: true, plugAnimation: true)), "插电动画播放时让开")
    }

    // MARK: 下载

    func testCombinedProgress() {
        XCTAssertNil(NotchIslandDownloadTracker.combined([]))
        XCTAssertEqual(NotchIslandDownloadTracker.combined([0.2, 0.6])!, 0.4, accuracy: 0.0001)
        XCTAssertNil(NotchIslandDownloadTracker.combined([0.2, nil]), "有一个不知道进度就转圈")
        XCTAssertEqual(NotchIslandDownloadTracker.combined([1.5])!, 1, accuracy: 0.0001)
    }

    func testDownloadLifecycle() {
        var tracker = NotchIslandDownloadTracker()
        XCTAssertNil(tracker.activity(now: now))
        tracker.progress([0.6], now: now)
        XCTAssertEqual(tracker.activity(now: now), .download(fraction: 0.6, done: false))
        XCTAssertFalse(tracker.pending)

        // 未完成的文件改名了，还没确认下好：继续显示，不闪掉。
        let gap = now.addingTimeInterval(1)
        tracker.progress([], now: gap)
        XCTAssertEqual(tracker.activity(now: gap), .download(fraction: 0.99, done: false))
        XCTAssertTrue(tracker.pending)

        // 确认下好：打勾 2 秒后收起。
        let done = now.addingTimeInterval(3)
        tracker.finished(now: done)
        XCTAssertEqual(tracker.activity(now: done), .download(fraction: 1, done: true))
        let later = done.addingTimeInterval(NotchIslandTiming.downloadDoneLinger)
        XCTAssertNil(tracker.activity(now: later))
        tracker.tick(now: later)
        XCTAssertFalse(tracker.pending)
    }

    func testDownloadWithoutProgressSpins() {
        var tracker = NotchIslandDownloadTracker()
        tracker.progress([nil], now: now)
        XCTAssertEqual(tracker.activity(now: now), .download(fraction: nil, done: false))
        // 空档里也不编进度。
        tracker.progress([], now: now)
        XCTAssertEqual(tracker.activity(now: now), .download(fraction: nil, done: false))
    }

    func testDownloadGapGivesUpWithoutFinish() {
        var tracker = NotchIslandDownloadTracker()
        tracker.progress([0.3], now: now)
        tracker.progress([], now: now)
        let late = now.addingTimeInterval(NotchIslandTiming.downloadSettleGrace)
        XCTAssertNil(tracker.activity(now: late), "取消或失败的下载：空档过了就收起")
        tracker.tick(now: late)
        XCTAssertFalse(tracker.pending)
        XCTAssertNil(tracker.activity(now: late))
    }

    func testFinishedWithoutSeeingProgress() {
        var tracker = NotchIslandDownloadTracker()
        tracker.finished(now: now)
        XCTAssertEqual(tracker.activity(now: now), .download(fraction: 1, done: true), "下得太快没看到进度也打勾")
    }

    // MARK: 计时器

    func testTimerActivity() {
        var state = TimerState()
        XCTAssertNil(NotchIslandTimer.activity(state, now: now), "没开始不显示")
        state.duration = 1500
        state.deadline = now.addingTimeInterval(600)
        XCTAssertEqual(NotchIslandTimer.activity(state, now: now),
                       .timer(deadline: now.addingTimeInterval(600), pausedLeft: nil, total: 1500, focus: true))
        state.deadline = now.addingTimeInterval(-1)
        XCTAssertNil(NotchIslandTimer.activity(state, now: now), "到点等下一步时不显示")
        state.deadline = nil
        state.paused = 300
        XCTAssertEqual(NotchIslandTimer.activity(state, now: now),
                       .timer(deadline: nil, pausedLeft: 300, total: 1500, focus: true))
        state.phase = .rest
        if case .timer(_, _, _, let focus)? = NotchIslandTimer.activity(state, now: now) {
            XCTAssertFalse(focus)
        } else {
            XCTFail("休息暂停中也显示")
        }
    }

    func testTimerToggleAndEnd() {
        var state = TimerState()
        state.duration = 1500
        state.deadline = now.addingTimeInterval(600)
        let paused = NotchIslandTimer.toggled(state, now: now)
        XCTAssertNil(paused.deadline)
        XCTAssertEqual(paused.paused ?? -1, 600, accuracy: 0.001)

        let resumed = NotchIslandTimer.toggled(paused, now: now.addingTimeInterval(50))
        XCTAssertNil(resumed.paused)
        XCTAssertEqual(resumed.deadline, now.addingTimeInterval(650))
        XCTAssertEqual(resumed.duration, 1500)

        let ended = NotchIslandTimer.ended(resumed)
        XCTAssertNil(ended.deadline)
        XCTAssertNil(ended.paused)
        XCTAssertNil(ended.duration)
        XCTAssertNil(NotchIslandTimer.activity(ended, now: now), "结束后小岛上就没有计时器了")
    }

    func testTimerRemainingAndFraction() {
        XCTAssertEqual(NotchIslandTimer.remaining(deadline: now.addingTimeInterval(90), pausedLeft: nil, now: now), 90)
        XCTAssertEqual(NotchIslandTimer.remaining(deadline: nil, pausedLeft: 42, now: now), 42)
        XCTAssertEqual(NotchIslandTimer.remaining(deadline: now.addingTimeInterval(-5), pausedLeft: nil, now: now), 0)
        XCTAssertEqual(NotchIslandTimer.elapsedFraction(remaining: 750, total: 1500), 0.5, accuracy: 0.0001)
        XCTAssertEqual(NotchIslandTimer.elapsedFraction(remaining: 2000, total: 1500), 0)
        XCTAssertEqual(NotchIslandTimer.elapsedFraction(remaining: 10, total: 0), 0)
    }

    // MARK: 文字

    func testText() {
        XCTAssertEqual(NotchIslandText.clock(1498), "24:58")
        XCTAssertEqual(NotchIslandText.clock(0.2), "0:01", "最后不到一秒还写 0:01")
        XCTAssertEqual(NotchIslandText.clock(0), "0:00")
        XCTAssertEqual(NotchIslandText.clock(3723), "1:02:03")
        XCTAssertEqual(NotchIslandText.percent(0.6), "60%")
        XCTAssertEqual(NotchIslandText.percent(0.999), "99%", "没下完不写 100%")
        XCTAssertEqual(NotchIslandText.percent(.nan), "0%")
        XCTAssertEqual(NotchIslandText.battery(80), "80%")
        XCTAssertEqual(NotchIslandText.battery(130), "100%")
        XCTAssertFalse(NotchIslandText.spoken(radio, now: now).isEmpty)
    }

    // MARK: 几何

    private let notched = AINotchScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                        notch: CGRect(x: 662, y: 950, width: 188, height: 32),
                                        menuBarHeight: 32, isMain: true)
    private let plain = AINotchScreen(id: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      notch: nil, menuBarHeight: 25, isMain: true)

    func testGeometryUsesNotchOrSimulatesOne() {
        let real = NotchIslandLayout.geometry(screen: notched)
        XCTAssertEqual(real, NotchIslandGeometry(notchWidth: 188, notchHeight: 32, hasNotch: true))
        XCTAssertEqual(NotchIslandLayout.centerX(screen: notched), 756)

        let fake = NotchIslandLayout.geometry(screen: plain)
        XCTAssertFalse(fake.hasNotch)
        XCTAssertEqual(fake.notchWidth, NotchIslandLayout.simulatedNotchWidth)
        XCTAssertEqual(fake.notchHeight, 25, "按菜单栏高度")
        XCTAssertEqual(NotchIslandLayout.centerX(screen: plain), 960, "顶部居中")
    }

    func testBodyGrowsFromBothSidesOfTheNotch() {
        let geometry = NotchIslandLayout.geometry(screen: notched)
        let notch = NotchIslandLayout.notch(geometry)
        for activity in [radio, download, charging, timer] {
            let body = NotchIslandLayout.body(geometry, activity)
            XCTAssertEqual(body.minY, 0, "顶边贴住屏幕顶边，和刘海连成一体")
            XCTAssertTrue(body.contains(notch), "\(activity) 的主岛盖住整段刘海")
            XCTAssertLessThan(body.minX, notch.minX)
            XCTAssertGreaterThan(body.maxX, notch.maxX)
        }
        XCTAssertEqual(NotchIslandLayout.body(geometry, timer).height, 32 + NotchIslandLayout.chinHeight,
                       "计时器在刘海下方多一条显示剩余时间")
        XCTAssertEqual(NotchIslandLayout.body(geometry, radio).height, 32)
    }

    func testBubbleSitsRightOfTheBody() {
        let geometry = NotchIslandLayout.geometry(screen: notched)
        let body = NotchIslandLayout.body(geometry, timer)
        let bubble = NotchIslandLayout.bubble(geometry, body: body)
        XCTAssertEqual(bubble.minX, body.maxX + NotchIslandLayout.bubbleGap)
        XCTAssertEqual(bubble.width, bubble.height)
        XCTAssertGreaterThanOrEqual(bubble.minY, 0)
        XCTAssertLessThanOrEqual(bubble.maxY, geometry.notchHeight)
    }

    func testPiecesPerForm() {
        let geometry = NotchIslandLayout.geometry(screen: notched)
        XCTAssertEqual(NotchIslandLayout.pieces(geometry, form: .compact(radio)).count, 1)
        XCTAssertEqual(NotchIslandLayout.pieces(geometry, form: .compact(charging)).count, 2, "插电带小熊猫")
        XCTAssertEqual(NotchIslandLayout.pieces(geometry, form: .split(timer, radio)).count, 2)
        let card = NotchIslandLayout.pieces(geometry, form: .expanded(radio, secondary: timer))
        XCTAssertEqual(card.count, 1)
        XCTAssertEqual(card[0].minY, 0)
        XCTAssertEqual(card[0].midX, 0, accuracy: 0.001, "卡片以刘海中线对称")
        XCTAssertGreaterThan(card[0].width, geometry.notchWidth)
        XCTAssertEqual(NotchIslandLayout.card(geometry, kind: .radio, hasSecondary: true).height
                       - NotchIslandLayout.card(geometry, kind: .radio, hasSecondary: false).height,
                       NotchIslandLayout.secondaryRowHeight)
    }

    func testHotZoneCoversWhatIsDrawn() {
        let geometry = NotchIslandLayout.geometry(screen: notched)
        let form = NotchIslandForm.split(download, radio)
        let zone = NotchIslandLayout.hotZone(geometry, form: form)
        for piece in NotchIslandLayout.pieces(geometry, form: form) {
            XCTAssertTrue(zone.contains(piece))
        }
    }

    func testWindowIsSymmetricAndTopAnchored() {
        let geometry = NotchIslandLayout.geometry(screen: notched)
        let pieces = NotchIslandLayout.pieces(geometry, form: .split(download, radio))
        let extent = NotchIslandLayout.extent(pieces)
        let frame = NotchIslandLayout.windowFrame(centerX: 756, screenTop: 982,
                                                  halfWidth: extent.halfWidth, height: extent.height)
        XCTAssertEqual(frame.midX, 756, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 982, accuracy: 0.001)
        // 每块都在窗口里。
        for piece in pieces {
            let onScreen = NotchIslandLayout.screenRect(piece, centerX: 756, screenTop: 982)
            XCTAssertTrue(frame.contains(onScreen))
        }
        let body = NotchIslandLayout.body(geometry, download)
        let onScreen = NotchIslandLayout.screenRect(body, centerX: 756, screenTop: 982)
        XCTAssertEqual(onScreen.maxY, 982)
        XCTAssertEqual(onScreen.minY, 982 - body.height)
    }

    // MARK: 动画

    func testMotion() {
        XCTAssertEqual(NotchIslandMotion.expandResponse, 0.35, accuracy: 0.001)
        XCTAssertEqual(NotchIslandMotion.expandDamping, 0.8, accuracy: 0.001)
        XCTAssertTrue(NotchIslandMotion.springs(reduceMotion: false))
        XCTAssertFalse(NotchIslandMotion.springs(reduceMotion: true), "减弱动态效果时不放弹簧")
        XCTAssertEqual(NotchIslandTiming.chargeLinger, 4)
        XCTAssertEqual(NotchIslandTiming.downloadDoneLinger, 2)
    }
}
