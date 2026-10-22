import AppKit
import SwiftUI

// 世界时钟改版共用的小零件：联系状态的圆点和胶囊、扩展栏卡片的天空格子。
// 颜色、分段和判断都在 Core（`WorldClockSky`、`WorldClockContact`），这里只负责画。

extension Color {
    init(sky rgb: WorldClockSky.RGB) {
        self.init(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }
}

extension NSColor {
    convenience init(sky rgb: WorldClockSky.RGB) {
        self.init(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }
}

extension WorldClockContact.Level {
    var dotColor: Color { Color(sky: dot) }

    /// 胶囊里的字，跟着面板外观。
    var capsuleInk: Color { Color.panelDynamic(dark: NSColor(sky: inkDark), light: NSColor(sky: inkLight)) }
}

/// 名字旁的红黄绿小圆点，外面一圈细白边，深浅底上都看得见。
struct ContactDot: View {
    var level: WorldClockContact.Level
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(level.dotColor)
            .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: size >= 8 ? 1.2 : 1) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 面板上的“● 对方在睡觉”胶囊：圆点色 18% 打底，字用同色深一档（深色外观浅一档）。
struct ContactCapsule: View {
    var reason: WorldClockContact.Reason

    var body: some View {
        let level = reason.level
        HStack(spacing: 5) {
            Circle().fill(level.dotColor).frame(width: 7, height: 7)
            Text(verbatim: reason.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(level.capsuleInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(level.dotColor.opacity(WorldClockContact.Level.capsuleOpacity)))
    }
}

/// 扩展栏卡片的一个城市格：当地此刻的天空渐变做底（夜里加几颗星），右下角
/// 一枚小地标线稿，名字旁是联系状态圆点。字按底色用白或深灰（`WorldClockSky.ink`），
/// 对比度不低于 4.5。
struct WorldClockSkyCell: View {
    enum Arrangement {
        /// 名字在上、时间在下，居中：横排三列、竖排每行一个。
        case stacked
        /// 名字在左、时间在右：横排两个城市时上下两行。
        case row
    }

    var city: WorldCity
    var now: Date
    var shape: Arrangement
    var timeSize: CGFloat
    /// 此处本身不画圆点。
    var showsDot: Bool
    var dayBadge: String?

    var body: some View {
        let phase = WorldClockSky.phase(city, now: now)
        let ink = Color(sky: WorldClockSky.ink(phase))
        ZStack {
            LinearGradient(colors: WorldClockSky.colors(phase).map { Color(sky: $0) },
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if phase.hasStars { stars }
            landmark(ink)
            switch shape {
            case .stacked: stacked(ink)
            case .row: row(ink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var level: WorldClockContact.Level {
        WorldClockContact.reason(there: city.timeZone ?? .current, now: now).level
    }

    private var time: String {
        ClockFormat.compactTime(now, zone: city.timeZone ?? .current).time
    }

    private func stacked(_ ink: Color) -> some View {
        VStack(spacing: 0) {
            name(ink)
            Text(verbatim: time)
                .font(.system(size: timeSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private func row(_ ink: Color) -> some View {
        HStack(spacing: 6) {
            name(ink)
            Spacer(minLength: 2)
            Text(verbatim: time)
                .font(.system(size: timeSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // 右边留出地标的位置，时间不压在线稿上。
        .padding(.leading, 10)
        .padding(.trailing, 26)
    }

    /// 名字、不是同一天时的 “+1”、联系状态圆点。字号不小于 13，太长时才缩。
    private func name(_ ink: Color) -> some View {
        HStack(alignment: .center, spacing: 3) {
            Text(verbatim: city.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
            if let dayBadge {
                Text(verbatim: dayBadge)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ink)
                    .monospacedDigit()
            }
            if showsDot { ContactDot(level: level, size: 7) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// 右下角的地标线稿，淡淡一层，不抢字。
    private func landmark(_ ink: Color) -> some View {
        let side: CGFloat = shape == .row ? 22 : 24
        return CityLandmarkMark(landmark: city.landmark, color: ink.opacity(0.42), lineWidth: 0.8)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 3)
            .padding(.bottom, 1)
    }

    private var stars: some View {
        GeometryReader { geo in
            ForEach(Array(Self.starSpots.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: star.2, height: star.2)
                    .position(x: geo.size.width * star.0, y: geo.size.height * star.1)
            }
        }
        .accessibilityHidden(true)
    }

    private static let starSpots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.16, 1.4), (0.86, 0.12, 1.1), (0.22, 0.82, 1.2), (0.62, 0.9, 1.0), (0.08, 0.55, 0.9),
    ]

    private var accessibilityText: String {
        var parts = [city.name, ClockFormat.time(now, zone: city.timeZone ?? .current)]
        if showsDot {
            parts.append(WorldClockContact.reason(there: city.timeZone ?? .current, now: now).text)
        }
        return parts.joined(separator: ", ")
    }
}
