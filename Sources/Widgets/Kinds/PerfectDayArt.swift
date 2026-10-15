import SwiftUI

/// 完美一天的图形，全部用 SwiftUI 画出来，不带任何图片素材：
/// 小太阳（圆、光芒、表情，金银铜三色，没得到时是灰色轮廓）、玻璃罐、
/// 三项的小进度环和圆形徽章。

// MARK: - Sun

/// A sun: a round face with twelve rays and a smile, gold, silver or
/// bronze. Nil draws the empty outline of one, for a day without a sun.
struct SunGlyph: View {
    var tier: PerfectDayTier?
    var size: CGFloat
    /// Below about 16pt a face is a smudge, so it is left off.
    var face: Bool = true
    /// The outline's colour for a day without a sun.
    var emptyInk: Color = .gray

    var body: some View {
        let tier = tier
        let face = face
        let emptyInk = emptyInk
        return Canvas { context, canvas in
            Self.draw(in: &context, size: canvas, tier: tier, face: face, emptyInk: emptyInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    nonisolated static func draw(in context: inout GraphicsContext, size canvas: CGSize,
                                 tier: PerfectDayTier?, face: Bool, emptyInk: Color) {
        let side = min(canvas.width, canvas.height)
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let outer = side / 2
        let core = outer * 0.62
        let rayWidth = max(1.2, outer * 0.17)
        let rayInner = core * 1.1
        let rayOuter = outer * 0.97

        var rays = Path()
        for index in 0..<12 {
            let angle = Double(index) / 12 * 2 * .pi
            let length = (index % 2 == 0 ? rayOuter : rayOuter * 0.9) - rayInner
            let ray = Path(roundedRect: CGRect(x: -rayWidth / 2, y: rayInner, width: rayWidth, height: length),
                           cornerRadius: rayWidth / 2)
            rays.addPath(ray, transform: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle))
        }
        let disc = Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2))

        guard let tier else {
            let line = max(0.8, outer * 0.07)
            context.stroke(rays, with: .color(emptyInk.opacity(0.45)), lineWidth: line * 0.8)
            context.stroke(disc, with: .color(emptyInk.opacity(0.6)), lineWidth: line)
            return
        }

        let light = Color(hex: tier.hexes.light)
        let deep = Color(hex: tier.hexes.deep)
        context.fill(rays, with: .linearGradient(Gradient(colors: [light, deep]),
                                                 startPoint: CGPoint(x: c.x, y: c.y - outer),
                                                 endPoint: CGPoint(x: c.x, y: c.y + outer)))
        context.fill(disc, with: .radialGradient(Gradient(colors: [light, deep]),
                                                 center: CGPoint(x: c.x - core * 0.3, y: c.y - core * 0.35),
                                                 startRadius: 0, endRadius: core * 1.5))
        // A sheen on the upper left, so it reads as round rather than flat.
        let sheen = Path(ellipseIn: CGRect(x: c.x - core * 0.62, y: c.y - core * 0.78,
                                           width: core * 0.7, height: core * 0.42))
        context.fill(sheen, with: .color(.white.opacity(0.35)))
        context.stroke(disc, with: .color(deep.opacity(0.9)), lineWidth: max(0.6, outer * 0.035))

        guard face, side >= 16 else { return }
        let ink = Color(hex: Self.inkHex(tier))
        let eyeW = core * 0.15
        let eyeH = core * 0.22
        for dx in [-0.34, 0.34] {
            let eye = Path(ellipseIn: CGRect(x: c.x + core * dx - eyeW / 2, y: c.y - core * 0.2 - eyeH / 2,
                                             width: eyeW, height: eyeH))
            context.fill(eye, with: .color(ink))
            let cheek = Path(ellipseIn: CGRect(x: c.x + core * dx * 1.55 - core * 0.13, y: c.y + core * 0.12,
                                               width: core * 0.26, height: core * 0.17))
            context.fill(cheek, with: .color(Color(hex: "#FF6F7D").opacity(0.4)))
        }
        var smile = Path()
        smile.addArc(center: CGPoint(x: c.x, y: c.y + core * 0.02), radius: core * 0.36,
                     startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
        context.stroke(smile, with: .color(ink),
                       style: StrokeStyle(lineWidth: max(0.8, core * 0.1), lineCap: .round))
    }

    nonisolated static func inkHex(_ tier: PerfectDayTier) -> String {
        switch tier {
        case .gold: "#6B3F0C"
        case .silver: "#3F4757"
        case .bronze: "#4E250B"
        }
    }
}

// MARK: - Jar

/// A glass jar with a lid, the month's suns piled up inside it from the
/// bottom, in the order they were earned.
struct SunJar: View {
    var suns: [PerfectDayTier]
    var width: CGFloat = 170
    var emptyText = "这个月还没有收集到小太阳"

    private var height: CGFloat { width * 1.2 }

    var body: some View {
        let glass = bodyRect
        ZStack(alignment: .topLeading) {
            // Lid and neck.
            RoundedRectangle(cornerRadius: width * 0.05, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#F3D27A"), Color(hex: "#B8892B")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    // Ridges on the lid.
                    VStack(spacing: width * 0.022) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(.black.opacity(0.12)).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, width * 0.04)
                }
                .frame(width: width * 0.74, height: height * 0.11)
                .offset(x: width * 0.13, y: 0)
            RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1.2)
                }
                .frame(width: width * 0.66, height: height * 0.07)
                .offset(x: width * 0.17, y: height * 0.105)

            // The glass.
            RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: glass.width, height: glass.height)
                .offset(x: glass.minX, y: glass.minY)

            // The suns, clipped to the glass.
            ZStack(alignment: .topLeading) {
                ForEach(Array(placements.enumerated()), id: \.offset) { _, place in
                    SunGlyph(tier: place.tier, size: place.size)
                        .rotationEffect(.degrees(place.tilt))
                        .position(x: place.center.x - glass.minX, y: place.center.y - glass.minY)
                }
            }
            .frame(width: glass.width, height: glass.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.2, style: .continuous))
            .offset(x: glass.minX, y: glass.minY)

            RoundedRectangle(cornerRadius: width * 0.2, style: .continuous)
                .strokeBorder(.white.opacity(0.38), lineWidth: 1.5)
                .frame(width: glass.width, height: glass.height)
                .offset(x: glass.minX, y: glass.minY)
            // A highlight down the left of the glass.
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: width * 0.05, height: glass.height * 0.55)
                .offset(x: glass.minX + width * 0.07, y: glass.minY + glass.height * 0.12)

            if suns.isEmpty {
                Text(emptyText)
                    .font(.system(size: max(10, width * 0.068)))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(width: glass.width * 0.78)
                    .position(x: glass.midX, y: glass.midY)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(suns.isEmpty ? emptyText : "罐子里有 \(suns.count) 个小太阳")
    }

    private var bodyRect: CGRect {
        CGRect(x: width * 0.04, y: height * 0.16, width: width * 0.92, height: height * 0.84)
    }

    private struct Placement {
        var tier: PerfectDayTier
        var center: CGPoint
        var size: CGFloat
        var tilt: Double
    }

    /// Rows from the bottom, every other row nudged half a sun over and one
    /// shorter, with as many columns as it takes for the month to fit.
    private var placements: [Placement] {
        guard !suns.isEmpty else { return [] }
        let inner = bodyRect.insetBy(dx: width * 0.05, dy: width * 0.05)
        var columns = 4
        var size = inner.width / CGFloat(columns)
        func capacity(_ columns: Int, _ size: CGFloat) -> Int {
            let rows = max(1, Int((inner.height - size) / (size * 0.86)) + 1)
            return (rows + 1) / 2 * columns + rows / 2 * (columns - 1)
        }
        while capacity(columns, size) < suns.count, columns < 10 {
            columns += 1
            size = inner.width / CGFloat(columns)
        }
        var result: [Placement] = []
        var row = 0
        var index = 0
        while index < suns.count {
            let odd = row % 2 == 1
            let count = odd ? columns - 1 : columns
            for column in 0..<count where index < suns.count {
                let x = inner.minX + size / 2 + CGFloat(column) * size + (odd ? size / 2 : 0)
                let y = inner.maxY - size / 2 - CGFloat(row) * size * 0.86
                // A tilt from the position, so the pile looks tipped in by
                // hand and stays the same every time it is drawn.
                let tilt = Double((index * 37 + row * 11) % 30) - 15
                result.append(Placement(tier: suns[index], center: CGPoint(x: x, y: y),
                                        size: size * 0.96, tilt: tilt))
                index += 1
            }
            row += 1
        }
        return result
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

/// A round badge: a dark rim, a gradient disc and an SF Symbol, greyed with
/// a small lock while it is still to earn.
struct PerfectBadgeMedal: View {
    var status: PerfectBadgeStatus
    var size: CGFloat = 56

    var body: some View {
        let badge = status.badge
        let light = Color(hex: badge.hexes.light)
        let deep = Color(hex: badge.hexes.deep)
        ZStack {
            Circle().fill(Color(hex: "#24222C"))
            Circle()
                .fill(LinearGradient(colors: status.unlocked ? [light, deep]
                                        : [Color(white: 0.42), Color(white: 0.26)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(size * 0.07)
            Circle()
                .strokeBorder(.white.opacity(status.unlocked ? 0.45 : 0.15), lineWidth: 1)
                .padding(size * 0.11)
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(status.unlocked ? 1 : 0.45))
                .shadow(color: .black.opacity(status.unlocked ? 0.25 : 0), radius: 1.5, y: 1)
            if !status.unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(size * 0.06)
                    .background(Circle().fill(Color(hex: "#24222C")))
                    .offset(x: size * 0.32, y: size * 0.32)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Frequency strip

/// A cell a day across the month, coloured by the sun it got.
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
        .accessibilityLabel("月度小太阳频率，\(days.filter { $0.tier != nil }.count) 天有太阳")
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

/// The month as a calendar, a sun or an empty outline under each date,
/// starting the week where the Mac's settings start it.
struct PerfectCalendarGrid: View {
    var weeks: [[PerfectDayCell?]]
    var weekdays: [String]
    var sunSize: CGFloat = 22

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
                    .foregroundStyle(day.isToday ? Color.black : .white.opacity(day.isFuture ? 0.3 : 0.75))
                    .padding(.horizontal, 5)
                    .background {
                        if day.isToday { Capsule().fill(Color(hex: PerfectDayTier.gold.hexes.light)) }
                    }
                SunGlyph(tier: day.tier, size: sunSize, emptyInk: .white)
                    .opacity(day.isFuture ? 0.35 : 1)
            }
            .accessibilityElement()
            .accessibilityLabel("\(day.day) 日，\(day.tier?.title ?? "没有太阳")")
        } else {
            Color.clear.frame(height: sunSize + 16)
        }
    }
}
