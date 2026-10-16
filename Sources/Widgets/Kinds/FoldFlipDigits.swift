import SwiftUI

/// 一串读数画成折叠翻页卡片：数字各占一张，冒号原样画在中间。
///
/// 卡片按从右往左的位置认身份（见 `FoldFlip.slot`），所以位数变少时
/// 个位那几张还是原来的卡片，接着翻。
struct FoldFlipText: View {
    var text: String
    /// 数字的字号，卡片的大小跟着它算。
    var size: CGFloat
    /// 给了宽度就按它缩小字号，免得多一位时把窄卡片撑出去。
    var maxWidth: CGFloat?

    private struct Slot: Identifiable {
        var id: Int
        var cell: FoldFlip.Cell
    }

    private var slots: [Slot] {
        let cells = FoldFlip.cells(text)
        return cells.enumerated().map { Slot(id: FoldFlip.slot($0.offset, count: cells.count), cell: $0.element) }
    }

    /// 宽度按卡片和冒号的比例估出来，超出 `maxWidth` 时整体缩小。
    private var fittedSize: CGFloat {
        guard let maxWidth else { return size }
        let cells = FoldFlip.cells(text)
        let cards = CGFloat(cells.filter(\.flips).count)
        let marks = CGFloat(cells.count) - cards
        let gaps = CGFloat(max(0, cells.count - 1))
        let natural = size * (cards * FoldFlipDigit.widthRatio + marks * 0.34 + gaps * 0.08)
        guard natural > maxWidth, natural > 0 else { return size }
        return size * maxWidth / natural
    }

    var body: some View {
        let size = fittedSize
        HStack(spacing: size * 0.08) {
            ForEach(slots) { slot in
                if slot.cell.flips {
                    FoldFlipDigit(digit: slot.cell.text, size: size)
                } else {
                    Text(slot.cell.text)
                        .font(.system(size: size * 0.8, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetStyle.secondary)
                        .frame(width: size * 0.34)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// 一张翻页卡片：上半张和下半张。
///
/// 数字一变，上半张带着旧数字绕着中缝往下折，折到侧面看不见时，
/// 下半张带着新数字从侧面落下来盖住旧的下半张。折的那半张越接近侧面越暗，
/// 像真的翻页钟。打开“减少动态效果”时直接换数字，不翻。
///
/// 两半各用一个关键帧动画，只改角度、亮度和透明度。静止时上面那张翻页已经
/// 折走（看不见），下面那张已经落下、盖住垫在底下的旧数字，所以底下那半张
/// 一直画旧数字也没关系。
struct FoldFlipDigit: View {
    var digit: String
    var size: CGFloat

    static let widthRatio: CGFloat = 0.7
    private static let heightRatio: CGFloat = 1.3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: String
    @State private var outgoing: String
    @State private var flips = 0

    init(digit: String, size: CGFloat) {
        self.digit = digit
        self.size = size
        _shown = State(initialValue: digit)
        _outgoing = State(initialValue: digit)
    }

    private var width: CGFloat { size * Self.widthRatio }
    private var height: CGFloat { size * Self.heightRatio }

    var body: some View {
        VStack(spacing: max(0.6, size * 0.04)) {
            ZStack {
                half(shown, top: true)
                // 旧数字的上半张：从竖着（0 度）往下折到侧面（-90 度）。
                // 第一帧就是竖着的旧数字，不会先闪一下新数字。
                half(outgoing, top: true)
                    .keyframeAnimator(initialValue: -90.0, trigger: flips) { view, angle in
                        view
                            .brightness(-0.25 * min(1, max(0, -angle / 90)))
                            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0),
                                              anchor: .bottom, perspective: 0.5)
                            .opacity(angle > -89.5 ? 1 : 0)
                    } keyframes: { _ in
                        KeyframeTrack {
                            MoveKeyframe(0.0)
                            CubicKeyframe(-90.0, duration: 0.16)
                        }
                    }
            }
            ZStack {
                half(outgoing, top: false)
                // 新数字的下半张：等上半张折完，从侧面（90 度）落到平放（0 度）。
                half(shown, top: false)
                    .keyframeAnimator(initialValue: 0.0, trigger: flips) { view, angle in
                        view
                            .brightness(-0.25 * min(1, max(0, angle / 90)))
                            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0),
                                              anchor: .top, perspective: 0.5)
                            .opacity(angle < 89.5 ? 1 : 0)
                    } keyframes: { _ in
                        KeyframeTrack {
                            MoveKeyframe(90.0)
                            LinearKeyframe(90.0, duration: 0.16)
                            CubicKeyframe(0.0, duration: 0.22)
                        }
                    }
            }
        }
        .frame(width: width, height: height)
        .onChange(of: digit) { _, new in
            guard new != shown else { return }
            outgoing = shown
            shown = new
            if !reduceMotion { flips &+= 1 }
        }
    }

    /// 整张卡片画好，只露出上半或下半。卡片是不透明的深色，
    /// 叠在一起翻的时候后面的数字不会透出来。
    private func half(_ text: String, top: Bool) -> some View {
        face(text)
            .frame(width: width, height: height / 2, alignment: top ? .top : .bottom)
            .clipped()
    }

    private func face(_ text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(Color(white: 0.17))
            // 上下半张各有一点不同的亮度，中缝就算没有缝隙也看得出来。
            LinearGradient(colors: [Color.white.opacity(0.06), Color.black.opacity(0.08)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
            Text(text)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(white: 0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: width, height: height)
    }
}
