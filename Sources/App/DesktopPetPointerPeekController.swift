import AppKit
import CoreAudio
import Foundation

/// 指针旁探头的窗口：鼠标停着约 20 秒，所选吉祥物在指针旁扒着一条看不见的水平边探出头，一动就收起。
///
/// 图层：`tiltLayer`（以遮罩边中点为轴朝指针歪几度）里先放一道极淡的接触阴影，再放 `clipLayer`
/// （只露边上面那一截，`masksToBounds`），里面的 `riseLayer` 管出场时的升起、停顿压一下和回弹，
/// 最里面是整张图（底下一截在边后面被裁掉）。
///
/// 规则在 Core 的 `DesktopPetPointerPeek`。平时每秒读一次系统的空闲秒数（不要辅助功能权限）；
/// 露着时挂一个鼠标事件的全局监听，一动立刻收起，收起后就摘掉。静止时只是一张图，不开显示刷新。
/// 窗口不接鼠标、不抢焦点，也不进屏幕共享和录屏（`sharingType = .none`，系统支持时生效）。
@MainActor
final class DesktopPetPointerPeekController {
    static let shared = DesktopPetPointerPeekController()

    private init() {}

    private var settings = DesktopPetSettings()
    private var timer: Timer?
    private var panel: NSPanel?
    private var tiltLayer: CALayer?
    private var shadowLayer: CALayer?
    private var clipLayer: CALayer?
    private var riseLayer: CALayer?
    private var imageLayer: CALayer?
    private var monitor: Any?
    private var shownAt: CGPoint?
    /// 收起以后，鼠标再动过一次才可以再出来（同一段静止只出来一次）。
    private var waitingForMove = false
    private var lastPointer = NSEvent.mouseLocation

    func apply(_ next: DesktopPetSettings) {
        settings = next
        if next.enabled, next.pointerPeek {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { DesktopPetPointerPeekController.shared.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        lastPointer = NSEvent.mouseLocation
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        hide(animated: false)
    }

    private func tick() {
        let pointer = NSEvent.mouseLocation
        if DesktopPetPointerPeek.moved(from: lastPointer, to: pointer) { waitingForMove = false }
        lastPointer = pointer
        let quiet = settings.quietInCalls && MicrophoneActivity.inUse()
        let wanted = DesktopPetPointerPeek.wanted(pointerIdle: Self.idle(.mouseMoved),
                                                  keyIdle: Self.idle(.keyDown),
                                                  quiet: quiet,
                                                  pressed: NSEvent.pressedMouseButtons != 0)
        if shownAt != nil {
            if !wanted { hide(animated: true) }
        } else if wanted, !waitingForMove {
            show(at: pointer)
        }
    }

    private static func idle(_ type: CGEventType) -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
    }

    // MARK: 露出、收起

    private func show(at pointer: CGPoint) {
        guard let found = currentImage(),
              let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return }
        let (name, image, mascot) = found
        let cut = DesktopPetPointerPeek.cut(forImage: name, mascot: mascot)
        let layout = DesktopPetPointerPeek.layout(imageSize: image.size, cut: cut, scale: settings.size.scale)
        let frame = DesktopPetPointerPeek.frame(pointer: pointer, size: layout.panel, bounds: screen.visibleFrame)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)
        arrange(layout, image: image, scaleFactor: screen.backingScaleFactor,
                lean: DesktopPetPointerPeek.lean(pointerOnRight: frame.midX < pointer.x))
        shownAt = pointer
        watchPointer()

        // 从边后面慢慢升起、停住压一下、轻轻回弹；减弱动态效果时直接出现，没有动画。
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        animateEntrance(DesktopPetPointerPeek.entrance(reduceMotion: reduce))
    }

    /// 按摆法放好各层（点，y 向上，原点在窗口左下角）。
    private func arrange(_ layout: DesktopPetPointerPeek.Layout, image: NSImage, scaleFactor: CGFloat, lean: Double) {
        guard let tiltLayer, let shadowLayer, let clipLayer, let riseLayer, let imageLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let margin = CGFloat(DesktopPetPointerPeek.margin)
        let visible = layout.visible
        // 以遮罩边中点为轴歪斜。
        tiltLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        tiltLayer.bounds = CGRect(origin: .zero, size: visible)
        tiltLayer.position = CGPoint(x: margin + visible.width / 2, y: margin)
        tiltLayer.transform = CATransform3DMakeRotation(-CGFloat(lean) * .pi / 180, 0, 0, 1)

        let shadowWidth = visible.width * CGFloat(DesktopPetPointerPeek.contactShadowWidth)
        let shadowRect = CGRect(x: (visible.width - shadowWidth) / 2, y: -1.5, width: shadowWidth, height: 3)
        shadowLayer.frame = CGRect(origin: .zero, size: visible)
        shadowLayer.shadowPath = CGPath(ellipseIn: shadowRect, transform: nil)
        shadowLayer.shadowOpacity = Float(DesktopPetPointerPeek.contactShadowOpacity)
        shadowLayer.shadowRadius = CGFloat(DesktopPetPointerPeek.contactShadowRadius)

        // 只裁边下面那截；上面多留一点，回弹时耳朵尖不被切。
        clipLayer.frame = CGRect(x: 0, y: 0, width: visible.width, height: visible.height + margin)
        riseLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        riseLayer.bounds = CGRect(origin: .zero, size: visible)
        riseLayer.position = CGPoint(x: visible.width / 2, y: 0)
        riseLayer.transform = CATransform3DIdentity
        imageLayer.frame = layout.image
        imageLayer.contentsScale = scaleFactor
        imageLayer.contents = image.layerContents(forContentsScale: scaleFactor)
        CATransaction.commit()
    }

    /// 出场的关键帧：升起（往上平移）和停顿时压一下（以遮罩边为基准竖直缩放）。
    private func animateEntrance(_ frames: [DesktopPetPointerPeek.Keyframe]) {
        guard let riseLayer else { return }
        riseLayer.removeAllAnimations()
        guard !frames.isEmpty else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = frames.map { frame in
            NSValue(caTransform3D: CATransform3DScale(
                CATransform3DMakeTranslation(0, CGFloat(frame.rise), 0), 1, CGFloat(frame.squash), 1))
        }
        animation.keyTimes = frames.map { NSNumber(value: $0.time) }
        // 第一段慢慢升起用缓出，其余缓入缓出。
        animation.timingFunctions = (1..<max(1, frames.count)).map { index in
            CAMediaTimingFunction(name: index == 1 ? .easeOut : .easeInEaseOut)
        }
        animation.duration = DesktopPetPointerPeek.entranceDuration
        riseLayer.add(animation, forKey: "entrance")
    }

    private func hide(animated: Bool) {
        unwatchPointer()
        guard shownAt != nil, let panel else {
            shownAt = nil
            return
        }
        shownAt = nil
        waitingForMove = true
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                let controller = DesktopPetPointerPeekController.shared
                if controller.shownAt == nil { controller.panel?.orderOut(nil) }
            }
        })
    }

    /// 露着时一动鼠标、点按、滚动就收起。全局鼠标监听不要辅助功能权限。
    private func watchPointer() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            let moved = event.type == .mouseMoved
            MainActor.assumeIsolated {
                let controller = DesktopPetPointerPeekController.shared
                guard let from = controller.shownAt else { return }
                if moved, !DesktopPetPointerPeek.moved(from: from, to: NSEvent.mouseLocation) { return }
                controller.lastPointer = NSEvent.mouseLocation
                controller.hide(animated: true)
            }
        }
    }

    private func unwatchPointer() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: 图

    /// 当前生效的吉祥物（没解锁 Pro 时是小熊猫）和它的探头图；缺图时退到整张坐姿。
    private func currentImage() -> (String, NSImage, FocusMascot)? {
        let mascot = FocusMascot.of(TimerStateProvider.shared.state, unlocked: ProAccess.isUnlocked)
        for name in DesktopPetPointerPeek.imageCandidates(mascot) {
            if let image = Bundle.main.image(forResource: name) { return (name, image, mascot) }
        }
        return nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        let root = view.layer ?? CALayer()
        let tilt = CALayer()
        let shadow = CALayer()
        shadow.shadowColor = NSColor.black.cgColor
        shadow.shadowOffset = .zero
        let clip = CALayer()
        clip.masksToBounds = true
        let rise = CALayer()
        let picture = CALayer()
        picture.contentsGravity = .resize
        picture.minificationFilter = .trilinear
        rise.addSublayer(picture)
        clip.addSublayer(rise)
        tilt.addSublayer(shadow)
        tilt.addSublayer(clip)
        root.addSublayer(tilt)
        panel.contentView = view
        tiltLayer = tilt
        shadowLayer = shadow
        clipLayer = clip
        riseLayer = rise
        imageLayer = picture
        return panel
    }
}

/// 麦克风是不是正在被哪个 App 用（通话、开会）：读默认输入设备的「在别处运行」。
/// 只看开没开，不录音、不读内容。
enum MicrophoneActivity {
    static func inUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
