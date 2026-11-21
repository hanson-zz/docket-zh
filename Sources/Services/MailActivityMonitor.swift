import AppKit
import ApplicationServices
import Observation

/// 邮件动态图标的「撰写中」「发送中」。
///
/// - 撰写中：邮件有没有窗口的工具栏上带「发送」按钮（写信窗口才有），走辅助功能，只读按钮名字。
/// - 发送中：用 AppleScript 问邮件发件箱里有几封信（要允许码头控制邮件），只数数，不读信。
///   用户拒绝后这一项就不再问，直到开关重开。
///
/// 只有邮件在运行、邮件图标开着动态图标时每 2 秒读一次，没人用就停。读不到就是 false（不挂）。
@MainActor @Observable
final class MailActivityMonitor {
    static let shared = MailActivityMonitor()
    static let interval: TimeInterval = 2
    static let bundleID = "com.apple.mail"

    private(set) var activity = LiveMailActivity()

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var outboxDenied = false

    func retain() {
        users += 1
        guard loop == nil else { return }
        outboxDenied = false
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                try? await Task.sleep(for: .seconds(lowPower ? Self.interval * 2 : Self.interval))
            }
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        loop?.cancel()
        loop = nil
        if activity != LiveMailActivity() { activity = LiveMailActivity() }
    }

    private func poll() async {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .first?.processIdentifier else {
            if activity != LiveMailActivity() { activity = LiveMailActivity() }
            return
        }
        let askOutbox = !outboxDenied
        let (composing, outbox) = await withCheckedContinuation { done in
            MailActivityReader.queue.async {
                let c = MailActivityReader.composing(pid: pid)
                let o = askOutbox ? MailActivityReader.outboxCount() : .unknown
                done.resume(returning: (c, o))
            }
        }
        guard !Task.isCancelled else { return }
        var sending = false
        switch outbox {
        case .count(let n): sending = n > 0
        case .denied: outboxDenied = true
        case .unknown: break
        }
        let next = LiveMailActivity(composing: composing, sending: sending)
        if next != activity { activity = next }
    }
}

enum MailActivityReader {
    static let queue = DispatchQueue(label: "com.docket-zh.live-mail", qos: .utility)

    enum Outbox: Sendable { case count(Int), denied, unknown }

    /// 只在 `queue` 上碰。
    nonisolated(unsafe) private static var compiled: NSAppleScript?

    /// 先看邮件还在不在跑，免得 `tell` 把它拉起来。
    private static let source = """
    if application id "com.apple.mail" is running then
        tell application id "com.apple.mail"
            return count of messages of outbox
        end tell
    end if
    return 0
    """

    static func outboxCount() -> Outbox {
        let script: NSAppleScript
        if let cached = compiled {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return .unknown }
            made.compileAndReturnError(nil)
            compiled = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743：用户没允许码头控制邮件。
            return code == -1743 ? .denied : .unknown
        }
        return .count(Int(result.int32Value))
    }

    /// 邮件有没有写信窗口：窗口工具栏上有「发送」按钮。没权限、读不到都算没有。
    static func composing(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement] else { return false }
        for window in windows.prefix(8) {
            guard let toolbar = children(window).first(where: { string($0, kAXRoleAttribute) == kAXToolbarRole })
            else { continue }
            var budget = 120
            if search(toolbar, depth: 0, budget: &budget) { return true }
        }
        return false
    }

    private static func search(_ element: AXUIElement, depth: Int, budget: inout Int) -> Bool {
        budget -= 1
        guard budget > 0, depth < 6 else { return false }
        if string(element, kAXRoleAttribute) == kAXButtonRole {
            let texts = [kAXDescriptionAttribute, kAXTitleAttribute].compactMap { string(element, $0) }
            return LiveMailActivity.isSendButton(texts)
        }
        for child in children(element) {
            if search(child, depth: depth + 1, budget: &budget) { return true }
        }
        return false
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}
