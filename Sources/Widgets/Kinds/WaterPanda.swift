import AppKit
import SwiftUI

/// The chosen character filling up with water.
///
/// The default is the author's own red panda, the one on the app icon, cut
/// out along its outline (Resources/Water/WaterPanda.png); the shiba, the
/// ginger cat, the penguin, the otter and the octopus each have four
/// pictures, one per `WaterMood`. The part above the water is drawn faded and
/// grey, thirsty; below the surface it is in full colour with a faint blue
/// over it, so the level reads as water rising inside the character rather
/// than a bar beside it. The water is masked by the picture's own alpha, so
/// it never spills outside the silhouette.
///
/// `phase` moves the surface. The tile passes a constant, so a shelf that sits
/// there all day does not redraw every frame; the panel passes its clock.
struct WaterPanda: View {
    var character: WaterCharacter = .redPanda
    var mood: WaterMood = .idle
    /// 0...1 toward today's goal.
    var level: Double
    var phase: Double = 0.3
    var celebrating: Bool = false
    var height: CGFloat
    /// 渴成骷髅（见 `WaterParched`）：换成骷髅图，水照样从底下涨。
    var parched: Bool = false
    /// 减少动态效果：涨水、换表情、骷髅都直接跳过去，不做过渡。
    var reduceMotion: Bool = false

    private var picture: NSImage? {
        if parched, let skeleton = WaterArt.skeleton(character) { return skeleton }
        return WaterArt.image(character, mood)
    }

    var body: some View {
        let width = height * CGFloat(character.aspect)
        ZStack {
            if let image = picture {
                art(image)
                    .saturation(0.15)
                    .opacity(0.5)
                art(image)
                    .mask { WaterWave(level: level, phase: phase, amplitude: amplitude).fill(.black) }
                WaterWave(level: level, phase: phase, amplitude: amplitude)
                    .fill(LinearGradient(colors: [WaterStyle.water.opacity(0.14), WaterStyle.water.opacity(0.3)],
                                         startPoint: .top, endPoint: .bottom))
                    .mask { art(image) }
                WaterWave(level: level, phase: phase, amplitude: amplitude, closed: false)
                    .stroke(WaterStyle.surface.opacity(level > 0.005 && level < 0.995 ? 0.85 : 0),
                            style: StrokeStyle(lineWidth: max(1, height / 45), lineCap: .round))
                    .mask { art(image) }
            } else {
                fallback
            }
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: level)
        // A new mood swaps the picture with a short cross-fade.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mood)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: parched)
        .overlay(alignment: .topTrailing) {
            // The other characters' cheer picture has its own confetti.
            if celebrating, !parched, !character.hasMoods {
                Image(systemName: "sparkles")
                    .font(.system(size: max(8, height * 0.26), weight: .semibold))
                    .foregroundStyle(Color(hex: PaletteColor.yellow.hex))
                    .offset(x: height * 0.06, y: -height * 0.08)
                    .phaseAnimator(reduceMotion ? [false] : [false, true]) { mark, up in
                        mark.scaleEffect(up ? 1.15 : 0.85).opacity(up ? 1 : 0.7)
                    } animation: { _ in .easeInOut(duration: 0.8) }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityHidden(true)
    }

    private var amplitude: CGFloat { max(1, height * 0.035) }

    private func art(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    /// No picture in the bundle (the screenshot tool has none): a drop that
    /// fills the same way, the old drink reminder's treatment.
    private var fallback: some View {
        ZStack {
            Image(systemName: "drop")
                .foregroundStyle(WidgetStyle.secondary)
            Image(systemName: "drop.fill")
                .foregroundStyle(WaterStyle.water.mix(with: WidgetStyle.primary, by: 0.35))
                .mask { WaterWave(level: level, phase: phase, amplitude: 0).fill(.black) }
        }
        .font(.system(size: height * 0.7, weight: .regular))
    }
}

/// The water's body, or with `closed` false just its surface line.
struct WaterWave: Shape {
    var level: Double
    /// Seconds; the surface drifts one swell every three of them.
    var phase: Double
    var amplitude: CGFloat
    var closed: Bool = true

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set {
            level = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(1, max(0, level))
        guard clamped > 0.001 else { return Path() }
        // Full is full: a flat top a little above the picture, so no wave
        // dips into the ears.
        let amp = clamped >= 0.999 ? 0 : amplitude
        let top = clamped >= 0.999 ? rect.minY - 2 : rect.maxY - rect.height * clamped
        let step = max(1, rect.width / 48)
        var path = Path()
        func y(_ x: CGFloat) -> CGFloat {
            let angle = Double((x - rect.minX) / max(rect.width, 1)) * 2 * .pi * 1.2 + phase * 2 * .pi / 3
            return top + amp * CGFloat(sin(angle))
        }
        if closed {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: y(rect.minX)))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: y(rect.minX)))
        }
        var x = rect.minX
        while x < rect.maxX {
            x = min(rect.maxX, x + step)
            path.addLine(to: CGPoint(x: x, y: y(x)))
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

@MainActor
enum WaterArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    /// Loose PNGs in the bundle's Resources, like the radio's; read once.
    static func image(_ character: WaterCharacter, _ mood: WaterMood) -> NSImage? {
        named(character.imageName(mood))
    }

    /// 渴成骷髅的图：小熊猫是趴姿的 WaterPanda-skeleton，其他角色借宠物的骷髅图。
    static func skeleton(_ character: WaterCharacter) -> NSImage? {
        named(WaterParched.imageName(character))
    }

    static func named(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard !missing.contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }
}

enum WaterStyle {
    /// The catalog's accent, the reminders' blue.
    static var water: Color { Color(hex: WidgetCatalog.accentHex(.water) ?? PaletteColor.blue.hex) }
    static let surface = Color(hex: "#C8E8FF")
}
