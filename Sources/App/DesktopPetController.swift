import AppKit
import Observation
import QuartzCore
import SwiftUI

/// 桌面宠物：小熊猫贴在程序坞上沿散步，或者蜷在屏幕某条边上，也可以拖到任意位置。
///
/// 窗口：一个和小熊猫差不多大的透明小窗口跟着它走（不再是铺满程序坞上方的大窗口
/// 再按 8 帧一次切换“接不接鼠标”）。窗口从不设置 ignoresMouseEvents，透明的地方
/// 点击由系统直接穿透到后面，小熊猫身上的点击由 `DesktopPetSpriteView` 自己的
/// mouseDown / mouseDragged / mouseUp 接住：没挪动是单击（跳一下、浮出快捷条），
/// 挪动超过 4 点是拖动，松手吸到最近的屏幕边缘（设成「随意」时停在松手的地方），
/// 停靠位置和位置写回设置。右键是菜单。
///
/// 画面：小熊猫是一个 CALayer（图片、晃动、缩放、翻转都在图层上改，不经过 SwiftUI），
/// 图一直正着画：屏幕上边缘前爪抓着菜单栏下沿吊着轻晃，左右边缘正着趴、身子一半藏在屏幕边外
/// （窗口不伸出那条边，伸出去的那块由视图裁掉），
/// 位置和缩放在动的时候按显示刷新（`NSView.displayLink`，60 帧）算，窗口原点取整、
/// 不足一点的部分放进图层位置，走得再慢也不一格一格跳；动作帧单独按 10~12 帧换。
/// 静止（坐着、趴着）时显示刷新停掉，只留每秒 10 次的计时器换眨眼这种帧，睡着时
/// 每秒 2 次。
///
/// 每 1.5 秒看一次程序坞在哪、要不要显示（读程序坞在后台队列），顺便看专注计时、
/// 收音机、电池有没有要说的，用头顶气泡说一句（同类 30 秒一次）。全屏 App 在前、
/// 屏幕睡了时不显示。
///
/// 废纸篓救回（单独的开关）：刚拖进废纸篓的文件，小熊猫跑到废纸篓叼着跑回来，请访达
/// 放回原处；访达不让时弹「放回原处」的气泡按钮。不在程序坞上时不跑，直接放回。
/// 专注陪伴（码头 Pro）：专注计时走着时坐着不乱跑，完成一轮欢呼。
@MainActor
final class DesktopPetController: NSObject {
    static let shared = DesktopPetController()

    private var settings = DesktopPetSettings()
    /// 扩展栏贴在哪条边（浮动的按朝向），启动时由 App 接上。
    var shelfPosition: @MainActor () -> DockPosition? = { nil }
    /// 小熊猫自己改了设置（拖到新位置、右键菜单换大小、停靠位置、隐藏），写回状态文件。
    var onSettingsChange: (@MainActor (DesktopPetSettings) -> Void)?
    /// 打开设置 ▸ 小组件。
    var openSettings: (@MainActor () -> Void)?

    private var panel: NSPanel?
    private var spriteView: DesktopPetSpriteView?
    private var displayLink: CADisplayLink?
    private var restingTimer: Timer?
    private var restingRate: Double = 0
    private var geometryTimer: Timer?
    private var lastStep = Date()
    private var reading = false
    private var screensAsleep = false
    private var wakeObservers: [NSObjectProtocol] = []
    /// 显示器插拔、改分辨率（默认通知中心），换桌面、进出全屏 App（工作区通知中心）。
    private var screenObservers: [(NotificationCenter, NSObjectProtocol)] = []

    private var track: DesktopPetTrack?
    private var trackScreen: NSScreen?
    private var trackKey = ""
    private var perch: DesktopPetPerch?
    private var dockRect: CGRect?
    private var state: DesktopPetState?
    private var lastTimer: TimerState?
    private var shown = false

    // 拖动
    private var pressPoint: CGPoint?
    private var dragging = false
    private var dragFeet = CGPoint.zero
    private var grabOffset = CGPoint.zero
    private var lastDragX: CGFloat = 0
    /// 从哪儿滑到哪儿：拖起来、松手吸过去时的短过渡。
    private var transit: (feet: CGPoint, start: Date, duration: TimeInterval)?
    /// 上一帧画在哪：过渡从这里开始。
    private var drawnFeet = CGPoint.zero
    private var drawnCenter = CGPoint.zero
    private var drawnSize = CGSize(width: 50, height: 50)
    /// 上一帧屏幕上看得见的那块（左右边藏到屏幕外的不算），悬停、气泡、快捷条按它算。
    private var drawnRect = CGRect(x: 0, y: 0, width: 50, height: 50)
    private var drawnFlip = false

    // 气泡和快捷条
    private let bubble = DesktopPetBubbleModel()
    private var bubblePanel: NSPanel?
    private var bubbleHost: NSHostingView<DesktopPetBubbleView>?
    private var bubbleClick: DesktopPetClickView?
    private let bar = DesktopPetQuickBarModel()
    private var barPanel: NSPanel?
    private var barVisibleUntil: Date?
    private var barHovering = false
    private var petHovering = false
    private var gate = DesktopPetBubbleGate()
    private var lastNewsCheck = Date()
    private var lastPower: DesktopPetPower?
    private var radioWasPlaying = false
    private var radioStation: String?
    private var newsPrimed = false

    // 废纸篓救回
    private var seen: Set<String> = []
    private var seeded = false
    private var lastTrashCount = 0
    private var rescuing: [TrashedItem] = []
    private var putBackInFlight = false
    private var trashSource: DispatchSourceFileSystemObject?
    private var autoPutBack = true

    // 状态助手：没站稳时排队的事、正在办的一趟、到了以后的「有待查看」。
    private var assistQueue: [DesktopPetEvent] = []
    private var errand: DesktopPetErrand?
    private var review: DesktopPetReview?
    /// 离开、回来，和离开期间先记下不演的事。
    private var awayLog = DesktopPetAwayLog()
    /// 锁屏、屏保、休眠、切换用户的通知（离开的判断用）。
    private var awayObservers: [(NotificationCenter, NSObjectProtocol)] = []
    /// 上一次有人理小熊猫（鼠标靠近、点、拖、松手、来了事）：吊着没人理约 20 秒打盹。
    private var lastTouch = Date()
    /// 上一次鼠标在小熊猫（或快捷条）上、被点、来了事：抱树爬出来以后约 5 秒没人理就缩回去。
    private var lastPet = Date()
    /// 连戳、摸头、经过、靠近头这些小互动的冷却。
    private var mood = DesktopPetMood()
    /// 上一帧指针在哪、什么时候：算鼠标移动速度（经过时抬头看）。
    private var lastPointer: (point: CGPoint, at: Date)?
    /// 上一帧是不是睡着、刚出现：每天第一次唤醒或出现时伸懒腰说「早」。
    private var wasAsleep = false
    private var justShown = false
    private static let greetedKey = "DesktopPetGreetedDay"

    // 有用的三件事：活动提醒、下载完成、拖文件到身上暂存（见 DesktopPetWatchers.swift）。
    private var stretchClock = DesktopPetStretchClock()
    private var downloads: DesktopPetDownloadsWatcher { .shared }
    /// 正叼着跑的那一批下载、刚报过的那一批（3 秒内合并）、到了以后单击在访达中显示的那些。
    private var fetching: DesktopPetDownloads?
    private var recentDownloads: DesktopPetDownloads?
    private var downloadReview: (paths: [String], until: Date)?

    /// 窗口边长（中号）：放得下最宽的跑步帧压扁、拖着晃的时候。
    static let windowSide: CGFloat = 132

    private override init() { super.init() }

    // MARK: 开关

    func apply(_ next: DesktopPetSettings) {
        let before = settings
        settings = next
        DesktopPetHotKey.shared.onPress = { DesktopPetController.shared.summon() }
        DesktopPetHotKey.shared.update(next.enabled ? next.hotKey : nil)
        if next.enabled {
            start()
            if next.anchor != before.anchor || next.size != before.size || next.spot != before.spot {
                refreshPlacement()
            }
            if !next.bubbles, bubble.content?.isNews == true { setBubble(nil) }
        } else {
            stop()
        }
        if next.rescueActive != before.rescueActive || (next.rescueActive && trashSource == nil) {
            next.rescueActive ? startRescueWatch() : stopRescueWatch()
        }
        updateDownloadWatch()
        if !next.stretchReminder { stretchClock = DesktopPetStretchClock() }
    }

    /// 下载完成提示：总开关和子开关都开着才看下载文件夹。
    private func updateDownloadWatch() {
        if settings.enabled, settings.downloadNotice {
            downloads.start { paths in DesktopPetController.shared.handle(.downloadFinished(paths: paths)) }
        } else {
            downloads.stop()
        }
    }

    /// 小熊猫这边改了设置：先记下（再收到同样的设置时不重复处理），再写回状态文件。
    private func save(_ change: (inout DesktopPetSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let before = settings
        settings = next
        onSettingsChange?(next)
        if next.anchor != before.anchor || next.size != before.size { refreshPlacement() }
        if !next.enabled { stop() }
    }

    private func start() {
        guard geometryTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                DesktopPetController.shared.refreshPlacement()
                DesktopPetController.shared.checkStretch()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        geometryTimer = timer
        observeSleep()
        newsPrimed = false
        refreshPlacement()
    }

    private func stop() {
        geometryTimer?.invalidate()
        geometryTimer = nil
        stopClocks()
        stopRescueWatch()
        downloads.stop()
        stretchClock = DesktopPetStretchClock()
        fetching = nil
        recentDownloads = nil
        downloadReview = nil
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
        for (center, observer) in screenObservers { center.removeObserver(observer) }
        screenObservers = []
        for (center, observer) in awayObservers { center.removeObserver(observer) }
        awayObservers = []
        awayLog = DesktopPetAwayLog()
        panel?.orderOut(nil)
        bubblePanel?.orderOut(nil)
        barPanel?.orderOut(nil)
        displayLink?.invalidate()
        displayLink = nil
        panel = nil
        spriteView = nil
        track = nil
        trackKey = ""
        perch = nil
        state = nil
        lastTimer = nil
        shown = false
        dragging = false
        pressPoint = nil
        transit = nil
        assistQueue = []
        errand = nil
        review = nil
        bubble.content = nil
        barVisibleUntil = nil
    }

    /// 屏幕睡了就全停，醒了再接着看。
    private func observeSleep() {
        guard wakeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        wakeObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let pet = DesktopPetController.shared
                pet.screensAsleep = true
                pet.stopClocks()
                pet.feedAway(.blocked(.displayOff))
            }
        })
        wakeObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let pet = DesktopPetController.shared
                pet.screensAsleep = false
                pet.lastStep = Date()
                pet.feedAway(.unblocked(.displayOff))
                pet.refreshPlacement()
            }
        })
        observeAway()
        // 显示器插拔、换桌面时马上重新看一次，不等 1.5 秒一次的轮询（拔掉的屏幕上不留残影，
        // 切进全屏 App 时尽快藏起来）。
        guard screenObservers.isEmpty else { return }
        let refresh: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { DesktopPetController.shared.refreshPlacement() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        screenObservers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main,
            using: refresh)))
        screenObservers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: refresh)))
    }

    // MARK: 停在哪

    private func refreshPlacement() {
        guard settings.enabled, !screensAsleep, !reading else { return }
        reading = true
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let screen = targetScreen()?.frame
        DesktopPetDockReader.queue.async {
            let reading = DesktopPetDockReader.shared.read(primaryHeight: primaryHeight,
                                                           frontPID: frontPID, screen: screen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DesktopPetController.shared.placed(reading) }
            }
        }
    }

    /// 要待的那块屏幕：程序坞上沿跟程序坞；其余按记住的屏幕，找不到用主屏。
    private func targetScreen() -> NSScreen? {
        if settings.anchor == .dock, let perch {
            return NSScreen.screens.first { $0.frame.intersects(perch.frame) } ?? NSScreen.screens.first
        }
        if let display = settings.spot?.display,
           let screen = NSScreen.screens.first(where: { Self.displayID($0) == display }) {
            return screen
        }
        return NSScreen.screens.first
    }

    static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// 小熊猫沿边占多长（算两头留多少）。
    private var petLength: Double { 56 * settings.size.scale }

    private func placed(_ reading: DesktopPetDockReading) {
        self.reading = false
        guard settings.enabled else { return }
        let dock = SystemDockSettings.shared
        var systemFrame = reading.frame
        if systemFrame == nil, let screen = NSScreen.screens.first {
            systemFrame = DesktopPetPlacement.estimatedDock(screen: screen.frame, visible: screen.visibleFrame,
                                                            tileSize: dock.tileSize,
                                                            tiles: dock.pinnedApps.count + 3)
        }
        let system = DesktopPetPlacement.SystemDock(frame: systemFrame, trashX: reading.trashX,
                                                    atBottom: dock.position == .bottom, autoHide: dock.autoHide)
        let presence = ShelfPresence.shared
        let shelfShown = presence.isShown()
        // 窗口顶上留给图标放大和弹跳的空白要去掉，小熊猫才踩在玻璃条上。
        var shelfFrame = shelfShown ? presence.revealedFrame() : nil
        if var frame = shelfFrame, shelfPosition() == .bottom {
            frame.size.height = max(0, frame.height - presence.headroom)
            shelfFrame = frame
        }
        let shelf = DesktopPetPlacement.Shelf(frame: shelfFrame,
                                              atBottom: shelfPosition() == .bottom,
                                              tucked: shelfShown && presence.isTuckedAway())
        perch = DesktopPetPlacement.perch(system: system, shelf: shelf, fullScreen: false)
        dockRect = perch?.frame

        var next: DesktopPetTrack?
        var screen: NSScreen?
        if !reading.fullScreen {
            if settings.anchor == .dock, let perch {
                next = DesktopPetTracks.dock(perch)
                screen = NSScreen.screens.first { $0.frame.intersects(perch.frame) } ?? NSScreen.screens.first
            } else {
                // 程序坞上沿但程序坞这会儿看不见（自动隐藏、在侧边）：先蜷在屏幕下边缘。
                let anchor: DesktopPetAnchor = settings.anchor == .dock ? .bottom : settings.anchor
                screen = targetScreen()
                if let screen {
                    next = DesktopPetTracks.edge(anchor, visible: screen.visibleFrame, length: petLength,
                                                 spot: settings.spot)
                }
            }
        }
        checkTrash()
        // 离开的判断：每 1.5 秒看一次系统空闲（动画那边离开着时每帧也看）。
        feedAway(.idle(Self.userIdleSeconds()))
        guard let next, let screen else {
            hide()
            return
        }
        adopt(next, screen: screen)
        show()
        checkNews()
    }

    /// 换了边（停靠位置、屏幕、大小）：按记住的位置重新放；只是程序坞挪了一点就夹回范围里。
    private func adopt(_ next: DesktopPetTrack, screen: NSScreen) {
        let key = "\(next.edge)-\(next.style)-\(Self.displayID(screen) ?? 0)-\(settings.size.rawValue)"
        let now = Date()
        trackScreen = screen
        if state == nil || key != trackKey {
            let along: Double
            if next.style == .stroll {
                along = state.map { DesktopPetBrain.clamp($0.x, next.lane) }
                    ?? DesktopPetBrain.initial(lane: next.lane, now: now).x
            } else {
                along = next.along(fraction: settings.spot?.along ?? (next.edge.vertical ? 0.3 : 0.75))
            }
            if dragging || transit != nil, var current = state {
                current.x = along
                state = current
            } else if let current = state, shown {
                // 已经在别处：滑过去再落下。
                transit = (drawnFeet, now, DesktopPetSnap.glideDuration)
                state = DesktopPetBrain.landed(current, at: along, now: now, style: next.style)
            } else {
                state = next.style == .stroll && state == nil
                    ? DesktopPetBrain.initial(lane: next.lane, now: now)
                    : DesktopPetBrain.placed(at: along, style: next.style, now: now)
            }
            trackKey = key
            lastStep = now
        }
        track = next
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        render(now: Date())
        if !panel.isVisible { panel.orderFrontRegardless() }
        let wasShown = shown
        shown = true
        if !wasShown { justShown = true }
        // 藏着（全屏 App、屏幕睡了）时留下的气泡（「放回原处」按钮、Zzz）出来时一起出来；
        // 已经过时的交给下一帧收掉。
        if !wasShown, let content = bubble.content, let bubblePanel, !bubblePanel.isVisible,
           content.until.map({ $0 > Date() }) ?? true {
            bubblePanel.orderFrontRegardless()
            positionFloats()
        }
        updateClock(now: Date())
    }

    private func hide() {
        stopClocks()
        panel?.orderOut(nil)
        bubblePanel?.orderOut(nil)
        barPanel?.orderOut(nil)
        shown = false
        dragging = false
        pressPoint = nil
        transit = nil
        // 藏着时错过的变化（全屏里插了电）出来以后不补说。
        newsPrimed = false
    }

    // MARK: 时钟

    /// 动的时候开显示刷新，静止时停掉，只留慢计时器。
    private func updateClock(now: Date) {
        // 屏幕睡着时别的地方（喝水提醒、救回结果、快捷键）也可能来画一帧，不重新开时钟。
        guard shown, !screensAsleep, let state else { return stopClocks() }
        let moving = dragging || transit != nil || DesktopPetBrain.isMoving(state, now: now)
        if moving {
            restingTimer?.invalidate()
            restingTimer = nil
            restingRate = 0
            if displayLink == nil, let view = spriteView {
                let link = view.displayLink(target: self, selector: #selector(displayFrame(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            displayLink?.isPaused = false
        } else {
            displayLink?.isPaused = true
            let rate = DesktopPetBrain.tickRate(state, style: track?.style ?? .stroll)
            guard restingTimer == nil || restingRate != rate else { return }
            restingTimer?.invalidate()
            restingRate = rate
            let timer = Timer(timeInterval: 1 / rate, repeats: true) { _ in
                MainActor.assumeIsolated { DesktopPetController.shared.advance() }
            }
            timer.tolerance = 0.2 / rate
            RunLoop.main.add(timer, forMode: .common)
            restingTimer = timer
        }
    }

    private func stopClocks() {
        restingTimer?.invalidate()
        restingTimer = nil
        restingRate = 0
        displayLink?.isPaused = true
    }

    @objc private func displayFrame(_ link: CADisplayLink) {
        advance()
    }

    // MARK: 状态助手

    /// 码头里发生了一件事（文件暂存成功、专注完成、离开回来、暂存到期）：离开着时先记下，
    /// 回来再合并成一条；否则交给 `DesktopPetDirector` 决定怎么回应。
    func handle(_ event: DesktopPetEvent) {
        guard settings.enabled else { return }
        // 空闲读数每帧（离开着时）或每 1.5 秒才看一次：刚拖进文件这类有人在的事，先补看一次是不是已经回来了。
        if awayLog.isAway, case .fileStored = event { feedAway(.idle(Self.userIdleSeconds())) }
        if awayLog.hold(event) { return }
        guard shown, let track, let current = state else { return }
        let now = Date()
        lastTouch = now
        lastPet = now
        let point: CGPoint? = switch event {
        case .fileStored(_, _, _, let at): at
        case .focusFinished(_, let at): at
        default: nil
        }
        let sameScreen = point.map { point in
            if let trackScreen { return trackScreen.frame.contains(point) }
            let feet = track.feet(along: current.x)
            return NSScreen.screens.contains { $0.frame.contains(point) && $0.frame.contains(feet) }
        } ?? false
        let context = DesktopPetDirectorContext(now: now, settling: settling(current), track: track,
                                                petX: current.x, sameScreen: sameScreen,
                                                scale: settings.size.scale, recent: errand,
                                                recentDownloads: recentDownloads)
        switch DesktopPetDirector.decide(event, context: context) {
        case .ignore:
            return
        case .queue:
            assistQueue = DesktopPetDirector.enqueue(event, into: assistQueue)
        case .deliver(let next, let goal):
            errand = next
            review = nil
            fetching = nil
            downloadReview = nil
            var moving = current
            if abs(goal - current.x) < 4 {
                arrive(&moving, errand: next, now: now)
            } else {
                DesktopPetBrain.turn(&moving, left: goal < current.x, now: now)
                moving.activity = .fileDelivery(to: goal)
                moving.since = now
            }
            state = moving
            lastStep = now
        case .notice(let next, _):
            errand = next
            review = DesktopPetReview(next, now: now)
            fetching = nil
            downloadReview = nil
            state = DesktopPetBrain.noticed(current, style: track.style, now: now)
            sayStored(next.text, now: now)
        case .celebrate(let widgetID, let toward, _):
            // 朝计时器看一眼、欢呼一次、坐回去；有计时器卡片时单击打开它（开始下一轮、休息用面板里的按钮）。
            errand = nil
            fetching = nil
            downloadReview = nil
            let next = widgetID.map { DesktopPetReview(widgetID: $0, text: DesktopPetAssist.focusDoneText, now: now) }
            review = next
            state = DesktopPetBrain.celebrate(current, toward: toward,
                                              until: next?.until ?? now.addingTimeInterval(DesktopPetAssist.celebrateDuration),
                                              now: now)
            say(DesktopPetAssist.focusDoneText, for: DesktopPetAssist.focusBubble, now: now)
        case .welcome(let summary, _):
            // 从睡着抬头探看；离开期间有事就说那一句，单击打开对应卡片。
            errand = nil
            fetching = nil
            review = summary.flatMap { summary in
                summary.widgetID.map { DesktopPetReview(widgetID: $0, text: summary.text, itemIDs: summary.itemIDs,
                                                        now: now) }
            }
            // 离开期间下好的文件：单击在访达中显示。
            if let paths = summary?.revealPaths, !paths.isEmpty {
                downloadReview = (paths, now.addingTimeInterval(DesktopPetAssist.reviewDuration))
            } else {
                downloadReview = nil
            }
            state = DesktopPetBrain.wokeUp(current, style: track.style, now: now)
            if let summary { say(summary.text, for: DesktopPetAssist.welcomeBubble, now: now) }
        case .stretch:
            // 伸个懒腰（吊着的晃一下），说一句；不打断正在办的事。
            state = DesktopPetBrain.stretched(current, style: track.style, now: now)
            say(DesktopPetAssist.stretchText, for: DesktopPetAssist.stretchBubble, now: now)
        case .fetch(let batch, let goal, _):
            // 下载好了：叼纸团跑一小段放下（贴边、吊着、侧边程序坞就地抬头），单击在访达中显示。
            errand = nil
            review = nil
            recentDownloads = batch
            var moving = current
            if let goal, abs(goal - current.x) >= 4, current.activity != .sit {
                fetching = batch
                downloadReview = nil
                DesktopPetBrain.turn(&moving, left: goal < current.x, now: now)
                moving.activity = .fileDelivery(to: goal)
                moving.since = now
                state = moving
                lastStep = now
            } else if goal != nil {
                arriveDownloads(&moving, batch: batch, now: now)
                state = moving
            } else {
                fetching = nil
                downloadReview = (batch.paths, now.addingTimeInterval(DesktopPetAssist.reviewDuration))
                state = DesktopPetBrain.noticed(current, style: track.style, now: now)
                say(batch.text, for: DesktopPetAssist.downloadBubble, now: now)
            }
        }
        render(now: now)
        updateClock(now: now)
    }

    /// 被拖着、正在落地、跳着、救回途中：先排队，站稳了再处理。
    private func settling(_ current: DesktopPetState) -> Bool {
        if dragging || transit != nil { return true }
        switch current.activity {
        case .dragged, .land, .jump, .rescue: return true
        default: return false
        }
    }

    /// 叼到卡片旁：放下坐好（专注陪着时照样坐着），进入「有待查看」，头顶说一句。
    private func arrive(_ current: inout DesktopPetState, errand: DesktopPetErrand, now: Date) {
        let next = DesktopPetReview(errand, now: now)
        review = next
        if current.activity != .sit {
            current = DesktopPetBrain.waitingBeside(current, until: next.until, now: now)
        }
        sayStored(next.text, now: now)
    }

    /// 下载的纸团叼到了：放下坐好（专注陪着时照样坐着），说一句，单击在访达中显示。
    private func arriveDownloads(_ current: inout DesktopPetState, batch: DesktopPetDownloads, now: Date) {
        fetching = nil
        let until = now.addingTimeInterval(DesktopPetAssist.reviewDuration)
        downloadReview = (batch.paths, until)
        if current.activity != .sit {
            current = DesktopPetBrain.waitingBeside(current, until: until, now: now)
        }
        say(batch.text, for: DesktopPetAssist.downloadBubble, now: now)
    }

    /// 活动提醒：每 1.5 秒看一次连续打字多久了（只看多久没按键，不要辅助功能权限）。
    fileprivate func checkStretch() {
        guard settings.enabled, settings.stretchReminder else { return }
        let focusing = FocusPandaClimb.isActive(TimerStateProvider.shared.state)
        if awayLog.isAway { stretchClock.reset() }
        guard stretchClock.tick(now: Date(), keyIdle: Self.keyIdleSeconds(), focusing: focusing) else { return }
        handle(.stretchReminder)
    }

    private func sayStored(_ text: String, now: Date) {
        say(text, for: DesktopPetAssist.noticeBubble, now: now)
    }

    private func say(_ text: String, for duration: TimeInterval, now: Date) {
        guard settings.bubbles, QuickActions.shared.presentation == nil, bubble.content?.isRescue != true else { return }
        setBubble(.news(text, until: now.addingTimeInterval(duration)))
    }

    // MARK: 离开回来

    /// 锁屏、屏保（分布式通知）和休眠、切换用户（工作区通知）一来就算离开；显示器睡醒在 `observeSleep` 里喂。
    private func observeAway() {
        guard awayObservers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, PostureAway.Event)] = [
            (NSWorkspace.willSleepNotification, .blocked(.asleep)),
            (NSWorkspace.didWakeNotification, .unblocked(.asleep)),
            (NSWorkspace.sessionDidResignActiveNotification, .blocked(.userSwitched)),
            (NSWorkspace.sessionDidBecomeActiveNotification, .unblocked(.userSwitched)),
        ]
        for (name, event) in pairs {
            awayObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DesktopPetController.shared.feedAway(event) }
            }))
        }
        let distributed = DistributedNotificationCenter.default()
        let named: [(String, PostureAway.Event)] = [
            ("com.apple.screenIsLocked", .blocked(.locked)),
            ("com.apple.screenIsUnlocked", .unblocked(.locked)),
            ("com.apple.screensaver.didstart", .blocked(.screensaver)),
            ("com.apple.screensaver.didstop", .unblocked(.screensaver)),
        ]
        for (name, event) in named {
            awayObservers.append((distributed, distributed.addObserver(forName: Notification.Name(name), object: nil,
                                                                       queue: .main) { _ in
                MainActor.assumeIsolated { DesktopPetController.shared.feedAway(event) }
            }))
        }
    }

    /// 喂一次离开的判断。回来那一刻：先看一眼专注有没有在离开时结束（记进去），再把记下的事合并成一条演出来。
    private func feedAway(_ event: PostureAway.Event, now: Date = Date()) {
        guard settings.enabled else { return }
        if awayLog.isAway {
            var probe = awayLog.tracker
            if case .back? = probe.handle(event, at: now) { checkFocus(now: now) }
        }
        let focusing = FocusPandaClimb.isActive(TimerStateProvider.shared.state)
        guard let back = awayLog.handle(event, at: now, focusing: focusing) else { return }
        lastTouch = now
        handle(back)
    }

    /// 「有待查看」结束（被点、拖走、超时）。
    private func endReview() {
        review = nil
        errand = nil
        fetching = nil
        downloadReview = nil
    }

    /// 有待查看时被点：打开那张文件暂存卡片的面板（扩展栏自动隐藏时先滑出来），新条目闪一下。
    private func openReview(_ pending: DesktopPetReview) {
        endReview()
        if !pending.itemIDs.isEmpty { FileShelfHighlight.shared.flash(pending.itemIDs, in: pending.widgetID) }
        WidgetPanelOpener.shared.open(pending.widgetID)
    }

    private func advance() {
        guard shown, let track, var current = state else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastStep)
        lastStep = now

        let timer = TimerStateProvider.shared.state
        let companion = ProLicenseGate.canUseFocusPanda(unlocked: ProAccess.isUnlocked)
        // 专注完成一轮的欢呼改由 `checkNews` 发 `.focusFinished`（看一眼计时器、欢呼一次、坐回去）。
        lastTimer = timer
        let focusing = companion && FocusPandaClimb.isActive(timer)

        // 离开着又有了输入：先探头打招呼（`handle` 改了 `state`），再接着走这一帧。
        let idle = Self.userIdleSeconds()
        if awayLog.isAway {
            state = current
            feedAway(.idle(idle), now: now)
            guard let updated = state else { return }
            current = updated
        }
        let pointer = attention(track: track)
        if pointer != nil || dragging || pressPoint != nil { lastTouch = now }
        if petHovering || barHovering || dragging || pressPoint != nil { lastPet = now }
        current = sense(current, track: track, now: now)

        let wasDelivering: Bool = if case .fileDelivery = current.activity { true } else { false }
        let wasClimbing: Bool = if case .hugClimb = current.activity { true } else { false }
        let night = DesktopPetRhythm.isNight(hour: Calendar.current.component(.hour, from: now))
        current = DesktopPetBrain.step(current, dt: dt, now: now, lane: track.lane,
                                       userIdle: idle, focusing: focusing,
                                       style: track.style, attention: pointer,
                                       hangQuiet: now.timeIntervalSince(lastTouch),
                                       touchQuiet: now.timeIntervalSince(lastPet), night: night,
                                       random: { Double.random(in: 0...1) })
        if wasClimbing, track.style == .side {
            if case .hugClimb = current.activity {} else {
                // 爬完换了高度：记住（同一个停靠位置字段）。
                let along = track.fraction(of: current.x)
                save { $0.spot = DesktopPetSpot(display: $0.spot?.display, along: along) }
            }
        }
        current = greetIfNeeded(current, style: track.style, now: now)
        if wasDelivering {
            if case .fileDelivery = current.activity {} else if let fetching {
                arriveDownloads(&current, batch: fetching, now: now)
            } else if let errand {
                arrive(&current, errand: errand, now: now)
            }
        }
        if let review, review.expired(at: now) { endReview() }
        if let pending = downloadReview, now >= pending.until { downloadReview = nil }
        state = current
        if DesktopPetBrain.awaitingPutBack(current) { putBack() }
        if let content = bubble.content, let until = content.until, now >= until { setBubble(nil) }
        // 指针移得太快时离开的事件可能没来：按指针实际位置补一次。
        let mouse = NSEvent.mouseLocation
        if petHovering, !drawnRect.insetBy(dx: -4, dy: -4).contains(mouse) {
            hovering(false)
        }
        if barHovering, barPanel?.frame.contains(mouse) != true { barHover(nil, width: 0) }
        if let until = barVisibleUntil, now >= until, !barHovering, !petHovering { hideBar() }
        if !assistQueue.isEmpty, !settling(current) {
            let waiting = assistQueue
            assistQueue = []
            for event in waiting { handle(event) }
        }
        render(now: now)
        updateClock(now: now)
    }

    /// 指针经过（底边姿势抬头看一眼）、靠近头（抱树抖耳朵），都带冷却。
    private func sense(_ current: DesktopPetState, track: DesktopPetTrack, now: Date) -> DesktopPetState {
        let mouse = NSEvent.mouseLocation
        defer { lastPointer = (mouse, now) }
        guard !dragging, pressPoint == nil else { return current }
        let distance = Double(hypot(mouse.x - drawnCenter.x, mouse.y - drawnCenter.y)) / settings.size.scale
        if track.style == .side {
            return mood.neared(distance: distance, now: now) ? DesktopPetBrain.earFlicked(current, now: now) : current
        }
        guard track.edge == .bottom, track.style != .sit, let last = lastPointer else { return current }
        let span = now.timeIntervalSince(last.at)
        guard span > 0, span < 1 else { return current }
        let speed = Double(hypot(mouse.x - last.point.x, mouse.y - last.point.y)) / span
        guard mood.passedBy(distance: distance, speed: speed, now: now) else { return current }
        return DesktopPetBrain.glanced(current, now: now)
    }

    /// 每天第一次唤醒（从睡着醒来）或出现时：伸个懒腰，头顶说「早」（受头顶气泡开关控制）。
    private func greetIfNeeded(_ current: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        let asleep: Bool = if case .sleep = current.activity { true } else { false }
        defer {
            wasAsleep = asleep
            justShown = false
        }
        guard (justShown || wasAsleep) && !asleep, !dragging, bubble.content?.isNews != true else { return current }
        let defaults = UserDefaults.standard
        guard DesktopPetRhythm.shouldGreet(lastDay: defaults.string(forKey: Self.greetedKey), now: now) else {
            return current
        }
        defaults.set(DesktopPetRhythm.greetingDay(now), forKey: Self.greetedKey)
        lastPet = now
        say(DesktopPetRhythm.morningText, for: DesktopPetAssist.noticeBubble, now: now)
        return DesktopPetBrain.greeted(current, style: style, now: now)
    }

    /// 指针在小熊猫身上移动（不按键）：来回划算摸头，开心一下（冷却 30 秒）。
    fileprivate func pointerMoved(_ point: CGPoint?, pressed: Bool) {
        let now = Date()
        if point != nil { lastPet = now }
        guard mood.rubbed(x: point.map { Double($0.x) }, pressed: pressed, now: now),
              let track, let current = state, !dragging else { return }
        state = DesktopPetBrain.petted(current, style: track.style, now: now)
        render(now: now)
        updateClock(now: now)
    }

    /// 鼠标靠近（小熊猫身边约 150 点以内）时它在沿边坐标上的位置，小熊猫转头看过去。
    private func attention(track: DesktopPetTrack) -> Double? {
        guard !dragging else { return nil }
        let pointer = NSEvent.mouseLocation
        let dx = pointer.x - drawnCenter.x
        let dy = pointer.y - drawnCenter.y
        let reach = 150 * CGFloat(settings.size.scale)
        guard dx * dx + dy * dy < reach * reach else { return nil }
        return Double(track.edge.vertical ? pointer.y : pointer.x)
    }

    // MARK: 画

    private func render(now: Date) {
        guard let track, let state, let panel, let view = spriteView else { return }
        let pose = DesktopPetBrain.pose(state, now: now, scale: settings.size.scale, style: track.style,
                                        edge: track.edge)
        let scale = CGFloat(settings.size.scale)
        let base = DesktopPetArt.size(pose)
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let tall = size.height * CGFloat(pose.scaleY)
        let wide = size.width * abs(CGFloat(pose.scaleX))

        // 图都正着画。脚底中点：上边吊着时由挂点往下量，左右边按露出多少往边外推。
        var feet: CGPoint
        if dragging {
            feet = dragFeet
        } else {
            switch track.style {
            case .hang:
                let hang = track.hangPoint(along: state.x)
                feet = CGPoint(x: hang.x, y: hang.y - tall * CGFloat(pose.anchor))
            case .side:
                feet = track.peekFeet(along: state.x, width: Double(size.width), reveal: pose.reveal)
            default:
                feet = track.feet(along: state.x, lift: pose.lift * Double(scale))
            }
        }
        if let transit {
            let t = now.timeIntervalSince(transit.start) / transit.duration
            let eased = DesktopPetSnap.glide(t)
            feet = CGPoint(x: transit.feet.x + (feet.x - transit.feet.x) * eased,
                           y: transit.feet.y + (feet.y - transit.feet.y) * eased)
            if t >= 1 { self.transit = nil }
        }
        let flip = dragging ? pose.facingLeft : track.edge.flipped(facingLeft: pose.facingLeft)

        let center = CGPoint(x: feet.x, y: feet.y + tall / 2)
        let side = (Self.windowSide * scale).rounded(.up)
        var originX = (center.x - side / 2).rounded(.down)
        var originY = (center.y - side / 2).rounded(.down)
        // 吊着、探头时窗口不伸出那条边：伸出去的那块（左右边藏起来的半只、上边钟摆时翘过菜单栏下沿的爪尖）
        // 由视图裁掉，也就不会出现在相邻的显示器上。拖着时不裁。
        if !dragging {
            let edgeLine = CGFloat(track.base)
            switch track.style {
            case .side where track.edge == .left: originX = max(originX, edgeLine.rounded(.up))
            case .side where track.edge == .right: originX = min(originX, edgeLine.rounded(.down) - side)
            case .hang: originY = min(originY, edgeLine.rounded(.down) - side)
            // 下边缘藏在草里：沉下去的那截不伸出屏幕底边。
            case .curl: originY = max(originY, edgeLine.rounded(.up))
            default: break
            }
        }
        let origin = CGPoint(x: originX, y: originY)
        if panel.frame.size != CGSize(width: side, height: side) {
            panel.setFrame(CGRect(origin: origin, size: CGSize(width: side, height: side)), display: false)
        } else if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        // 窗口原点是整数点，剩下不足一点的放进图层位置，慢慢走也是平滑的。
        // 图层绕 `anchor`（脚底；拎着时的后颈；吊着时前爪抓握线，即图顶）转和缩放。
        let pivot = CGPoint(x: feet.x, y: feet.y + tall * CGFloat(pose.anchor))
        let localPivot = CGPoint(x: pivot.x - originX, y: pivot.y - originY)
        view.draw(image: pose.image, size: size, anchor: pose.anchor, position: localPivot,
                  rotation: pose.wobble, scaleX: pose.scaleX * (flip ? -1 : 1), scaleY: pose.scaleY)
        // 草丛：草根贴在没沉、没跳时脚底那条线上，横向以小熊猫为中。拖着时没有。
        if let grass = pose.grass, !dragging, !track.edge.vertical {
            let root = CGPoint(x: feet.x - originX, y: feet.y - CGFloat(pose.lift) * scale - originY)
            view.drawGrass(front: grass.frontImage(time: now.timeIntervalSinceReferenceDate), back: grass.backImage,
                           root: root, scale: scale)
        } else {
            view.drawGrass(front: nil, back: nil, root: .zero, scale: scale)
        }

        let window = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let body = CGRect(x: feet.x - wide / 2, y: feet.y, width: wide, height: tall)
        let seen = body.intersection(window)
        drawnFeet = feet
        drawnSize = size
        drawnRect = seen.isNull || seen.isEmpty ? body : seen
        drawnCenter = CGPoint(x: drawnRect.midX, y: drawnRect.midY)
        drawnFlip = flip

        if pose.zzz > 0, bubble.content == nil || bubble.content?.isZzz == true {
            if bubble.content != .zzz(pose.zzz) { setBubble(.zzz(pose.zzz), position: false) }
        } else if pose.zzz == 0, bubble.content?.isZzz == true {
            setBubble(nil)
        }
        positionFloats()
    }

    // MARK: 鼠标

    fileprivate func mouseDown(at point: CGPoint) {
        pressPoint = point
        grabOffset = CGPoint(x: drawnFeet.x - point.x, y: drawnFeet.y - point.y)
        lastDragX = point.x
    }

    fileprivate func mouseDragged(to point: CGPoint) {
        guard let press = pressPoint, var current = state else { return }
        let now = Date()
        if !dragging {
            let moved = hypot(point.x - press.x, point.y - press.y)
            guard Double(moved) >= DesktopPetSnap.dragThreshold else { return }
            dragging = true
            if case .rescue = current.activity { abandonRescue() }
            // 拖走了：叼着的这一趟、有待查看都算结束。
            endReview()
            // 抓着后颈提起来：脚在指针下面一点，拖起来那一下滑过去。
            transit = (drawnFeet, now, 0.14)
            current = DesktopPetBrain.grabbed(current, now: now)
            hideBar()
            if bubble.content?.isNews == true || bubble.content?.isZzz == true { setBubble(nil) }
        }
        // 拎起来那套帧头顶在图片上沿，指针捏在后颈。
        let dragArt = DesktopPetArt.size(DesktopPetPose(image: DesktopPetStrip.drag.imageName(0)))
        let hang = dragArt.height * CGFloat(settings.size.scale) * CGFloat(DesktopPetHang.scruff)
        dragFeet = CGPoint(x: point.x, y: point.y - hang)
        current = DesktopPetBrain.dragging(current, dx: Double(point.x - lastDragX), now: now)
        lastDragX = point.x
        state = current
        render(now: now)
        updateClock(now: now)
    }

    fileprivate func mouseUp(at point: CGPoint) {
        defer { pressPoint = nil }
        guard dragging else {
            if pressPoint != nil { tapped() }
            return
        }
        dragging = false
        drop(at: dragFeet)
    }

    /// 单击：有待查看时打开刚暂存的那张卡片（下载好的在访达中显示）；否则同 `clicked`。
    private func tapped() {
        let now = Date()
        lastPet = now
        if mood.clicked(now: now), let current = state {
            // 10 秒内连戳 3 次：不高兴，耷拉耳朵约 3 秒。
            state = DesktopPetBrain.sulked(current, now: now)
            hideBar()
            render(now: now)
            updateClock(now: now)
            return
        }
        let hugging = track?.style == .side
        if hugging, let current = state, review == nil, downloadReview == nil,
           !DesktopPetBrain.hugIsOut(current, now: now) {
            // 抱着的被点头：先爬出来露全身挥手，再点才是平时的点击。
            state = DesktopPetBrain.hugTapped(current, now: now)
            render(now: now)
            updateClock(now: now)
            return
        }
        if let pending = downloadReview, let current = state {
            state = hugging ? DesktopPetBrain.hugTapped(current, now: now) : DesktopPetBrain.poked(current, now: now)
            hideBar()
            endReview()
            DesktopPetDownloadsWatcher.reveal(pending.paths)
            render(now: now)
            updateClock(now: now)
            return
        }
        if let pending = review, let current = state {
            state = hugging ? DesktopPetBrain.hugTapped(current, now: now) : DesktopPetBrain.poked(current, now: now)
            hideBar()
            openReview(pending)
            render(now: now)
            updateClock(now: now)
            return
        }
        clicked()
    }

    /// 单击：跳一下，浮出快捷条。
    private func clicked() {
        guard let current = state else { return }
        let now = Date()
        state = track?.style == .side ? DesktopPetBrain.hugTapped(current, now: now)
            : DesktopPetBrain.poked(current, now: now)
        showBar(for: DesktopPetQuickAction.shownAfterClick)
        render(now: now)
        updateClock(now: now)
    }

    /// 松手：设成随意就停在这里，否则吸到松手那块屏幕最近的边（程序坞上方吸回程序坞），
    /// 停靠位置和位置写回设置。
    private func drop(at feet: CGPoint) {
        guard let current = state else { return }
        let now = Date()
        let screen = NSScreen.screens.first { $0.frame.contains(feet) }
            ?? NSScreen.screens.min { distance(feet, $0.frame) < distance(feet, $1.frame) }
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let dockOnScreen = dockRect.flatMap { screen.frame.intersects($0) ? $0 : nil }
        let anchor: DesktopPetAnchor = settings.anchor == .free
            ? .free
            : DesktopPetSnap.nearest(feet, visible: visible, dock: perch == nil ? nil : dockOnScreen)
        let display = Self.displayID(screen)

        var next: DesktopPetTrack?
        var spot: DesktopPetSpot
        if anchor == .dock, let perch {
            next = DesktopPetTracks.dock(perch)
            spot = DesktopPetSpot(display: display, along: 0.5)
        } else {
            let clamped = CGPoint(x: min(max(feet.x, visible.minX), visible.maxX),
                                  y: min(max(feet.y, visible.minY), visible.maxY))
            let probe = DesktopPetTracks.edge(anchor, visible: visible, length: petLength,
                                              spot: DesktopPetSpot(display: display))
            spot = probe.map { DesktopPetSnap.spot(for: clamped, track: $0, visible: visible, display: display,
                                                   length: petLength) }
                ?? DesktopPetSpot(display: display)
            next = DesktopPetTracks.edge(anchor, visible: visible, length: petLength, spot: spot)
        }
        guard let next else { return }
        let along = next.style == .stroll ? next.along(of: feet) : next.along(fraction: spot.along)
        transit = (drawnFeet, now, DesktopPetSnap.glideDuration)
        lastTouch = now
        state = DesktopPetBrain.landed(current, at: along, now: now, style: next.style)
        track = next
        trackScreen = screen
        trackKey = "\(next.edge)-\(next.style)-\(display ?? 0)-\(settings.size.rawValue)"
        // 先改自己的设置，状态文件回传同样的值时什么都不做。
        settings.anchor = anchor
        settings.spot = spot
        onSettingsChange?(settings)
        render(now: now)
        updateClock(now: now)
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    fileprivate func hovering(_ inside: Bool) {
        petHovering = inside
        if inside {
            // 抱着的只露头：爬出来以后悬停才浮出快捷条。
            let tucked = track?.style == .side && !(state.map { DesktopPetBrain.hugIsOut($0, now: Date()) } ?? false)
            if !dragging, !tucked { showBar(for: nil) }
        } else {
            lingerBar()
        }
    }

    /// 快捷键：唤出小熊猫（跳一下）并显示快捷条。
    func summon() {
        guard settings.enabled else { return }
        if !shown { refreshPlacement() }
        clicked()
    }

    // MARK: 右键菜单

    private func menuItem(_ title: String, _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(menuChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = DesktopPetMenuAction(run)
        return item
    }

    @objc private func menuChosen(_ sender: NSMenuItem) {
        (sender.representedObject as? DesktopPetMenuAction)?.run()
    }

    fileprivate func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(tr("隐藏桌面宠物")) {
            DesktopPetController.shared.save { $0.enabled = false }
        })
        menu.addItem(.separator())

        let sizeItem = NSMenuItem(title: tr("大小"), action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for size in DesktopPetSize.allCases {
            let item = menuItem(size.title) {
                DesktopPetController.shared.save { $0.size = size }
            }
            item.state = settings.size == size ? .on : .off
            sizes.addItem(item)
        }
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)

        let anchorItem = NSMenuItem(title: tr("停靠位置"), action: nil, keyEquivalent: "")
        let anchors = NSMenu()
        for anchor in DesktopPetAnchor.allCases {
            let item = menuItem(anchor.title) {
                DesktopPetController.shared.save { settings in
                    settings.anchor = anchor
                    // 换到别的边时沿边的位置重新从默认开始，屏幕保持。
                    if anchor != .free, let old = settings.spot { settings.spot = DesktopPetSpot(display: old.display) }
                }
            }
            item.state = settings.anchor == anchor ? .on : .off
            anchors.addItem(item)
        }
        anchorItem.submenu = anchors
        menu.addItem(anchorItem)

        if settings.anchor != .dock {
            menu.addItem(menuItem(tr("回到程序坞")) {
                DesktopPetController.shared.save {
                    $0.anchor = .dock
                    $0.spot = nil
                }
            })
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(tr("桌面宠物设置…")) {
            DesktopPetController.shared.openSettings?()
        })
        return menu
    }

    // MARK: 气泡

    /// 码头的状态有了变化：小熊猫头顶说一句（头顶气泡开着、没在全屏或演示时）。
    func announce(_ news: DesktopPetNews) {
        let now = Date()
        guard settings.enabled, shown, !dragging, QuickActions.shared.presentation == nil else { return }
        guard gate.allow(news.kind, now: now) else { return }
        if var current = state {
            switch news {
            case .plugged:
                current = DesktopPetBrain.plugged(current, toward: notchAlong(), now: now)
            case .unplugged:
                current = DesktopPetBrain.noticed(current, style: track?.style ?? .stroll, now: now)
            case .lowBattery:
                current = DesktopPetBrain.droop(current, now: now)
            case .charged, .focusDone:
                current = DesktopPetBrain.cheer(current, now: now)
            default:
                break
            }
            state = current
        }
        if settings.bubbles, bubble.content?.isRescue != true {
            setBubble(.news(news.text, until: now.addingTimeInterval(news.duration)))
        }
        render(now: now)
        updateClock(now: now)
    }

    /// 刘海（带刘海的屏幕，没有就是主屏菜单栏中间）在沿边坐标上的位置。
    private func notchAlong() -> Double? {
        guard let track else { return nil }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        else { return nil }
        return Double(track.edge.vertical ? screen.frame.maxY : screen.frame.midX)
    }

    /// 每 1.5 秒看一次专注、收音机、电池。第一次只记下现状，不说话。
    private func checkNews() {
        let now = Date()
        let timer = TimerStateProvider.shared.state
        let radio = RadioPlayer.shared
        let power = BatteryNeonPlugController.read().map { DesktopPetPower(onPower: $0.source == .ac,
                                                                            percent: $0.percent) }
        // 还在连的电台先不算在播，真的出声那一刻再说。
        let playing = radio.isPlaying && !radio.isBuffering
        defer {
            newsTimer = timer
            lastNewsCheck = now
            radioWasPlaying = playing
            radioStation = radio.station?.name
            if let power { lastPower = power }
            newsPrimed = true
        }
        guard newsPrimed else { return }
        if let old = newsTimer,
           let news = DesktopPetNewsDesk.focus(from: old, at: lastNewsCheck, to: timer, at: now) {
            focusNews(news)
        }
        if let news = DesktopPetNewsDesk.radio(wasPlaying: radioWasPlaying, oldStation: radioStation,
                                               playing: playing, station: radio.station?.name) {
            announce(news)
        }
        if let power, let news = DesktopPetNewsDesk.battery(from: lastPower, to: power) {
            DockLog.notice(.pet, "power news \(news.kind) \(power.percent)% shown=\(shown) bubbles=\(settings.bubbles) presenting=\(QuickActions.shared.presentation != nil)")
            announce(news)
        }
    }

    private var newsTimer: TimerState?

    /// 专注完成交给状态助手（`.focusFinished`：朝计时器卡片看一眼、欢呼一次、坐回去，单击打开计时器）；
    /// 开始、还剩 5 分钟照旧说一句。
    private func focusNews(_ news: DesktopPetNews) {
        guard news == .focusDone else { return announce(news) }
        let widgets = DockItemTree.widgets(in: WidgetPanelOpener.shared.currentItems())
        let timerID = DesktopPetDirector.timerWidget(in: widgets)
        handle(.focusFinished(widgetID: timerID, at: timerID.flatMap { DesktopPetCardSpots.shared.center(of: $0) }))
    }

    /// 离开着、回来之前：单独看一眼专注计时，离开时结束的那一轮记进离开的事里。
    private func checkFocus(now: Date) {
        let timer = TimerStateProvider.shared.state
        defer {
            newsTimer = timer
            lastNewsCheck = now
        }
        guard newsPrimed, let old = newsTimer,
              DesktopPetNewsDesk.focus(from: old, at: lastNewsCheck, to: timer, at: now) == .focusDone else { return }
        focusNews(.focusDone)
    }

    private func setBubble(_ content: DesktopPetBubbleContent?, position: Bool = true) {
        bubble.content = content
        guard let content else {
            bubblePanel?.orderOut(nil)
            return
        }
        let panel = bubblePanel ?? makeBubblePanel()
        bubblePanel = panel
        bubbleClick?.isClickable = content.isRescue
        panel.ignoresMouseEvents = !content.isRescue
        if let host = bubbleHost {
            host.rootView = DesktopPetBubbleView(content: content)
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            if panel.frame.size != size { panel.setContentSize(size) }
        }
        if shown, !panel.isVisible { panel.orderFrontRegardless() }
        if position { positionFloats() }
    }

    /// 快捷条和气泡放在小熊猫“外侧”（离开那条边的方向）：程序坞和下边缘在头顶，
    /// 上边吊着的在身子下面（睡着的 Zzz 在身子旁边），左右边的在屏幕里侧；随意放的时候
    /// 快捷条在下面、气泡在头顶。都夹在屏幕可见区域里。
    private func positionFloats() {
        guard shown, let track else { return }
        let visible = (trackScreen ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let barShown = barPanel?.isVisible == true
        let barSize = barPanel?.frame.size ?? DesktopPetQuickAction.barSize
        let rect = drawnRect
        let edge = dragging ? DesktopPetEdge.bottom : track.edge
        let style = dragging ? DesktopPetStyle.stroll : track.style
        let gap: CGFloat = 8
        // 左右边按探出来最多时的那条线放，身子探进探出时快捷条不跟着跑。
        let peekLine: CGFloat
        switch edge {
        case .left: peekLine = max(rect.maxX, CGFloat(track.base) + drawnSize.width * CGFloat(DesktopPetSide.peek))
        case .right: peekLine = min(rect.minX, CGFloat(track.base) - drawnSize.width * CGFloat(DesktopPetSide.peek))
        default: peekLine = 0
        }

        var barCenter = CGPoint(x: rect.midX, y: rect.midY)
        switch (edge, style) {
        case (.bottom, .sit):
            barCenter.y = rect.minY - gap - barSize.height / 2
            if barCenter.y - barSize.height / 2 < visible.minY {
                barCenter.y = rect.maxY + gap + barSize.height / 2
            }
        case (.bottom, _):
            barCenter.y = rect.maxY + gap + barSize.height / 2
        case (.top, _):
            barCenter.y = rect.minY - gap - barSize.height / 2
        case (.left, _):
            barCenter.x = peekLine + gap + barSize.width / 2
        case (.right, _):
            barCenter.x = peekLine - gap - barSize.width / 2
        }
        if let barPanel, barShown {
            let frame = clampRect(CGRect(x: barCenter.x - barSize.width / 2, y: barCenter.y - barSize.height / 2,
                                         width: barSize.width, height: barSize.height), in: visible)
            if barPanel.frame.origin != frame.origin { barPanel.setFrameOrigin(frame.origin) }
        }

        guard let bubblePanel, bubblePanel.isVisible else { return }
        let size = bubblePanel.frame.size
        var bubbleCenter = CGPoint(x: rect.midX, y: rect.midY)
        let barAbove = barShown && barCenter.y > rect.midY && !edge.vertical
        let barBelow = barShown && barCenter.y < rect.midY && !edge.vertical
        switch edge {
        case .bottom:
            bubbleCenter.y = rect.maxY + gap / 2 + size.height / 2
            if barAbove { bubbleCenter.y += barSize.height + gap }
        case .top where bubble.content?.isZzz == true && !barShown:
            // 睡着吊着：Zzz 在脑袋旁边（吊挂帧的脑袋在图顶往下约四分之一处），那边放不下就放另一边。
            let right = rect.maxX + gap + size.width / 2
            let left = rect.minX - gap - size.width / 2
            let fitsRight = right + size.width / 2 <= visible.maxX
            let fitsLeft = left - size.width / 2 >= visible.minX
            bubbleCenter.x = drawnFlip ? (fitsLeft ? left : right) : (fitsRight ? right : left)
            bubbleCenter.y = rect.maxY - rect.height * 0.25
        case .top:
            bubbleCenter.y = rect.minY - gap / 2 - size.height / 2
            if barBelow { bubbleCenter.y -= barSize.height + gap }
        case .left:
            bubbleCenter.x = peekLine + gap + size.width / 2
            if barShown { bubbleCenter.y = barCenter.y + barSize.height / 2 + gap + size.height / 2 }
        case .right:
            bubbleCenter.x = peekLine - gap - size.width / 2
            if barShown { bubbleCenter.y = barCenter.y + barSize.height / 2 + gap + size.height / 2 }
        }
        let frame = clampRect(CGRect(x: bubbleCenter.x - size.width / 2, y: bubbleCenter.y - size.height / 2,
                                     width: size.width, height: size.height), in: visible)
        if bubblePanel.frame.origin != frame.origin { bubblePanel.setFrameOrigin(frame.origin) }
    }

    private func clampRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard bounds.width > rect.width, bounds.height > rect.height else { return rect }
        var r = rect
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r.integral
    }

    // MARK: 快捷条

    /// 浮出快捷条。`duration` 是单击、快捷键唤出时至少留多久；悬停时 nil（移开后收起）。
    private func showBar(for duration: TimeInterval?) {
        guard shown else { return }
        refreshBarModel()
        let panel = barPanel ?? makeBarPanel()
        barPanel = panel
        let now = Date()
        if let duration {
            barVisibleUntil = max(barVisibleUntil ?? now, now.addingTimeInterval(duration))
        } else {
            barVisibleUntil = nil
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        positionFloats()
        ensureBarTimer()
    }

    private func refreshBarModel() {
        let timer = TimerStateProvider.shared.state
        bar.focusRunning = DesktopPetQuickAction.focusRunning(timer)
        bar.radioPlaying = RadioPlayer.shared.isPlaying
        bar.radioAvailable = RadioPlayer.shared.isPlaying || RadioPlayer.shared.station != nil
    }

    /// 指针离开小熊猫和快捷条：过一会儿收起。
    private func lingerBar() {
        guard barPanel?.isVisible == true, !barHovering, !petHovering else { return }
        let until = Date().addingTimeInterval(DesktopPetQuickAction.lingerAfterLeave)
        barVisibleUntil = max(barVisibleUntil ?? until, until)
        ensureBarTimer()
    }

    /// 静止时慢计时器本来就在跑，收起快捷条由 `advance` 顺带检查；保险起见再排一次。
    private func ensureBarTimer() {
        guard let until = barVisibleUntil else { return }
        let delay = max(0.1, until.timeIntervalSinceNow + 0.05)
        _ = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                let pet = DesktopPetController.shared
                if let until = pet.barVisibleUntil, Date() >= until, !pet.barHovering, !pet.petHovering {
                    pet.hideBar()
                }
            }
        }
    }

    private func hideBar() {
        barVisibleUntil = nil
        bar.hovered = nil
        barPanel?.orderOut(nil)
        positionFloats()
    }

    fileprivate func barHover(_ point: CGPoint?, width: CGFloat) {
        barHovering = point != nil
        bar.hovered = point.flatMap { DesktopPetQuickAction.at(x: Double($0.x), width: Double(width)) }
        if point == nil { lingerBar() }
    }

    fileprivate func barClick(_ point: CGPoint, width: CGFloat) {
        guard let action = DesktopPetQuickAction.at(x: Double(point.x), width: Double(width)) else { return }
        run(action)
        refreshBarModel()
    }

    private func run(_ action: DesktopPetQuickAction) {
        switch action {
        case .todo:
            hideBar()
            QuickTodoCapture.shared.toggle()
        case .focus:
            let next = DesktopPetQuickAction.toggledFocus(TimerStateProvider.shared.state, now: Date())
            TimerStateProvider.shared.state = next
        case .radio:
            let radio = RadioPlayer.shared
            if radio.isPlaying {
                radio.pause()
            } else if let station = radio.station {
                radio.play(station, volume: radio.volume(for: station, fallback: 60))
            } else {
                NSSound.beep()
            }
        case .expand:
            hideBar()
            if ShelfPresence.shared.isShown() {
                ShelfPresence.shared.reveal()
            } else {
                openSettings?()
            }
        }
    }

    // MARK: 窗口

    private static func floatingPanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return panel
    }

    private func makePanel() -> NSPanel {
        let side = (Self.windowSide * CGFloat(settings.size.scale)).rounded(.up)
        let panel = Self.floatingPanel(size: CGSize(width: side, height: side))
        // 不设 ignoresMouseEvents：透明的地方点击由系统穿透到后面，小熊猫身上的点击
        // 由下面这个视图接住。设过（哪怕设成 false）就会整块窗口都拦鼠标。
        let view = DesktopPetSpriteView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        spriteView = view
        displayLink?.invalidate()
        displayLink = nil
        return panel
    }

    private func makeBubblePanel() -> NSPanel {
        let host = NSHostingView(rootView: DesktopPetBubbleView(content: bubble.content))
        let size = host.fittingSize
        let panel = Self.floatingPanel(size: size)
        panel.ignoresMouseEvents = true
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        let click = DesktopPetClickView(frame: container.bounds)
        click.autoresizingMask = [.width, .height]
        click.onClick = { _, _ in DesktopPetController.shared.putBackFromBubble() }
        container.addSubview(click)
        panel.contentView = container
        bubbleHost = host
        bubbleClick = click
        return panel
    }

    private func makeBarPanel() -> NSPanel {
        let size = DesktopPetQuickAction.barSize
        let panel = Self.floatingPanel(size: size)
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        let host = NSHostingView(rootView: DesktopPetQuickBarView(model: bar))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        let click = DesktopPetClickView(frame: container.bounds)
        click.autoresizingMask = [.width, .height]
        click.isClickable = true
        click.onHover = { point, width in DesktopPetController.shared.barHover(point, width: width) }
        click.onClick = { point, width in DesktopPetController.shared.barClick(point, width: width) }
        click.setAccessibilityElement(true)
        click.setAccessibilityRole(.toolbar)
        click.setAccessibilityLabel(tr("小熊猫快捷条"))
        container.addSubview(click)
        panel.contentView = container
        return panel
    }

    /// 多少秒没按键（系统读数，不要辅助功能权限）。
    private static func keyIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    // MARK: 拖文件到身上

    /// 文件拖到小熊猫身上（还没松手）：码头上有文件暂存卡片就抬头等着接，返回 true；
    /// 没有就说一句「先在扩展栏添加文件暂存」，不接。
    fileprivate func filesEntered() -> Bool {
        guard settings.enabled, shown, !dragging, let current = state else { return false }
        let now = Date()
        guard shelfForDrops() != nil else {
            sayAnyway(DesktopPetAssist.needsShelfText, now: now)
            return false
        }
        lastTouch = now
        state = DesktopPetBrain.expecting(current, now: now)
        render(now: now)
        updateClock(now: now)
        return true
    }

    /// 文件移开了没松手：趴回去。
    fileprivate func filesExited() {
        guard let current = state else { return }
        let now = Date()
        state = DesktopPetBrain.stopExpecting(current, now: now)
        render(now: now)
        updateClock(now: now)
    }

    /// 松手：放进文件暂存（和拖到卡片上一样，只记位置不复制），再走 `.fileStored` 叼过去。
    fileprivate func filesDropped(_ urls: [URL]) -> Bool {
        let now = Date()
        guard let shelf = shelfForDrops() else {
            sayAnyway(DesktopPetAssist.needsShelfText, now: now)
            return false
        }
        let added = FileShelf.add(urls, to: shelf)
        guard !added.isEmpty else {
            filesExited()
            return false
        }
        if let current = state { state = DesktopPetBrain.stopExpecting(current, now: now) }
        // 卡片看得见就叼到卡片旁；看不见时以小熊猫自己的位置为准，叼着走一小步放下。
        let point = DesktopPetCardSpots.shared.center(of: shelf.id) ?? drawnCenter
        handle(.fileStored(count: added.count, widgetID: shelf.id, newItemIDs: added, at: point))
        return true
    }

    private func shelfForDrops() -> WidgetInstance? {
        DesktopPetDirector.shelfWidget(in: DockItemTree.widgets(in: WidgetPanelOpener.shared.currentItems()))
    }

    /// 直接回应的话（拖文件过来时）：头顶气泡关着也说，救回的按钮气泡在时不盖掉。
    private func sayAnyway(_ text: String, now: Date) {
        guard bubble.content?.isRescue != true else { return }
        setBubble(.news(text, until: now.addingTimeInterval(DesktopPetAssist.noticeBubble)))
    }

    private static func userIdleSeconds() -> TimeInterval {
        guard let any = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    // MARK: 废纸篓救回

    private func startRescueWatch() {
        let monitor = TrashMonitor.shared
        monitor.start(threshold: TrashFlies.thresholdBytes(TrashFlies.defaultThreshold))
        seeded = false
        seen = []
        // 废纸篓文件夹一有变化就请 TrashMonitor 马上看一次（不等它 5 秒一次的轮询）。
        // 没有完全磁盘访问权限时打不开，只靠轮询（那时也读不到废纸篓）。
        guard trashSource == nil else { return }
        let fd = open(TrashMonitor.trashURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename],
                                                               queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { TrashMonitor.shared.check(force: false) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        trashSource = source
    }

    private func stopRescueWatch() {
        trashSource?.cancel()
        trashSource = nil
        seeded = false
        seen = []
        rescuing = []
        putBackInFlight = false
    }

    /// 看废纸篓里有没有刚拖进来的。打开开关时已经在里面的、处理过的都不算；
    /// 小熊猫这会儿不显示（全屏、程序坞收起来）时只记下，不去救。
    private func checkTrash() {
        guard settings.rescueActive else { return }
        let monitor = TrashMonitor.shared
        guard monitor.loaded, !monitor.needsAccess else { return }
        let now = Date()
        guard seeded else {
            seen = Set(monitor.recent.map(\.trashName))
            lastTrashCount = monitor.items
            seeded = true
            return
        }
        let added = max(0, monitor.items - lastTrashCount)
        lastTrashCount = monitor.items
        let fresh = DesktopPetRescue.fresh(monitor.recent, seen: seen, now: now)
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh.map(\.trashName))
        guard shown, let track, var current = state, rescuing.isEmpty, !putBackInFlight, !dragging else { return }
        if case .rescue = current.activity { return }
        rescuing = fresh
        autoPutBack = DesktopPetRescue.autoPutBack(fresh: fresh.count, added: added)
        if bubble.content?.isRescue == true { setBubble(nil) }
        guard track.style == .stroll else {
            // 不在程序坞上（够不着废纸篓）：不跑，直接放回。
            putBack()
            return
        }
        current = DesktopPetBrain.startRescue(current, trashX: track.rescueX, lane: track.lane, now: now)
        state = current
        render(now: now)
        updateClock(now: now)
    }

    /// 救回途中被拖走了：不跑了，直接请访达放回。
    private func abandonRescue() {
        guard !rescuing.isEmpty else { return }
        putBack()
    }

    /// 叼回来了：请访达放回原处；不能自动放的、访达没放成的，弹气泡按钮。
    private func putBack() {
        guard !putBackInFlight else { return }
        putBackInFlight = true
        let items = rescuing
        guard autoPutBack else {
            finish(failed: items)
            return
        }
        DesktopPetPutBack.viaFinder(items) { failed in
            DesktopPetController.shared.finish(failed: failed)
        }
    }

    private func finish(failed: [TrashedItem]) {
        putBackInFlight = false
        rescuing = []
        guard let current = state else { return }
        let now = Date()
        if case .dragged = current.activity {
            // 还拖着：不改动作。
        } else {
            state = DesktopPetBrain.finishRescue(current, succeeded: failed.isEmpty, now: now)
        }
        if !failed.isEmpty {
            setBubble(.rescue(DesktopPetRescue.bubbleTitle(count: failed.count), items: failed,
                              until: now.addingTimeInterval(20)))
        }
        render(now: now)
        updateClock(now: now)
    }

    /// 气泡上的「放回原处」：直接移回访达记下的原位置。放不回去时气泡换成原因。
    func putBackFromBubble() {
        guard case .rescue(_, let items, _) = bubble.content, !items.isEmpty else {
            setBubble(nil)
            return
        }
        var messages: [String] = []
        for item in items {
            if let message = TrashMonitor.shared.putBack(item) { messages.append(message) }
        }
        let now = Date()
        if let message = messages.first {
            setBubble(.news(message, until: now.addingTimeInterval(6)))
        } else {
            setBubble(nil)
            if let current = state { state = DesktopPetBrain.cheer(current, now: now) }
        }
        render(now: now)
        updateClock(now: now)
    }
}

// MARK: - 小熊猫那个视图

/// 小熊猫的图层和鼠标。点击只认画着小熊猫的那块（图层转过、翻过以后的外框），
/// 别处交给后面的窗口；不是前台 App 时第一下点击也算数。
final class DesktopPetSpriteView: NSView {
    private let sprite = CALayer()
    private var imageName = ""
    /// 草丛前后两层（见 `DesktopPetGrass`）：后层在小熊猫身后，前层挡在身前。
    private let grassBack = CALayer()
    private let grassFront = CALayer()
    private var grassNames: (front: String?, back: String?) = (nil, nil)
    private var grassRoot: CGPoint = .zero
    private var grassScale: CGFloat = 0
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        // 贴左右边、吊在上边时窗口不伸出那条边，伸出去的半只在这里裁掉。
        layer?.masksToBounds = true
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.contentsGravity = .resize
        sprite.minificationFilter = .linear
        sprite.shadowColor = .black
        sprite.shadowOpacity = 0.18
        sprite.shadowRadius = 2
        sprite.shadowOffset = CGSize(width: 0, height: -1)
        for grass in [grassBack, grassFront] {
            grass.anchorPoint = CGPoint(x: 0.5, y: 0)
            grass.contentsGravity = .resize
            grass.minificationFilter = .linear
            grass.opacity = 0
        }
        layer?.addSublayer(grassBack)
        layer?.addSublayer(sprite)
        layer?.addSublayer(grassFront)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tr("桌面宠物小熊猫"))
        // 访达拖来的文件放到小熊猫身上就暂存。只认画着小熊猫的那块（见 `hitTest`）。
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sprite.contentsScale = window?.backingScaleFactor ?? 2
        grassBack.contentsScale = sprite.contentsScale
        grassFront.contentsScale = sprite.contentsScale
    }

    /// 画草丛。`root` 是草根中点在窗口里的位置；名字给 nil 就淡出那一层。画面没变不提交。
    func drawGrass(front: String?, back: String?, root: CGPoint, scale: CGFloat) {
        if grassNames.front == front, grassNames.back == back, grassRoot == root, grassScale == scale { return }
        let fadeFront = (grassNames.front == nil) != (front == nil)
        let fadeBack = (grassNames.back == nil) != (back == nil)
        grassNames = (front, back)
        grassRoot = root
        grassScale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, name) in [(grassFront, front), (grassBack, back)] {
            guard let name, let image = DesktopPetArt.image(name), let cg = DesktopPetArt.cgImage(name) else { continue }
            layer.contents = cg
            layer.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
            layer.position = root
        }
        CATransaction.commit()
        // 出现、消失淡入淡出，走开时草不是一下没了。
        for (layer, name, fade) in [(grassFront, front, fadeFront), (grassBack, back, fadeBack)] where fade {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            layer.opacity = name == nil ? 0 : 1
            CATransaction.commit()
        }
    }

    /// 上一次画的参数：静止时慢计时器每秒 10 次来画，画面没变就不提交图层，省得窗口服务器白白重合成。
    private var lastDrawn: (image: String, size: CGSize, anchor: Double, position: CGPoint, rotation: Double,
                            scaleX: Double, scaleY: Double)?

    /// `anchor` 是转动、缩放的那一点在图高的哪儿（0 脚底，拎着时是后颈，吊着时是图顶的前爪抓握线），
    /// `position` 是那一点在窗口里的位置。
    func draw(image: String, size: CGSize, anchor: Double, position: CGPoint, rotation: Double,
              scaleX: Double, scaleY: Double) {
        if let last = lastDrawn, last.image == image, last.size == size, last.anchor == anchor,
           last.position == position, last.rotation == rotation, last.scaleX == scaleX, last.scaleY == scaleY,
           imageName == image {
            return
        }
        lastDrawn = (image, size, anchor, position, rotation, scaleX, scaleY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if image != imageName, let cg = DesktopPetArt.cgImage(image) {
            sprite.contents = cg
            imageName = image
        }
        sprite.transform = CATransform3DIdentity
        sprite.anchorPoint = CGPoint(x: 0.5, y: CGFloat(anchor))
        sprite.bounds = CGRect(origin: .zero, size: size)
        sprite.position = position
        var transform = CATransform3DMakeRotation(-CGFloat(rotation) * .pi / 180, 0, 0, 1)
        transform = CATransform3DScale(transform, CGFloat(scaleX), CGFloat(scaleY), 1)
        sprite.transform = transform
        CATransaction.commit()
    }

    /// 小熊猫看得见的那块（窗口坐标里，裁掉的不算），四周各收 3 点。
    private var hitRect: CGRect {
        let seen = sprite.frame.intersection(bounds)
        return seen.isNull ? .zero : seen.insetBy(dx: 3, dy: 3)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return hitRect.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private var inside = false

    private func updateHover(_ event: NSEvent) {
        let now = hitRect.contains(convert(event.locationInWindow, from: nil))
        DesktopPetController.shared.pointerMoved(now ? NSEvent.mouseLocation : nil,
                                                 pressed: NSEvent.pressedMouseButtons != 0)
        guard now != inside else { return }
        inside = now
        DesktopPetController.shared.hovering(now)
    }

    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) {
        DesktopPetController.shared.pointerMoved(nil, pressed: false)
        if inside {
            inside = false
            DesktopPetController.shared.hovering(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        DesktopPetController.shared.mouseDown(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        DesktopPetController.shared.mouseDragged(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        DesktopPetController.shared.mouseUp(at: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(DesktopPetController.shared.menu(), with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool {
        DesktopPetController.shared.summon()
        return true
    }

    // MARK: 拖文件到身上

    private var accepting = false

    private static func fileURLs(_ sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !Self.fileURLs(sender).isEmpty else { return [] }
        accepting = DesktopPetController.shared.filesEntered()
        return accepting ? .generic : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepting ? .generic : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        if accepting { DesktopPetController.shared.filesExited() }
        accepting = false
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepting }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { accepting = false }
        guard accepting else { return false }
        return DesktopPetController.shared.filesDropped(Self.fileURLs(sender))
    }
}

/// 盖在气泡、快捷条上面接鼠标的透明视图：SwiftUI 只管画，点击和悬停在这里按位置算，
/// 不是前台 App 时第一下点击也算数。
final class DesktopPetClickView: NSView {
    var isClickable = false
    var onClick: (@MainActor (CGPoint, CGFloat) -> Void)?
    var onHover: (@MainActor (CGPoint?, CGFloat) -> Void)?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isClickable else { return nil }
        return frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseExited(with event: NSEvent) { onHover?(nil, bounds.width) }

    private func hover(_ event: NSEvent) {
        onHover?(convert(event.locationInWindow, from: nil), bounds.width)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?(point, bounds.width)
    }
}

/// 右键菜单一项要跑的代码，挂在菜单项的 representedObject 上。
final class DesktopPetMenuAction: NSObject {
    let run: @MainActor () -> Void

    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }
}

// MARK: - 画面

/// 小熊猫头顶的气泡：码头状态的一句话、救回的「放回原处」按钮，或睡着时的 Zzz。
enum DesktopPetBubbleContent: Equatable {
    case news(String, until: Date)
    case rescue(String, items: [TrashedItem], until: Date)
    case zzz(Int)

    var until: Date? {
        switch self {
        case .news(_, let until), .rescue(_, _, let until): until
        case .zzz: nil
        }
    }

    var isNews: Bool { if case .news = self { true } else { false } }
    var isRescue: Bool { if case .rescue = self { true } else { false } }
    var isZzz: Bool { if case .zzz = self { true } else { false } }
}

@MainActor @Observable
final class DesktopPetBubbleModel {
    var content: DesktopPetBubbleContent?
}

@MainActor @Observable
final class DesktopPetQuickBarModel {
    var focusRunning = false
    var radioPlaying = false
    var radioAvailable = false
    var hovered: DesktopPetQuickAction?
}

/// 动作帧和静态图：读一次存着。动作帧是 @2x，显示成像素的一半。
@MainActor
enum DesktopPetArt {
    private static var cache: [String: NSImage] = [:]
    private static var cgCache: [String: CGImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            // 每个缺的图只记一次，动画每帧都会来要。
            if missing.insert(name).inserted { DockLog.error(.pet, "missing pet image \(name)") }
            return nil
        }
        if let rep = image.representations.first, rep.pixelsWide > 0, name.hasPrefix("pet-sprite-") {
            image.size = CGSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
        }
        cache[name] = image
        return image
    }

    static func cgImage(_ name: String) -> CGImage? {
        if let image = cgCache[name] { return image }
        guard let image = image(name)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        cgCache[name] = image
        return image
    }

    static func size(_ pose: DesktopPetPose) -> CGSize {
        guard let image = image(pose.image), image.size.height > 0 else { return CGSize(width: 50, height: 50) }
        guard let height = pose.height else { return image.size }
        return CGSize(width: image.size.width * CGFloat(height) / image.size.height, height: CGFloat(height))
    }
}

/// 气泡：Liquid Glass 胶囊，跟随浅色、深色。
struct DesktopPetBubbleView: View {
    let content: DesktopPetBubbleContent?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch content {
            case .news(let text, _):
                capsule { Text(text).lineLimit(2) }
            case .rescue(let title, _, _):
                capsule {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                        Text(title).lineLimit(1)
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(tr("把小熊猫叼回来的文件放回原来的位置"))
            case .zzz(let count):
                Text(String(repeating: "z", count: max(0, count - 1)) + "Z")
                    .font(.system(size: 13 + CGFloat(count) * 1.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(scheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.7))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .glassEffect(.regular, in: Capsule())
                    .accessibilityLabel(tr("小熊猫睡着了"))
            case nil:
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .fixedSize()
        .padding(2)
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 13, weight: .semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 220)
            .foregroundStyle(scheme == .dark ? Color.white : Color.black.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .glassEffect(.regular, in: Capsule())
    }
}

/// 快捷条：Liquid Glass 胶囊里一排图标按钮，悬停的那个垫一层中性浅色。
struct DesktopPetQuickBarView: View {
    let model: DesktopPetQuickBarModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DesktopPetQuickAction.allCases, id: \.self) { action in
                let enabled = action != .radio || model.radioAvailable
                Image(systemName: action.symbol(focusRunning: model.focusRunning, radioPlaying: model.radioPlaying))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink.opacity(enabled ? 1 : 0.4))
                    .frame(width: DesktopPetQuickAction.buttonSize.width,
                           height: DesktopPetQuickAction.buttonSize.height)
                    .background(Capsule().fill(ink.opacity(model.hovered == action && enabled ? 0.14 : 0)))
                    .accessibilityElement()
                    .accessibilityLabel(action.title(focusRunning: model.focusRunning,
                                                     radioPlaying: model.radioPlaying))
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(DesktopPetQuickAction.padding)
        .glassEffect(.regular, in: Capsule())
        .frame(width: DesktopPetQuickAction.barSize.width, height: DesktopPetQuickAction.barSize.height)
    }

    /// 浅色玻璃上用近黑，深色玻璃上用纯白，图标都看得清。
    private var ink: Color { scheme == .dark ? .white : Color.black.opacity(0.82) }
}
