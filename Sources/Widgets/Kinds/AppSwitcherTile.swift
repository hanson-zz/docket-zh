import AppKit
import SwiftUI

/// The apps that are open, as icons; a click brings one forward.
///
/// Regular apps only, the ones with a window and a Dock tile of their own,
/// which is what Command-Tab shows. The frontmost one leads and wears a
/// small dot, the way the Dock marks a running app.
struct AppSwitcherTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var catalog: AppCatalog { AppCatalog.shared }

    /// What the tile draws: the live list, or the library's sample.
    private var apps: [AppSwitcherItem] {
        if context.isPreview { return AppSwitcherItem.samples }
        let ordered = AppStrip.ordered(catalog.running, isActive: \.isActive)
        return ordered.map { AppSwitcherItem(id: $0.id, name: $0.name, url: $0.url, isActive: $0.isActive) }
    }

    var body: some View {
        let column = context.position.isVertical
        let capacity = 6
        let fit = AppStrip.fit(total: apps.count, capacity: capacity)
        let shown = Array(apps.prefix(fit.shown))
        return WidgetSurface {
            if apps.isEmpty {
                Text("没有正在运行的应用")
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
            _ = catalog.activate(bundleID: app.id)
        } label: {
            AppSwitcherIcon(app: app, size: size)
                .overlay(alignment: .bottom) {
                    if app.isActive {
                        Circle().fill(WidgetStyle.primary).frame(width: 3, height: 3).offset(y: 3)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(app.name)
        .accessibilityLabel(app.isActive ? "\(app.name)（当前）" : app.name)
    }

    /// The rest are in the panel, which the card opens.
    private func more(_ count: Int, size: CGFloat) -> some View {
        Text("+\(count)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
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

    static let samples: [AppSwitcherItem] = [
        AppSwitcherItem(id: "sample.safari", name: "Safari 浏览器", url: nil, isActive: true, sampleSymbol: "safari"),
        AppSwitcherItem(id: "sample.mail", name: "邮件", url: nil, isActive: false, sampleSymbol: "envelope"),
        AppSwitcherItem(id: "sample.notes", name: "备忘录", url: nil, isActive: false, sampleSymbol: "note.text"),
        AppSwitcherItem(id: "sample.music", name: "音乐", url: nil, isActive: false, sampleSymbol: "music.note"),
        AppSwitcherItem(id: "sample.terminal", name: "终端", url: nil, isActive: false, sampleSymbol: "terminal"),
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
