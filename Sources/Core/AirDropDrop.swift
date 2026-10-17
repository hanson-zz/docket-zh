import Foundation

/// 隔空投送卡片的状态和文字：平时、拖着文件进来、拖进来的不是文件、
/// 这台 Mac 用不了隔空投送。卡片只负责画，发送交给系统的隔空投送面板，
/// 卡片上不显示发送结果。
public enum AirDropDrop {
    public enum State: Equatable, Sendable {
        /// 平时：等文件拖进来。
        case idle
        /// 拖着 N 个文件停在卡片上，松手就发。
        case targeted(files: Int)
        /// 拖进来的东西里没有文件（文字、链接等），发不了。
        case noFiles
        /// 系统没有隔空投送服务（例如没有无线网卡的 Mac）。
        case unavailable

        public var title: String {
            switch self {
            case .targeted: tr("松手发送")
            case .idle, .noFiles, .unavailable: tr("隔空投送")
            }
        }

        public var caption: String {
            switch self {
            case .idle: tr("拖文件到这里")
            case .targeted(let files): tr("\(files) 个文件")
            case .noFiles: tr("只能发送文件")
            case .unavailable: tr("此 Mac 不支持")
            }
        }

        /// 蓝色虚线高亮只在能发的时候出现。
        public var highlighted: Bool {
            if case .targeted = self { return true }
            return false
        }

        /// 灰掉：用不了，或者拖来的不是文件。
        public var disabled: Bool {
            self == .unavailable || self == .noFiles
        }
    }

    /// 由“系统能不能发”“有没有东西拖在卡片上”“里面几个文件”得出状态。
    public static func state(available: Bool, dragging: Bool, files: Int) -> State {
        guard available else { return .unavailable }
        guard dragging else { return .idle }
        return files > 0 ? .targeted(files: files) : .noFiles
    }

    /// 竖排只在空间不够时用：竖排货架，或者卡片窄到放不下横排。
    public static let minimumRowWidth: Double = 120

    public static func usesColumn(vertical: Bool, width: Double) -> Bool {
        vertical || width < minimumRowWidth
    }

    /// 竖排时「隔空投送」拆成两行。
    public static let columnTitle = tr("隔空\n投送")
}
