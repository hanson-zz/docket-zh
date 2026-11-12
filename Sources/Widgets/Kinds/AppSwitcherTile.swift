import AppKit
import SwiftUI

/// The apps that are open, as icons; a click brings one forward.
///
/// Regular apps only, the ones with a window and a Dock tile of their own,
/// which is what Command-Tab shows. 应用切换器 v2（效果图 design/app-switcher-v2.py）：
/// 横排图标 30，都放得下时 7 个全放，多了放 6 个加「+N」；当前的 App 垫一块中性浅色高亮块
/// （不用主题色、不发光），开着的下面一个小点，固定了没开的半透明。面板里固定的 App 排在最前
/// （点了启动），隐藏的不出现，其余按面板选的排序（见 `AppSwitcherList.tile`）。
struct AppSwitcherTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var catalog: AppCatalog { AppCatalog.shared }

    /// What the tile draws: the live list, or the library's sample.
    private var apps: [AppSwitcherItem] {
        if context.isPreview { return AppSwitcherItem.samples }
        let config = instance.config
        let running = catalog.running
        let slots = AppSwitcherList.tile(running.map { .init(id: $0.id, name: $0.name, isActive: $0.isActive) },
                                         recent: catalog.recentIDs, pinned: AppSwitcherList.pinned(config),
                                         hidden: AppSwitcherList.hidden(config), sort: AppSwitcherList.sort(config))
        return slots.map { slot in
            if let app = running.first(where: { $0.id == slot.id }) {
                return AppSwitcherItem(id: app.id, name: app.name, url: app.url, isActive: app.isActive)
            }
            return AppSwitcherItem.notRunning(slot.id)
        }
    }

    var body: some View {
        let column = context.position.isVertical
        let all = apps
        let fit = AppStrip.fit(total: all.count, capacity: column ? 6 : AppSwitcherLayout.tileCapacity)
        let shown = Array(all.prefix(fit.shown))
        return WidgetSurface {
            if all.isEmpty {
                Text(catalog.running.isEmpty ? tr("没有正在运行的应用") : tr("正在运行的应用都隐藏了"))
                    .font(WidgetStyle.note)
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if column {
                // 竖排货架和原来一样两列 28（内容区 60 宽），图标 24 垫在 28 的格里。
                LazyVGrid(columns: [GridItem(.fixed(28), spacing: 4), GridItem(.fixed(28), spacing: 4)],
                          spacing: 4) {
                    ForEach(shown) { icon($0, size: 24, plate: 28, dotOffset: 0) }
                    if fit.overflow > 0 { more(fit.overflow, size: 26, plate: 28) }
                }
            } else {
                HStack(spacing: CGFloat(AppSwitcherLayout.tileSpacing)) {
                    ForEach(shown) {
                        icon($0, size: CGFloat(AppSwitcherLayout.tileIcon), plate: CGFloat(AppSwitcherLayout.tilePlate),
                             dotOffset: 4)
                    }
                    if fit.overflow > 0 {
                        more(fit.overflow, size: CGFloat(AppSwitcherLayout.tileIcon),
                             plate: CGFloat(AppSwitcherLayout.tilePlate))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func icon(_ app: AppSwitcherItem, size: CGFloat, plate: CGFloat, dotOffset: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            catalog.open(WidgetTarget.app(bundleID: app.id))
        } label: {
            AppSwitcherIcon(app: app, size: size, plate: plate, selected: app.isActive,
                            dot: app.isRunning && !app.isActive, dimsWhenOff: true, dotOffset: dotOffset)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(app.isRunning ? app.name : tr("\(app.name)（没开，点了启动）"))
        .accessibilityLabel(app.isActive ? tr("\(app.name)（当前）")
                            : app.isRunning ? app.name : tr("\(app.name)，没开，点按启动"))
    }

    /// The rest are in the panel, which the card opens.
    private func more(_ count: Int, size: CGFloat, plate: CGFloat) -> some View {
        AppSwitcherMore(count: count, size: size)
            .frame(width: plate, height: plate)
            .allowsHitTesting(false)
    }
}

/// One app as the switcher shows it.
struct AppSwitcherItem: Identifiable, Hashable {
    var id: String
    var name: String
    var url: URL?
    var isActive: Bool
    /// The library has no apps to read, so it draws symbols instead.
    var sampleSymbol: String?
    /// 固定了但没开的 App 是 false：卡片和面板画半透明，点了启动。
    var isRunning = true

    /// 一个固定了但没开的 App：名字和图标从磁盘上的 .app 读，找不到（删掉了）时写 bundle id。
    @MainActor
    static func notRunning(_ id: String) -> AppSwitcherItem {
        guard let url = appURL(id) else {
            return AppSwitcherItem(id: id, name: id, url: nil, isActive: false, sampleSymbol: "questionmark.app",
                                   isRunning: false)
        }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        let trimmed = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return AppSwitcherItem(id: id, name: trimmed, url: url, isActive: false, isRunning: false)
    }

    /// 卡片每次重画都要问，查过的记下来；文件不在了（删掉或挪走）再查一次。
    @MainActor private static var urls: [String: URL] = [:]

    @MainActor
    private static func appURL(_ id: String) -> URL? {
        if let url = urls[id], FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        urls[id] = url
        return url
    }

    static let samples: [AppSwitcherItem] = [
        AppSwitcherItem(id: "sample.safari", name: tr("Safari 浏览器"), url: nil, isActive: true, sampleSymbol: "safari"),
        AppSwitcherItem(id: "sample.mail", name: tr("邮件"), url: nil, isActive: false, sampleSymbol: "envelope"),
        AppSwitcherItem(id: "sample.notes", name: tr("备忘录"), url: nil, isActive: false, sampleSymbol: "note.text"),
        AppSwitcherItem(id: "sample.music", name: tr("音乐"), url: nil, isActive: false, sampleSymbol: "music.note"),
        AppSwitcherItem(id: "sample.terminal", name: tr("终端"), url: nil, isActive: false, sampleSymbol: "terminal"),
    ]
}

/// An app's own icon, or the sample's symbol on a plain square.
///
/// 只给 `size` 时就是图标本身（编辑列表、右键菜单里用）。给了 `plate` 时画成切换器里的
/// 一格：边长 `plate` 的格子，图标居中；选中（当前、键盘选中、展开的）垫一块中性浅色高亮块，
/// 悬停垫淡一些的同一块；下面可以有小点（开着），右上角可以有小图钉（固定）或窗口数角标
/// （大于 1 才画，实心底，深色下也看得清）；没开的 App 可以半透明。
struct AppSwitcherIcon: View {
    var app: AppSwitcherItem
    var size: CGFloat
    var plate: CGFloat? = nil
    var selected = false
    var hovered = false
    var dot = false
    var pinned = false
    var badge: Int? = nil
    var dimsWhenOff = false
    /// 小点往下挪多少（扩展栏格子矮，点画在格子下面）。
    var dotOffset: CGFloat = 0

    var body: some View {
        if let plate {
            ZStack {
                if selected || hovered {
                    AppSwitcherHighlight(cornerRadius: plate * 0.3, strength: selected ? 1 : 0.55)
                }
                image.opacity(dimsWhenOff && !app.isRunning ? 0.42 : 1)
            }
            .frame(width: plate, height: plate)
            .overlay(alignment: .bottom) {
                if dot {
                    Circle()
                        .fill(Color.panelSecondary)
                        .frame(width: 4, height: 4)
                        .padding(.bottom, 1)
                        .offset(y: dotOffset)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 1 {
                    AppSwitcherBadge(count: badge).offset(x: 3, y: -3)
                } else if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                        .rotationEffect(.degrees(35))
                        .offset(x: 1, y: -1)
                        .accessibilityHidden(true)
                }
            }
        } else {
            image
        }
    }

    @ViewBuilder
    private var image: some View {
        if let url = app.url {
            Image(nsImage: AppCatalog.shared.icon(for: url))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: app.sampleSymbol ?? "app")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .frame(width: size * 0.84, height: size * 0.84)
                .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(WidgetStyle.primary.opacity(0.1)))
                .frame(width: size, height: size)
        }
    }
}

/// 切换器的选中块：中性浅色，不用主题色、不发光。浅色外观近白加一道淡阴影和细边，
/// 深色外观白 17% 加细亮边（效果图 `--hi`）。`strength` 小于 1 时是悬停的淡一档。
struct AppSwitcherHighlight: View {
    var cornerRadius: CGFloat
    var strength: Double = 1

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(dark ? Color.white.opacity(0.17) : Color.white.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0 : 0.13), radius: 4, y: 2)
            .opacity(strength)
            .allowsHitTesting(false)
    }
}

/// 右上角的窗口数：实心底（浅色白、深色 #50535E）、细边、小阴影，13pt 粗体。
struct AppSwitcherBadge: View {
    var count: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.panelPrimary)
            .padding(.horizontal, 5)
            .frame(minWidth: 19, minHeight: 19)
            .background(Capsule().fill(dark ? Color(red: 0.314, green: 0.325, blue: 0.369) : Color.white))
            .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                                            lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .fixedSize()
            .help(tr("\(count) 个窗口"))
            .accessibilityLabel(tr("\(count) 个窗口"))
    }
}

/// 放不下的那几个：「+N」小圆，13pt 粗体次级色，最多写到 +99。
struct AppSwitcherMore: View {
    var count: Int
    var size: CGFloat

    var body: some View {
        Text(verbatim: "+\(min(count, 99))")
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: size, height: size)
            .background(Circle().fill(Color.panelFill))
            .overlay(Circle().strokeBorder(Color.panelSeparator, lineWidth: 1))
            .accessibilityLabel(tr("还有 \(count) 个"))
    }
}
