import Foundation

/// 设置 ▸ 通用 ▸ 导出诊断信息 的纯逻辑：文件名、偏好里该剔除的键、挑哪些崩溃报告、
/// 日志留多少行、info.txt 的排版。真正读系统、写 zip 的在 `DiagnosticsExporter`。
///
/// 诊断包是给开发者看的，所以绝不能带出激活码、邮箱、密钥这类东西：偏好里名字沾边的
/// 键整条去掉（嵌套的字典里也去），字符串值长得像邮箱的也换成占位。
public enum Diagnostics {
    /// 键名里含这些片段（不分大小写）就整条剔除。
    public static let sensitiveFragments = ["license", "key", "token", "email", "password", "secret", "code"]

    /// 替换掉像邮箱的字符串值。
    public static let redacted = "<redacted>"

    /// log.txt 最多几行，多了留最新的。
    public static let logLineLimit = 5000

    /// 日志往回取多久（秒）。
    public static let logWindow: TimeInterval = 24 * 60 * 60

    /// 崩溃报告最多带几个。
    public static let crashLimit = 10

    /// 这个键名是否敏感。
    public static func isSensitive(_ key: String) -> Bool {
        let lower = key.lowercased()
        return sensitiveFragments.contains { lower.contains($0) }
    }

    /// 偏好字典剔除敏感键后的样子。嵌套的字典和数组里也照样处理。
    public static func sanitizedDefaults(_ domain: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in domain where !isSensitive(key) {
            result[key] = sanitizedValue(value)
        }
        return result
    }

    private static func sanitizedValue(_ value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]:
            return sanitizedDefaults(dictionary)
        case let array as [Any]:
            return array.map(sanitizedValue)
        case let string as String:
            return looksLikeEmail(string) ? redacted : string
        default:
            return value
        }
    }

    /// 粗略判断一个字符串里有没有邮箱地址。
    public static func looksLikeEmail(_ text: String) -> Bool {
        text.range(of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, options: .regularExpression) != nil
    }

    /// 默认文件名：Dockling-诊断-20261111-2252.zip，英文界面是 Dockling-Diagnostics-…。
    public static func fileName(date: Date, english: Bool, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let word = english ? "Diagnostics" : "诊断"
        return "Dockling-\(word)-\(formatter.string(from: date)).zip"
    }

    /// 从 DiagnosticReports 的文件里挑本 App 的崩溃报告：.ips，文件名含任一进程名，
    /// 按修改时间从新到旧，最多 `crashLimit` 个。
    public static func crashReports(_ files: [(name: String, modified: Date)],
                                    processNames: [String]) -> [String] {
        let needles = processNames.filter { !$0.isEmpty }.map { $0.lowercased() }
        return files
            .filter { file in
                let lower = file.name.lowercased()
                return lower.hasSuffix(".ips") && needles.contains { lower.contains($0) }
            }
            .sorted { $0.modified > $1.modified }
            .prefix(crashLimit)
            .map(\.name)
    }

    /// 日志只留最后 `logLineLimit` 行。
    public static func trimmedLog(_ lines: [String]) -> [String] {
        lines.count > logLineLimit ? Array(lines.suffix(logLineLimit)) : lines
    }

    /// info.txt：一节一个标题，下面是“名字: 值”。
    public static func infoText(_ sections: [(title: String, rows: [(String, String)])]) -> String {
        sections.map { section in
            let rows = section.rows.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            return "[\(section.title)]\n\(rows)"
        }
        .joined(separator: "\n\n") + "\n"
    }
}
