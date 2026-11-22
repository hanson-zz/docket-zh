import SwiftUI
import AppKit

/// One non-widget tile on the shelf: an app, folder, file, link or spacer.
struct DockItemView: View {
    var item: DockItem
    var scale: Double
    var position: DockPosition
    var isRunning: Bool
    var showRunningDot: Bool
    /// 设置里的小组件间距，小间隔的长度跟着它走，和扩展栏算的一致。
    var itemGap: Double = Geometry.defaultItemGap

    @Environment(\.colorScheme) private var scheme
    @State private var spacerHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 动态图标：总开关默认关，访达、Chrome、ChatGPT、Codex、Claude 子开关和「AI 额度水位」默认开。
    @AppStorage(LiveIconToggles.masterKey) private var liveIconsEnabled = false
    @AppStorage(LiveIconToggles.finderKey) private var liveFinder = true
    @AppStorage(LiveIconToggles.chromeKey) private var liveChrome = true
    @AppStorage(LiveIconToggles.openAIKey) private var liveChatGPT = true
    @AppStorage(LiveIconToggles.codexKey) private var liveCodex = true
    @AppStorage(LiveIconToggles.claudeKey) private var liveClaude = true
    @AppStorage(LiveIconToggles.quotaKey) private var liveQuota = true
    @AppStorage(LiveIconToggles.percentKey) private var liveQuotaPercent = true
    // 日历：真实日程驱动的液位和倒计时，默认开（总开关仍默认关）。
    @AppStorage(LiveIconToggles.calendarKey) private var liveCalendar = true
    // 消息未读：信息、微信、邮件各一个子开关，默认开（总开关仍默认关）。
    @AppStorage(LiveBadgeApp.messages.toggleKey) private var liveMessages = true
    @AppStorage(LiveBadgeApp.wechat.toggleKey) private var liveWeChat = true
    @AppStorage(LiveBadgeApp.mail.toggleKey) private var liveMail = true
    @AppStorage(LiveBrowser.safariKey) private var liveSafari = true
    // 自定义 App 图标（Pro）跟着授权变：过期时画回默认图标，解锁后自动回来。
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

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
                                             itemGap: Geometry.chrome(scale: scale, itemGap: itemGap).itemGap))
    }

    /// 这个格子是哪个动态图标 App；不是 App 或不认得时是 nil。
    private var liveApp: LiveIconApp? {
        guard case .app(_, let bundleID, _) = item else { return nil }
        return LiveIconApp(bundleID: bundleID)
    }

    private var liveToggles: LiveIconToggles {
        LiveIconToggles(master: liveIconsEnabled, finder: liveFinder, chrome: liveChrome, chatGPT: liveChatGPT,
                        codex: liveCodex, claude: liveClaude, quota: liveQuota, calendar: liveCalendar)
    }

    private func liveOn(_ app: LiveIconApp) -> Bool {
        liveApp == app && liveToggles.isOn(app)
    }

    /// Chrome、Safari 悬停轻转、Chrome 加载细弧（只给这两个格子挂，别的格子不多一层）；
    /// 访达的图标整张换成小熊猫访达（缺图时照常画系统图标）；日历的图标在今天有日程要倒数时
    /// 整张换成码头画的日历（液位、倒计时、换场转一圈），没权限或没日程时只画星期和日期。
    @ViewBuilder
    private var liveIcon: some View {
        if liveOn(.finder), LiveFinderPandaArt.available {
            LiveFinderPanda(side: geo.icon)
        } else if liveOn(.calendar) {
            LiveCalendarIcon(side: geo.icon)
        } else if let browser = browserApp {
            icon
                .frame(width: geo.icon, height: geo.icon)
                .modifier(LiveBrowserModifier(browser: browser, side: geo.icon,
                                              active: browserOn(browser) && !reduceMotion,
                                              enabled: browserOn(browser), isRunning: isRunning))
        } else if let badgeApp, liveIconsEnabled, badgeOn(badgeApp) {
            icon
                .frame(width: geo.icon, height: geo.icon)
                .modifier(LiveBadgeModifier(app: badgeApp, side: geo.icon, image: appIconImage))
        } else {
            icon
                .frame(width: geo.icon, height: geo.icon)
        }
    }

    /// 这个格子是不是 Chrome 或 Safari。
    private var browserApp: LiveBrowser? {
        guard case .app(_, let bundleID, _) = item else { return nil }
        return LiveBrowser(bundleID: bundleID)
    }

    private func browserOn(_ browser: LiveBrowser) -> Bool {
        switch browser {
        case .chrome: liveOn(.chrome)
        case .safari: liveIconsEnabled && liveSafari
        }
    }

    /// 这个格子是不是按未读数动的消息 App（信息、微信、邮件）。
    private var badgeApp: LiveBadgeApp? {
        guard case .app(_, let bundleID, _) = item else { return nil }
        return LiveBadgeApp(bundleID: bundleID)
    }

    private func badgeOn(_ app: LiveBadgeApp) -> Bool {
        switch app {
        case .messages: liveMessages
        case .wechat: liveWeChat
        case .mail: liveMail
        }
    }

    /// App 格子此刻画的那张图（含自定义图标），给消息未读换色用。
    private var appIconImage: NSImage? {
        guard case .app(_, let bundleID, let ref) = item else { return nil }
        let unlocked = licenseUnlocked || supporter
        if let url = ref.resolve() {
            return DockAppIconStore.shared.icon(for: bundleID, fallback: AppCatalog.shared.icon(for: url),
                                                unlocked: unlocked)
        }
        guard let image = AppCatalog.shared.icon(forBundleID: bundleID) else { return nil }
        return DockAppIconStore.shared.icon(for: bundleID, fallback: image, unlocked: unlocked)
    }

    @ViewBuilder
    private var tile: some View {
        ZStack {
            liveIcon
                .overlay {
                    if let app = liveApp, app == .chatGPT || app == .codex, liveToggles.isOn(app) {
                        // 水位开关关着时只剩 Codex 干活时的流光。
                        LiveOpenAIOverlay(side: geo.icon, tint: .of(app), showWater: liveToggles.showsQuota(app),
                                          showPercent: liveQuotaPercent)
                    } else if liveOn(.claude), liveToggles.showsQuota(.claude) {
                        LiveClaudeOverlay(side: geo.icon, showPercent: liveQuotaPercent)
                    }
                }
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
            // 只换画的图：卸载了的 App 照旧画成失效项，不拿自定义图标盖住。
            if let url = ref.resolve() {
                Image(nsImage: DockAppIconStore.shared.icon(for: bundleID, fallback: AppCatalog.shared.icon(for: url),
                                                            unlocked: licenseUnlocked || supporter))
                    .resizable()
                    .interpolation(.high)
            } else if let image = AppCatalog.shared.icon(forBundleID: bundleID) {
                Image(nsImage: DockAppIconStore.shared.icon(for: bundleID, fallback: image,
                                                            unlocked: licenseUnlocked || supporter))
                    .resizable()
                    .interpolation(.high)
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
