import AppKit
import Foundation
import Observation
import OSLog
import Security

/// 授权相关的系统日志（只记录错误种类，不记录许可证密钥）。
private let proLicenseLog = Logger(subsystem: "com.docket-zh.app", category: "license")

// MARK: - 钥匙串

/// 码头 Pro 的授权信息存在钥匙串里，重装码头也不会丢，试用期也不会被重置。
///
/// 四样东西（许可证、实例 ID、上次校验、试用开始）合成一个钥匙串项，内容是 JSON
/// （`ProLicenseRecord`）。码头是 ad-hoc 签名，每次更新签名都会变，macOS 读旧项时会弹
/// 钥匙串授权框；以前四项分开存、每次算状态都重读四项、写的时候先删再加，一次能弹好几个。
/// 现在每次运行只在第一次用到时读一次，之后都读内存；值真的变了才写，写用
/// SecItemUpdate，没有才 Add。读失败（用户点了拒绝）也记住，这次运行不再读。
///
/// 旧版的四个项（service 是 `legacyService`）在第一次读不到新项时读一次、合并写进新项，
/// 成功后一次删掉。判断都在 Core 的 `ProLicenseStorePlan`。
@MainActor
enum ProLicenseKeychain {
    /// 新的合并项。和旧项分开 service，按 service 一次删光旧项时不会碰到新项。
    /// 和拾掇（io.github.hansonzz.shiduo.license）以及码头存 GitHub 令牌的 com.docket-zh.app 都分开。
    nonisolated static let service = "com.docket-zh.app.license.v2"
    nonisolated static let account = "license"
    /// 旧版四个独立项的 service。
    nonisolated static let legacyService = "com.docket-zh.app.license"

    private static var loaded: ProLicenseLoad?

    /// 这次运行的授权信息：第一次调用时读钥匙串（必要时迁移旧项），之后只读内存。
    static func snapshot() -> ProLicenseSnapshot {
        load().snapshot
    }

    /// 授权信息和它可不可信（是不是钥匙串里的完整真相，用户拒绝读取时为 false），
    /// 取自同一次读取。钥匙串暂时锁着时每次调用都会重读，分两次取可能一次没读到、
    /// 一次读到，拼出「空授权但可信」，已购用户的付费墙上就会出现「开始试用」。
    static func current() -> (snapshot: ProLicenseSnapshot, trusted: Bool) {
        let result = load()
        return (result.snapshot, result.trusted)
    }

    private static func load() -> ProLicenseLoad {
        if let loaded { return loaded }
        var result = ProLicenseStorePlan.load(record: read(service: service, account: account)) {
            var reads: [ProLicenseLegacyField: KeychainRead] = [:]
            for field in ProLicenseLegacyField.allCases {
                reads[field] = read(service: legacyService, account: field.rawValue)
            }
            return reads
        }
        if result.writeRecord {
            if write(ProLicenseRecord.encode(result.snapshot)) {
                if result.deleteLegacy { deleteLegacy() }
            } else {
                // 写不进去时内存照用；旧项留着，下次启动再迁。
                proLicenseLog.error("Keychain migration write failed")
            }
            result.writeRecord = false
            result.deleteLegacy = false
        }
        if result.retryLater {
            // 钥匙串暂时锁着（锁屏、登录时还没解锁）：这次按读不到算，不记住，
            // 下次算状态（每小时、唤醒）时再读，读到了就恢复，不用等重启。
            proLicenseLog.error("Keychain license locked; will retry")
            return result
        }
        if !result.trusted {
            proLicenseLog.error("Keychain license read failed; not retrying this run")
        }
        loaded = result
        return result
    }

    /// 改授权信息。值没变就不碰钥匙串。
    static func update(_ change: (inout ProLicenseSnapshot) -> Void) {
        var current = load()
        var next = current.snapshot
        change(&next)
        next = ProLicenseStorePlan.prepared(next, trusted: current.trusted)
        guard ProLicenseStorePlan.needsWrite(current: current.snapshot, next: next) else { return }
        if write(ProLicenseRecord.encode(next)) {
            // 写成功后钥匙串里就是这一份，之后可以放心按它算。
            current.trusted = true
        }
        // 写失败时内存照样更新，这次运行按新状态走。
        current.snapshot = next
        loaded = current
    }

    nonisolated private static func read(service: String, account: String) -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let read = KeychainRead.classify(status: status, data: result as? Data)
        if read.isFailed {
            proLicenseLog.error("Keychain read \(account, privacy: .public) failed: \(status, privacy: .public)")
        }
        return read
    }

    /// 写新项：先 SecItemUpdate，没有这一项才 SecItemAdd。
    nonisolated private static func write(_ text: String) -> Bool {
        let data = Data(text.utf8)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = match
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = tr("码头 Pro 授权")
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            proLicenseLog.error("Keychain write failed: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    /// 旧的四个项按 service 一次删掉（macOS 上 SecItemDelete 删除所有匹配项）。
    nonisolated private static func deleteLegacy() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            proLicenseLog.error("Keychain legacy delete failed: \(status, privacy: .public)")
        }
    }
}

// MARK: - 授权 API（经 Cloudflare Worker 中转到 Creem）

enum ProLicenseAPIError: Error {
    case network
    case badResponse
}

/// 中转服务：server/license-relay/worker.js。地址见 `ProLicenseConfig.apiBase`。
enum ProLicenseAPI {
    static func activate(key: String, instanceName: String) async throws -> ProLicenseResponse {
        try await post("activate", ["key": key, "instance_name": instanceName])
    }

    static func validate(key: String, instanceID: String) async throws -> ProLicenseResponse {
        try await post("validate", ["key": key, "instance_id": instanceID])
    }

    static func deactivate(key: String, instanceID: String) async throws -> ProLicenseResponse {
        try await post("deactivate", ["key": key, "instance_id": instanceID])
    }

    private static func post(_ endpoint: String, _ params: [String: String]) async throws -> ProLicenseResponse {
        guard let url = URL(string: ProLicenseConfig.apiBase + endpoint) else { throw ProLicenseAPIError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: params)
        request.timeoutInterval = 15

        let data: Data
        do {
            let result = try await URLSession.shared.data(for: request)
            data = result.0
        } catch {
            let ns = error as NSError
            proLicenseLog.error("License \(endpoint, privacy: .public) failed: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
            throw ProLicenseAPIError.network
        }
        guard let response = ProLicenseResponse.parse(data) else {
            proLicenseLog.error("License \(endpoint, privacy: .public): response is not JSON")
            throw ProLicenseAPIError.badResponse
        }
        return response
    }
}

// MARK: - 是否解锁（任何地方都能读）

/// 码头 Pro 是否已解锁：试用中、已激活，或老赞助者。
///
/// 授权状态由 `ProLicenseManager` 算好写进 UserDefaults，这样不在主线程的地方
/// 和每一帧重画的小组件都能便宜地读到，界面也能用 `@AppStorage` 跟着变。启动时
/// 和之后每小时都会从钥匙串重新计算并覆盖这个值。
enum ProAccess {
    /// 授权（试用或激活）是否解锁，由 ProLicenseManager 写。
    static let licenseKey = "pro.licenseUnlocked"

    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: licenseKey) || Supporter.isUnlocked
    }
}

// MARK: - 授权管理

/// 码头 Pro 的授权与试用。
@MainActor @Observable
final class ProLicenseManager {
    static let shared = ProLicenseManager()

    private(set) var state: ProLicenseState = .free
    private(set) var isWorking = false
    var errorMessage: String?

    /// 这台 Mac 已经用许可证或兑换码激活。
    private(set) var isActivated = false
    /// 打码后的许可证。
    private(set) var maskedKey: String?
    private(set) var lastValidated: Date?
    private(set) var trialEndDate: Date?
    private(set) var canStartTrial = true

    @ObservationIgnored private var started = false
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    private init() {
        refreshState()
    }

    static var instanceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// 启动时调用一次：算状态，按需联网校验，之后每小时再算一次（试用到期、
    /// 宽限期过了都能及时上锁），唤醒后也算一次。首次启动不会自动开始试用。
    func start() {
        guard !started else { return }
        started = true
        refreshState()
        // 有解锁动画之前就已激活的 Mac 不算第一次，以后解绑再激活也不自动弹。
        ProUnlockCelebration.markIfActivatedBefore(isActivated: isActivated)
        Task {
            await revalidateIfNeeded()
            // 启动后稍等一会儿再看要不要提醒试用快到期，别和启动时的窗口抢。
            try? await Task.sleep(for: .seconds(8))
            ProLicenseManager.shared.remindTrialIfNeeded()
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard let self else { return }
                self.refreshState()
                await self.revalidateIfNeeded()
                self.remindTrialIfNeeded()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                ProLicenseManager.shared.refreshState()
                Task {
                    await ProLicenseManager.shared.revalidateIfNeeded()
                    ProLicenseManager.shared.remindTrialIfNeeded()
                }
            }
        }
    }

    /// 根据钥匙串里的信息重新计算状态（不联网）。
    func refreshState() {
        let (snapshot, trusted) = ProLicenseKeychain.current()
        let now = Date()
        state = ProLicenseLogic.state(snapshot, now: now)
        isActivated = snapshot.isActivated
        maskedKey = snapshot.isActivated ? snapshot.licenseKey.map(ProLicenseText.mask) : nil
        lastValidated = snapshot.lastValidated
        trialEndDate = snapshot.trialStart.map(ProLicenseLogic.trialEndDate)
        canStartTrial = ProLicenseStorePlan.canStartTrial(snapshot, trusted: trusted)
        let unlocked = state.isUnlocked
        if UserDefaults.standard.bool(forKey: ProAccess.licenseKey) != unlocked {
            UserDefaults.standard.set(unlocked, forKey: ProAccess.licenseKey)
        }
        applyLocks()
    }

    /// 解锁状态变了以后，让不在界面上的锁跟上：充电上限没解锁时停止生效
    /// （解锁后恢复），刘海对话开着而 Pro 已锁时收起。
    private func applyLocks() {
        let unlocked = ProAccess.isUnlocked
        ChargeLimitService.shared.applyLicense(unlocked: unlocked)
        if !ProLicenseGate.canOpenAINotch(unlocked: unlocked), AINotchController.shared.isOpen {
            AINotchController.shared.close()
        }
        // 播客、环境音都是 Pro 小组件：锁定后停下并交出系统的“正在播放”会话，
        // 媒体键和控制中心不能再把它们放起来。收音机整种免费，照常播放。
        if !unlocked {
            if PodcastPlayer.shared.episode != nil { PodcastPlayer.shared.pauseAndEnd() }
            if AmbientPlayer.shared.isPlaying { AmbientPlayer.shared.stop() }
        }
    }

    // MARK: 试用到期提醒

    /// 试用剩最后 1 天时和到期后各提醒一次（应用内提示，点按钮打开付费墙）。
    /// 提醒过的记在 UserDefaults，不重复；已激活或老赞助者不提醒。
    func remindTrialIfNeeded() {
        let defaults = UserDefaults.standard
        let shown = ProTrialReminder.decode(defaults.stringArray(forKey: ProTrialReminder.defaultsKey) ?? [])
        guard let reminder = ProTrialReminder.due(state: state, supporter: Supporter.isUnlocked, shown: shown) else { return }
        // 先记下再弹，弹的过程中出什么事也不会再弹第二次。
        defaults.set(ProTrialReminder.encode(ProTrialReminder.marking(reminder, in: shown)),
                     forKey: ProTrialReminder.defaultsKey)
        // 付费墙已经开着就不用再弹一次提示。
        guard PaywallWindow.shared.window?.isVisible != true else { return }

        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = reminder.title
        alert.informativeText = reminder.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: reminder.actionTitle)
        alert.addButton(withTitle: ProTrialReminder.laterTitle)
        let response = alert.runModal()
        NSApp.setActivationPolicy(policy)
        if response == .alertFirstButtonReturn {
            PaywallWindow.shared.show()
        }
    }

    /// 用户在付费墙点“开始试用”时开始 7 天试用。开始过就不会再重置。
    func startTrial() {
        let (snapshot, trusted) = ProLicenseKeychain.current()
        guard ProLicenseStorePlan.canStartTrial(snapshot, trusted: trusted) else { return }
        ProLicenseKeychain.update { $0.trialStart = Date() }
        refreshState()
    }

    /// 距离上次成功校验超过 24 小时才联网；离线时保持 30 天。
    func revalidateIfNeeded() async {
        defer { refreshState() }
        let snapshot = ProLicenseKeychain.snapshot()
        guard ProLicenseLogic.needsRevalidation(snapshot, now: Date()),
              let key = snapshot.licenseKey, let instance = snapshot.instanceID else { return }
        let response = try? await ProLicenseAPI.validate(key: key, instanceID: instance)
        switch ProLicenseLogic.revalidation(response) {
        case .keep:
            break
        case .confirmed:
            ProLicenseKeychain.update { $0.lastValidated = Date() }
        case .revoked(let message):
            ProLicenseKeychain.update {
                $0.instanceID = nil
                $0.lastValidated = nil
            }
            errorMessage = message
            proLicenseLog.error("License revalidation rejected, status: \(response?.status ?? "-", privacy: .public)")
        }
    }

    /// 用许可证或兑换码激活这台 Mac。成功返回 true。
    @discardableResult
    func activate(_ raw: String) async -> Bool {
        let input = ProLicenseInput.classify(raw)
        if let problem = ProLicenseText.inputProblem(input) {
            errorMessage = problem
            return false
        }
        let key: String
        switch input {
        case .gift(let code): key = code
        case .licenseKey(let text): key = text
        default: return false
        }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await ProLicenseAPI.activate(key: key, instanceName: Self.instanceName)
            switch ProLicenseLogic.activation(response) {
            case .success(let instance):
                ProLicenseKeychain.update {
                    $0.licenseKey = key
                    $0.instanceID = instance
                    $0.lastValidated = Date()
                }
                refreshState()
                // 第一次激活成功时播放解锁庆祝动画（只自动播一次，见 ProUnlockFirstRun）。
                ProUnlockCelebration.shared.activationSucceeded()
                return true
            case .wrongProduct(let instance):
                // 不是码头的许可证：把刚占用的激活名额还回去。
                _ = try? await ProLicenseAPI.deactivate(key: key, instanceID: instance)
                errorMessage = ProLicenseText.wrongProduct
                return false
            case .failure(let message):
                errorMessage = message
                proLicenseLog.error("Activation failed: \(response.error ?? "-", privacy: .public)")
                return false
            }
        } catch {
            errorMessage = ProLicenseText.network
            return false
        }
    }

    /// 解绑这台 Mac，把激活名额留给别的 Mac（兑换码同样一码一机，解绑后可换机）。
    func deactivate() async {
        let snapshot = ProLicenseKeychain.snapshot()
        guard let key = snapshot.licenseKey else { return }
        guard let instance = snapshot.instanceID else {
            clearActivation()
            return
        }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await ProLicenseAPI.deactivate(key: key, instanceID: instance)
            if ProLicenseLogic.deactivationSucceeded(response) {
                clearActivation()
            } else {
                errorMessage = ProLicenseText.message(error: response.error, status: response.status)
            }
        } catch {
            errorMessage = ProLicenseText.network
        }
    }

    private func clearActivation() {
        ProLicenseKeychain.update {
            $0.licenseKey = nil
            $0.instanceID = nil
            $0.lastValidated = nil
        }
        refreshState()
    }

    func buy() {
        NSWorkspace.shared.open(ProLicenseConfig.buyURL)
    }
}
