import SwiftUI

/// 全部完成时的庆祝：小熊猫举手跳出来，身边撒一圈小星点，两秒后自己消失。
///
/// Shown by the to-do tile and panel the moment the last open task is
/// checked. The curves are `CheerMotion`'s. With Reduce Motion on, the panda
/// only fades in and out, with no pop, hops or sparks.
struct TodoCheer: View {
    var startedAt: Date
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 减少动态效果：不弹、不跳、不撒星点，只按同一条曲线淡入淡出，帧率也降下来。
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 20 : 1.0 / 60)) { timeline in
            content(t: timeline.date.timeIntervalSince(startedAt))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pandaSize: CGFloat { compact ? 34 : 92 }

    private func content(t: Double) -> some View {
        ZStack {
            if !reduceMotion {
                Canvas { canvas, size in drawSparks(in: &canvas, size: size, t: t) }
            }
            VStack(spacing: 4) {
                panda
                    .frame(width: pandaSize, height: pandaSize)
                    .scaleEffect(reduceMotion ? 1 : CheerMotion.pandaScale(t), anchor: .bottom)
                    .offset(y: reduceMotion ? 0 : -CheerMotion.hop(t) * pandaSize * 0.16)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                if !compact {
                    Text("全部完成，歇会儿吧")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: ShelfColor.redPanda.hex).opacity(0.85)))
                        .scaleEffect(reduceMotion ? 1 : min(1, CheerMotion.pandaScale(t - 0.15)))
                }
            }
        }
        .opacity(CheerMotion.opacity(t))
    }

    @ViewBuilder
    private var panda: some View {
        if let art = PetArt.image(.redPanda, .cheer) {
            Image(nsImage: art)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "party.popper.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: ShelfColor.redPanda.hex))
        }
    }

    private func drawSparks(in canvas: inout GraphicsContext, size: CGSize, t: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.5
        let dot = compact ? 2.0 : 3.6
        let warm = Color(hex: ShelfColor.redPanda.hex)
        let gold = Color(hex: PaletteColor.yellow.hex)
        for index in 0..<CheerMotion.sparks {
            let spark = CheerMotion.spark(index: index, t: t)
            guard spark.opacity > 0.02 else { continue }
            var layer = canvas
            layer.opacity = spark.opacity
            let point = CGPoint(x: center.x + spark.x * radius, y: center.y + spark.y * radius)
            let r = dot * spark.size
            let color = index % 3 == 0 ? Color.white : (index % 3 == 1 ? warm : gold)
            if index.isMultiple(of: 2) {
                layer.fill(star(at: point, radius: r * 1.6), with: .color(color))
            } else {
                layer.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                           with: .color(color))
            }
        }
    }

    /// A four-pointed twinkle.
    private func star(at point: CGPoint, radius: Double) -> Path {
        var path = Path()
        let inner = radius * 0.35
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4 - .pi / 2
            let r = step.isMultiple(of: 2) ? radius : inner
            let p = CGPoint(x: point.x + cos(angle) * r, y: point.y + sin(angle) * r)
            if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// 往左拖一行就删除：拖的时候后面露出红底和垃圾桶，拖过一半左右或甩一下就删，
/// 不够就弹回去。触控板和鼠标都是按住拖。
struct SwipeToDelete: ViewModifier {
    var enabled: Bool
    var onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 1
    @State private var tracking = false
    /// 减少动态效果时删除不滑出去，改成原地淡掉。
    @State private var fade: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let progress = SwipeDelete.progress(offset: offset, width: width)
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: PaletteColor.red.hex).opacity(0.35 + 0.6 * progress))
                    .overlay(alignment: .trailing) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .scaleEffect(reduceMotion ? 1 : (progress >= 1 ? 1.2 : 0.9))
                            .opacity(reduceMotion ? 0.6 + 0.4 * progress : 1)
                            .animation(reduceMotion ? nil : .snappy(duration: 0.15), value: progress >= 1)
                            .padding(.trailing, 12)
                    }
                    .opacity(offset < 0 ? 1 : 0)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
            .opacity(fade)
            .gesture(drag, including: enabled ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // A mostly vertical drag is not a swipe; leave it alone.
                if !tracking, abs(value.translation.height) > abs(value.translation.width) { return }
                tracking = true
                offset = SwipeDelete.offset(for: value.translation.width)
            }
            .onEnded { value in
                guard tracking else { return }
                tracking = false
                if SwipeDelete.shouldDelete(offset: offset, predicted: value.predictedEndTranslation.width, width: width) {
                    if reduceMotion {
                        withAnimation(.easeOut(duration: 0.15), completionCriteria: .logicallyComplete) {
                            fade = 0
                        } completion: {
                            onDelete()
                        }
                    } else {
                        withAnimation(.easeIn(duration: 0.16), completionCriteria: .logicallyComplete) {
                            offset = -width - 24
                        } completion: {
                            onDelete()
                        }
                    }
                } else {
                    // 不够远：弹回去；减少动态效果时不回弹，平平地退回原位。
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.32, bounce: 0.35)) {
                        offset = 0
                    }
                }
            }
    }
}

extension View {
    func swipeToDelete(enabled: Bool, perform: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(enabled: enabled, onDelete: perform))
    }
}

/// 删除或完成后在清单下面停几秒的一条：说最近一步做了什么，点“撤销”放回原处；
/// 还有更早的几步时按钮上带着数字，可以一步步接着撤销。
struct TodoUndoBar: View {
    var step: TodoUndoStep
    /// 这一步之外还能再撤销几步。
    var more: Int
    var undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: step.kind == .deleted ? "trash" : "checkmark.circle")
                .font(WidgetStyle.note)
                .foregroundStyle(.white.opacity(0.7))
            Text(step.caption)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(more > 0 ? tr("撤销（还有 \(more) 步）") : tr("撤销"), action: undo)
                .buttonStyle(.plain)
                .font(WidgetStyle.label(12))
                .foregroundStyle(Color(hex: PaletteColor.orange.hex))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassPane(cornerRadius: WidgetStyle.innerCorner)
    }
}

/// 废纸篓被清空时：几张纸从上面落下，转着缩小掉进桶口，桶每吞一张就鼓一下。
///
/// Wraps the bin glyph. Without a moment to play, or with Reduce Motion on,
/// it is just the bin.
struct SwallowingBin<Bin: View>: View {
    var startedAt: Date?
    /// The bin glyph's size, which the sheets are drawn against.
    var binSize: CGFloat
    @ViewBuilder var bin: Bin

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let startedAt, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                let t = timeline.date.timeIntervalSince(startedAt)
                let squash = SwallowMotion.binScale(t)
                ZStack {
                    bin.scaleEffect(x: squash.x, y: squash.y, anchor: .bottom)
                    Canvas { canvas, size in drawSheets(in: &canvas, size: size, t: t) }
                        .frame(width: binSize * 2.2, height: binSize * 2.6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        } else {
            bin
        }
    }

    private func drawSheets(in canvas: inout GraphicsContext, size: CGSize, t: Double) {
        // The mouth sits a little above the middle, where the glyph's lid is.
        let mouth = CGPoint(x: size.width / 2, y: size.height / 2 - binSize * 0.3)
        let drop = binSize * 0.95
        let w = binSize * 0.4
        let h = w * 1.25
        for index in 0..<SwallowMotion.sheets {
            let sheet = SwallowMotion.sheet(index: index, t: t)
            guard sheet.opacity > 0.02 else { continue }
            var paper = canvas
            paper.opacity = sheet.opacity
            paper.translateBy(x: mouth.x + sheet.x * binSize * 0.5, y: mouth.y + sheet.y * drop)
            paper.rotate(by: .radians(sheet.rotation))
            paper.scaleBy(x: sheet.scale, y: sheet.scale)
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            paper.fill(Path(roundedRect: rect, cornerRadius: w * 0.1), with: .color(.white))
            paper.stroke(Path(roundedRect: rect, cornerRadius: w * 0.1), with: .color(.black.opacity(0.15)), lineWidth: 0.6)
            for line in 0..<3 {
                let y = rect.minY + h * (0.3 + 0.2 * Double(line))
                let length = w * (line == 2 ? 0.38 : 0.62)
                paper.fill(Path(CGRect(x: rect.minX + w * 0.19, y: y, width: length, height: max(0.8, h * 0.05))),
                           with: .color(.black.opacity(0.2)))
            }
        }
    }
}
