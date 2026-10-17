import CoreGraphics
import Foundation

/// 新手引导里的聚光灯导览：整个窗口压暗，只在要讲的那个控件周围挖一个亮洞，
/// 旁边一张小卡片说它是干什么的，点“下一步”亮洞滑到下一个控件。
///
/// 这里只放纯数据和几何（洞挖多大、卡片放上面还是下面），测试可以直接算。
public struct SpotlightStop: Equatable, Hashable, Sendable, Identifiable {
    /// 和界面上 `spotlightTarget(_:)` 标的名字对应。
    public var id: String
    public var title: String
    public var message: String

    public init(id: String, title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

public enum SpotlightTour {

    /// 欢迎页上“先带我看看”走的三站。
    public static let onboarding: [SpotlightStop] = [
        SpotlightStop(id: "progress", title: tr("一共六步"),
                      message: tr("顶上这排小格是进度，走到哪一步就亮到哪一格，左边的箭头可以回到上一步。")),
        SpotlightStop(id: "skip", title: tr("随时可以跳过"),
                      message: tr("现在不想设置就点“跳过”。以后想再看，在“设置 ▸ 通用”里重新打开这份引导。")),
        SpotlightStop(id: "primary", title: tr("准备好了就开始"),
                      message: tr("底部的大按钮带你走下一步，选位置、选用途，再把小组件一个个放进扩展栏。")),
    ]

    public enum Placement: Equatable, Sendable { case above, below }

    /// 亮洞：目标外扩 `padding`，再收进窗口里，不会挖到窗口外面去。
    public static func cutout(_ target: CGRect, padding: CGFloat, in bounds: CGRect) -> CGRect {
        let grown = target.insetBy(dx: -padding, dy: -padding)
        let clipped = grown.intersection(bounds)
        return clipped.isNull ? .zero : clipped
    }

    /// 卡片放在亮洞下面还是上面：下面放得下就放下面，否则放上面空得多的一边。
    /// 坐标是 SwiftUI 的，y 往下变大。
    public static func placement(cutout: CGRect, calloutHeight: CGFloat, gap: CGFloat,
                                 in bounds: CGRect) -> Placement {
        let below = bounds.maxY - cutout.maxY
        let above = cutout.minY - bounds.minY
        if below >= calloutHeight + gap * 2 { return .below }
        return above > below ? .above : .below
    }

    /// 卡片的中心点：水平对准亮洞中间，但离窗口左右至少 `margin`；
    /// 竖直方向贴着亮洞，隔 `gap`。
    public static func calloutCenter(cutout: CGRect, size: CGSize, gap: CGFloat, margin: CGFloat,
                                     in bounds: CGRect) -> CGPoint {
        let half = size.width / 2
        let lo = bounds.minX + margin + half
        let hi = bounds.maxX - margin - half
        let x = lo <= hi ? min(max(cutout.midX, lo), hi) : bounds.midX
        let y: CGFloat
        switch placement(cutout: cutout, calloutHeight: size.height, gap: gap, in: bounds) {
        case .below: y = cutout.maxY + gap + size.height / 2
        case .above: y = cutout.minY - gap - size.height / 2
        }
        return CGPoint(x: x, y: y)
    }

    /// 卡片角上的“1 / 3”。
    public static func counter(index: Int, total: Int) -> String {
        "\(min(max(index, 0), max(total - 1, 0)) + 1) / \(max(total, 1))"
    }

    /// 下一站；已经是最后一站时返回 nil，导览结束。
    public static func next(after index: Int, total: Int) -> Int? {
        index + 1 < total ? index + 1 : nil
    }
}
