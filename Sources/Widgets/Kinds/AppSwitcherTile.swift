import AppKit
import SwiftUI

/// The apps that are open, as icons; a click brings one forward.
///
/// Regular apps only, the ones with a window and a Dock tile of their own,
/// which is what Command-Tab shows. The frontmost one wears a small dot, the
/// way the Dock marks a running app. 面板里固定的 App 排在最前（没开的半透明，
/// 点了启动），隐藏的不出现，其余按面板选的排序（见 `AppSwitcherList.tile`）。
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
        let capacity = 6
        let fit = AppStrip.fit(total: apps.count, capacity: capacity)
        let shown = Array(apps.prefix(fit.shown))
        return WidgetSurface {
            if apps.isEmpty {
                Text(catalog.running.isEmpty ? tr("没有正在运行的应用") : tr("正在运行的应用都隐藏了"))
                    .font(WidgetStyle.note)
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if column {
                LazyVGrid(columns: [GridItem(.fixed(28), spacing: 4), GridItem(.fixed(28), spacing: 4)],
                          spacing: 4) {
                    ForEach(shown) { icon($0, size: 26) }
                    if fit.overflow > 0 { more(fit.overflow, size: 26) }
                }
            } else {
                HStack(spacing: 4) {
                    ForEach(shown) { icon($0, size: 30) }
                    if fit.overflow > 0 { more(fit.overflow, size: 30) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func icon(_ app: AppSwitcherItem, size: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            catalog.open(WidgetTarget.app(bundleID: app.id))
        } label: {
            AppSwitcherIcon(app: app, size: size)
                .opacity(app.isRunning ? 1 : 0.45)
                .overlay(alignment: .bottom) {
                    if app.isActive {
                        Circle().fill(WidgetStyle.primary).frame(width: 3, height: 3).offset(y: 3)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(app.isRunning ? app.name : tr("\(app.name)（没开，点了启动）"))
        .accessibilityLabel(app.isActive ? tr("\(app.name)（当前）")
                            : app.isRunning ? app.name : tr("\(app.name)，没开，点按启动"))
    }

    /// The rest are in the panel, which the card opens.
    private func more(_ count: Int, size: CGFloat) -> some View {
        Text("+\(count)")
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(WidgetStyle.secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(WidgetStyle.primary.opacity(0.08)))
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
struct AppSwitcherIcon: View {
    var app: AppSwitcherItem
    var size: CGFloat

    var body: some View {
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
