import AppKit
import SwiftUI

/// A group of apps drawn as one dock tile: a tinted plate carrying a 2×2 grid
/// of its contents, the way iOS draws a home-screen folder.
///
/// The plate fills the whole slot rather than sitting inside it like an app
/// icon's artwork does. That is what makes a group read as a container at a
/// glance even though it occupies exactly one slot.
struct GroupTile: View {
    var group: DockGroup
    /// The slot's side, so everything inside scales with the shelf.
    var side: CGFloat

    @Environment(\.colorScheme) private var scheme

    private var padding: CGFloat { side * 0.10 }
    private var spacing: CGFloat { side * 0.06 }
    private var cell: CGFloat { (side - padding * 2 - spacing) / 2 }
    private var radius: CGFloat { side * 0.225 }

    var body: some View {
        if group.items.isEmpty {
            emptyPlate
        } else {
            filledPlate
        }
    }

    /// 空组（从小组件库「应用分组」新建、还没放东西）：淡底加虚线框，中间一个「＋」，
    /// 一眼看出是个等着放 App 的容器，而不是三格空白。
    private var emptyPlate: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let ink = scheme == .dark ? Color.white : Color.black
        return shape
            .fill(group.tint.swatch.map { $0.opacity(scheme == .dark ? 0.30 : 0.20) }
                  ?? ink.opacity(scheme == .dark ? 0.08 : 0.05))
            .overlay {
                shape.strokeBorder(ink.opacity(scheme == .dark ? 0.42 : 0.32),
                                   style: StrokeStyle(lineWidth: max(1, side * 0.035),
                                                      dash: [max(2, side * 0.09), max(2, side * 0.06)]))
            }
            .overlay {
                // 文件夹分组画文件夹加号，一眼和应用分组分开。
                Image(systemName: group.isFolderGroup ? "folder.badge.plus" : "plus")
                    .font(.system(size: side * (group.isFolderGroup ? 0.30 : 0.36), weight: .medium))
                    .foregroundStyle(ink.opacity(scheme == .dark ? 0.70 : 0.55))
            }
            .frame(width: side, height: side)
    }

    private var filledPlate: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(plate)
            .overlay {
                // Two rows of two. A fixed grid, not a flow: the cells must
                // line up across every group on the shelf.
                VStack(spacing: spacing) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<2, id: \.self) { column in
                                cellContent(at: row * 2 + column)
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
    }

    /// Tinted plates are translucent so the shelf's own material still reads
    /// through; an untinted group gets a neutral plate rather than nothing, or
    /// it would be indistinguishable from empty space.
    private var plate: Color {
        guard let swatch = group.tint.swatch else {
            return scheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)
        }
        return swatch.opacity(scheme == .dark ? 0.55 : 0.38)
    }

    @ViewBuilder
    private func cellContent(at index: Int) -> some View {
        let shown = group.preview
        // The last cell gives way to a count when there is more inside, so a
        // group never silently hides what it holds.
        if group.hiddenCount > 0, index == DockGroup.previewCount - 1 {
            overflow
        } else if index < shown.count {
            MiniIcon(item: shown[index])
        } else {
            Color.clear
        }
    }

    private var overflow: some View {
        RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
            .overlay {
                Text("+\(group.hiddenCount + 1)")
                    .font(.system(size: cell * 0.42, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(scheme == .dark ? Color.white : Color.black)
            }
    }
}

/// One app's artwork inside a group, at its natural shape.
private struct MiniIcon: View {
    var item: DockItem

    var body: some View {
        if let url = item.fileRef?.resolve() {
            Image(nsImage: AppCatalog.shared.icon(for: url))
                .resizable()
                .interpolation(.high)
        } else if case .app(_, let bundleID, _) = item,
                  let image = AppCatalog.shared.icon(forBundleID: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.35))
        }
    }
}

extension GroupTint {
    /// nil for `.none`, which is a neutral plate rather than a colour.
    var swatch: Color? {
        switch self {
        case .none: nil
        case .red: Color(hex: "#FF453A")
        case .orange: Color(hex: "#FF9F0A")
        case .yellow: Color(hex: "#FFD60A")
        case .green: Color(hex: "#32D74B")
        case .teal: Color(hex: "#40C8E0")
        case .blue: Color(hex: "#0A84FF")
        case .purple: Color(hex: "#BF5AF2")
        case .pink: Color(hex: "#FF375F")
        case .graphite: Color(hex: "#8E8E93")
        }
    }

    var title: String {
        switch self {
        case .none: tr("无色调")
        default: docketColourName(rawValue)
        }
    }
}
