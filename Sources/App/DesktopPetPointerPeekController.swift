import AppKit
import CoreAudio
import Foundation

/// 指针旁探头的窗口：鼠标停着约 20 秒，所选吉祥物以完整的小坐姿出现在指针旁，一动就收起。
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
    private var imageView: NSImageView?
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
        guard let image = currentImage(),
              let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return }
        let size = DesktopPetPointerPeek.size(imageSize: image.size, scale: settings.size.scale)
        let frame = DesktopPetPointerPeek.frame(pointer: pointer, size: size, bounds: screen.visibleFrame)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        imageView?.image = image
        shownAt = pointer
        watchPointer()

        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // 从下面轻轻冒出来一点；减弱动态效果时只淡入。
        let rise = CGFloat(DesktopPetPointerPeek.rise(reduceMotion: reduce))
        panel.setFrame(frame.offsetBy(dx: 0, dy: -rise), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0.2 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if rise > 0 { panel.animator().setFrame(frame, display: true) }
        }
    }

    private func hide(animated: Bool) {
        unwatchPointer()
        guard shownAt != nil, let panel else {
            shownAt = nil
            return
        }
        shownAt = nil
        waitingForMove = true
        guard animated else {
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

    /// 当前生效的吉祥物（没解锁 Pro 时是小熊猫），专注中用专注的样子。
    private func currentImage() -> NSImage? {
        let timer = TimerStateProvider.shared.state
        let mascot = FocusMascot.of(timer, unlocked: ProAccess.isUnlocked)
        let focusing = FocusMascotState.of(timer, now: Date()) == .focus
        for name in DesktopPetPointerPeek.imageCandidates(mascot, focusing: focusing) {
            if let image = Bundle.main.image(forResource: name) { return image }
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
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityElement(false)
        panel.contentView = view
        imageView = view
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
