import AppKit
import SwiftUI

/// 电子宠物：the chosen character (the red panda by default) with how it is
/// doing, a bar for its four needs averaged, and a bowl to feed it.
///
/// Like 喝水, the bowl is the tile's only control and the card's own click
/// opens the panel, where it is played with, put to bed and washed. Feeding
/// from the shelf is the one thing worth not opening anything for.
///
/// The tile is also where treats from elsewhere in 码头 arrive: a glass of
/// water or a habit checked off leaves one in `PetTreats`, and a focus session
/// that ran out is noticed here from the shared timer. Draining them here
/// rather than at the source keeps 喝水 and 习惯打卡 knowing nothing about the
/// pet beyond dropping a note in a box.
struct PetTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var character: WaterCharacter {
        WaterCharacter.shown(instance.config, unlocked: Supporter.isUnlocked || context.isPreview)
    }

    private var state: PetState {
        if context.isPreview { return VirtualPet.sample(now: context.now) }
        return VirtualPet.advanced(VirtualPet.state(instance.config, now: context.now), to: context.now)
    }

    var body: some View {
        let s = state
        let look = VirtualPet.look(s, now: context.now)
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(s, look: look)
                } else {
                    wide(s, look: look)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("电子宠物\(character.title)，\(VirtualPet.statusLine(s, now: context.now))")
        .onAppear { collectTreats() }
        .onChange(of: context.now) { _, _ in collectTreats() }
    }

    private func wide(_ s: PetState, look: PetLook) -> some View {
        HStack(spacing: 10) {
            PetFigure(character: character, look: look, height: 44,
                      effect: VirtualPet.effect(s, now: context.now))
            VStack(alignment: .leading, spacing: 3) {
                Text(character.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                Text(VirtualPet.statusLine(s, now: context.now))
                    .font(.system(size: 11))
                    .foregroundStyle(PetStyle.tint(look: look, health: s.health))
                PetBar(value: s.health, height: 4)
                    .frame(maxWidth: 80)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            feedButton(size: 12)
        }
    }

    private func column(_ s: PetState, look: PetLook) -> some View {
        VStack(spacing: 4) {
            PetFigure(character: character, look: look, height: 40,
                      effect: VirtualPet.effect(s, now: context.now))
            Text(VirtualPet.statusLine(s, now: context.now))
                .font(WidgetStyle.caption(9))
                .foregroundStyle(PetStyle.tint(look: look, health: s.health))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            PetBar(value: s.health, height: 3)
                .padding(.horizontal, 6)
            feedButton(size: 10)
        }
    }

    private func feedButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "fork.knife", size: size, tint: PetStyle.accent, action: context.isPreview ? nil : {
            withAnimation(.snappy(duration: 0.3)) { PetLog.act(.feed, in: instance) }
        })
        .help("喂它吃一顿")
        .accessibilityLabel("喂食")
    }

    private func collectTreats() {
        guard !context.isPreview else { return }
        PetLog.collect(in: instance, now: context.now)
    }
}

/// The character in one of its six looks, cross-faded when the look changes.
struct PetFigure: View {
    var character: WaterCharacter
    var look: PetLook
    var height: CGFloat
    var effect: PetEffect = .none

    var body: some View {
        Group {
            if let image = PetArt.image(character, look) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .id(look)
                    .transition(.opacity)
            } else {
                // No pictures in the bundle (the screenshot tool has none).
                Image(systemName: "pawprint.fill")
                    .font(.system(size: height * 0.55))
                    .foregroundStyle(PetStyle.accent)
            }
        }
        .frame(width: height * 0.95, height: height)
        .overlay { PetEffectLayer(effect: effect, height: height) }
        .animation(.easeInOut(duration: 0.25), value: look)
        .animation(.easeInOut(duration: 0.4), value: effect)
        .accessibilityHidden(true)
    }
}

/// Bubbles rising over the pet after a wash, or a few smudges on it while it
/// is dirty. The bubbles keep their own clock and stop by themselves, since
/// the tile is not redrawn every second.
struct PetEffectLayer: View {
    var effect: PetEffect
    var height: CGFloat

    var body: some View {
        Group {
            switch effect {
            case .none:
                EmptyView()
            case .bubbles(let until):
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let left = until.timeIntervalSince(timeline.date)
                    if left > 0 {
                        Canvas { context, size in
                            Self.drawBubbles(in: &context, size: size,
                                             time: timeline.date.timeIntervalSinceReferenceDate,
                                             fade: min(1, left / 0.6), height: height)
                        }
                    }
                }
                .transition(.opacity)
            case .dirty:
                Canvas { context, size in Self.drawSmudges(in: &context, size: size) }
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated private static func fraction(_ x: Double) -> Double { x - x.rounded(.down) }

    nonisolated static func drawBubbles(in context: inout GraphicsContext, size: CGSize, time: Double,
                            fade: Double, height: CGFloat) {
        for i in 0..<12 {
            let n = Double(i)
            let phase = fraction(time * 0.55 + n * 0.137)
            let x = size.width * (0.12 + 0.76 * fraction(n * 0.618))
                + sin(time * 2.4 + n) * size.width * 0.04
            let y = size.height * (1.05 - phase * 1.1)
            let r = height * (0.035 + 0.035 * fraction(n * 0.37))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let alpha = fade * (phase < 0.15 ? phase / 0.15 : 1 - (phase - 0.15) / 0.85)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(.white.opacity(0.22 * alpha)))
            context.stroke(circle, with: .color(.white.opacity(0.9 * alpha)), lineWidth: max(0.6, r * 0.18))
            // The highlight that makes a circle read as a bubble.
            let shine = CGRect(x: x - r * 0.5, y: y - r * 0.55, width: r * 0.35, height: r * 0.35)
            context.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.85 * alpha)))
        }
    }

    nonisolated static func drawSmudges(in context: inout GraphicsContext, size: CGSize) {
        // Fixed spots on the lower half, where a pet that has been rolling
        // around picks up dirt.
        let spots: [(Double, Double, Double)] = [
            (0.30, 0.62, 0.10), (0.62, 0.70, 0.08), (0.46, 0.82, 0.07), (0.70, 0.52, 0.06), (0.24, 0.80, 0.05),
        ]
        let mud = Color(red: 0.42, green: 0.30, blue: 0.20)
        for (x, y, r) in spots {
            let w = size.width * r * 1.4
            let h = size.width * r
            let rect = CGRect(x: size.width * x - w / 2, y: size.height * y - h / 2, width: w, height: h)
            context.fill(Path(ellipseIn: rect), with: .color(mud.opacity(0.55)))
        }
    }
}

/// A rounded bar, green when healthy, then yellow, then red.
struct PetBar: View {
    var value: Double
    var height: CGFloat
    var tint: Color?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetStyle.secondary.opacity(0.25))
                Capsule()
                    .fill(tint ?? PetStyle.level(value))
                    .frame(width: max(height, proxy.size.width * CGFloat(VirtualPet.clamp(value) / 100)))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.5), value: value)
    }
}

/// Treats left by other widgets for whichever pet draws next. Kept in the
/// defaults rather than a widget's config because the widget that earns one
/// is not the pet: a glass of water knows nothing about which pet is on
/// which shelf, and there may be none.
@MainActor
enum PetTreats {
    private static let key = "docket.pet.treats"
    /// A backlog is a bowl, not a buffet: a long day away is worth a good
    /// meal, not a hundred.
    static let maxPending = 20

    static func give(_ treat: PetTreat) {
        let defaults = UserDefaults.standard
        var pending = defaults.stringArray(forKey: key) ?? []
        guard pending.count < maxPending else { return }
        pending.append(treat.rawValue)
        defaults.set(pending, forKey: key)
    }

    /// Takes every pending treat, leaving none for another pet.
    static func take() -> [PetTreat] {
        let defaults = UserDefaults.standard
        guard let pending = defaults.stringArray(forKey: key), !pending.isEmpty else { return [] }
        defaults.removeObject(forKey: key)
        return pending.compactMap(PetTreat.init(rawValue:))
    }

    static var hasPending: Bool { !(UserDefaults.standard.stringArray(forKey: key) ?? []).isEmpty }
}

/// The writes the tile and the panel both make, from the instance's current
/// config so the two can never disagree.
@MainActor
enum PetLog {
    static func act(_ action: PetAction, in instance: WidgetInstance) {
        let now = Date.now
        WidgetWriter.write(instance) { config in
            let state = VirtualPet.performing(action, on: VirtualPet.state(config, now: now), now: now)
            VirtualPet.store(state, in: &config, now: now)
        }
    }

    /// Pending treats and a finished focus session, written in one go and
    /// only when there is something: the tile calls this every tick.
    static func collect(in instance: WidgetInstance, now: Date) {
        let credited = instance.config.double("focusCredited")
        let focus = VirtualPet.finishedFocus(TimerStateProvider.shared.state,
                                             credited: credited > 0 ? Date(timeIntervalSince1970: credited) : nil,
                                             now: now)
        guard PetTreats.hasPending || focus != nil else { return }
        let count = PetTreats.take().count + (focus == nil ? 0 : 1)
        WidgetWriter.write(instance) { config in
            var state = VirtualPet.treating(count, on: VirtualPet.state(config, now: now), now: now)
            if let focus { state.focusCredited = focus }
            VirtualPet.store(state, in: &config, now: now)
        }
    }

    static func set(_ key: String, _ value: WidgetConfig.Value, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(key, value) }
    }
}

@MainActor
enum PetArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    /// Loose PNGs in the bundle's Resources, like 喝水's; read once.
    static func image(_ character: WaterCharacter, _ look: PetLook) -> NSImage? {
        let name = VirtualPet.imageName(character, look)
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

enum PetStyle {
    static var accent: Color { Color(hex: WidgetCatalog.accentHex(.pet) ?? ShelfColor.redPanda.hex) }

    static func level(_ value: Double) -> Color {
        if value >= 60 { return Color(hex: PaletteColor.green.hex) }
        if value >= 30 { return Color(hex: PaletteColor.yellow.hex) }
        return Color(hex: PaletteColor.red.hex)
    }

    static func tint(look: PetLook, health: Double) -> Color {
        switch look {
        case .sick, .hungry: Color(hex: PaletteColor.red.hex)
        case .cheer, .eat: accent
        default: health < 30 ? Color(hex: PaletteColor.red.hex) : WidgetStyle.secondary
        }
    }
}
