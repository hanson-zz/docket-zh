import SwiftUI

/// Presentational for now - the drop target lands with file handling.
struct AirDropTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // A column is narrower, not different: same glyph over the same
        // caption, just sized for 56pt of usable width.
        let column = context.position.isVertical
        return WidgetSurface {
            // 高度够就上下叠（图标在上、字在下）；货架矮或小组件库的缩略图
            // 只有一点高时改成左右排，图标不再顶出卡片上沿。
            ViewThatFits(in: .vertical) {
                VStack(spacing: 5) {
                    badge(size: column ? 32 : 34)
                    caption(size: column ? 12 : 13)
                }
                HStack(spacing: 8) {
                    badge(size: 26)
                    caption(size: 13)
                }
                caption(size: 12)
            }
        }
    }

    private func badge(size: CGFloat) -> some View {
        // 和货架其他卡片一样的中性玻璃底，不用苹果的蓝色应用图标。
        TileBadge(size: size) {
            AirDropGlyph()
                .stroke(WidgetStyle.primary, style: StrokeStyle(lineWidth: max(1.4, size * 0.05), lineCap: .round))
                .frame(width: size * 0.56, height: size * 0.56)
                .overlay(alignment: .center) {
                    Circle()
                        .fill(WidgetStyle.primary)
                        .frame(width: size * 0.1, height: size * 0.1)
                        .offset(y: size * 0.56 * 0.08)
                }
        }
    }

    private func caption(size: CGFloat) -> some View {
        Text("隔空投送")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(WidgetStyle.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 隔空投送的样子：一个点外面三圈同心圆弧，底下留个缺口。SF Symbols 里
/// 没有这个图形，原来借的 Wi-Fi 式扇形波纹看起来像无线网，这里自己画。
struct AirDropGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.08)
        let outer = min(rect.width, rect.height) / 2
        // 底部留 80 度的缺口（SwiftUI 角度从 3 点钟方向起、顺时针为正）。
        let start = Angle.degrees(130)
        let end = Angle.degrees(50)
        for ratio in [0.36, 0.68, 1.0] {
            // 先挪到这一圈的起点，不然三段弧会被直线连起来。
            let r = outer * ratio
            path.move(to: CGPoint(x: center.x + r * cos(start.radians), y: center.y + r * sin(start.radians)))
            path.addArc(center: center, radius: outer * ratio, startAngle: start, endAngle: end, clockwise: false)
        }
        return path
    }
}
