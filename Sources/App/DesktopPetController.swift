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
/// 画面：小熊猫是一个 CALayer（图片、旋转、缩放、翻转都在图层上改，不经过 SwiftUI），
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
    private var transit: (feet: CGPoint, rotation: Double, start: Date, duration: TimeInterval)?
    /// 上一帧画在哪：过渡从这里开始。
    private var drawnFeet = CGPoint.zero
    private var drawnRotation: Double = 0
    private var drawnCenter = CGPoint.zero
    private var drawnSize = CGSize(width: 50, height: 50)

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
            MainActor.assumeIsolated { DesktopPetController.shared.refreshPlacement() }
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
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
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
        transit = nil
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
            }
        })
        wakeObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let pet = DesktopPetController.shared
                pet.screensAsleep = false
                pet.lastStep = Date()
                pet.refreshPlacement()
            }
        })
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
        let shelf = DesktopPetPlacement.Shelf(frame: shelfShown ? presence.revealedFrame() : nil,
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
                transit = (drawnFeet, drawnRotation, now, DesktopPetSnap.glideDuration)
                state = DesktopPetBrain.landed(current, at: along, now: now)
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
        shown = true
        updateClock(now: Date())
    }

    private func hide() {
        stopClocks()
        panel?.orderOut(nil)
        bubblePanel?.orderOut(nil)
        barPanel?.orderOut(nil)
        shown = false
        dragging = false
        transit = nil
        // 藏着时错过的变化（全屏里插了电）出来以后不补说。
        newsPrimed = false
    }

    // MARK: 时钟

    /// 动的时候开显示刷新，静止时停掉，只留慢计时器。
    private func updateClock(now: Date) {
        guard shown, let state else { return stopClocks() }
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
            let rate = DesktopPetBrain.tickRate(state)
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

    private func advance() {
        guard shown, let track, var current = state else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastStep)
        lastStep = now

        let timer = TimerStateProvider.shared.state
        let companion = ProLicenseGate.canUseFocusPanda(unlocked: ProAccess.isUnlocked)
        if companion, let last = lastTimer, FocusPandaClimb.event(from: last, to: timer, now: now) == .cheer {
            current = DesktopPetBrain.cheer(current, now: now)
        }
        lastTimer = timer
        let focusing = companion && FocusPandaClimb.isActive(timer)

        current = DesktopPetBrain.step(current, dt: dt, now: now, lane: track.lane,
                                       userIdle: Self.userIdleSeconds(), focusing: focusing,
                                       style: track.style, attention: attention(track: track),
                                       random: { Double.random(in: 0...1) })
        state = current
        if DesktopPetBrain.awaitingPutBack(current) { putBack() }
        if let content = bubble.content, let until = content.until, now >= until { setBubble(nil) }
        // 指针移得太快时离开的事件可能没来：按指针实际位置补一次。
        let pointer = NSEvent.mouseLocation
        if petHovering, !CGRect(x: drawnCenter.x - drawnSize.width / 2 - 4, y: drawnCenter.y - drawnSize.height / 2 - 4,
                                width: drawnSize.width + 8, height: drawnSize.height + 8).contains(pointer) {
            hovering(false)
        }
        if barHovering, barPanel?.frame.contains(pointer) != true { barHover(nil, width: 0) }
        if let until = barVisibleUntil, now >= until, !barHovering, !petHovering { hideBar() }
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
        let pose = DesktopPetBrain.pose(state, now: now)
        let scale = CGFloat(settings.size.scale)
        let base = DesktopPetArt.size(pose)
        let size = CGSize(width: base.width * scale, height: base.height * scale)

        var feet = dragging ? dragFeet : track.feet(along: state.x, lift: pose.lift * Double(scale))
        var rotation = dragging ? 0 : track.edge.rotation
        if let transit {
            let t = now.timeIntervalSince(transit.start) / transit.duration
            let eased = DesktopPetSnap.glide(t)
            feet = CGPoint(x: transit.feet.x + (feet.x - transit.feet.x) * eased,
                           y: transit.feet.y + (feet.y - transit.feet.y) * eased)
            rotation = DesktopPetSnap.angle(from: transit.rotation, to: rotation, t: min(1, t * 1.3))
            if t >= 1 { self.transit = nil }
        }
        let flip = dragging ? pose.facingLeft : track.edge.flipped(facingLeft: pose.facingLeft)

        let radians = rotation * .pi / 180
        let up = CGPoint(x: sin(radians), y: cos(radians))
        let tall = size.height * CGFloat(pose.scaleY)
        let center = CGPoint(x: feet.x + up.x * tall / 2, y: feet.y + up.y * tall / 2)
        let side = (Self.windowSide * scale).rounded(.up)
        let originX = (center.x - side / 2).rounded(.down)
        let originY = (center.y - side / 2).rounded(.down)
        let origin = CGPoint(x: originX, y: originY)
        if panel.frame.size != CGSize(width: side, height: side) {
            panel.setFrame(CGRect(origin: origin, size: CGSize(width: side, height: side)), display: false)
        } else if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        // 窗口原点是整数点，剩下不足一点的放进图层位置，慢慢走也是平滑的。
        let localCenter = CGPoint(x: center.x - originX, y: center.y - originY)
        let localFeet = CGPoint(x: localCenter.x - up.x * tall / 2, y: localCenter.y - up.y * tall / 2)
        view.draw(image: pose.image, size: size, feet: localFeet,
                  rotation: rotation + pose.wobble, scaleX: pose.scaleX * (flip ? -1 : 1), scaleY: pose.scaleY)

        drawnFeet = feet
        drawnRotation = rotation
        drawnCenter = center
        drawnSize = size

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
            // 抓着后颈提起来：脚在指针下面一点，拖起来那一下滑过去。
            transit = (drawnFeet, drawnRotation, now, 0.14)
            current = DesktopPetBrain.grabbed(current, now: now)
            hideBar()
            if bubble.content?.isNews == true || bubble.content?.isZzz == true { setBubble(nil) }
        }
        let hang = drawnSize.height * 0.62
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
            if pressPoint != nil { clicked() }
            return
        }
        dragging = false
        drop(at: dragFeet)
    }

    /// 单击：跳一下，浮出快捷条。
    private func clicked() {
        guard let current = state else { return }
        let now = Date()
        state = DesktopPetBrain.poked(current, now: now)
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
        transit = (drawnFeet, drawnRotation, now, DesktopPetSnap.glideDuration)
        state = DesktopPetBrain.landed(current, at: along, now: now)
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
            if !dragging { showBar(for: nil) }
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
            announce(news)
        }
        if let news = DesktopPetNewsDesk.radio(wasPlaying: radioWasPlaying, oldStation: radioStation,
                                               playing: playing, station: radio.station?.name) {
            announce(news)
        }
        if let power, let news = DesktopPetNewsDesk.battery(from: lastPower, to: power) {
            announce(news)
        }
    }

    private var newsTimer: TimerState?

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

    /// 快捷条和气泡放在小熊猫“外侧”（离开那条边的方向）；随意放的时候快捷条在下面、
    /// 气泡在头顶。都夹在屏幕可见区域里。
    private func positionFloats() {
        guard shown, let track else { return }
        let visible = (trackScreen ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let barShown = barPanel?.isVisible == true
        let barSize = barPanel?.frame.size ?? DesktopPetQuickAction.barSize
        let petHalf = CGSize(width: drawnSize.width / 2, height: drawnSize.height / 2)
        let center = drawnCenter
        let edge = dragging ? DesktopPetEdge.bottom : track.edge
        let gap: CGFloat = 8

        var barCenter = center
        switch (edge, track.style) {
        case (.bottom, .sit):
            barCenter.y = center.y - petHalf.height - gap - barSize.height / 2
            if barCenter.y - barSize.height / 2 < visible.minY {
                barCenter.y = center.y + petHalf.height + gap + barSize.height / 2
            }
        case (.bottom, _):
            barCenter.y = center.y + petHalf.height + gap + barSize.height / 2
        case (.top, _):
            barCenter.y = center.y - petHalf.height - gap - barSize.height / 2
        case (.left, _):
            barCenter.x = center.x + petHalf.height + gap + barSize.width / 2
        case (.right, _):
            barCenter.x = center.x - petHalf.height - gap - barSize.width / 2
        }
        if let barPanel, barShown {
            let frame = clampRect(CGRect(x: barCenter.x - barSize.width / 2, y: barCenter.y - barSize.height / 2,
                                         width: barSize.width, height: barSize.height), in: visible)
            if barPanel.frame.origin != frame.origin { barPanel.setFrameOrigin(frame.origin) }
        }

        guard let bubblePanel, bubblePanel.isVisible else { return }
        let size = bubblePanel.frame.size
        var bubbleCenter = center
        let barAbove = barShown && barCenter.y > center.y && !edge.vertical
        let barBelow = barShown && barCenter.y < center.y && !edge.vertical
        switch edge {
        case .bottom:
            bubbleCenter.y = center.y + petHalf.height + gap / 2 + size.height / 2
            if barAbove { bubbleCenter.y += barSize.height + gap }
        case .top:
            bubbleCenter.y = center.y - petHalf.height - gap / 2 - size.height / 2
            if barBelow { bubbleCenter.y -= barSize.height + gap }
        case .left:
            bubbleCenter.x = center.x + petHalf.height + gap + size.width / 2
            if barShown { bubbleCenter.y += barSize.height / 2 + gap + size.height / 2 }
        case .right:
            bubbleCenter.x = center.x - petHalf.height - gap - size.width / 2
            if barShown { bubbleCenter.y += barSize.height / 2 + gap + size.height / 2 }
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
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.contentsGravity = .resize
        sprite.minificationFilter = .linear
        sprite.shadowColor = .black
        sprite.shadowOpacity = 0.18
        sprite.shadowRadius = 2
        sprite.shadowOffset = CGSize(width: 0, height: -1)
        layer?.addSublayer(sprite)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tr("桌面宠物小熊猫"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sprite.contentsScale = window?.backingScaleFactor ?? 2
    }

    func draw(image: String, size: CGSize, feet: CGPoint, rotation: Double, scaleX: Double, scaleY: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if image != imageName, let cg = DesktopPetArt.cgImage(image) {
            sprite.contents = cg
            imageName = image
        }
        sprite.transform = CATransform3DIdentity
        sprite.bounds = CGRect(origin: .zero, size: size)
        sprite.position = feet
        var transform = CATransform3DMakeRotation(-CGFloat(rotation) * .pi / 180, 0, 0, 1)
        transform = CATransform3DScale(transform, CGFloat(scaleX), CGFloat(scaleY), 1)
        sprite.transform = transform
        CATransaction.commit()
    }

    /// 小熊猫占的那块（窗口坐标里），四周各收 3 点。
    private var hitRect: CGRect { sprite.frame.insetBy(dx: 3, dy: 3) }

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
        guard now != inside else { return }
        inside = now
        DesktopPetController.shared.hovering(now)
    }

    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) {
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

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
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
