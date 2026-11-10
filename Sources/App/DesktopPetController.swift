import AppKit
import Observation
import SwiftUI

/// 桌面宠物：一个透明、点击穿透的小窗口贴在程序坞（系统程序坞或码头扩展栏，
/// 在底边、看得见的那条）上沿，小熊猫左右散步、停下发呆，用户几分钟没操作就睡觉，
/// 点它跳一下。全屏 App 在前、程序坞自动隐藏时不显示。
///
/// 两个计时器：每 1.5 秒看一次程序坞在哪、要不要显示（读程序坞在后台队列）；
/// 显示着才开的动画计时器，每秒 8 帧，睡着时每秒 2 帧。窗口只在小熊猫（和气泡）
/// 底下接鼠标，别处点下去落到后面的窗口。
///
/// 废纸篓救回（单独的开关）：刚拖进废纸篓的文件，小熊猫跑到废纸篓（读不到图标位置
/// 时到程序坞最右端），叼着跑回来，请访达放回原处；访达不让时弹一个「放回原处」的
/// 气泡按钮。专注陪伴（码头 Pro）：专注计时走着时坐着不乱跑，完成一轮欢呼。
@MainActor
final class DesktopPetController {
    static let shared = DesktopPetController()

    private var settings = DesktopPetSettings()
    /// 扩展栏贴在哪条边（浮动的按朝向），启动时由 App 接上。
    var shelfPosition: @MainActor () -> DockPosition? = { nil }
    private var panel: NSPanel?
    private let model = DesktopPetModel()

    private var geometryTimer: Timer?
    private var animationTimer: Timer?
    private var animationRate: Double = 0
    private var lastStep = Date()
    private var reading = false
    private var sleeping = false
    private var wakeObservers: [NSObjectProtocol] = []

    private var perch: DesktopPetPerch?
    private var state: DesktopPetState?
    private var lastTimer: TimerState?

    // 废纸篓救回
    private var seen: Set<String> = []
    private var seeded = false
    private var lastTrashCount = 0
    private var rescuing: [TrashedItem] = []
    private var putBackInFlight = false
    private var trashSource: DispatchSourceFileSystemObject?

    /// 小熊猫底下比程序坞上沿低多少（脚踩进程序坞一点点）。
    static let footSink: CGFloat = 4
    /// 窗口比程序坞两头各宽多少，跳起来、气泡都在窗口里。
    static let sideMargin: CGFloat = 70
    static let windowHeight: CGFloat = 150

    private init() {}

    // MARK: 开关

    func apply(_ next: DesktopPetSettings) {
        let before = settings
        settings = next
        if next.enabled {
            start()
        } else {
            stop()
        }
        if next.rescueActive != before.rescueActive || (next.rescueActive && trashSource == nil) {
            next.rescueActive ? startRescueWatch() : stopRescueWatch()
        }
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
        refreshPlacement()
    }

    private func stop() {
        geometryTimer?.invalidate()
        geometryTimer = nil
        stopAnimation()
        stopRescueWatch()
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
        panel?.orderOut(nil)
        panel = nil
        perch = nil
        state = nil
        lastTimer = nil
        model.bubble = nil
    }

    /// 屏幕睡了就全停，醒了再接着看。
    private func observeSleep() {
        guard wakeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        wakeObservers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let pet = DesktopPetController.shared
                pet.sleeping = true
                pet.stopAnimation()
            }
        })
        wakeObservers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let pet = DesktopPetController.shared
                pet.sleeping = false
                pet.refreshPlacement()
            }
        })
    }

    // MARK: 站在哪

    private func refreshPlacement() {
        guard settings.enabled, !sleeping, !reading else { return }
        reading = true
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let screen = (perch.flatMap { p in NSScreen.screens.first { $0.frame.intersects(p.frame) } }
            ?? NSScreen.screens.first)?.frame
        DesktopPetDockReader.queue.async {
            let reading = DesktopPetDockReader.shared.read(primaryHeight: primaryHeight,
                                                           frontPID: frontPID, screen: screen)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DesktopPetController.shared.placed(reading) }
            }
        }
    }

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
        let next = DesktopPetPlacement.perch(system: system, shelf: shelf, fullScreen: reading.fullScreen)
        perch = next
        checkTrash()
        guard let next else {
            hide()
            return
        }
        show(on: next)
    }

    private func show(on perch: DesktopPetPerch) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let frame = CGRect(x: perch.frame.minX - Self.sideMargin, y: perch.frame.maxY - Self.footSink,
                           width: perch.frame.width + Self.sideMargin * 2, height: Self.windowHeight)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        model.origin = frame.origin
        let now = Date()
        if state == nil {
            state = DesktopPetBrain.initial(lane: perch.lane, now: now)
            lastStep = now
        }
        render(now: now)
        if !panel.isVisible { panel.orderFrontRegardless() }
        startAnimation()
    }

    private func hide() {
        stopAnimation()
        panel?.orderOut(nil)
    }

    // MARK: 动画

    private func startAnimation() {
        let rate = state.map(DesktopPetBrain.tickRate) ?? DesktopPetBrain.fps
        guard animationTimer == nil || animationRate != rate else { return }
        animationTimer?.invalidate()
        animationRate = rate
        let timer = Timer(timeInterval: 1 / rate, repeats: true) { _ in
            MainActor.assumeIsolated { DesktopPetController.shared.tick() }
        }
        timer.tolerance = 0.25 / rate
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
        lastStep = Date()
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationRate = 0
    }

    private func tick() {
        guard let perch, var current = state else { return }
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

        current = DesktopPetBrain.step(current, dt: dt, now: now, lane: perch.lane,
                                       userIdle: Self.userIdleSeconds(), focusing: focusing,
                                       random: { Double.random(in: 0...1) })
        state = current
        if DesktopPetBrain.awaitingPutBack(current) { putBack() }
        if let bubble = model.bubble, let until = bubble.until, now >= until { model.bubble = nil }
        render(now: now)
        // 睡着、醒来换计时器的快慢。
        if DesktopPetBrain.tickRate(current) != animationRate { startAnimation() }
    }

    private func render(now: Date) {
        guard let state else { return }
        let pose = DesktopPetBrain.pose(state, now: now)
        model.pose = pose
        model.x = CGFloat(state.x) - model.origin.x
        updateHitTesting(pose: pose, x: CGFloat(state.x))
    }

    /// 只在小熊猫和气泡底下接鼠标；别处点击穿透到后面。
    private func updateHitTesting(pose: DesktopPetPose, x: CGFloat) {
        guard let panel else { return }
        let size = DesktopPetArt.size(pose)
        let bottom = model.origin.y + CGFloat(pose.lift)
        var hit = CGRect(x: x - size.width / 2, y: bottom, width: size.width, height: size.height)
            .insetBy(dx: 6, dy: 4)
        if model.bubble != nil {
            hit = hit.union(CGRect(x: x - 110, y: bottom + size.height, width: 220, height: 44))
        }
        let inside = hit.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    /// 被点了：跳一下。
    func poke() {
        guard let current = state else { return }
        let now = Date()
        state = DesktopPetBrain.poked(current, now: now)
        render(now: now)
        startAnimation()
    }

    private static func userIdleSeconds() -> TimeInterval {
        guard let any = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }

    // MARK: 窗口

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: Self.windowHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let host = DesktopPetHostingView(rootView: DesktopPetView(model: model))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
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
        guard let perch, var current = state, rescuing.isEmpty, !putBackInFlight else { return }
        if case .rescue = current.activity { return }
        rescuing = fresh
        autoPutBack = DesktopPetRescue.autoPutBack(fresh: fresh.count, added: added)
        model.bubble = nil
        current = DesktopPetBrain.startRescue(current, trashX: perch.rescueX, lane: perch.lane, now: now)
        state = current
        render(now: now)
        startAnimation()
    }

    private var autoPutBack = true

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
        state = DesktopPetBrain.finishRescue(current, succeeded: failed.isEmpty, now: now)
        if !failed.isEmpty {
            model.bubble = DesktopPetBubble(title: DesktopPetRescue.bubbleTitle(count: failed.count),
                                            items: failed, until: now.addingTimeInterval(20))
        }
        render(now: now)
    }

    /// 气泡上的「放回原处」：直接移回访达记下的原位置。放不回去时气泡换成原因。
    func putBackFromBubble() {
        guard let bubble = model.bubble, !bubble.items.isEmpty else {
            model.bubble = nil
            return
        }
        var messages: [String] = []
        for item in bubble.items {
            if let message = TrashMonitor.shared.putBack(item) { messages.append(message) }
        }
        let now = Date()
        if let message = messages.first {
            model.bubble = DesktopPetBubble(title: message, items: [], until: now.addingTimeInterval(6))
        } else {
            model.bubble = nil
            if let current = state { state = DesktopPetBrain.cheer(current, now: now) }
        }
        render(now: now)
    }
}

// MARK: - 画面

/// 小熊猫的气泡：「放回原处」按钮，或放不回去的原因。
struct DesktopPetBubble: Equatable {
    var title: String
    /// 点按钮要放回的；空的是只显示一句话。
    var items: [TrashedItem]
    var until: Date?
}

@MainActor @Observable
final class DesktopPetModel {
    var pose = DesktopPetPose(image: "pet-panda-idle")
    /// 小熊猫中心在窗口里的横坐标。
    var x: CGFloat = 0
    @ObservationIgnored var origin: CGPoint = .zero
    var bubble: DesktopPetBubble?
}

/// 动作帧和静态图：读一次存着。动作帧是 @2x，显示成像素的一半。
@MainActor
enum DesktopPetArt {
    private static var cache: [String: NSImage] = [:]

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

    static func size(_ pose: DesktopPetPose) -> CGSize {
        guard let image = image(pose.image), image.size.height > 0 else { return CGSize(width: 50, height: 50) }
        guard let height = pose.height else { return image.size }
        return CGSize(width: image.size.width * CGFloat(height) / image.size.height, height: CGFloat(height))
    }
}

struct DesktopPetView: View {
    let model: DesktopPetModel

    var body: some View {
        GeometryReader { proxy in
            let pose = model.pose
            let size = DesktopPetArt.size(pose)
            let bottom = proxy.size.height - CGFloat(pose.lift)
            ZStack(alignment: .topLeading) {
                if let image = DesktopPetArt.image(pose.image) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(x: pose.facingLeft ? -1 : 1, y: 1)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .contentShape(.rect)
                        .onTapGesture { DesktopPetController.shared.poke() }
                        .position(x: model.x, y: bottom - size.height / 2)
                        .accessibilityLabel(tr("桌面宠物小熊猫"))
                }
                if let bubble = model.bubble {
                    DesktopPetBubbleView(bubble: bubble)
                        .position(x: min(max(model.x, 110), proxy.size.width - 110),
                                  y: max(18, bottom - size.height - 20))
                }
            }
        }
    }
}

/// 气泡：Liquid Glass 胶囊，「放回原处」是按钮，原因只是一行字。
private struct DesktopPetBubbleView: View {
    let bubble: DesktopPetBubble
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if bubble.items.isEmpty {
                label
            } else {
                Button { DesktopPetController.shared.putBackFromBubble() } label: { label }
                    .buttonStyle(.plain)
                    .help(tr("把小熊猫叼回来的文件放回原来的位置"))
            }
        }
        .fixedSize()
    }

    private var label: some View {
        HStack(spacing: 6) {
            if !bubble.items.isEmpty {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(bubble.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 200)
        }
        .foregroundStyle(scheme == .dark ? Color.white : Color.black.opacity(0.85))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
    }
}

/// 不是前台窗口时第一下点击也算数：点小熊猫不用先点一下激活。
private final class DesktopPetHostingView: NSHostingView<DesktopPetView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
