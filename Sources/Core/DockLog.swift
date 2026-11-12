import Foundation
import os

/// 码头的统一日志：子系统是 bundle id，按模块分类。
///
/// 只记错误和少量值得留意的事（notice），不刷屏。消息按 public 写进系统日志，
/// 所以调用方不要把文件路径、文件名、账号这类隐私放进消息里。
/// 设置 ▸ 通用 ▸ 导出诊断信息 会把最近 24 小时的这些条目打进 log.txt。
public enum DockLog {
    public enum Area: String, CaseIterable, Sendable {
        case pet
        case fileShelf = "file-shelf"
        case radio
        case switcher
        case diagnostics
    }

    public static let subsystem = Bundle.main.bundleIdentifier ?? "com.docket-zh.app"

    public static func logger(_ area: Area) -> Logger {
        Logger(subsystem: subsystem, category: area.rawValue)
    }

    public static func error(_ area: Area, _ message: String) {
        logger(area).error("\(message, privacy: .public)")
    }

    public static func notice(_ area: Area, _ message: String) {
        logger(area).notice("\(message, privacy: .public)")
    }
}
