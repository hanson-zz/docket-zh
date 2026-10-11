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

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// The Apple Event itself, on its own serial queue.
enum MailBridge {
    private static let queue = DispatchQueue(label: "com.docket-zh.mail")

    static func unreadCount() async -> MailState {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: run()) }
        }
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
