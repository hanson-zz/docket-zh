import Foundation

/// Transport connectivity alone does not establish that a website is being recorded.
public enum TimeInsightsWebsiteConnection: Equatable, Sendable {
    case disabled
    case notPlaced
    case blocked(TimeInsightsStatus)
    case disconnected(BrowserBridgeState)
    case waitingForeground
    case applicationOnly
    case recording

    public static func resolve(bridge: BrowserBridgeState, status: TimeInsightsStatus,
                               enabled: Bool, placed: Bool, excluded: Bool,
                               foreground: Bool, hasWebsite: Bool) -> Self {
        guard enabled else { return .disabled }
        guard placed else { return .notPlaced }
        switch status {
        case .paused, .away, .idle, .storageError: return .blocked(status)
        default: break
        }
        guard !excluded else { return .blocked(.excluded) }
        guard bridge == .connected else { return .disconnected(bridge) }
        guard foreground && status == .recording else { return .waitingForeground }
        return hasWebsite ? .recording : .applicationOnly
    }

    public var title: String {
        switch self {
        case .disabled: tr("网站统计未开启")
        case .notPlaced: tr("放置时间洞察小组件后开始记录")
        case .blocked(let status): status.title
        case .disconnected(.permissionRequired): tr("扩展缺少权限。仅记录应用。")
        case .disconnected(.offline): tr("扩展已断开。仅记录应用。")
        case .disconnected: tr("扩展未连接，请检查安装。仅记录应用。")
        case .waitingForeground: tr("扩展已连接，等待此浏览器在前台")
        case .applicationOnly: tr("扩展已连接，当前仅记录应用")
        case .recording: tr("扩展已连接，正在统计前台网站")
        }
    }
}
