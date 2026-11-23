import AppKit
import SwiftUI

/// 把视图所在窗口「看不看得见」写进 `shown`（判断在 Core `MediaOnScreen`）。
///
/// 小组件面板关上时窗口只是 `orderOut`，视图还挂着、不会 `onDisappear`；被别的窗口
/// 整个挡住、切到别的桌面时也一样。播放动画（黑胶唱片、正在播放的小竖条）用它暂停，
/// 不在后台按帧刷新。窗口还没读到前保持传进来的初值，首帧照常画。
struct MediaWindowShown: ViewModifier {
    @Binding var shown: Bool
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background {
                WindowReader { resolved in
                    if window !== resolved { window = resolved }
                    refresh(resolved)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
                guard let window, note.object as? NSWindow === window else { return }
                refresh(window)
            }
    }

    private func refresh(_ window: NSWindow?) {
        let now = MediaOnScreen.windowShown(window.map {
            MediaOnScreen.Window(isVisible: $0.isVisible, occlusionVisible: $0.occlusionState.contains(.visible))
        })
        if now != shown { shown = now }
    }
}

extension View {
    /// 见 `MediaWindowShown`。
    func trackingWindowShown(_ shown: Binding<Bool>) -> some View {
        modifier(MediaWindowShown(shown: shown))
    }
}
