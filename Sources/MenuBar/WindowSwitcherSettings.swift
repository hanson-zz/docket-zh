import SwiftUI

/// 设置 ▸ 快捷键 ▸ 窗口切换（⌥Tab 按窗口切换，免费功能）。
///
/// 快捷键（默认 ⌥Tab，可改可清空，撞上 ⌘Tab 或码头里别的快捷键时提醒）、只显示当前桌面、
/// 按 App 分组、包含已最小化和已隐藏的窗口。缺辅助功能权限时说明不会生效并给去授权；
/// 缺屏幕录制权限时只在这里提示一句，卡片改画 App 大图标，运行时不弹授权。
struct WindowSwitcherSettingsSection: View {
    @Binding var state: PersistedState

    @State private var trusted = AppWindows.isTrusted
    @State private var canCapture = WindowPreviewSource.canCapture

    private var settings: Binding<WindowSwitcherSettings> { $state.windowSwitcher }

    /// 码头里别的全局快捷键，查重用。
    private var others: [KeyCombo?] {
        [state.aiNotch.hotKey, state.quickTodoHotKey, state.shotHotKeys.edit, state.shotHotKeys.translate]
            + state.profiles.map(\.shortcut)
    }

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 6) {
                    ShortcutRecorder(combo: state.windowSwitcher.hotKey) { state.windowSwitcher.hotKey = $0 }
                    if state.windowSwitcher.hotKey != nil {
                        Button("清除") { state.windowSwitcher.hotKey = nil }
                            .controlSize(.small)
                    } else {
                        Button(tr("恢复 ⌥Tab")) { state.windowSwitcher.hotKey = WindowSwitcherSettings.defaultHotKey }
                            .controlSize(.small)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("快捷键"))
                    Text(tr("按住 ⌥ 按 Tab 列出所有窗口，松开 ⌥ 切过去。清空后不启用。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let warning = WindowSwitcherHotKeyAdvice.warning(for: state.windowSwitcher.hotKey, others: others) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !trusted {
                permissionRow(tr("需要辅助功能权限才能列出和切换窗口，授权前快捷键不生效。"),
                              symbol: "exclamationmark.triangle.fill", tint: .orange) {
                    AppWindows.requestAccess()
                }
            }

            Toggle(tr("只显示当前桌面"), isOn: settings.currentDesktopOnly)
            Toggle(tr("按 App 分组"), isOn: settings.groupByApp)
            Toggle(tr("包含已最小化、已隐藏的窗口"), isOn: settings.includeMinimized)

            if trusted, !canCapture {
                permissionRow(tr("没有屏幕录制权限，卡片显示 App 大图标。授权后显示窗口缩略图。"),
                              symbol: "info.circle", tint: .secondary) {
                    WindowPreviewSource.requestCapture()
                }
            }

            Text(tr("⌘Tab 不受影响，系统的 App 切换照常用。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(tr("窗口切换"))
        }
        .onAppear(perform: recheck)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recheck()
        }
    }

    private func permissionRow(_ text: String, symbol: String, tint: Color,
                               grant: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(text, systemImage: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(tr("去授权"), action: grant)
                .controlSize(.small)
        }
    }

    /// 权限可能刚在系统设置里改过：刷新提示，也让切换器重新决定注不注册快捷键。
    private func recheck() {
        trusted = AppWindows.isTrusted
        canCapture = WindowPreviewSource.canCapture
        WindowSwitcherController.shared.refresh()
    }
}
