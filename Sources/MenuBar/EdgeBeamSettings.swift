import SwiftUI

/// 设置 ▸ 小组件 ▸「沿边流光」：AI 生成中、AI 输入框聚焦、专注进行中时，
/// 卡片边缘绕一道细光。默认开，免费。规则在 Core 的 `EdgeBeam`。
struct EdgeBeamSettingsSection: View {
    @AppStorage(EdgeBeam.enabledKey) private var enabled = EdgeBeam.defaultEnabled

    var body: some View {
        Section("状态提示") {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("沿边流光")
                    Text("AI 正在生成、AI 输入框聚焦、专注计时进行中时，卡片边缘绕一道细细的光，颜色跟随小组件外观。开启「减弱动态效果」或低电量模式时只显示静止的光。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
