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
/// required after sleep, the macOS default. Do Not Disturb, Night Shift and
/// Low Power Mode have no public switch, so they are not offered.
@MainActor @Observable
final class QuickActions {
    static let shared = QuickActions()

    /// Bumped after every action so state read from other apps' settings is
    /// drawn again.
    private(set) var revision = 0
    private(set) var keepAwake = false
    private(set) var micMuted = UserDefaults.standard.bool(forKey: "quick.micMuted")

    @ObservationIgnored private var assertion = IOPMAssertionID(0)

    private init() {}

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
            setKeepAwake(!keepAwake)
            done()
        case .lock:
            Self.run("/usr/bin/pmset", ["displaysleepnow"], then: done)
        case .screenSaver:
            let engine = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            NSWorkspace.shared.openApplication(at: engine, configuration: NSWorkspace.OpenConfiguration())
            done()
        case .emptyTrash:
            guard Self.confirm("要清空废纸篓吗？", "废纸篓中的所有项目将被永久抹掉，此操作无法撤销。", button: "清空废纸篓") else { return }
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
            CleanMode.shared.start()
            done()
        case .quitApps:
            quitOtherApps()
            done()
        }
    }

    // MARK: Keep Awake

    private func setKeepAwake(_ on: Bool) {
        if on, !keepAwake {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "码头：保持唤醒" as CFString, &assertion)
            keepAwake = result == kIOReturnSuccess
        } else if !on, keepAwake {
            IOPMAssertionRelease(assertion)
            keepAwake = false
        }
    }

    // MARK: Microphone

    /// Input volume to 0, remembering what it was so the second click puts
    /// it back.
    private func toggleMicrophone(then done: @escaping @MainActor () -> Void) {
        let muting = !micMuted
        micMuted = muting
        UserDefaults.standard.set(muting, forKey: "quick.micMuted")
        if muting {
            Self.capture("/usr/bin/osascript", ["-e", "input volume of (get volume settings)"]) { output in
                let level = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
                if level > 0 { UserDefaults.standard.set(level, forKey: "quick.micLevel") }
                Self.run("/usr/bin/osascript", ["-e", "set volume input volume 0"], then: done)
            }
        } else {
            let saved = UserDefaults.standard.integer(forKey: "quick.micLevel")
            let level = saved > 0 ? saved : 50
            Self.run("/usr/bin/osascript", ["-e", "set volume input volume \(level)"], then: done)
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
        let names = targets.prefix(6).compactMap(\.localizedName).joined(separator: "、")
        let more = targets.count > 6 ? " 等 \(targets.count) 个应用" : ""
        guard Self.confirm("要退出其他 \(targets.count) 个应用吗？",
                           "\(names)\(more)。当前使用的应用和访达会保留；有未存储内容的应用会照常询问。",
                           button: "全部退出") else { return }
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
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func shell(_ command: String, then done: @escaping @MainActor () -> Void) {
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
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timeout: Timer?

    var isActive: Bool { !windows.isEmpty }

    func start() {
        guard !isActive else { return }
        let trusted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        let locked = trusted && lockKeyboard()
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
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        CleanModeTap.port = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func lockKeyboard() -> Bool {
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
                Text(keyboardLocked ? "屏幕和键盘可以放心擦拭，键盘已暂时锁定。" : "屏幕可以擦拭了。键盘未锁定：需要在“辅助功能”中允许码头。")
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
