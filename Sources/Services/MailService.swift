import AppKit
import Observation

/// What the mail widget knows.
enum MailState: Equatable, Sendable {
    case notRunning
    case denied
    case failed
    case unread(Int)
}

/// The unread count of Mail's inbox, asked of Mail itself.
///
/// AppleScript through `NSAppleScript`, the only public way to read it, and
/// only while Mail is already running: asking a closed Mail would launch it,
/// which nobody wants from a glance at the shelf. The first ask makes macOS
/// request Automation consent for Mail; a refusal is reported as such, so the
/// tile can say what is wrong instead of showing zero.
@MainActor @Observable
final class MailService {
    static let shared = MailService()
    static let bundleID = "com.apple.mail"

    private(set) var state: MailState = .notRunning

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var lastStart: Date = .distantPast

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh(force: true)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static var isMailRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Every 30 seconds while Mail is open, at once when forced.
    func refresh(force: Bool = false) {
        guard Self.isMailRunning else {
            state = .notRunning
            return
        }
        let now = Date.now
        // Refused consent is not asked again on the poll: it would only fail
        // the same way. A forced refresh (the tile reappearing) retries.
        let interval: TimeInterval = state == .denied ? 300 : 30
        guard PollGate.shouldStart(inFlight: inFlight, blocked: false,
                                   sinceLastStart: force ? .infinity : now.timeIntervalSince(lastStart),
                                   interval: interval) else { return }
        inFlight = true
        lastStart = now
        Task {
            let result = await withTimeout(seconds: 6) { await MailBridge.unreadCount() }
            inFlight = false
            state = result ?? .failed
        }
    }

    // MARK: 面板的未读列表

    /// 面板读到的列表；nil 是还没读过。只在面板开着时读，关上就不再读。
    private(set) var snapshot: MailSnapshot?
    /// 面板列表这一次读得怎样：读到了、「邮件」没开、没有权限、读不出来。
    private(set) var listState: MailListState = .idle
    @ObservationIgnored private var listInFlight = false

    /// 读一次账户和最近的未读。「邮件」没开时不读（问它会把它打开）。
    func loadList(summary: Bool) async {
        guard Self.isMailRunning else {
            listState = .notRunning
            return
        }
        guard !listInFlight else { return }
        listInFlight = true
        defer { listInFlight = false }
        if snapshot == nil { listState = .loading }
        let source = MailInbox.fetchScript(perAccount: MailInbox.perAccount, summary: summary)
        var result = await withTimeout(seconds: 20) { await MailBridge.execute(source) }
        if result == nil, summary {
            // 读正文太慢（没下载的信要现取）：这次先不要摘要，列表照样出来。
            let quick = MailInbox.fetchScript(perAccount: MailInbox.perAccount, summary: false)
            result = await withTimeout(seconds: 20) { await MailBridge.execute(quick) }
        }
        switch result {
        case .some(.text(let text)):
            snapshot = MailInbox.parse(text, now: .now)
            listState = .loaded
        case .some(.denied):
            listState = .denied
            state = .denied
        case .some(.failed), .none:
            // 读过一次的照旧显示上次的列表，只是这次没读到。
            listState = snapshot == nil ? .failed : .loaded
        }
    }

    /// 把一封标成已读：先在本地拿掉，再让「邮件」改，改完刷新卡片上的数。
    func markRead(_ message: MailMessage) async -> Bool {
        if let snapshot { self.snapshot = MailInbox.removing(message, from: snapshot) }
        let source = MailInbox.markReadScript(account: message.account, mailID: message.mailID)
        let result = await withTimeout(seconds: 10) { await MailBridge.execute(source) }
        refresh(force: true)
        return Self.succeeded(result)
    }

    /// 把几个账户的未读全部标成已读。
    func markAllRead(_ accounts: [String]) async -> Bool {
        guard !accounts.isEmpty else { return true }
        if let snapshot { self.snapshot = MailInbox.clearing(accounts, from: snapshot) }
        let source = MailInbox.markAllReadScript(accounts: accounts)
        let result = await withTimeout(seconds: 20) { await MailBridge.execute(source) }
        refresh(force: true)
        return Self.succeeded(result)
    }

    private static func succeeded(_ result: MailScriptResult?) -> Bool {
        if case .some(.text) = result { return true }
        return false
    }

    /// 点开一封：有 Message-ID 就跳到那一封，没有就只打开「邮件」。
    func open(_ message: MailMessage) {
        if let url = MailInbox.messageURL(message.messageID), NSWorkspace.shared.open(url) { return }
        openMail()
    }

    func openMail() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 面板列表的状态。
enum MailListState: Equatable, Sendable {
    case idle
    case loading
    case notRunning
    case denied
    case failed
    case loaded
}

/// 跑一段脚本的结果：返回的文字、没有权限、出错。
enum MailScriptResult: Sendable {
    case text(String)
    case denied
    case failed
}

/// The Apple Event itself, on its own serial queue.
enum MailBridge {
    private static let queue = DispatchQueue(label: "com.docket-zh.mail")

    static func unreadCount() async -> MailState {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: run()) }
        }
    }

    /// 跑任意一段脚本（读列表、标已读），和读未读数排在同一个队列里。
    static func execute(_ source: String) async -> MailScriptResult {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: runScript(source)) }
        }
    }

    private static func runScript(_ source: String) -> MailScriptResult {
        guard let script = NSAppleScript(source: source) else { return .failed }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return code == -1743 || code == -1744 ? .denied : .failed
        }
        return .text(result.stringValue ?? "")
    }

    private static func run() -> MailState {
        let source = "tell application id \"com.apple.mail\" to get unread count of inbox"
        guard let script = NSAppleScript(source: source) else { return .failed }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743 not permitted, -1744 consent never granted.
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return code == -1743 || code == -1744 ? .denied : .failed
        }
        let count = Int(result.int32Value)
        return .unread(MailBadge.parse(result.stringValue) ?? max(0, count))
    }
}
