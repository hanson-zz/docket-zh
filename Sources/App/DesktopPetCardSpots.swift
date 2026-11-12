import AppKit
import SwiftUI

/// 小熊猫要知道某张卡片此刻在屏幕上的哪儿（专注完成时朝计时器卡片看一眼）。
/// 卡片在背景里放一个不接鼠标的空视图登记自己，要用时现算它在屏幕上的框；
/// 卡片不在屏幕上（扩展栏收起、窗口没显示）时是 nil，小熊猫就地欢呼。
@MainActor
final class DesktopPetCardSpots {
    static let shared = DesktopPetCardSpots()

    private final class Weak {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var views: [UUID: Weak] = [:]

    private init() {}

    func register(_ id: UUID, view: NSView) {
        views[id] = Weak(view)
    }

    func unregister(_ id: UUID, view: NSView) {
        if views[id]?.view === view { views[id] = nil }
    }

    /// 卡片中心（屏幕坐标，左下原点）；看不见时 nil。
    func center(of id: UUID) -> CGPoint? {
        guard let view = views[id]?.view, let window = view.window, window.isVisible,
              window.occlusionState.contains(.visible), !view.isHiddenOrHasHiddenAncestor else { return nil }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard frame.width > 0, frame.height > 0,
              NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

/// 放在卡片背景里：登记这张卡片的位置，不画东西、不接鼠标。
struct DesktopPetCardSpot: NSViewRepresentable {
    var id: UUID
    var enabled: Bool

    final class SpotView: NSView {
        var id: UUID?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let id else { return }
            if window == nil {
                DesktopPetCardSpots.shared.unregister(id, view: self)
            } else {
                DesktopPetCardSpots.shared.register(id, view: self)
            }
        }
    }

    func makeNSView(context: Context) -> SpotView {
        let view = SpotView()
        view.id = enabled ? id : nil
        return view
    }

    func updateNSView(_ view: SpotView, context: Context) {
        let next = enabled ? id : nil
        guard view.id != next else { return }
        if let old = view.id { DesktopPetCardSpots.shared.unregister(old, view: view) }
        view.id = next
        if let next, view.window != nil { DesktopPetCardSpots.shared.register(next, view: view) }
    }
}
