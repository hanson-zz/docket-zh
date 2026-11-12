import AppKit
import SwiftUI

// 应用切换器 v2 的窗口一排和中性按钮（效果图 design/app-switcher-v2.py），
// 大号桌面卡片和面板展开区共用。
//
// - 有辅助功能和屏幕录制权限：一排窗口缩略图（第一张垫浅色高亮块），点一张跳到那个窗口。
//   截图走 `AppWindowThumbnails`（缓存、一次一批），这里只在窗口列表变了时要图，重画不截。
// - 没屏幕录制权限：改列窗口标题，下面一行「看缩略图需要「屏幕录制」权限」和「去授权」。
// - 没辅助功能权限：沿用原来的说明「列出窗口需要辅助功能权限」和「去授权」。

/// 中性的小按钮（「切到前台」「去授权」）：浅色实心白加淡阴影，深色实心灰（#50535E），
/// 都不用主题色，深色下也看得清。
struct AppSwitcherButtonLabel: View {
    var title: String
    var height: CGFloat = 26

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(verbatim: title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(Capsule()
                .fill(dark ? Color(red: 0.314, green: 0.325, blue: 0.369) : Color.white.opacity(0.95))
                .panelLift())
            .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                                            lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// 排序胶囊和「编辑 / 完成」：选中的是中性浅色块（浅色近白加淡阴影，深色白 88% 配深字），
/// 没选中的是薄玻璃填充。
struct AppSwitcherChipLabel: View {
    var title: String
    var on: Bool
    var height: CGFloat = 30

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Text(verbatim: title)
            .font(.system(size: 13, weight: on ? .bold : .semibold))
            .foregroundStyle(on && dark ? Color(red: 0.082, green: 0.086, blue: 0.11) : Color.panelPrimary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background {
                if on {
                    if dark {
                        Capsule().fill(Color.white.opacity(0.88))
                    } else {
                        Capsule().fill(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.13), radius: 4, y: 2)
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
                    }
                } else {
                    Capsule().fill(Color.panelFill)
                        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.6))
                }
            }
            .contentShape(Capsule())
    }
}

/// 一张窗口缩略图：画面框（截图按比例放进去，还没截好时淡淡画 App 图标，最小化的不截）
/// 和下面 13pt 的标题。`highlighted` 时整张垫浅色高亮块，悬停垫淡一档。
struct AppSwitcherWindowThumb: View {
    var window: AppWindows.Window
    var app: AppSwitcherItem
    var width: CGFloat
    var height: CGFloat
    var highlighted: Bool
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private var thumbnails: AppWindowThumbnails { AppWindowThumbnails.shared }

    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(dark ? Color(red: 0.227, green: 0.235, blue: 0.27)
                                   : Color(red: 0.914, green: 0.918, blue: 0.933))
                    if !window.minimized, let image = thumbnails.image(for: window) {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(3)
                    } else {
                        AppSwitcherIcon(app: app, size: min(28, height * 0.4))
                            .opacity(window.minimized ? 0.6 : 0.35)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10), lineWidth: 1))

                Text(verbatim: window.title)
                    .font(.system(size: 13, weight: highlighted ? .semibold : .medium))
                    .foregroundStyle(highlighted ? Color.panelPrimary : Color.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: width)
            }
            .padding(5)
            .background {
                if highlighted || hovering {
                    AppSwitcherHighlight(cornerRadius: 12, strength: highlighted ? 1 : 0.55)
                }
            }
            .padding(-5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(window.title)
        .accessibilityLabel(tr("跳到窗口：\(window.title)"))
    }
}

/// 一个 App 的窗口一排，按权限三种样子（见文件顶上的说明）。
struct AppSwitcherWindowStrip: View {
    enum Style {
        /// 大号桌面卡片：最多 3 张 96×76，标题最多列 2 个。
        case card
        /// 面板展开区：按宽度平分（92 到 124），放不下横向滚动，标题最多列 6 个。
        case panel
    }

    var app: AppSwitcherItem
    var windows: [AppWindows.Window]
    var trusted: Bool
    var canCapture: Bool
    var style: Style
    /// 这一排能用多宽。
    var width: CGFloat
    var onFocus: (AppWindows.Window) -> Void

    private var thumbnails: AppWindowThumbnails { AppWindowThumbnails.shared }

    /// 窗口列表变了（或权限变了）才要图，重画不截。
    private var signature: String {
        (canCapture ? "1|" : "0|") + windows.map { AppWindowThumbnails.key($0) }.joined(separator: ";")
    }

    var body: some View {
        content
            .task(id: signature) {
                guard canCapture, trusted else { return }
                thumbnails.request(Array(windows.prefix(style == .card ? 3 : WindowPreview.maxWindows)))
            }
    }

    @ViewBuilder
    private var content: some View {
        if !trusted {
            permissionRow(tr("列出窗口需要辅助功能权限")) { AppWindows.requestAccess() }
        } else if windows.isEmpty {
            Text("没有打开的窗口")
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .frame(maxWidth: .infinity, minHeight: 28)
        } else if !canCapture {
            titleList
        } else {
            thumbRow
        }
    }

    // MARK: 缩略图

    @ViewBuilder
    private var thumbRow: some View {
        switch style {
        case .card:
            let shown = Array(windows.prefix(3))
            HStack(spacing: 10) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, window in
                    thumb(window, index: index, width: 96, height: 76)
                }
            }
            .frame(maxWidth: .infinity)
        case .panel:
            let shown = Array(windows.prefix(WindowPreview.maxWindows))
            let fit = AppSwitcherLayout.thumbWidth(count: shown.count, available: Double(width))
            let w = CGFloat(fit.width), h = CGFloat((fit.width * AppSwitcherLayout.thumbAspect).rounded())
            let row = HStack(spacing: CGFloat(AppSwitcherLayout.thumbSpacing)) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, window in
                    thumb(window, index: index, width: w, height: h)
                }
            }
            .padding(5)
            if fit.scrolls {
                ScrollView(.horizontal) { row }
                    .scrollIndicators(.never)
                    .padding(.horizontal, -5)
            } else {
                row
                    .padding(.horizontal, -5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func thumb(_ window: AppWindows.Window, index: Int, width: CGFloat, height: CGFloat) -> some View {
        AppSwitcherWindowThumb(window: window, app: app, width: width, height: height,
                               highlighted: index == 0) { onFocus(window) }
    }

    // MARK: 没屏幕录制权限

    private var titleList: some View {
        let limit = style == .card ? 2 : 6
        let shown = Array(windows.prefix(limit))
        let more = windows.count - shown.count
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, window in
                Button { onFocus(window) } label: {
                    Text(verbatim: window.title)
                        .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(index == 0 ? Color.panelPrimary : Color.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .background {
                            if index == 0 { AppSwitcherHighlight(cornerRadius: 9) }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(window.title)
            }
            if more > 0 {
                Text(verbatim: tr("还有 \(more) 个窗口"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .padding(.horizontal, 10)
            }
            permissionRow(tr("看缩略图需要「屏幕录制」权限")) { AppWindows.requestCapture() }
                .padding(.top, 4)
        }
    }

    // MARK: 权限

    private func permissionRow(_ text: String, grant: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: text)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: grant) {
                AppSwitcherButtonLabel(title: tr("去授权"))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 28)
    }
}
