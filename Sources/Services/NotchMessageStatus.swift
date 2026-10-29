import AppKit
import ApplicationServices
import Observation
import UserNotifications

/// 消息灵动岛现在的情况，设置里「状态」几行读它（判断和文案在 Core 的
/// `NotchMessageDiagnosis` / `NotchMessageProbe`）。`NotchBannerWatcher` 往里写权限、
/// 通知中心连没连上、最近一次读到横幅；`NotchMessageController` 写测试通知的结果。
@MainActor @Observable
final class NotchMessageStatus {
    static let shared = NotchMessageStatus()

    /// 上次读到「已授权」时的码头版本，用来认出「自签名更新后授权失效」。
    static let trustedBuildKey = "notchMessage.lastTrustedBuild"

    private(set) var trusted = AXIsProcessTrusted()
    var notificationCenterRunning = true
    var connected = false
    private(set) var lastBanner: Date?
    private(set) var lastBannerApp: String?
    private(set) var lastMessage: Date?
    var probe = NotchMessageProbe()
    /// 最近一次读通知中心的结构摘要（不含消息内容）；最近一次读到横幅那次单独留着，
    /// 横幅消失后的空读不会把它盖掉。
    @ObservationIgnored private var lastScan = ""
    @ObservationIgnored private var lastScanAt: Date?
    @ObservationIgnored private var lastBannerScan = ""
    @ObservationIgnored private var scans = 0

    private init() {}

    /// 当前版本：版本号加构建号，形如「0.8.0 (9)」。
    static var currentBuild: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    func updateTrust(_ value: Bool) {
        if trusted != value { trusted = value }
        guard value else { return }
        let build = Self.currentBuild
        if UserDefaults.standard.string(forKey: Self.trustedBuildKey) != build {
            UserDefaults.standard.set(build, forKey: Self.trustedBuildKey)
        }
    }

    func sawBanner(app: String?, at now: Date = Date()) {
        lastBanner = now
        lastBannerApp = app
    }

    func sawMessage(at now: Date = Date()) { lastMessage = now }

    func recordScan(_ report: String, windows: Int, banners: Int, at now: Date = Date()) {
        scans += 1
        lastScanAt = now
        lastScan = "windows=\(windows) banners=\(banners)\n" + report
        if banners > 0 || report.contains("banner path=") { lastBannerScan = lastScan }
    }

    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// 「复制诊断信息」：版本、权限、连接、最近两次读到的通知中心结构。不含消息内容和发件人。
    func diagnosticText(now: Date = Date()) -> String {
        let snap = snapshot()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let formatter = ISO8601DateFormatter()
        func time(_ date: Date?) -> String { date.map { formatter.string(from: $0) } ?? "never" }
        var lines = [
            "Dockling \(Self.currentBuild) · macOS \(os)",
            "accessibility trusted=\(snap.trusted) lastTrustedBuild=\(snap.lastTrustedBuild ?? "none")",
            "notificationCenter running=\(snap.notificationCenterRunning) connected=\(snap.connected)",
            "scans=\(scans) lastScan=\(time(lastScanAt)) lastBanner=\(time(lastBanner)) lastMessage=\(time(lastMessage))",
            "probe=\(probe.state)",
            "now=\(formatter.string(from: now))",
        ]
        if !lastBannerScan.isEmpty, lastBannerScan != lastScan {
            lines.append("--- last scan with a banner ---")
            lines.append(lastBannerScan)
        }
        lines.append("--- last scan ---")
        lines.append(lastScan.isEmpty ? "none" : lastScan)
        return lines.joined(separator: "\n")
    }

    /// 给 Core 判断用的快照。权限现读（设置页每秒刷新一次），别的用观察器写进来的。
    func snapshot() -> NotchMessageDiagnosis.Snapshot {
        let live = AXIsProcessTrusted()
        return NotchMessageDiagnosis.Snapshot(
            trusted: live,
            lastTrustedBuild: UserDefaults.standard.string(forKey: Self.trustedBuildKey),
            currentBuild: Self.currentBuild,
            osMajor: Self.osMajor,
            notificationCenterRunning: notificationCenterRunning,
            connected: live && connected,
            lastBanner: lastBanner,
            lastBannerApp: lastBannerApp,
            lastMessage: lastMessage)
    }
}

/// 「发一条测试通知」：码头自己发一条本地通知。码头在前台时也出横幅（启动时设好的
/// `BannerPresenter` 返回 .banner），读横幅那边按正文里的暗号认出它，弹一张不能回复的
/// 消息卡。通知设置不跨线程传，在这里读完只交出暗号。
enum NotchMessageProbeSender {
    nonisolated static func identifier(_ token: String) -> String {
        NotchMessageProbe.identifierPrefix + token.replacingOccurrences(of: "#", with: "")
    }

    /// 发出去返回暗号；码头的通知被关了返回 nil。
    nonisolated static func send() async -> String? {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings()
        if status.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings()
        }
        // 只进通知中心、不出横幅的（临时授权、样式选了「无」）读不到，当没开。
        guard status.authorizationStatus == .authorized, status.alertStyle != .none else { return nil }
        let token = NotchMessageProbe.makeToken(Int.random(in: 0..<10_000))
        let content = UNMutableNotificationContent()
        content.title = tr("消息灵动岛")
        content.body = NotchMessageProbe.body(token: token)
        let request = UNNotificationRequest(identifier: identifier(token), content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            return nil
        }
        return token
    }

    /// 读到了就把那条测试通知从通知中心收走，不留在列表里。
    nonisolated static func withdraw(_ token: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(token)])
    }
}
