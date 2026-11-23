import Foundation

// MARK: - 播放动画什么时候该动
//
// 小组件面板关上时只是 `orderOut`，里面的 SwiftUI 视图还挂在窗口上，收不到
// `onDisappear`。只靠 onAppear / onDisappear 判断「看得见」的动画（黑胶唱片、
// 正在播放的小竖条）会在面板关掉以后照样按帧刷新。这里按窗口的真实状态判断。

public enum MediaOnScreen {
    /// 视图所在窗口此刻的样子；视图不在任何窗口里（量尺寸的临时视图、已经拿下来的）时是 nil。
    public struct Window: Equatable, Sendable {
        /// `NSWindow.isVisible`：收起（orderOut）后是 false。
        public var isVisible: Bool
        /// `occlusionState` 里有 `.visible`：被别的窗口整个挡住、在别的桌面、屏幕休眠时是 false。
        public var occlusionVisible: Bool

        public init(isVisible: Bool, occlusionVisible: Bool) {
            self.isVisible = isVisible
            self.occlusionVisible = occlusionVisible
        }
    }

    /// 窗口看得见：在屏幕上并且没被整个挡住。不在窗口里按看不见。
    public static func windowShown(_ window: Window?) -> Bool {
        guard let window else { return false }
        return window.isVisible && window.occlusionVisible
    }

    /// 动画该不该跑：视图出现过（onAppear 之后、onDisappear 之前）并且窗口看得见。
    public static func visible(appeared: Bool, windowShown: Bool) -> Bool {
        appeared && windowShown
    }
}

// MARK: - 播客播放失败以后再点播放

/// 播放失败（网络断了、音频地址失效）后，`AVPlayer` 还拿着那个坏掉的条目：对它再
/// `play()` 不会出声，也不会再报一次失败，界面会停在「正在播放」却没有声音。
/// 失败过的条目再点播放时要从记下的位置重新载入。
public enum PodcastResume {
    public enum Action: Equatable, Sendable {
        /// 条目还好，接着放。
        case resume
        /// 没有条目或条目失败过：重新建条目，从保存的进度开始。
        case reload
        /// 没有当前单集，什么也不做。
        case nothing
    }

    public static func action(hasEpisode: Bool, hasItem: Bool, itemFailed: Bool) -> Action {
        guard hasEpisode else { return hasItem && !itemFailed ? .resume : .nothing }
        return hasItem && !itemFailed ? .resume : .reload
    }
}
