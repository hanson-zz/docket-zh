import Foundation

/// 充电上限：充到上限就暂停充电，掉到“上限减缓冲”再恢复，电源一直供电，
/// 电池不用长时间停在满电。
///
/// 真正动手的是一个以 root 身份运行的小助手（Tools/ChargeHelper），它读
/// 这里的设置、写电池控制芯片（SMC）。码头和助手只通过两个 JSON 文件
/// 打交道：码头写设置，助手写状态。这个文件两边都编译，所以只放纯逻辑。
public struct ChargeLimitConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// 50 到 100，5 的倍数。100 等于不限制。
    public var limit: Int
    /// 暂停后掉到 `limit - buffer` 才恢复充电，免得在上限附近反复开关。
    public var buffer: Int

    public static let limits = Array(stride(from: 50, through: 100, by: 5))
    public static let buffers = [2, 3, 5, 8, 10]
    public static let `default` = ChargeLimitConfig(enabled: false, limit: 80, buffer: 5)

    public init(enabled: Bool, limit: Int, buffer: Int) {
        self.enabled = enabled
        self.limit = limit
        self.buffer = buffer
    }

    /// 文件里读到的值可能被手改过，收进合法范围。
    public var clamped: ChargeLimitConfig {
        let l = min(100, max(50, (limit / 5) * 5))
        let b = min(10, max(2, buffer))
        return ChargeLimitConfig(enabled: enabled, limit: l, buffer: b)
    }

    /// 真的会去限制：打开了且上限低于 100。
    public var isActive: Bool { enabled && clamped.limit < 100 }
}

public enum ChargeLimitPolicy {
    /// 这一刻要不要暂停充电。`percent` 是 0 到 100 的电量；读不到电量时
    /// 不限制（宁可多充，不能让电池一直不充）。
    public static func shouldInhibit(percent: Int?, config: ChargeLimitConfig,
                                     currentlyInhibited: Bool) -> Bool {
        let c = config.clamped
        guard c.isActive, let percent else { return false }
        if percent >= c.limit { return true }
        if percent <= c.limit - c.buffer { return false }
        return currentlyInhibited
    }
}

/// 助手写给码头看的状态。
public struct ChargeHelperStatus: Codable, Equatable, Sendable {
    /// 助手的版本，和 `ChargeHelperFiles.helperVersion` 不同时提示更新助手。
    public var version: Int
    /// 这台 Mac 有没有找到能控制充电的键。
    public var supported: Bool
    /// 用的是哪个键（CHTE，或旧固件的 CH0B/CH0C）。
    public var key: String?
    /// 现在是不是被助手暂停了充电。
    public var inhibited: Bool
    public var percent: Int?
    public var pluggedIn: Bool
    public var updated: Date

    public init(version: Int, supported: Bool, key: String?, inhibited: Bool,
                percent: Int?, pluggedIn: Bool, updated: Date) {
        self.version = version
        self.supported = supported
        self.key = key
        self.inhibited = inhibited
        self.percent = percent
        self.pluggedIn = pluggedIn
        self.updated = updated
    }

    /// 助手每 20 秒写一次，超过 2 分钟没更新就当它没在运行。
    public func isFresh(now: Date) -> Bool { now.timeIntervalSince(updated) < 120 }
}

/// 两边约定的路径和安装脚本。
public enum ChargeHelperFiles {
    public static let helperVersion = 1
    public static let label = "com.docket-zh.chargehelper"
    /// 应用包 Contents/MacOS 里的助手文件名。
    public static let bundledName = "dockling-charge-helper"
    public static let installedPath = "/Library/PrivilegedHelperTools/com.docket-zh.chargehelper"
    public static let plistPath = "/Library/LaunchDaemons/com.docket-zh.chargehelper.plist"
    /// 共享目录：码头（普通用户）写设置，助手（root）写状态。
    public static let directory = "/Users/Shared/Dockling"
    public static let configPath = directory + "/charge-limit.json"
    public static let statusPath = directory + "/charge-status.json"
    /// 助手多久看一次电量。
    public static let interval: TimeInterval = 20

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// launchd 的配置：开机就跑、退出就重启。
    public static func launchdPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(installedPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    /// 单引号包起来给 shell，里面的单引号转义。
    public static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 以管理员身份执行的安装脚本：把助手和 launchd 配置放到系统位置，
    /// 共享目录交给当前用户，然后启动助手。`helper` 是应用包里的助手，
    /// `plist` 是码头先写好的临时 launchd 配置。
    public static func installScript(helper: String, plist: String, user: String) -> String {
        let q = shellQuoted
        return [
            "set -e",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/bin/mkdir -p /Library/PrivilegedHelperTools \(q(directory))",
            "/usr/sbin/chown \(q(user)) \(q(directory))",
            "/bin/chmod 755 \(q(directory))",
            "/bin/cp -f \(q(helper)) \(q(installedPath))",
            "/usr/bin/xattr -c \(q(installedPath)) 2>/dev/null || true",
            "/usr/sbin/chown root:wheel \(q(installedPath))",
            "/bin/chmod 755 \(q(installedPath))",
            "/bin/cp -f \(q(plist)) \(q(plistPath))",
            "/usr/sbin/chown root:wheel \(q(plistPath))",
            "/bin/chmod 644 \(q(plistPath))",
            "/bin/launchctl bootstrap system \(q(plistPath))",
        ].joined(separator: "\n")
    }

    /// 卸载：停掉助手、恢复充电、删掉文件。设置文件留着，再装时还在。
    public static func uninstallScript() -> String {
        let q = shellQuoted
        return [
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "\(q(installedPath)) --reset 2>/dev/null || true",
            "/bin/rm -f \(q(installedPath)) \(q(plistPath)) \(q(statusPath))",
        ].joined(separator: "\n")
    }

    /// 放进 AppleScript 字符串前把反斜杠和双引号转义。
    public static func appleScriptQuoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
