import SwiftUI

/// The shape every inline control on these tiles wears.
///
/// A bare symbol dropped at the trailing edge of a card reads as decoration -
/// nothing about it says it can be pressed. Every compact macOS surface that
/// has to fit a control beside a readout answers this the same way, from
/// Control Center's tiles to the menu bar's Now Playing: a low-opacity disc
/// sized to the glyph, so the target is visible before the pointer finds it.
/// This is that disc and nothing more.
///
/// It is twice the glyph across, which is the hit target these tiles already
/// reserved, so a control gains its backing without any layout moving around
/// it - the 76pt column keeps the smaller glyph it was drawn with and the
/// 168pt card keeps its larger one.
///
/// The disc takes its colour from the glyph, so the Alarm's orange stays
/// orange and the Stopwatch's reset stays as quiet as its symbol, without a
/// second rule per tile.
///
/// Pressed, not hovered: `.onHover` never fires in this non-activating
/// accessory panel (see HoverCatcher), which is why the Music tile's artwork
/// control is fixed rather than revealed. A hover-only affordance here would
/// simply never be seen.
struct TileGlyph: View {
    var symbol: String
    /// Point size of the glyph; the disc follows from it.
    var size: CGFloat
    var tint: Color = WidgetStyle.primary
    /// Morphs between symbols instead of cutting, for controls whose glyph
    /// flips with their state (play and pause). Off by default so the other
    /// tiles keep their plain swap.
    var morphs = false
    /// `nil` draws the control without making it pressable, which is what the
    /// library wants: the card's own click there adds the widget, and a button
    /// that refused to act would still swallow it. Drawing nothing instead
    /// would preview a tile the shelf never shows.
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { Image(systemName: symbol).playPauseMorph(symbol, enabled: morphs) }
                .buttonStyle(TileGlyphButton(size: size, tint: tint))
        } else {
            Image(systemName: symbol)
                .playPauseMorph(symbol, enabled: morphs)
                .tileGlyphDisc(size: size, tint: tint, pressed: false)
        }
    }
}

extension View {
    /// Turns a play/pause swap into a morph.
    ///
    /// The state behind these buttons arrives from the player's own
    /// notifications, outside any animation transaction, so the transition
    /// alone would still hard-cut; the animation keyed on the symbol is what
    /// gives it a transaction to run in. Magic Replace where the two glyphs
    /// share a shape, a quick down-up swap where they do not. 打开“减少动态效果”
    /// 时不变形也不上下换，两个图标原地淡入淡出，不指望符号动效自己去判断。
    func playPauseMorph(_ symbol: String, enabled: Bool = true) -> some View {
        modifier(PlayPauseMorph(symbol: symbol, enabled: enabled))
    }
}

private struct PlayPauseMorph: ViewModifier {
    var symbol: String
    var enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(transition)
            .animation(animation, value: symbol)
    }

    private var transition: ContentTransition {
        guard enabled else { return .identity }
        if reduceMotion { return .opacity }
        return .symbolEffect(.replace.magic(fallback: .replace.downUp.byLayer))
    }

    private var animation: Animation? {
        guard enabled else { return nil }
        return reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3)
    }
}

/// A style rather than a modifier on the label, because the press is the only
/// feedback this panel can give and it has to reach the disc, not just the
/// glyph sitting on it.
private struct TileGlyphButton: ButtonStyle {
    var size: CGFloat
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tileGlyphDisc(size: size, tint: tint, pressed: configuration.isPressed)
    }
}

private extension View {
    func tileGlyphDisc(size: CGFloat, tint: Color, pressed: Bool) -> some View {
        font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size * 2, height: size * 2)
            .background(Circle().fill(tint.opacity(pressed ? 0.3 : 0.13)))
            // Confined to the disc - and to the disc's own round shape, so the
            // corners of its box still belong to the card. A descendant tap
            // beats the shelf's, and the shelf's is what opens the widget.
            .contentShape(Circle())
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.14), value: pressed)
    }
}
