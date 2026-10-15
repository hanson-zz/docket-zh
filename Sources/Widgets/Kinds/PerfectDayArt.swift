import SwiftUI

/// 小熊猫的竹篮的图形，全部用 SwiftUI 画出来，不带任何图片素材：
/// 竹叶（金银铜三色，没得到时是虚线轮廓）、编织竹篮、三项的小进度环、
/// 码头木牌样式的徽章、月度频率条、日历和点缀用的竹子。

// MARK: - Leaf

/// A bamboo leaf: a long pointed blade with a midrib and a short stalk,
/// leaning to the right, gold, silver or bronze. Nil draws a dashed outline
/// of one, for a day without a leaf.
struct LeafGlyph: View {
    var tier: PerfectDayTier?
    var size: CGFloat
    /// The outline's colour for a day without a leaf.
    var emptyInk: Color = .gray

    var body: some View {
        let tier = tier
        let emptyInk = emptyInk
        return Canvas { context, canvas in
            Self.draw(in: &context, size: canvas, tier: tier, emptyInk: emptyInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The blade, its midrib and its stalk inside `rect`, tilted about 36 degrees.
    nonisolated static func paths(in rect: CGRect) -> (blade: Path, rib: Path, stalk: Path) {
        let s = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }

        var blade = Path()
        blade.move(to: p(0.5, 0.84))
        blade.addCurve(to: p(0.5, 0.05), control1: p(0.2, 0.7), control2: p(0.33, 0.24))
        blade.addCurve(to: p(0.5, 0.84), control1: p(0.67, 0.24), control2: p(0.8, 0.7))
        blade.closeSubpath()

        var rib = Path()
        rib.move(to: p(0.5, 0.82))
        rib.addQuadCurve(to: p(0.5, 0.13), control: p(0.53, 0.48))

        var stalk = Path()
        stalk.move(to: p(0.5, 0.83))
        stalk.addQuadCurve(to: p(0.45, 0.97), control: p(0.5, 0.92))

        let turn = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: .pi / 5)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        return (blade.applying(turn), rib.applying(turn), stalk.applying(turn))
    }

    nonisolated static func draw(in context: inout GraphicsContext, size canvas: CGSize,
                                 tier: PerfectDayTier?, emptyInk: Color) {
        let rect = CGRect(origin: .zero, size: canvas)
        let side = min(canvas.width, canvas.height)
        let (blade, rib, stalk) = paths(in: rect)
        let line = max(0.8, side * 0.05)

        guard let tier else {
            context.stroke(blade, with: .color(emptyInk.opacity(0.55)),
                           style: StrokeStyle(lineWidth: line, lineJoin: .round, dash: [max(1.5, side * 0.09), max(1, side * 0.06)]))
            context.stroke(stalk, with: .color(emptyInk.opacity(0.4)),
                           style: StrokeStyle(lineWidth: line, lineCap: .round))
            return
        }

        let light = Color(hex: tier.hexes.light)
        let deep = Color(hex: tier.hexes.deep)
        context.stroke(stalk, with: .color(deep), style: StrokeStyle(lineWidth: line * 1.3, lineCap: .round))
        context.fill(blade, with: .linearGradient(Gradient(colors: [light, deep]),
                                                  startPoint: CGPoint(x: rect.minX + side * 0.25, y: rect.minY + side * 0.15),
                                                  endPoint: CGPoint(x: rect.maxX - side * 0.2, y: rect.maxY - side * 0.1)))
        context.stroke(blade, with: .color(deep.opacity(0.9)), lineWidth: max(0.5, side * 0.03))
        guard side >= 12 else { return }
        context.stroke(rib, with: .color(deep.opacity(0.75)),
                       style: StrokeStyle(lineWidth: max(0.6, side * 0.035), lineCap: .round))
        // A soft shine along one half of the blade, so it reads as waxy.
        var shine = Path()
        let half = paths(in: rect.insetBy(dx: side * 0.12, dy: side * 0.12)).rib
        shine.addPath(half, transform: CGAffineTransform(translationX: -side * 0.07, y: -side * 0.02))
        context.stroke(shine, with: .color(.white.opacity(0.35)),
                       style: StrokeStyle(lineWidth: max(0.6, side * 0.04), lineCap: .round))
    }
}

// MARK: - Basket

/// A woven bamboo basket with a handle, the month's leaves heaped inside it
/// from the bottom in the order they were earned, seen through the gaps of
/// the weave.
struct BambooBasket: View {
    var leaves: [PerfectDayTier]
    var width: CGFloat = 170
    var emptyText = "这个月的竹篮还空着"

    private var height: CGFloat { width * 1.05 }
    private var rimY: CGFloat { height * 0.34 }
    private var bottomY: CGFloat { height * 0.95 }

    private var cane: (light: Color, deep: Color) {
        (Color(hex: PerfectDay.basketHexes.light), Color(hex: PerfectDay.basketHexes.deep))
    }

    var body: some View {
        let shape = BasketBody(rimY: rimY / height, bottomY: bottomY / height)
        ZStack(alignment: .topLeading) {
            handle

            // The inside of the basket, dark, so leaves stand out.
            shape
                .fill(LinearGradient(colors: [Color(hex: "#3B2A1A").opacity(0.85), Color(hex: "#24190F").opacity(0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: height)

            // The leaves, clipped to the basket.
            ZStack(alignment: .topLeading) {
                ForEach(Array(placements.enumerated()), id: \.offset) { _, place in
                    LeafGlyph(tier: place.tier, size: place.size)
                        .rotationEffect(.degrees(place.tilt))
                        .position(place.center)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(shape)

            // The weave over them: horizontal canes with gaps, ribs that
            // narrow toward the base.
            weave
                .frame(width: width, height: height)
                .clipShape(shape)
                .allowsHitTesting(false)

            shape
                .stroke(cane.deep, lineWidth: max(1.2, width * 0.012))
                .frame(width: width, height: height)

            // The rim, a thick bound cane across the top.
            Capsule()
                .fill(LinearGradient(colors: [cane.light, cane.deep], startPoint: .top, endPoint: .bottom))
                .overlay {
                    HStack(spacing: width * 0.05) {
                        ForEach(0..<9, id: \.self) { _ in
                            Capsule().fill(.black.opacity(0.15)).frame(width: 1.2)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(width: width * 0.94, height: width * 0.07)
                .offset(x: width * 0.03, y: rimY - width * 0.035)

            if leaves.isEmpty {
                Text(emptyText)
                    .font(.system(size: max(10, width * 0.068)))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(width: width * 0.6)
                    .position(x: width / 2, y: (rimY + bottomY) / 2)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(leaves.isEmpty ? emptyText : "竹篮里有 \(leaves.count) 片竹叶")
    }

    private var handle: some View {
        let top = height * 0.03
        let control = 2 * top - rimY
        return Path { path in
            path.move(to: CGPoint(x: width * 0.17, y: rimY))
            path.addQuadCurve(to: CGPoint(x: width * 0.83, y: rimY), control: CGPoint(x: width / 2, y: control))
        }
        .stroke(LinearGradient(colors: [cane.light, cane.deep], startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: width * 0.05, lineCap: .round))
        .overlay {
            Path { path in
                path.move(to: CGPoint(x: width * 0.17, y: rimY))
                path.addQuadCurve(to: CGPoint(x: width * 0.83, y: rimY), control: CGPoint(x: width / 2, y: control))
            }
            .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: width * 0.012, lineCap: .round, dash: [width * 0.04, width * 0.03]))
        }
        .frame(width: width, height: height)
    }

    private var weave: some View {
        let w = width
        let rim = rimY
        let bottom = bottomY
        let light = cane.light
        let deep = cane.deep
        return Canvas { context, _ in
            let bandHeight = w * 0.045
            var y = rim + w * 0.06
            var row = 0
            while y < bottom {
                let band = Path(roundedRect: CGRect(x: 0, y: y, width: w, height: bandHeight),
                                cornerRadius: bandHeight / 2)
                context.fill(band, with: .linearGradient(Gradient(colors: [light, deep]),
                                                         startPoint: CGPoint(x: 0, y: y),
                                                         endPoint: CGPoint(x: 0, y: y + bandHeight)))
                // Little ticks where the canes cross the ribs, offset each row.
                var x = (row % 2 == 0 ? w * 0.04 : w * 0.1)
                while x < w {
                    let tick = Path(CGRect(x: x, y: y, width: 1, height: bandHeight))
                    context.fill(tick, with: .color(.black.opacity(0.2)))
                    x += w * 0.12
                }
                y += bandHeight + w * 0.07
                row += 1
            }
            // Ribs from the rim down toward the base, converging.
            for index in 0...8 {
                let t = CGFloat(index) / 8
                let topX = w * (0.06 + 0.88 * t)
                let bottomX = w * (0.17 + 0.66 * t)
                var rib = Path()
                rib.move(to: CGPoint(x: topX, y: rim))
                rib.addLine(to: CGPoint(x: bottomX, y: bottom))
                context.stroke(rib, with: .color(deep.opacity(0.8)), lineWidth: max(1, w * 0.012))
            }
        }
    }

    private struct Placement {
        var tier: PerfectDayTier
        var center: CGPoint
        var size: CGFloat
        var tilt: Double
    }

    /// Half the basket's width at height `y`: wide at the rim, narrower at the base.
    private func halfWidth(at y: CGFloat) -> CGFloat {
        let t = min(1, max(0, (y - rimY) / (bottomY - rimY)))
        return width * (0.44 - 0.11 * t)
    }

    /// Rows from the bottom up, each as wide as the basket is at that
    /// height, the leaves shrinking until the whole month fits.
    private var placements: [Placement] {
        guard !leaves.isEmpty else { return [] }
        func rows(_ size: CGFloat) -> [(y: CGFloat, count: Int)] {
            var result: [(y: CGFloat, count: Int)] = []
            var y = bottomY - size * 0.55
            while y - size * 0.35 >= rimY + width * 0.02 {
                let count = max(1, Int((halfWidth(at: y) * 2 - width * 0.06) / (size * 0.8)))
                result.append((y: y, count: count))
                y -= size * 0.62
            }
            return result
        }
        var size = width * 0.24
        while rows(size).reduce(0, { $0 + $1.count }) < leaves.count, size > width * 0.07 {
            size *= 0.92
        }
        var result: [Placement] = []
        var index = 0
        for (row, line) in rows(size).enumerated() where index < leaves.count {
            let slot = size * 0.8
            let span = CGFloat(line.count) * slot
            let start = width / 2 - span / 2 + slot / 2 + (row % 2 == 1 ? slot * 0.25 : 0)
            for column in 0..<line.count where index < leaves.count {
                // A tilt from the position, so the heap looks tipped in by
                // hand and stays the same every time it is drawn.
                let tilt = Double((index * 53 + row * 17) % 70) - 35
                result.append(Placement(tier: leaves[index],
                                        center: CGPoint(x: start + CGFloat(column) * slot, y: line.y),
                                        size: size, tilt: tilt))
                index += 1
            }
        }
        return result
    }
}

/// The basket's outline: straight sides tapering from the rim to a rounded base.
struct BasketBody: Shape {
    /// The rim and the base as fractions of the height.
    var rimY: CGFloat
    var bottomY: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.06, y: rect.minY + h * rimY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: rect.minY + h * rimY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.84, y: rect.minY + h * (bottomY - 0.04)))
        path.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.16, y: rect.minY + h * (bottomY - 0.04)),
                          control: CGPoint(x: rect.midX, y: rect.minY + h * (bottomY + 0.04)))
        path.closeSubpath()
        return path
    }
}

// MARK: - Bamboo

/// A few bamboo stalks with their nodes and a leaf or two, as decoration.
struct BambooStalks: View {
    var height: CGFloat = 160
    var color: Color = Color(hex: PerfectDay.bambooHex)

    var body: some View {
        HStack(alignment: .bottom, spacing: height * 0.05) {
            stalk(height * 0.9, width: height * 0.07)
            stalk(height, width: height * 0.08)
            stalk(height * 0.72, width: height * 0.06)
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func stalk(_ length: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: width * 0.25) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: width * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.9), color.opacity(0.55)],
                                         startPoint: .leading, endPoint: .trailing))
            }
        }
        .frame(width: width, height: length)
    }
}

// MARK: - Item ring

/// One of the three items as a little ring: its colour filling toward the
/// goal, its symbol inside, solid once met, dashed and grey when it does not
/// take part.
struct PerfectItemRing: View {
    var progress: PerfectDayProgress
    var size: CGFloat
    var track: Color = WidgetStyle.primary

    var body: some View {
        let tint = Color(hex: progress.item.hex)
        let line = max(1.6, size * 0.13)
        ZStack {
            switch progress.mark {
            case .off:
                Circle()
                    .stroke(track.opacity(0.3), style: StrokeStyle(lineWidth: line * 0.7, dash: [2, 2]))
            case .met:
                Circle().fill(tint)
                Image(systemName: progress.item.symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            case .missed:
                Circle().stroke(tint.opacity(0.22), lineWidth: line)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress.fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: progress.item.symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(progress.item.title)，\(progress.mark == .met ? "已达标" : progress.detail)")
    }
}

// MARK: - Badge

/// A luggage tag's outline: the top corners cut off, the bottom ones rounded.
struct HarborTagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = rect.width * 0.3
        let round = rect.width * 0.14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - round))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - round, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + round, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - round), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}

/// A badge as a wooden dock tag on a string: a gradient tag with a hole at
/// the top and an SF Symbol, greyed with a small lock while it is still to
/// earn. A hidden badge not yet found shows only a question mark.
struct PerfectBadgeMedal: View {
    var status: PerfectBadgeStatus
    var size: CGFloat = 56

    var body: some View {
        let badge = status.badge
        let light = Color(hex: badge.hexes.light)
        let deep = Color(hex: badge.hexes.deep)
        let tagWidth = size * 0.68
        let tagHeight = size * 0.78
        let tagTop = size * 0.2
        ZStack(alignment: .top) {
            // The string, looped over a peg above the tag.
            Path { path in
                path.move(to: CGPoint(x: size / 2 - size * 0.08, y: tagTop + size * 0.1))
                path.addLine(to: CGPoint(x: size / 2, y: size * 0.02))
                path.addLine(to: CGPoint(x: size / 2 + size * 0.08, y: tagTop + size * 0.1))
            }
            .stroke(Color(hex: "#C9B08A").opacity(status.isLit ? 0.9 : 0.4),
                    style: StrokeStyle(lineWidth: max(1, size * 0.025), lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)

            ZStack {
                HarborTagShape()
                    .fill(LinearGradient(colors: status.isLit ? [light, deep]
                                            : [Color(white: 0.42), Color(white: 0.26)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                HarborTagShape()
                    .stroke(.white.opacity(status.isLit ? 0.45 : 0.15), lineWidth: 1)
                    .padding(size * 0.04)
                // The eyelet.
                Circle()
                    .frame(width: size * 0.09, height: size * 0.09)
                    .offset(y: -tagHeight * 0.36)
                    .blendMode(.destinationOut)
                Image(systemName: status.isConcealed ? "questionmark" : badge.symbol)
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(.white.opacity(status.isLit ? 1 : 0.45))
                    .shadow(color: .black.opacity(status.isLit ? 0.25 : 0), radius: 1.5, y: 1)
                    .offset(y: tagHeight * 0.08)
            }
            .compositingGroup()
            .frame(width: tagWidth, height: tagHeight)
            .offset(y: tagTop)

            if status.phase == .missed {
                Text(PerfectBadges.missedText)
                    .font(.system(size: max(7, size * 0.13), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, size * 0.06)
                    .padding(.vertical, size * 0.015)
                    .background(Capsule().fill(Color(hex: "#24222C")))
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                    .offset(y: size * 0.84)
            } else if !status.isLit, !status.isConcealed {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(size * 0.05)
                    .background(Circle().fill(Color(hex: "#24222C")))
                    .offset(x: size * 0.28, y: size * 0.8)
            }
        }
        .frame(width: size, height: size + size * 0.02, alignment: .top)
    }
}

// MARK: - Frequency strip

/// A cell a day across the month, coloured by the leaf it got.
struct PerfectFrequencyStrip: View {
    var days: [PerfectDayCell]
    var height: CGFloat = 22

    var body: some View {
        HStack(spacing: 2) {
            ForEach(days, id: \.key) { day in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(fill(day))
                    .overlay {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                        }
                    }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("月度竹叶频率，\(days.filter { $0.tier != nil }.count) 天收到竹叶")
    }

    private func fill(_ day: PerfectDayCell) -> AnyShapeStyle {
        if let tier = day.tier {
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: tier.hexes.light), Color(hex: tier.hexes.deep)],
                                                startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Color.white.opacity(day.isFuture ? 0.05 : 0.13))
    }
}

// MARK: - Calendar

/// The month as a calendar, a leaf or an empty outline under each date,
/// starting the week where the Mac's settings start it.
struct PerfectCalendarGrid: View {
    var weeks: [[PerfectDayCell?]]
    var weekdays: [String]
    var leafSize: CGFloat = 22

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        cell(week.indices.contains(index) ? week[index] : nil)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ day: PerfectDayCell?) -> some View {
        if let day {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.white : .white.opacity(day.isFuture ? 0.3 : 0.75))
                    .padding(.horizontal, 5)
                    .background {
                        if day.isToday { Capsule().fill(Color(hex: PerfectDay.bambooHex)) }
                    }
                LeafGlyph(tier: day.tier, size: leafSize, emptyInk: .white)
                    .opacity(day.isFuture ? 0.35 : 1)
            }
            .accessibilityElement()
            .accessibilityLabel("\(day.day) 日，\(day.tier.map { "\($0.title)，\($0.leafName)" } ?? "没有竹叶")")
        } else {
            Color.clear.frame(height: leafSize + 16)
        }
    }
}
