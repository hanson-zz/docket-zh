import AppKit
import Observation

/// 码头这一侧的充电上限：读写设置文件、读助手的状态、装和卸助手。
///
/// 真正暂停充电的是 root 运行的助手（见 Core/ChargeLimit.swift）。装助手
/// 要管理员密码，用系统的授权框（AppleScript 的 with administrator
/// privileges），码头自己从不碰密码。
///
/// 充电上限是码头 Pro 的功能。`config` 是用户自己的选择；写给助手的设置文件
/// 是 `ProLicenseGate.chargeLimitConfig` 算出的实际生效的那份：没解锁时开关写成
/// 关，助手就恢复正常充电（旧版助手也认）。用户的开关另外存在 UserDefaults，
/// 解锁后写回去，上限恢复生效。
@MainActor @Observable
final class ChargeLimitService {
    static let shared = ChargeLimitService()

    /// 用户自己的选择（开关、上限、缓冲）。
    private(set) var config: ChargeLimitConfig
    /// Pro 是否已解锁，由 `ProLicenseManager` 在状态变化时告诉这里。
    private(set) var unlocked = ProAccess.isUnlocked
    /// 设置文件里现在写着的（实际生效的那份），没有文件时为 nil。
    @ObservationIgnored private var onDisk: ChargeLimitConfig?

    /// UserDefaults 里存用户自己打开没打开充电上限。
    static let enabledByUserKey = "chargeLimit.enabledByUser"
    private(set) var status: ChargeHelperStatus?
    private(set) var installed = false
    /// 最近一次装、卸或保存失败的原因。
    private(set) var problem: String?
    private(set) var working = false

    private init() {
        let disk = Self.readConfigFile()
        onDisk = disk
        var mine = disk ?? .default
        if let wanted = UserDefaults.standard.object(forKey: Self.enabledByUserKey) as? Bool {
            mine.enabled = wanted
        } else if mine.enabled {
            // 以前打开过，还没单独记下来：记下，锁上以后解锁还能恢复。
            UserDefaults.standard.set(true, forKey: Self.enabledByUserKey)
        }
        config = mine
        refresh()
    }

    /// 写给助手的那份：没解锁时开关是关的。
    var effectiveConfig: ChargeLimitConfig {
        ProLicenseGate.chargeLimitConfig(config, unlocked: unlocked)
    }

    /// 授权状态变了：没解锁时让上限停止生效，解锁后恢复。设置文件只在实际
    /// 生效的那份变了时才重写；从没写过设置文件（没用过充电上限）时不写。
    func applyLicense(unlocked: Bool) {
        if self.unlocked != unlocked { self.unlocked = unlocked }
        guard let onDisk, onDisk != effectiveConfig else { return }
        save()
    }

    // MARK: 状态

    enum State: Equatable {
        case notInstalled
        case starting
        case unsupported
        case needsUpdate
        case running
    }

    func state(now: Date = .now) -> State {
        // 助手在按时写状态就说明它在跑，哪怕码头这边看不到安装的文件。
        let fresh = status.map { $0.isFresh(now: now) } ?? false
        guard installed || fresh else { return .notInstalled }
        guard let status, fresh else { return .starting }
        if !status.supported { return .unsupported }
        if status.version != ChargeHelperFiles.helperVersion { return .needsUpdate }
        return .running
    }

    /// 重新看一眼文件。面板打开时每几秒调用一次。
    func refresh() {
        installed = FileManager.default.fileExists(atPath: ChargeHelperFiles.plistPath)
            && FileManager.default.fileExists(atPath: ChargeHelperFiles.installedPath)
        if let data = FileManager.default.contents(atPath: ChargeHelperFiles.statusPath) {
            status = try? ChargeHelperFiles.decoder().decode(ChargeHelperStatus.self, from: data)
        } else {
            status = nil
        }
    }

    // MARK: 设置

    func update(_ change: (inout ChargeLimitConfig) -> Void) {
        var next = config
        change(&next)
        next = next.clamped
        guard next != config else { return }
        config = next
        UserDefaults.standard.set(next.enabled, forKey: Self.enabledByUserKey)
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(atPath: ChargeHelperFiles.directory,
                                                    withIntermediateDirectories: true)
            let effective = effectiveConfig
            let data = try ChargeHelperFiles.encoder().encode(effective)
            try data.write(to: URL(fileURLWithPath: ChargeHelperFiles.configPath), options: .atomic)
            onDisk = effective
            problem = nil
        } catch {
            problem = tr("设置没存上：\(ChargeHelperFiles.directory) 不可写。重新安装助手可以修好。")
        }
    }

    private static func readConfigFile() -> ChargeLimitConfig? {
        guard let data = FileManager.default.contents(atPath: ChargeHelperFiles.configPath),
              let config = try? ChargeHelperFiles.decoder().decode(ChargeLimitConfig.self, from: data) else {
            return nil
        }
        return config.clamped
    }

    // MARK: 装和卸

    /// 应用包里的助手。
    private var bundledHelper: String? {
        let path = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/\(ChargeHelperFiles.bundledName)").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    func install() {
        // 装和更新助手是 Pro 的一部分；界面上已经拦了，这里再守一道。
        guard ProLicenseGate.canUse(.chargeLimit, unlocked: unlocked) else { return }
        guard let helper = bundledHelper else {
            problem = tr("应用包里没有找到充电助手，重新下载码头试试。")
            return
        }
        let plist = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ChargeHelperFiles.label).plist")
        do {
            try ChargeHelperFiles.launchdPlist().write(to: plist, atomically: true, encoding: .utf8)
        } catch {
            problem = tr("临时文件写不进去，没能安装助手。")
            return
        }
        let script = ChargeHelperFiles.installScript(helper: helper, plist: plist.path, user: NSUserName())
        let ok = runAsAdmin(script, prompt: tr("码头要安装充电助手，用来在充到上限时暂停充电。"))
        if ok { save() }
        try? FileManager.default.removeItem(at: plist)
        refresh()
        if ok && !installed {
            problem = tr("授权完成了，但没在 /Library/PrivilegedHelperTools 和 /Library/LaunchDaemons 找到助手文件。")
                + tr("可以点“复制诊断”把结果发给开发者。")
        }
    }

    /// 把排查用的信息拷进剪贴板：文件在不在、状态文件内容、应用包里的助手。
    func copyDiagnostics(now: Date = .now) {
        let fm = FileManager.default
        func line(_ path: String) -> String { "\(fm.fileExists(atPath: path) ? tr("有") : tr("没有"))  \(path)" }
        var lines = [
            tr("码头充电上限诊断 \(now.formatted(.iso8601))"),
            tr("状态：\(state(now: now))"),
            line(ChargeHelperFiles.installedPath),
            line(ChargeHelperFiles.plistPath),
            line(ChargeHelperFiles.configPath),
            line(ChargeHelperFiles.statusPath),
            tr("应用包助手：\(bundledHelper ?? tr("没有"))"),
            tr("应用位置：\(Bundle.main.bundleURL.path)"),
        ]
        if let data = fm.contents(atPath: ChargeHelperFiles.statusPath),
           let text = String(data: data, encoding: .utf8) {
            lines.append(tr("状态文件：\(text)"))
        }
        if let problem { lines.append(tr("最近的错误：\(problem)")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func uninstall() {
        _ = runAsAdmin(ChargeHelperFiles.uninstallScript(), prompt: tr("码头要卸载充电助手，并恢复正常充电。"))
        refresh()
    }

    /// 弹出系统的管理员授权框执行脚本。用户取消时不算错误。
    private func runAsAdmin(_ script: String, prompt: String) -> Bool {
        working = true
        defer { working = false }
        let source = "do shell script \"\(ChargeHelperFiles.appleScriptQuoted(script))\" "
            + "with prompt \"\(ChargeHelperFiles.appleScriptQuoted(prompt))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else {
            problem = nil
            return true
        }
        let code = error[NSAppleScript.errorNumber] as? Int
        problem = code == -128 ? nil : tr("没能完成：\(error[NSAppleScript.errorMessage] as? String ?? tr("未知错误"))")
        return false
    }
}
