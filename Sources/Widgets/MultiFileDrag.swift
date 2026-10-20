import AppKit
import SwiftUI

/// 一次拖出好几个文件。SwiftUI 的 `onDrag` 一次只给一个，这里用 AppKit 的
/// 拖拽会话，每个文件一个拖拽项，叠成一摞，松到访达、邮件、聊天窗口里都
/// 和从访达拖出来一样。
///
/// 盖在按钮上：按住拖动开始拖；只是点一下（没拖动）调 `onClick`，面板用它
/// 提示「按住拖到要放的地方」。
struct MultiFileDragSource: NSViewRepresentable {
    var urls: [URL]
    var onClick: () -> Void

    func makeNSView(context: Context) -> MultiFileDragView {
        let view = MultiFileDragView()
        view.urls = urls
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: MultiFileDragView, context: Context) {
        view.urls = urls
        view.onClick = onClick
    }
}

final class MultiFileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onClick: () -> Void = {}

    private var down: NSEvent?
    private var dragging = false

    /// 面板不在前台时第一下也算数。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        down = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let down, !urls.isEmpty else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }
        dragging = true
        let origin = convert(down.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 40, height: 40)
            let shift = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(NSRect(x: origin.x - 20 + shift, y: origin.y - 20 - shift, width: 40, height: 40),
                                  contents: icon)
            return item
        }
        let session = beginDraggingSession(with: items, event: down, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging, down != nil { onClick() }
        down = nil
        dragging = false
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // 和单个拖出一样只给拷贝：拖到访达是拷一份过去，原文件留在原处，
        // 暂存里的条目也不会变成「找不到了」。
        .copy
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                     operation: NSDragOperation) {
        MainActor.assumeIsolated {
            down = nil
            dragging = false
        }
    }
}
