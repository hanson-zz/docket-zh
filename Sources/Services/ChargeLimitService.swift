import AppKit
import Observation

/// 码头这一侧的充电上限：读写设置文件、读助手的状态、装和卸助手。
///
/// 真正暂停充电的是 root 运行的助手（见 Core/ChargeLimit.swift）。装助手
/// 要管理员密码，用系统的授权框（AppleScript 的 with administrator
/// privileges），码头自己从不碰密码。
@MainActor @Observable
final class ChargeLimitService {
    static let shared = ChargeLimitService()

    private(set) var config: ChargeLimitConfig
    private(set) var status: ChargeHelperStatus?
    private(set) var installed = false
    /// 最近一次装、卸或保存失败的原因。
    private(set) var problem: String?
    private(set) var working = false

    private init() {
        config = Self.readConfig()
        refresh()
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
        guard installed else { return .notInstalled }
        guard let status, status.isFresh(now: now) else { return .starting }
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
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(atPath: ChargeHelperFiles.directory,
                                                    withIntermediateDirectories: true)
            let data = try ChargeHelperFiles.encoder().encode(config)
            try data.write(to: URL(fileURLWithPath: ChargeHelperFiles.configPath), options: .atomic)
            problem = nil
        } catch {
            problem = "设置没存上：\(ChargeHelperFiles.directory) 不可写。重新安装助手可以修好。"
        }
    }

    private static func readConfig() -> ChargeLimitConfig {
        guard let data = FileManager.default.contents(atPath: ChargeHelperFiles.configPath),
              let config = try? ChargeHelperFiles.decoder().decode(ChargeLimitConfig.self, from: data) else {
            return .default
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
        guard let helper = bundledHelper else {
            problem = "应用包里没有找到充电助手，重新下载码头试试。"
            return
        }
        let plist = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ChargeHelperFiles.label).plist")
        do {
            try ChargeHelperFiles.launchdPlist().write(to: plist, atomically: true, encoding: .utf8)
        } catch {
            problem = "临时文件写不进去，没能安装助手。"
            return
        }
        let script = ChargeHelperFiles.installScript(helper: helper, plist: plist.path, user: NSUserName())
        if runAsAdmin(script, prompt: "码头要安装充电助手，用来在充到上限时暂停充电。") {
            save()
        }
        try? FileManager.default.removeItem(at: plist)
        refresh()
    }

    func uninstall() {
        _ = runAsAdmin(ChargeHelperFiles.uninstallScript(), prompt: "码头要卸载充电助手，并恢复正常充电。")
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
        problem = code == -128 ? nil : "没能完成：\(error[NSAppleScript.errorMessage] as? String ?? "未知错误")"
        return false
    }
}
