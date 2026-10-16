import SwiftUI

/// 货架上的一层搁板：一条带高光的薄板，板下一道软影子。
struct ShelfLedge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.12)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: 6)
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.45)).frame(height: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
            .accessibilityHidden(true)
    }
}

/// 立在搁板上的一张剪贴卡片：上面是缩略图，下面是两行字。
///
/// 平时微微歪着，鼠标移上去会扶正并往上抬一点；点一下拷贝时卡片轻轻跳一下，
/// 说明文字换成“已拷贝”。打开“减少动态效果”时不歪、不抬、不跳。
struct ShelfClipCard<Thumb: View, Accessory: View>: View {
    var title: String
    var caption: String
    var tilt: Double
    /// 刚被拷贝的那张：跳一下，说明换成“已拷贝”或“已粘贴”。
    var flashed: Bool
    var flashText: String
    @ViewBuilder var thumb: () -> Thumb
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            thumb()
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(flashed ? flashText : caption)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(flashed ? 0.95 : 0.55))
                .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovering ? 0.18 : 0.12))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) { accessory() }
                .padding(2)
                .opacity(hovering ? 1 : 0.85)
        }
        .contentShape(.rect(cornerRadius: 10))
        .rotationEffect(.degrees(reduceMotion || hovering ? 0 : tilt), anchor: .bottom)
        .offset(y: hovering && !reduceMotion ? -5 : 0)
        .shadow(color: .black.opacity(hovering ? 0.35 : 0.2), radius: hovering ? 6 : 3, y: hovering ? 5 : 2)
        .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? false : flashed) { view, lift in
            view.offset(y: -lift)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(0, duration: 0.01)
                SpringKeyframe(flashed ? 8 : 0, duration: 0.14)
                SpringKeyframe(0, duration: 0.3)
            }
        }
        .onHover { inside in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.3)) { hovering = inside }
        }
    }
}
