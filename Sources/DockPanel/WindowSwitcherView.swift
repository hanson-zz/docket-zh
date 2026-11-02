import AppKit
import SwiftUI

/// ⌥Tab 窗口切换器的面板内容，照效果图 design/window-switcher.png：
/// 左上角小熊猫和搜索框（右边「N 个窗口」），中间窗口卡片，底部一行按键提示。
/// 液态玻璃，跟随浅色 / 深色。选中的卡片白描边、往上抬一点，不用蓝色发光。
/// 三种样式（设置 ▸ 窗口切换 ▸ 样式）：缩略图、图标（大 App 图标加一行标题）、标题列表
/// （一列紧凑的行：小图标、窗口标题、App 名）。搜索、角标、按键都一样。
struct WindowSwitcherView: View {
    var model: WindowSwitcherModel
    var pick: (Int) -> Void

    @Environment(\.colorScheme) private var scheme

    private typealias L = WindowSwitcherLayout

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 28, style: .continuous) }

    var body: some View {
        VStack(spacing: 0) {
            searchRow
                .frame(height: L.searchHeight)
                .padding(.top, L.paddingTop)
            Spacer(minLength: L.searchGap)
            grid
                .frame(width: model.layout.gridSize.width, height: model.layout.gridSize.height)
            Spacer(minLength: L.hintsGap)
            hints
                .frame(height: L.hintsHeight)
                .padding(.bottom, L.paddingBottom)
        }
        .padding(.horizontal, L.paddingX)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelGlassSurface(cornerRadius: 28, dark: false) }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.panelStroke, lineWidth: 0.5) }
    }

    // MARK: 顶部

    private var searchRow: some View {
        HStack(spacing: 12) {
            if let panda = Self.panda {
                Image(nsImage: panda)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                if model.query.isEmpty {
                    Text(model.searching ? tr("输入 App 名、窗口标题或拼音首字母") : tr("输入以搜索窗口"))
                        .font(.system(size: 15))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: model.query)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if model.searching {
                    // 光标：在搜索时说明打的字进了这里。
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.panelPrimary)
                        .frame(width: 2, height: 18)
                }
                Spacer(minLength: 8)
                Text(WindowSwitcher.countText(model.visible.count))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
            .background(Capsule().fill(.panelFill))
            .overlay { Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5) }
        }
    }

    // MARK: 卡片

    @ViewBuilder private var grid: some View {
        let entries = model.visible
        if entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: model.query.isEmpty ? "macwindow" : "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.panelTertiary)
                Text(model.query.isEmpty ? tr("没有可以切换的窗口") : tr("没有匹配的窗口"))
                    .font(.system(size: 15))
                    .foregroundStyle(.panelSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.layout.style == .list {
            list(entries)
        } else if model.layout.scrolls {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    rows(entries)
                }
                // 选中的卡片往上抬，不裁掉抬出去的那一点。
                .scrollClipDisabled()
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: model.selection) { _, index in
                    guard entries.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(entries[index].id) }
                }
            }
            .id(model.session)
        } else {
            rows(entries)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// 按行从左到右排，和方向键上下移动的算法一致。
    private func rows(_ entries: [WindowSwitcher.Entry]) -> some View {
        let columns = max(1, model.layout.columns)
        let rowCount = Int((Double(entries.count) / Double(columns)).rounded(.up))
        return VStack(alignment: .leading, spacing: L.gap) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: L.gap) {
                    ForEach(row * columns ..< min(entries.count, (row + 1) * columns), id: \.self) { index in
                        let entry = entries[index]
                        WindowSwitcherCard(entry: entry,
                                           style: model.layout.style,
                                           image: model.shots[entry.id],
                                           icon: model.icons[entry.pid],
                                           thumbnails: model.canCapture,
                                           selected: index == model.selection,
                                           layout: model.layout,
                                           pick: { pick(entry.id) })
                            .id(entry.id)
                    }
                }
            }
        }
    }

    /// 标题列表：一列，放不下时竖向滚动，选中的行滚进来。
    private func list(_ entries: [WindowSwitcher.Entry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: model.layout.scrolls) {
                VStack(spacing: model.layout.gap) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        WindowSwitcherRow(entry: entry,
                                          icon: model.icons[entry.pid],
                                          selected: index == model.selection,
                                          size: model.layout.cardSize,
                                          iconSize: model.layout.thumbnailSize.width,
                                          pick: { pick(entry.id) })
                            .id(entry.id)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(!model.layout.scrolls)
            .onChange(of: model.selection) { _, index in
                guard entries.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(entries[index].id) }
            }
        }
        .id(model.session)
    }

    // MARK: 底部

    private var hints: some View {
        let hold = model.holdSymbols
        let full: [(String, String)]
        let short: [(String, String)]
        if model.searching {
            full = [("Tab", tr("下一个")), ("↩", tr("切换")), ("⌫", tr("删除")), ("Esc", tr("取消"))]
            short = [("↩", tr("切换")), ("Esc", tr("取消"))]
        } else {
            full = [("Tab", tr("下一个")), ("⇧Tab", tr("上一个")), ("W", tr("关闭")), ("M", tr("最小化")),
                    ("Q", tr("退出 App")), (tr("松开 \(hold)"), tr("切换"))]
            short = [("Tab", tr("下一个")), (tr("松开 \(hold)"), tr("切换"))]
        }
        return ViewThatFits(in: .horizontal) {
            hintRow(full)
            hintRow(short)
        }
    }

    private func hintRow(_ items: [(String, String)]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                if offset > 0 {
                    Text(verbatim: "·")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                }
                Text(verbatim: item.0)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.panelRaised).panelLift())
                Text(item.1)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// 左上角的小熊猫（Resources/Pet）。
    @MainActor private static let panda: NSImage? = {
        guard let url = Bundle.main.url(forResource: "pet-panda-idle", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// 一张窗口卡片：缩略图（没屏幕录制权限或截不到时是 App 大图标）、右上角角标、
/// App 图标加单行标题。选中白描边、往上抬 4pt；悬停淡淡的底。
private struct WindowSwitcherCard: View {
    var entry: WindowSwitcher.Entry
    var style: WindowSwitcherStyle = .thumbnails
    var image: CGImage?
    var icon: NSImage?
    var thumbnails: Bool
    var selected: Bool
    var layout: WindowSwitcherLayout.Layout
    var pick: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private typealias L = WindowSwitcherLayout

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }
    private var thumb: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    private var title: String { WindowSwitcher.cardTitle(appName: entry.appName, title: entry.title) }

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 0) {
                thumbnail
                    .frame(width: layout.thumbnailSize.width, height: layout.thumbnailSize.height)
                    .clipShape(thumb)
                    .overlay(alignment: .topTrailing) { badge }
                    .shadow(color: .black.opacity(style == .thumbnails ? (scheme == .dark ? 0.3 : 0.14) : 0),
                            radius: 4, y: 2)
                    .opacity(entry.dimmed ? 0.55 : 1)
                    .padding(.top, L.cardInset)
                caption
                    .frame(width: layout.thumbnailSize.width, height: L.captionHeight)
                    .padding(.top, L.cardInset)
                Spacer(minLength: 0)
            }
            .frame(width: layout.cardSize.width, height: layout.cardSize.height)
            .background { background }
            .contentShape(card)
        }
        .buttonStyle(.plain)
        .offset(y: selected ? -L.lift : 0)
        .shadow(color: .black.opacity(selected ? (scheme == .dark ? 0.32 : 0.2) : 0), radius: 10, y: 6)
        .animation(.easeOut(duration: 0.12), value: selected)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        if selected {
            card.fill(Color.white.opacity(scheme == .dark ? 0.14 : 0.72))
                .overlay { card.strokeBorder(Color.white.opacity(scheme == .dark ? 0.85 : 1), lineWidth: 2) }
                .overlay {
                    if scheme != .dark {
                        // 浅色玻璃上白描边外再压一圈极淡的深线，白边才看得出来。
                        card.inset(by: -1).stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    }
                }
        } else if hovering {
            card.fill(.panelFill)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var thumbnail: some View {
        if style == .icons {
            bigIcon
        } else {
            thumbnailImage
        }
    }

    /// 图标样式：只有大 App 图标，不画底。
    @ViewBuilder private var bigIcon: some View {
        let side = min(L.iconSize * layout.scale, layout.thumbnailSize.height)
        ZStack {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.panelTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var thumbnailImage: some View {
        ZStack {
            thumb.fill(.panelFill)
            if thumbnails, let image, !entry.dimmed {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layout.thumbnailSize.width, height: layout.thumbnailSize.height,
                           alignment: .top)
                    .clipped()
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(64, layout.thumbnailSize.height * 0.62),
                           height: min(64, layout.thumbnailSize.height * 0.62))
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.panelTertiary)
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if let badge = WindowSwitcher.badge(for: entry) {
            Text(badge.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(scheme == .dark ? Color.black.opacity(0.6) : Color.white.opacity(0.92)))
                .padding(style == .icons ? 4 : 6)
        }
    }

    @ViewBuilder private var caption: some View {
        if style == .icons {
            // 图标样式：只一行窗口标题，居中。
            Text(verbatim: entry.title.isEmpty ? entry.appName : entry.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .opacity(entry.dimmed && !selected ? 0.6 : 1)
        } else {
            thumbnailCaption
        }
    }

    private var thumbnailCaption: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }
            Text(verbatim: title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .opacity(entry.dimmed && !selected ? 0.6 : 1)
    }

    private var accessibility: String {
        if let badge = WindowSwitcher.badge(for: entry) { return tr("\(title)，\(badge.text)") }
        return title
    }
}

/// 标题列表的一行：小 App 图标、窗口标题、右边 App 名和角标。选中是中性的浅色块，
/// 和卡片一样不用蓝色。
private struct WindowSwitcherRow: View {
    var entry: WindowSwitcher.Entry
    var icon: NSImage?
    var selected: Bool
    var size: CGSize
    var iconSize: CGFloat
    var pick: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private var row: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    private var title: String { entry.title.isEmpty ? entry.appName : entry.title }

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(.panelTertiary)
                    }
                }
                .frame(width: iconSize, height: iconSize)
                Text(verbatim: title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let badge = WindowSwitcher.badge(for: entry) {
                    Text(badge.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(.panelFill))
                        .fixedSize()
                }
                if title != entry.appName {
                    Text(verbatim: entry.appName)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: size.width * 0.32, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: size.width, height: size.height)
            .opacity(entry.dimmed && !selected ? 0.6 : 1)
            .background { background }
            .contentShape(row)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.1), value: selected)
        .onHover { hovering = $0 }
        .help(title)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        if selected {
            row.fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.72))
                .overlay { row.strokeBorder(Color.white.opacity(scheme == .dark ? 0.5 : 1), lineWidth: 1) }
                .overlay {
                    if scheme != .dark {
                        row.inset(by: -1).stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                    }
                }
        } else if hovering {
            row.fill(.panelFill)
        } else {
            Color.clear
        }
    }

    private var accessibility: String {
        let base = title == entry.appName ? title : tr("\(title)，\(entry.appName)")
        if let badge = WindowSwitcher.badge(for: entry) { return tr("\(base)，\(badge.text)") }
        return base
    }
}
