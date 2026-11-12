import AppKit
import IOKit.ps
import SwiftUI

/// 插上电源时的霓虹动画（码头 Pro，设置里「插电时霓虹动画」，默认开）。
///
/// 盯着电源变化（IOPS 通知，不轮询）：从电池切到接通电源的那一下，在有刘海的屏幕顶部
/// 中间弹一个透明、点击穿透、置顶的窗口，播约 2.5 秒：刘海边缘亮一下，一滴光从刘海
/// 落下，落进屏幕中央偏上的霓虹电量数字，从下往上灌到当前电量，数字淡出；刘海右边
/// 留一个「⚡ 23%」小胶囊约 3 秒后淡出。没有刘海的屏幕从菜单栏中间落下，胶囊在菜单栏
/// 下面。
///
/// 什么时候不播（判断在 Core 的 `BatteryNeon.plugDecision`，有测试）：开关关着、没解锁、
/// 有全屏 App、系统屏幕共享在看这台 Mac、码头的演示模式开着、刘海那里码头已有东西
/// 展开着（消息灵动岛的卡片、AI 刘海对话、提醒弹窗、音量亮度的灵动提示），以及
/// 30 秒内已经播过一次。减少动态效果时只留小胶囊。
@MainActor
final class BatteryNeonPlugController {
    static let shared = BatteryNeonPlugController()

    private var source: CFRunLoopSource?
    private var last: BatteryNeon.PowerSource?
    private var gate = BatteryNeon.PlugGate()
    private var panel: NSPanel?
    private var closeTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard source == nil else { return }
        last = Self.read()?.source
        // 回调在主线程的 run loop 上跑（下面加到 main run loop）。
        guard let created = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { BatteryNeonPlugController.shared.powerChanged() }
        }, nil)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
    }

    // MARK: 电源

    struct Reading {
        var source: BatteryNeon.PowerSource
        var percent: Int
        var minutesToFull: Int?
    }

    /// 内置电池的电量和电源来路；台式机（没有内置电池）是 nil。
    static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue()
                    as? [String: Any],
                  (description[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey as String] as? Int, capacity > 0 else { continue }
            let onPower = (description[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue
            let minutes = (description[kIOPSTimeToFullChargeKey as String] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return Reading(source: onPower ? .ac : .battery,
                           percent: Int((Double(current) / Double(capacity) * 100).rounded()),
                           minutesToFull: minutes)
        }
        return nil
    }

    private func powerChanged() {
        let current = Self.read()
        let previous = last
        last = current?.source
        guard let current, BatteryNeon.isPlugIn(from: previous, to: current.source),
              let screen = Self.targetScreen() else { return }
        let now = Date()
        let context = BatteryNeon.PlugContext(
            enabled: BatteryNeon.plugAnimationEnabled(stored: UserDefaults.standard.object(forKey: BatteryNeon.plugAnimationKey)),
            unlocked: ProAccess.isUnlocked,
            fullscreen: NotchFullscreen.isFullscreen(
                NotchWindowScanner.windows(), screen: screen.frame, topInset: screen.safeAreaInsets.top,
                frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                ownPID: ProcessInfo.processInfo.processIdentifier),
            sharing: Self.screenShared(),
            presenting: QuickActions.shared.presentation != nil,
            notchBusy: NotchMessageOccupancy.shared.cardExpanded || AINotchController.shared.isOpen
                || ReminderPopupCenter.shared.isShowing || IslandOccupancy.shared.frame != nil)
        guard BatteryNeon.plugDecision(context, gate: gate, at: now) == .play else { return }
        gate.recordPlay(at: now)
        play(current, on: screen)
    }

    /// 带刘海的那块屏幕（MacBook 自己的屏幕）；没有就是带菜单栏的主屏。
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    /// 系统屏幕共享、远程管理正在看这台 Mac（会议软件的共享屏幕读不到）。
    private static func screenShared() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return ReminderSoundDecision.screenShared(sessionValue: session["CGSSessionScreenIsShared"]) ?? false
    }

    // MARK: 窗口

    private func play(_ reading: Reading, on screen: NSScreen) {
        closeTask?.cancel()
        panel?.orderOut(nil)

        let frame = screen.frame
        let notch = AINotchLayout.notchRect(screen: frame, topInset: screen.safeAreaInsets.top,
                                            leftArea: screen.auxiliaryTopLeftArea,
                                            rightArea: screen.auxiliaryTopRightArea)
        var menuBar = frame.maxY - screen.visibleFrame.maxY
        if menuBar <= 0 { menuBar = notch?.height ?? AINotchLayout.fallbackMenuBarHeight }
        let width = min(frame.width, 520)
        let centerX = notch?.midX ?? frame.midX
        let digitsCenter = max(menuBar + 120, frame.height * 0.27)
        let height = min(frame.height, digitsCenter + 130)
        let windowFrame = CGRect(x: max(frame.minX, min(centerX - width / 2, frame.maxX - width)),
                                 y: frame.maxY - height, width: width, height: height)
        // 刘海在窗口里的位置（SwiftUI 坐标，原点左上）。
        let localNotch = notch.map {
            CGRect(x: $0.minX - windowFrame.minX, y: 0, width: $0.width, height: $0.height)
        }

        let scene = BatteryNeonPlugScene(
            start: .now, percent: reading.percent,
            status: Self.status(reading),
            notch: localNotch, menuBar: menuBar,
            originX: centerX - windowFrame.minX, digitsCenter: digitsCenter,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        let panel = self.panel ?? makePanel()
        panel.setFrame(windowFrame, display: false)
        let host = NSHostingView(rootView: BatteryNeonPlugView(scene: scene))
        host.frame = CGRect(origin: .zero, size: windowFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()

        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BatteryNeon.Plug.total + 0.1))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel?.contentView = nil
        }
    }

    /// 「充电中 · 2 小时 05 分充满」；系统还在估算时只写「充电中」。
    private static func status(_ reading: Reading) -> String {
        guard let time = BatteryNeon.hoursMinutes(reading.minutesToFull) else { return tr("充电中") }
        let text = time.hours > 0
            ? tr("\(time.hours) 小时 \(String(format: "%02d", time.minutes)) 分充满")
            : tr("\(time.minutes) 分钟后充满")
        return tr("充电中") + " · " + text
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        // 比菜单栏高一层，刘海旁的小胶囊盖在菜单栏上面。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

// MARK: - 画面

/// 一次插电动画要的全部东西，坐标是窗口里的（原点左上）。
struct BatteryNeonPlugScene {
    var start: Date
    var percent: Int
    var status: String
    /// 刘海的位置；没有刘海时 nil，从菜单栏中间落下。
    var notch: CGRect?
    var menuBar: CGFloat
    /// 光滴落下的那条竖线（刘海或菜单栏的中间）。
    var originX: CGFloat
    /// 霓虹数字的中心离窗口顶边多远。
    var digitsCenter: CGFloat
    var reduceMotion: Bool

    static let digitSize: CGFloat = 112

    /// 这一刻画什么。减少动态效果时只留小胶囊（淡入淡出照旧）。
    func frame(at t: TimeInterval) -> BatteryNeon.Plug.Frame {
        var frame = BatteryNeon.Plug.frame(at: t)
        if reduceMotion {
            frame.edgeGlow = 0
            frame.drop = nil
            frame.digits = 0
        }
        return frame
    }
}

struct BatteryNeonPlugView: View {
    var scene: BatteryNeonPlugScene

    private var color: Color { BatteryNeon.color(percent: scene.percent, dark: true).neonColor }
    private var core: Color { BatteryNeon.core(BatteryNeon.color(percent: scene.percent, dark: true), dark: true).neonColor }
    /// 光滴落到的地方：数字的顶。
    private var digitsTop: CGFloat { scene.digitsCenter - BatteryNeonPlugScene.digitSize * 0.38 }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(scene.start)
            let frame = scene.frame(at: t)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawEdge(&context, glow: frame.edgeGlow)
                    if let drop = frame.drop { drawDrop(&context, progress: drop) }
                }
                if frame.digits > 0 { digits(frame) }
                if frame.chip > 0 { chip.opacity(frame.chip) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // 刘海边缘（或菜单栏中间一段）亮一下：一道细亮线，外面一圈柔光。
    private func edgePath() -> Path {
        if let notch = scene.notch {
            let rect = CGRect(x: notch.minX - 1, y: -14, width: notch.width + 2, height: notch.height + 15)
            return Path(roundedRect: rect, cornerRadius: 11)
        }
        var path = Path()
        path.move(to: CGPoint(x: scene.originX - 90, y: scene.menuBar))
        path.addLine(to: CGPoint(x: scene.originX + 90, y: scene.menuBar))
        return path
    }

    private func drawEdge(_ context: inout GraphicsContext, glow: Double) {
        guard glow > 0 else { return }
        let path = edgePath()
        var halo = context
        halo.addFilter(.blur(radius: 9))
        halo.stroke(path, with: .color(color.opacity(0.9 * glow)), lineWidth: 7)
        context.stroke(path, with: .color(core.opacity(glow)), lineWidth: 1.5)
    }

    /// 一滴光：圆头在下、尖尾在上，越落越拉长。
    private func drawDrop(_ context: inout GraphicsContext, progress: Double) {
        let top = scene.notch.map { $0.maxY } ?? scene.menuBar
        let y = top + 6 + (digitsTop - top - 6) * progress
        let r: CGFloat = 5.5
        let tail = r * (2.2 + 2.5 * progress)
        var drop = Path()
        drop.move(to: CGPoint(x: scene.originX, y: y - tail))
        drop.addQuadCurve(to: CGPoint(x: scene.originX + r, y: y),
                          control: CGPoint(x: scene.originX + r * 0.2, y: y - r * 1.2))
        drop.addArc(center: CGPoint(x: scene.originX, y: y), radius: r, startAngle: .zero,
                    endAngle: .degrees(180), clockwise: false)
        drop.addQuadCurve(to: CGPoint(x: scene.originX, y: y - tail),
                          control: CGPoint(x: scene.originX - r * 0.2, y: y - r * 1.2))
        drop.closeSubpath()
        var halo = context
        halo.addFilter(.blur(radius: 8))
        halo.fill(drop, with: .color(color.opacity(0.9)))
        context.fill(drop, with: .color(core))
    }

    private func digits(_ frame: BatteryNeon.Plug.Frame) -> some View {
        VStack(spacing: 10) {
            BatteryNeonDigits(text: "\(scene.percent)", percent: scene.percent,
                              fraction: BatteryNeon.fillFraction(percent: scene.percent) * frame.fill,
                              fontSize: BatteryNeonPlugScene.digitSize, showsPercentSign: false, forceDark: true)
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill").foregroundStyle(color)
                Text(verbatim: scene.status).foregroundStyle(.white.opacity(0.92))
            }
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .shadow(color: .black.opacity(0.5), radius: 3)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .background {
            // 不管桌面多亮，数字后面都有一团淡淡的暗，灯管看得清。
            Ellipse().fill(.black.opacity(0.32)).blur(radius: 36)
        }
        .fixedSize()
        .opacity(frame.digits)
        .position(x: scene.originX, y: scene.digitsCenter + 14)
    }

    /// 刘海右边的「⚡ 23%」小胶囊（没有刘海时在菜单栏下面），玻璃底。
    private var chip: some View {
        let content = HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(color)
            Text(verbatim: "\(scene.percent)%")
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(.black.opacity(0.55))
            Color.clear.glassEffect(.regular, in: Capsule())
            Capsule().strokeBorder(color.opacity(0.75), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .fixedSize()
        return Group {
            if let notch = scene.notch {
                content
                    .position(x: notch.maxX + 12 + 34, y: notch.height / 2)
            } else {
                content
                    .position(x: scene.originX, y: scene.menuBar + 18)
            }
        }
    }
}
