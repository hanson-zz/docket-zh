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
    private(set) var notificationCenterRunning = true
    private(set) var connected = false
    private(set) var lastBanner: Date?
    private(set) var lastBannerApp: String?
    private(set) var lastMessage: Date?
    var probe = NotchMessageProbe()
    /// 最近一次读通知中心的结构摘要（不含消息内容）；最近一次读到横幅那次单独留着，
    /// 横幅消失后的空读不会把它盖掉。
    @ObservationIgnored private var lastScan = ""
    @ObservationIgnored private var lastScanAt: Date?
    @ObservationIgnored private var lastBannerScan = ""
    @ObservationIgnored private var lastBannerScanAt: Date?
    @ObservationIgnored private var scans = 0
    /// 每种触发方式各读了几次（`NotchScanTrigger`）。
    @ObservationIgnored private var scansBy: [String: Int] = [:]
    /// 收到的 AX 事件按名字计数，和最近一次的时间：真实横幅来时有没有事件，看这里。
    @ObservationIgnored private var events: [String: Int] = [:]
    @ObservationIgnored private var lastEventAt: Date?
    /// 每秒轻读：跑了几次、因为正在读横幅跳过几次、发现变了几次（变了才会算进 by=[poll]），
    /// 最近一次的时间和读到几个横幅元素。
    @ObservationIgnored private var pollsRan = 0
    @ObservationIgnored private var pollsSkipped = 0
    @ObservationIgnored private var pollsChanged = 0
    @ObservationIgnored private var lastPollAt: Date?
    @ObservationIgnored private var lastPollBanners = 0
    /// 程序坞角标记了几次、最近一次的角标（只有数字）。
    @ObservationIgnored private var dockSamples = 0
    @ObservationIgnored private var lastDock: NotchDockSample?
    /// 最近几条非测试横幅、测试横幅的分析记录和计数，存在 UserDefaults 里，码头重开后还在。
    @ObservationIgnored private(set) var bannerLog: NotchBannerLog
    /// 这次启动的时间：两次诊断的 scans 一样多时，看它就知道码头是不是中间重开过。
    private let launchedAt = Date()
    /// 从装着的 App 包里读到的额外 App 名（`NotchAppNames.summary`），诊断信息用。
    @ObservationIgnored private var extraNames = "not loaded"

    static let bannerLogKey = "notchMessage.bannerLog"

    private init() {
        let build = Self.currentBuild
        if let data = UserDefaults.standard.data(forKey: Self.bannerLogKey),
           let saved = try? JSONDecoder().decode(NotchBannerLog.self, from: data), saved.build == build {
            bannerLog = saved
        } else {
            bannerLog = NotchBannerLog(build: build)
        }
    }

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

    /// 观察器每 2 秒都会报一遍；@Observable 每次赋值都通知，值没变时不写，免得设置页
    /// 跟着白白重画。
    func setNotificationCenterRunning(_ value: Bool) {
        if notificationCenterRunning != value { notificationCenterRunning = value }
    }

    func setConnected(_ value: Bool) {
        if connected != value { connected = value }
    }

    func sawBanner(app: String?, at now: Date = Date()) {
        lastBanner = now
        lastBannerApp = app
    }

    func sawMessage(at now: Date = Date()) { lastMessage = now }

    func recordNames(_ summary: String) { extraNames = summary }

    /// 记一次读通知中心。「最近一次读到真实横幅」只在这次读到了非测试横幅时更新，测试通知
    /// 不会把它盖掉。
    func recordScan(_ report: String, windows: Int, banners: Int, realBanners: Int,
                    trigger: NotchScanTrigger, at now: Date = Date()) {
        scans += 1
        scansBy[trigger.rawValue, default: 0] += 1
        lastScanAt = now
        lastScan = "windows=\(windows) banners=\(banners) trigger=\(trigger.rawValue)\n" + report
        if realBanners > 0 {
            lastBannerScan = lastScan
            lastBannerScanAt = now
        }
    }

    func recordPoll(skipped: Bool, changed: Bool = false, banners: Int = 0, at now: Date = Date()) {
        if skipped {
            pollsSkipped += 1
            return
        }
        pollsRan += 1
        if changed { pollsChanged += 1 }
        lastPollAt = now
        lastPollBanners = banners
    }

    func recordDockSample(_ sample: NotchDockSample) {
        dockSamples += 1
        lastDock = sample
    }

    func recordEvent(_ name: String, at now: Date = Date()) {
        events[name, default: 0] += 1
        lastEventAt = now
    }

    /// 记这次读到的每条横幅，存下来。
    func recordBanners(_ items: [(key: String, analysis: NotchBannerAnalysis)]) {
        guard !items.isEmpty else { return }
        for item in items { bannerLog.record(item.analysis, key: item.key) }
        if let data = try? JSONEncoder().encode(bannerLog) {
            UserDefaults.standard.set(data, forKey: Self.bannerLogKey)
        }
    }

    static var osMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    /// 「复制诊断信息」：版本、权限、连接、最近两次读到的通知中心结构。不含消息内容和发件人。
    func diagnosticText(now: Date = Date()) -> String {
        let snap = snapshot()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let formatter = ISO8601DateFormatter()
        func time(_ date: Date?) -> String { date.map { formatter.string(from: $0) } ?? "never" }
        func counts(_ dict: [String: Int]) -> String {
            dict.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        }
        var lines = [
            "Dockling \(Self.currentBuild) · macOS \(os)",
            "accessibility trusted=\(snap.trusted) lastTrustedBuild=\(snap.lastTrustedBuild ?? "none")",
            "notificationCenter running=\(snap.notificationCenterRunning) connected=\(snap.connected)",
            "launched=\(time(launchedAt)) scans=\(scans) by=[\(counts(scansBy))] lastScan=\(time(lastScanAt))",
            "events=[\(counts(events))] lastEvent=\(time(lastEventAt))",
            "polls ran=\(pollsRan) skipped=\(pollsSkipped) changed=\(pollsChanged) lastPoll=\(time(lastPollAt)) bannerElements=\(lastPollBanners)",
            "dock samples=\(dockSamples) last=[\(lastDock?.summary ?? "none")] at=\(time(lastDock?.at))",
            "lastBanner=\(time(lastBanner)) lastMessage=\(time(lastMessage))",
            "probe=\(probe.state)",
            "appNames extra=[\(extraNames)]",
            "now=\(formatter.string(from: now))",
        ]
        let since = bannerLog.since.map { " since=\(time($0))" } ?? ""
        lines.append("bannerLog build=\(bannerLog.build)\(since)")
        lines.append(contentsOf: bannerLog.report(time: time))
        if !lastBannerScan.isEmpty, lastBannerScan != lastScan {
            lines.append("--- last scan with a real banner (\(time(lastBannerScanAt))) ---")
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
