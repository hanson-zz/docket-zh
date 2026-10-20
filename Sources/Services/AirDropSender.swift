import AppKit

/// 把文件交给系统的隔空投送面板，发送成功后记进那张隔空投送卡片的「最近发过」。
///
/// 选设备、进度和结果都在系统面板里。系统通过代理告诉我们发成功了没有：
/// 成功才记，取消或对方拒收不记。代理要活到系统回话为止，所以每次发送一个
/// 对象，放在 `inFlight` 里，回话后放掉。
@MainActor
final class AirDropSender: NSObject, NSSharingServiceDelegate {
    /// 系统有没有隔空投送服务，启动后不会变。
    static let available = NSSharingService(named: .sendViaAirDrop) != nil

    private static var inFlight: [AirDropSender] = []

    /// 记到哪张卡片上；nil 只发不记。
    private let record: ((Date, [URL]) -> Void)?
    private let urls: [URL]
    /// 系统面板开着时服务对象得有人拿着。
    private var service: NSSharingService?

    private init(urls: [URL], record: ((Date, [URL]) -> Void)?) {
        self.urls = urls
        self.record = record
    }

    /// 发送。返回 false 表示发不了（没有隔空投送，或者里面没有能发的文件），已经响过一声。
    @discardableResult
    static func send(_ urls: [URL], recordInto widgetID: UUID?) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: files) else {
            NSSound.beep()
            return false
        }
        var record: ((Date, [URL]) -> Void)?
        if let widgetID {
            record = { date, sent in Self.remember(sent, at: date, in: widgetID) }
        }
        let sender = AirDropSender(urls: files, record: record)
        sender.service = service
        inFlight.append(sender)
        service.delegate = sender
        // 先把码头带到前台，系统面板才不会躲在别的窗口后面。
        NSApp.activate()
        service.perform(withItems: files)
        return true
    }

    /// 只用选文件的面板挑文件（可以多选），挑好就发。
    static func chooseAndSend(recordInto widgetID: UUID?) {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = tr("选择要用隔空投送发送的文件")
        panel.prompt = tr("发送")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        let chosen = panel.runModal() == .OK ? panel.urls : []
        NSApp.setActivationPolicy(policy)
        guard !chosen.isEmpty else { return }
        send(chosen, recordInto: widgetID)
    }

    private static func remember(_ urls: [URL], at date: Date, in id: UUID) {
        guard let current = WidgetWriter.current(id) else { return }
        WidgetWriter.write(current) { config in
            let next = AirDropHistory.recording(urls.map(\.path), at: date,
                                                into: AirDropHistory.read(config))
            AirDropHistory.write(next, into: &config)
        }
    }

    private func finish(sent: Bool) {
        if sent { record?(Date(), urls) }
        service?.delegate = nil
        service = nil
        Self.inFlight.removeAll { $0 === self }
    }

    // MARK: NSSharingServiceDelegate

    // 系统在主线程回话。
    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { finish(sent: true) }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService,
                                    didFailToShareItems items: [Any], error: any Error) {
        MainActor.assumeIsolated { finish(sent: false) }
    }
}
