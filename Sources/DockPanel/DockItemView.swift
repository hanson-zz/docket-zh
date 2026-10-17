import SwiftUI
import AppKit

/// One non-widget tile on the shelf: an app, folder, file, link or spacer.
struct DockItemView: View {
    var item: DockItem
    var scale: Double
    var position: DockPosition
    var isRunning: Bool
    var showRunningDot: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var spacerHovered = false

    private var geo: Geometry.IconGeometry {
        Geometry.iconGeometry(scale: scale, vertical: position.isVertical)
    }

    var body: some View {
        switch item {
        case .spacer(_, let size):
            // 透明但要能点中：没有 contentShape 时右键、拖出都落空，
            // 间隔就成了删不掉的空白。鼠标停上去显示虚线框，右键可移除。
            SpacerSlot(hovering: spacerHovered)
                .frame(width: position.isVertical ? geo.width : spacerLength(size),
                       height: position.isVertical ? spacerLength(size) : geo.height)
                .contentShape(.rect)
                .onHover { spacerHovered = $0 }
                .help(tr("间隔：右键可移除，也可拖出程序坞"))
                .accessibilityLabel(tr("间隔"))
        default:
            tile
                .frame(width: geo.width, height: geo.height)
                .contentShape(.rect)
        }
    }

    /// The same length the shelf budgets for it (`Geometry.spacerLength`).
    private func spacerLength(_ size: SpacerSize) -> CGFloat {
        let full = position.isVertical ? geo.height : geo.width
        return CGFloat(Geometry.spacerLength(size, tile: Double(full),
                                             itemGap: Geometry.chrome(scale: scale).itemGap))
    }

    @ViewBuilder
    private var tile: some View {
        ZStack {
            icon
                .frame(width: geo.icon, height: geo.icon)
                // Bottom shelves sit the icon slightly high so the running dot
                // has room underneath without enlarging the tile; top shelves
                // mirror it, the dot going above, by the screen edge.
                .offset(y: position == .bottom ? -4 * geo.factor
                           : position == .top ? 4 * geo.factor : 0)

            if showRunningDot && isRunning {
                // Fades and scales rather than blinking on: it appears the
                // moment an app launches, already a busy instant on the shelf.
                runningDot
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        // The source is AppCatalog's workspace notifications, which fire well
        // outside any withAnimation, so the transition needs its own.
        .animation(.snappy(duration: 0.24), value: isRunning)
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(_, let bundleID, let ref):
            if let url = ref.resolve() {
                Image(nsImage: AppCatalog.shared.icon(for: url)).resizable()
            } else if let image = AppCatalog.shared.icon(forBundleID: bundleID) {
                Image(nsImage: image).resizable()
            } else {
                deadItem
            }

        case .folder(_, let ref, let folderIcon):
            if folderIcon.isEmpty {
                if let url = ref.resolve() {
                    Image(nsImage: AppCatalog.shared.icon(for: url)).resizable()
                } else {
                    deadItem
                }
            } else {
                tintedFolder(folderIcon)
            }

        case .file(_, let ref):
            if let url = ref.resolve() {
                Image(nsImage: AppCatalog.shared.icon(for: url)).resizable()
            } else {
                deadItem
            }

        case .link(_, _, let title):
            linkIcon(title)

        case .group(let group):
            // The plate fills the slot, so it takes the icon's own extent.
            GroupTile(group: group, side: geo.icon)

        case .spacer, .widget:
            EmptyView()
        }
    }

    /// Docket draws its own folder art rather than touching the folder on
    /// disk, so customising an icon can never modify the user's files.
    private func tintedFolder(_ folderIcon: FolderIcon) -> some View {
        let tint = folderIcon.color.map { Color(hex: $0.hex) } ?? Color(hex: PaletteColor.blue.hex)
        return ZStack {
            Image(systemName: "folder.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint.gradient)
            if let letter = folderIcon.letter, !letter.isEmpty {
                Text(letter.prefix(1).uppercased())
                    .font(.system(size: geo.icon * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: geo.icon * 0.06)
            }
        }
    }

    private func linkIcon(_ title: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: geo.icon * 0.22, style: .continuous)
                .fill(Color(hex: PaletteColor.indigo.hex).gradient)
            Text(title.prefix(1).uppercased())
                .font(.system(size: geo.icon * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    /// The target is gone. Show it greyed so the user can repair or remove it
    /// - silently dropping someone's pinned item is worse than showing a gap.
    private var deadItem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: geo.icon * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
            Image(systemName: "questionmark")
                .font(.system(size: geo.icon * 0.38, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var runningDot: some View {
        Circle()
            .fill(Color.primary.opacity(scheme == .dark ? 0.75 : 0.55))
            .frame(width: geo.dot, height: geo.dot)
            .offset(x: position == .left ? -geo.dotOffset : position == .right ? geo.dotOffset : 0,
                    y: position == .bottom ? geo.dotBottom
                       : position == .top ? -geo.dotBottom : 0)
    }
}


/// 间隔平时看不见，鼠标停上去露出一圈虚线框，让人知道这里有东西可删。
private struct SpacerSlot: View {
    var hovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(Color.primary.opacity(hovering ? 0.35 : 0))
            .padding(.vertical, 6)
            .animation(.easeOut(duration: 0.14), value: hovering)
    }
}
