import SwiftUI

/// 设置 ▸ 小组件 ▸「桌面卡片」：总开关、所有桌面 / 仅当前桌面、窗口盖住时、外观，
/// 已钉几张和「排列…」「全部取消钉」。
///
/// 免费钉 1 张、小 / 中两档；第 2 张起和大号是码头 Pro（见 `DesktopPinGate`）。
struct DesktopPinSettingsSection: View {
    @Binding var state: PersistedState

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var unlocked: Bool { licenseUnlocked || supporter }
    private var pins: Binding<DesktopPinSettings> { $state.desktopPins }

    var body: some View {
        Section {
            Toggle(isOn: pins.enabled) {
                subtitled(tr("钉在桌面"), tr("把扩展栏里的卡片拖到桌面，或右键选「钉在桌面」。关掉后桌面卡片全部收起，位置记着。"))
            }
            if state.desktopPins.enabled {
                Picker(selection: pins.spaces) {
                    Text(tr("所有桌面")).tag(DesktopPinSpaces.all)
                    Text(tr("仅当前桌面")).tag(DesktopPinSpaces.current)
                } label: {
                    subtitled(tr("显示在"), tr("所有桌面：切换桌面（空间）时卡片跟着走。全屏 App 的桌面上不显示。"))
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker(selection: pins.covered) {
                    Text(tr("照常留在窗口后")).tag(DesktopPinCovered.stay)
                    Text(tr("自动隐藏")).tag(DesktopPinCovered.autoHide)
                } label: {
                    subtitled(tr("窗口盖住桌面时"), tr("自动隐藏：被窗口盖住时收起，窗口挪开或最小化后再出现。"))
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker(selection: pins.appearance) {
                    Text(tr("跟随系统")).tag(AppAppearance.system)
                    Text(tr("浅色")).tag(AppAppearance.light)
                    Text(tr("深色")).tag(AppAppearance.dark)
                } label: {
                    subtitled(tr("外观"), tr("跟随码头的外观设置，也可以单独选。"))
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            LabeledContent {
                HStack(spacing: 8) {
                    Button(tr("排列…")) { DesktopPinController.shared.setEditing(true) }
                        .disabled(state.desktopPins.pins.isEmpty || !state.desktopPins.enabled)
                    Button(tr("全部取消钉"), role: .destructive) { DesktopPinController.shared.unpinAll() }
                        .disabled(state.desktopPins.pins.isEmpty)
                }
            } label: {
                subtitled(tr("已钉 \(state.desktopPins.pins.count) 张"), pinnedSummary)
            }
        } header: {
            Text(tr("桌面卡片"))
        } footer: {
            if !unlocked {
                HStack(spacing: 6) {
                    Text(tr("大尺寸和第 2 张起的卡片需要码头 Pro。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button { PaywallWindow.shared.show() } label: { ProBadge() }
                        .buttonStyle(.plain)
                        .help(ProFeatures.help)
                }
            }
        }
    }

    /// 「算（大）、快速待办（中）、时钟（小）」；一张没钉时说怎么钉。
    private var pinnedSummary: String {
        let settings = state.desktopPins
        guard !settings.pins.isEmpty else { return tr("还没有钉在桌面的卡片。") }
        let widgets = state.profiles.flatMap { DockItemTree.widgets(in: $0.items) }
        return settings.summary { pin in
            let kind = widgets.first { $0.id == pin.widgetID }?.kind
            return kind.flatMap { WidgetCatalog.entry($0)?.name } ?? tr("小组件")
        }
    }

    private func subtitled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
