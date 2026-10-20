import AppKit
import ApplicationServices
import Foundation
import IOKit.pwr_mgt
import Observation
import SwiftUI

/// The quick toggles' actions, each through a public door.
///
/// Most follow OnlySwitch (jacklandrin/OnlySwitch, MIT, credited in NOTICE):
/// Finder's own `defaults` keys for hidden files, desktop icons and
/// extensions (then `killall Finder` so it rereads them), AppleScript to
/// System Events and Finder for Dark Mode, emptying the Trash and ejecting
/// disks, the input volume for muting the microphone, and an IOKit power
/// assertion for Keep Awake. macOS asks once for Automation consent. Locking
/// is `pmset displaysleepnow`, which locks the Mac when a password is
/// required after sleep, the macOS default. Do Not Disturb and Night Shift
/// have no public switch, so they are not offered. 低电量模式走 `pmset`，
/// 要管理员密码，用系统的授权框（和充电助手的安装一样）。
///
/// 第二批工具（截图识字、取色器、只锁键盘、二维码、镜子）的窗口和识别
/// 在 QuickTools.swift；演示模式、低电量模式和重启程序坞在这里。
@MainActor @Observable
final class QuickActions {
    static let shared = QuickActions()

    /// Bumped after every action so state read from other apps' settings is
    /// drawn again.
    private(set) var revision = 0
    private(set) var keepAwake = false
    /// 保持唤醒到点自动关的时刻；一直开着或没开是 nil（见 `KeepAwakeTimer`）。
    private(set) var keepAwakeUntil: Date?
    /// 麦克风静音和麦克风面板的全局静音是同一份（`MicrophoneMonitor.globalMuted`）。
    var micMuted: Bool { MicrophoneMonitor.shared.globalMuted }

    /// 演示模式打开前的样子；nil 表示没在演示。
    private(set) var presentation: PresentationSnapshot? = QuickActions.loadPresentation()
    /// 最近一次从 `pmset -g` 读到的低电量模式；nil 是还没读到或这台 Mac 不支持。
    private(set) var lowPower: LowPowerSetting.Reading?

    @ObservationIgnored private var assertion = IOPMAssertionID(0)
    @ObservationIgnored private var keepAwakeTimer: Timer?
    @ObservationIgnored private var lowPowerRequested = false

    private init() {
        // 上次退出时还在演示：保持唤醒的断言跟着进程没了，补上，让演示模式前后一致。
        if presentation != nil { setKeepAwake(true) }
    }

    /// 别的地方改了开关状态（比如只锁键盘到点自动解锁），让卡片重画。
    func noteChange() {
        revision += 1
    }

    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func isOn(_ toggle: QuickToggle) -> Bool {
        _ = revision
        switch toggle {
        case .darkMode: return Self.isDark
        case .keepAwake: return keepAwake
        case .hiddenFiles: return Self.preference("AppleShowAllFiles", in: "com.apple.finder") ?? false
        case .hideDesktop: return (Self.preference("CreateDesktop", in: "com.apple.finder") ?? true) == false
        case .extensions: return Self.preference("AppleShowAllExtensions", in: "kCFPreferencesAnyApplication") ?? false
        case .muteMic: return micMuted
        case .presentation: return presentation != nil
        case .keyboardLock: return KeyboardLockMode.shared.isActive
        case .lowPower:
            if !lowPowerRequested {
                lowPowerRequested = true
                refreshLowPower()
            }
            return lowPower?.isOn ?? false
        default: return false
        }
    }

    /// Another app's boolean setting, accepting the "true"/"1" strings
    /// `defaults write` without `-bool` leaves behind.
    private static func preference(_ key: String, in domain: String) -> Bool? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return ["1", "true", "yes"].contains(text.lowercased()) }
        return nil
    }

    static func perform(_ toggle: QuickToggle, completion: (@MainActor () -> Void)? = nil) {
        shared.perform(toggle, completion: completion)
    }

    func perform(_ toggle: QuickToggle, completion: (@MainActor () -> Void)? = nil) {
        let done: @MainActor () -> Void = { [weak self] in
            self?.revision += 1
            completion?()
        }
        switch toggle {
        case .darkMode:
            Self.run("/usr/bin/osascript", ["-e",
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"], then: done)
        case .keepAwake:
            // 没有卡片时长可读（菜单、快捷键）时按一直开着，和以前一样。
            if keepAwake { setKeepAwake(false) } else { setKeepAwake(true) }
            done()
        case .lock:
            Self.run("/usr/bin/pmset", ["displaysleepnow"], then: done)
        case .screenSaver:
            let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
            done()
        case .emptyTrash:
            guard Self.confirm(tr("要清空废纸篓吗？"), tr("废纸篓中的所有项目将被永久抹掉，此操作无法撤销。"), button: tr("清空废纸篓")) else { return }
            Self.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"], then: done)
        case .hiddenFiles:
            let on = !isOn(.hiddenFiles)
            Self.shell("defaults write com.apple.finder AppleShowAllFiles -bool \(on); killall Finder", then: done)
        case .hideDesktop:
            let hide = !isOn(.hideDesktop)
            Self.shell("defaults write com.apple.finder CreateDesktop -bool \(!hide); killall Finder", then: done)
        case .extensions:
            let on = !isOn(.extensions)
            Self.shell("defaults write NSGlobalDomain AppleShowAllExtensions -bool \(on); killall Finder", then: done)
        case .muteMic:
            toggleMicrophone(then: done)
        case .ejectDisks:
            Self.run("/usr/bin/osascript", ["-e",
                "tell application \"Finder\" to eject (every disk whose ejectable is true)"], then: done)
        case .clearClipboard:
            NSPasteboard.general.clearContents()
            done()
        case .cleanScreen:
            KeyboardLockMode.shared.stop()
            CleanMode.shared.start()
            done()
        case .quitApps:
            quitOtherApps()
            done()
        case .textCapture:
            TextCapture.start()
            done()
        case .colorPicker:
            ColorPickerTool.start()
            done()
        case .presentation:
            togglePresentation(then: done)
        case .keyboardLock:
            KeyboardLockMode.shared.toggle()
            done()
        case .qrCode:
            QRCodePanel.shared.show()
            done()
        case .mirror:
            MirrorWindow.shared.open()
            done()
        case .lowPower:
            toggleLowPower(then: done)
        case .restartDock:
            guard Self.confirm(tr("要重新启动程序坞和访达吗？"),
                               tr("程序坞和访达会退出并马上自动重新打开，访达窗口会关闭后再恢复。"),
                               button: tr("重新启动")) else { return }
            Self.shell("killall Dock; killall Finder", then: done)
        }
    }

    // MARK: Keep Awake

    /// 卡片和面板点保持唤醒：关着就按卡片选的时长打开（0 是一直），开着就关。
    func toggleKeepAwake(minutes: Int) {
        if keepAwake {
            setKeepAwake(false)
        } else {
            setKeepAwake(true)
            if keepAwake { armKeepAwake(minutes: minutes) }
        }
        revision += 1
    }

    /// 在面板里换了时长：正开着的从现在起按新时长重新计（选「一直」就不再到点关）。
    func changeKeepAwakeDuration(minutes: Int) {
        guard keepAwake, presentation == nil else { return }
        armKeepAwake(minutes: minutes)
    }

    /// 定一个到点自动关的时刻；0 分钟是一直开着。只有一个定时器，换时长先撤掉旧的。
    private func armKeepAwake(minutes: Int) {
        keepAwakeTimer?.invalidate()
        keepAwakeTimer = nil
        keepAwakeUntil = KeepAwakeTimer.deadline(minutes: minutes, from: .now)
        guard let until = keepAwakeUntil else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepAwakeExpired() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        keepAwakeTimer = timer
    }

    private func keepAwakeExpired() {
        keepAwakeTimer = nil
        keepAwakeUntil = nil
        // 演示模式要一直醒着，到点也不关。
        guard presentation == nil else { return }
        setKeepAwake(false)
        revision += 1
    }

    func setKeepAwake(_ on: Bool) {
        if !on {
            keepAwakeTimer?.invalidate()
            keepAwakeTimer = nil
            keepAwakeUntil = nil
        }
        if on, !keepAwake {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     tr("码头：保持唤醒") as CFString, &assertion)
            keepAwake = result == kIOReturnSuccess
        } else if !on, keepAwake {
            IOPMAssertionRelease(assertion)
            keepAwake = false
        }
    }

    // MARK: Microphone

    /// Input volume to 0, remembering what it was so the second click puts
    /// it back. 和麦克风面板的全局静音同一份：Core Audio 拉输入音量，记下的原值
    /// 存在 `quick.micLevel`。
    private func toggleMicrophone(then done: @escaping @MainActor () -> Void) {
        let mic = MicrophoneMonitor.shared
        mic.start()
        mic.toggleGlobalMute()
        done()
    }

    // MARK: Presentation

    nonisolated private static let presentationKey = "quick.presentation"

    nonisolated private static func loadPresentation() -> PresentationSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: presentationKey) else { return nil }
        return try? JSONDecoder().decode(PresentationSnapshot.self, from: data)
    }

    private func savePresentation() {
        if let presentation, let data = try? JSONEncoder().encode(presentation) {
            UserDefaults.standard.set(data, forKey: Self.presentationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.presentationKey)
        }
    }

    private static func runningApps() -> [PresentationPlan.App] {
        let me = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.map {
            PresentationPlan.App(pid: $0.processIdentifier,
                                 isRegular: $0.activationPolicy == .regular,
                                 isHidden: $0.isHidden,
                                 isFrontmost: $0.processIdentifier == front,
                                 isSelf: $0.processIdentifier == me,
                                 isFinder: $0.bundleIdentifier == "com.apple.finder")
        }
    }

    /// 打开：隐藏桌面图标、保持唤醒、隐藏其他应用，先记下原样；
    /// 关闭：照记下的样子恢复，只把演示模式藏起来的应用显示回来。
    private func togglePresentation(then done: @escaping @MainActor () -> Void) {
        let apps = Self.runningApps()
        let desktopHidden = isOn(.hideDesktop)
        let changes: PresentationPlan.Changes
        if let snapshot = presentation {
            changes = PresentationPlan.exit(snapshot, desktopHidden: desktopHidden, keepAwake: keepAwake, apps: apps)
            presentation = nil
        } else {
            let plan = PresentationPlan.enter(desktopHidden: desktopHidden, keepAwake: keepAwake, apps: apps)
            presentation = plan.snapshot
            changes = plan.changes
        }
        savePresentation()
        if let awake = changes.setKeepAwake { setKeepAwake(awake) }
        // 进演示模式时保持唤醒本来就开着（带时长）：改成一直开着，不让它中途到点关掉。
        if presentation != nil, keepAwakeUntil != nil {
            keepAwakeTimer?.invalidate()
            keepAwakeTimer = nil
            keepAwakeUntil = nil
        }
        let running = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
                                 uniquingKeysWith: { first, _ in first })
        changes.hide.forEach { _ = running[$0]?.hide() }
        changes.unhide.forEach { _ = running[$0]?.unhide() }
        // 访达改桌面图标要重启，重启后的访达是新进程，等它起来再藏或显示。
        let finderStep: @MainActor () -> Void = {
            guard changes.hideFinder || changes.unhideFinder else { return }
            let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
            if changes.hideFinder { _ = finder?.hide() } else { _ = finder?.unhide() }
        }
        guard let hidden = changes.setDesktopHidden else {
            finderStep()
            done()
            return
        }
        Self.shell("defaults write com.apple.finder CreateDesktop -bool \(!hidden); killall Finder") {
            done()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                finderStep()
            }
        }
    }

    // MARK: Low Power Mode

    func refreshLowPower() {
        Self.capture("/usr/bin/pmset", ["-g"]) { [weak self] output in
            self?.lowPower = LowPowerSetting.parse(output)
            self?.revision += 1
        }
    }

    /// 先读现在的状态，再用管理员授权框执行 pmset。用户取消授权框时什么都不做。
    private func toggleLowPower(then done: @escaping @MainActor () -> Void) {
        Self.capture("/usr/bin/pmset", ["-g"]) { [weak self] output in
            guard let self else { return }
            guard let reading = LowPowerSetting.parse(output),
                  let command = LowPowerSetting.command(key: reading.key, on: !reading.isOn) else {
                self.lowPower = nil
                QuickHint.show(tr("这台 Mac 不支持低电量模式"), symbol: "battery.25", tint: .secondary)
                done()
                return
            }
            let turningOn = !reading.isOn
            let prompt = turningOn ? tr("码头要打开低电量模式。") : tr("码头要关闭低电量模式。")
            let source = "do shell script \"\(ChargeHelperFiles.appleScriptQuoted(command))\" "
                + "with prompt \"\(ChargeHelperFiles.appleScriptQuoted(prompt))\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int
                if code != -128 {
                    QuickHint.show(tr("没能切换低电量模式：\(error[NSAppleScript.errorMessage] as? String ?? tr("未知错误"))"),
                                   symbol: "exclamationmark.triangle.fill", tint: .orange, seconds: 4)
                }
            } else {
                self.lowPower = LowPowerSetting.Reading(key: reading.key, isOn: turningOn)
                QuickHint.show(turningOn ? tr("低电量模式已打开") : tr("低电量模式已关闭"),
                               symbol: turningOn ? "battery.25" : "battery.100", tint: turningOn ? .yellow : .green)
            }
            self.refreshLowPower()
            done()
        }
    }

    // MARK: Quit apps

    /// A normal quit request to every other regular app, keeping the one in
    /// front, Finder and this one. Apps with unsaved work ask as usual.
    private func quitOtherApps() {
        let keep: Set<String> = ["com.apple.finder", Bundle.main.bundleIdentifier ?? ""]
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targets = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !keep.contains($0.bundleIdentifier ?? "")
                && $0.processIdentifier != front && !$0.isTerminated
        }
        guard !targets.isEmpty else { return }
        let names = targets.prefix(6).compactMap(\.localizedName).joined(separator: tr("、"))
        let more = targets.count > 6 ? tr(" 等 \(targets.count) 个应用") : ""
        guard Self.confirm(tr("要退出其他 \(targets.count) 个应用吗？"),
                           tr("\(names)\(more)。当前使用的应用和访达会保留；有未存储内容的应用会照常询问。"),
                           button: tr("全部退出")) else { return }
        targets.forEach { $0.terminate() }
    }

    // MARK: Helpers

    /// Same brief promotion to a regular app the shelf uses for its other
    /// alerts, so the question is in front rather than behind the frontmost
    /// window.
    static func confirm(_ title: String, _ detail: String, button: String) -> Bool {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: tr("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func shell(_ command: String, then done: @escaping @MainActor () -> Void) {
        run("/bin/sh", ["-c", command], then: done)
    }

    private static func run(_ tool: String, _ arguments: [String], then done: @escaping @MainActor () -> Void) {
        capture(tool, arguments) { _ in done() }
    }

    private static func capture(_ tool: String, _ arguments: [String],
                                then done: @escaping @MainActor (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var output = ""
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                output = String(decoding: data, as: UTF8.self)
            }
            let result = output
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }
}

// MARK: - Clean mode

/// 清洁屏幕和键盘：每块屏幕都变黑，键盘暂时不起作用，用鼠标点“完成”退出。
///
/// The keyboard is held by a session event tap that swallows key, modifier
/// and media-key events, which needs Accessibility permission; without it
/// the screens still go black and the panel says the keyboard is live. It
/// ends by itself after five minutes in case the mouse is out of reach.
@MainActor
final class CleanMode {
    static let shared = CleanMode()

    private var windows: [NSWindow] = []
    private var timeout: Timer?

    var isActive: Bool { !windows.isEmpty }

    func start() {
        guard !isActive else { return }
        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let locked = trusted && KeyboardBlocker.shared.start()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .black
            window.isOpaque = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = NSHostingView(rootView: CleanModeView(keyboardLocked: locked) { [weak self] in
                self?.stop()
            })
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSCursor.unhide()
        timeout = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        timeout?.invalidate()
        timeout = nil
        KeyboardBlocker.shared.stop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

/// 锁键盘：一个会话级事件拦截，吞掉按键、修饰键和媒体键。
/// 清洁模式和“只锁键盘”共用它，需要辅助功能授权。
@MainActor
final class KeyboardBlocker {
    static let shared = KeyboardBlocker()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isActive: Bool { tap != nil }

    /// 已经锁着时直接算成功。
    func start() -> Bool {
        if isActive { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        var mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // NX_SYSDEFINED: brightness, volume and the other media keys.
        mask |= CGEventMask(1) << 14
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: CleanModeTap.callback, userInfo: nil) else { return false }
        CleanModeTap.port = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        CleanModeTap.port = nil
    }
}

/// The C callback can capture nothing, so the port it re-enables lives here.
enum CleanModeTap {
    nonisolated(unsafe) static var port: CFMachPort?

    nonisolated(unsafe) static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = CleanModeTap.port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        return nil
    }
}

private struct CleanModeView: View {
    var keyboardLocked: Bool
    var done: () -> Void

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.35))
                Text("清洁模式")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(keyboardLocked ? tr("屏幕和键盘可以放心擦拭，键盘已暂时锁定。") : tr("屏幕可以擦拭了。键盘未锁定：需要在“辅助功能”中允许码头。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                Button("完成", action: done)
                    .controlSize(.large)
                    .padding(.top, 6)
                Text("5 分钟后自动退出")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .ignoresSafeArea()
    }
}
