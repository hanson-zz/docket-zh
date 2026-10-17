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
/// 用码头自己的 bundle 前缀做 service 名，和拾掇（io.github.hansonzz.shiduo.license）
/// 以及码头存 GitHub 令牌的 com.docket-zh.app 都分开。
enum ProLicenseKeychain {
    static let service = "com.docket-zh.app.license"

    enum Account: String, CaseIterable {
        case licenseKey
        case instanceID
        case lastValidated
        case trialStart
    }

    static func get(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: Account) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrLabel as String] = tr("码头 Pro 授权")
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            proLicenseLog.error("Keychain write \(account.rawValue, privacy: .public) failed: \(status, privacy: .public)")
        }
    }

    static func date(_ account: Account) -> Date? {
        guard let text = get(account), let seconds = Double(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func setDate(_ date: Date?, for account: Account) {
        set(date.map { String($0.timeIntervalSince1970) }, for: account)
    }

    static func snapshot() -> ProLicenseSnapshot {
        ProLicenseSnapshot(licenseKey: get(.licenseKey), instanceID: get(.instanceID),
                           lastValidated: date(.lastValidated), trialStart: date(.trialStart))
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
        let snapshot = ProLicenseKeychain.snapshot()
        let now = Date()
        state = ProLicenseLogic.state(snapshot, now: now)
        isActivated = snapshot.isActivated
        maskedKey = snapshot.isActivated ? snapshot.licenseKey.map(ProLicenseText.mask) : nil
        lastValidated = snapshot.lastValidated
        trialEndDate = snapshot.trialStart.map(ProLicenseLogic.trialEndDate)
        canStartTrial = ProLicenseLogic.canStartTrial(snapshot)
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
        let snapshot = ProLicenseKeychain.snapshot()
        guard ProLicenseLogic.canStartTrial(snapshot) else { return }
        ProLicenseKeychain.setDate(Date(), for: .trialStart)
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
            ProLicenseKeychain.setDate(Date(), for: .lastValidated)
        case .revoked(let message):
            ProLicenseKeychain.set(nil, for: .instanceID)
            ProLicenseKeychain.set(nil, for: .lastValidated)
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
                ProLicenseKeychain.set(key, for: .licenseKey)
                ProLicenseKeychain.set(instance, for: .instanceID)
                ProLicenseKeychain.setDate(Date(), for: .lastValidated)
                refreshState()
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
        guard let key = ProLicenseKeychain.get(.licenseKey) else { return }
        guard let instance = ProLicenseKeychain.get(.instanceID) else {
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
        ProLicenseKeychain.set(nil, for: .licenseKey)
        ProLicenseKeychain.set(nil, for: .instanceID)
        ProLicenseKeychain.set(nil, for: .lastValidated)
        refreshState()
    }

    func buy() {
        NSWorkspace.shared.open(ProLicenseConfig.buyURL)
    }
}
