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
            PetFigure(character: character, look: look, height: 44)
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
            PetFigure(character: character, look: look, height: 40)
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
        .animation(.easeInOut(duration: 0.25), value: look)
        .accessibilityHidden(true)
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
