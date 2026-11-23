import SwiftUI

/// 正在播放的小竖条：播放时跟着节奏跳，暂停时停成一排矮条。
/// 只在扩展栏看得见、所在窗口也看得见时跳（12 帧），减少动态效果时静止。面板关上
/// （窗口 orderOut）或被整个挡住时停帧，不在后台刷新。
struct PlayingBarsView: View {
    var playing: Bool
    var tint: Color
    var height: CGFloat = 12
    var visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowShown = true

    var body: some View {
        let fps = PlayingBars.framesPerSecond(playing: playing,
                                              visible: MediaOnScreen.visible(appeared: visible, windowShown: windowShown),
                                              reduceMotion: reduceMotion)
        let barWidth = max(2, height * 0.2)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? PlayingBars.fps), paused: fps == nil)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barWidth * 0.7) {
                ForEach(0..<PlayingBars.count, id: \.self) { index in
                    let h = fps == nil ? PlayingBars.stillHeight(index: index) : PlayingBars.height(index: index, t: t)
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: max(barWidth, height * h))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .opacity(playing ? 1 : 0.55)
        .trackingWindowShown($windowShown)
        .accessibilityHidden(true)
    }
}
