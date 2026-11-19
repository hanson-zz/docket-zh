import SwiftUI

/// 设置 ▸ 扩展栏：动态图标。总开关默认关；打开后访达、Chrome、ChatGPT/Codex、Claude 各有子开关，默认都开。
struct LiveIconsSettingRow: View {
    @AppStorage(LiveIconToggles.masterKey) private var enabled = false
    @AppStorage(LiveIconToggles.finderKey) private var finder = true
    @AppStorage(LiveIconToggles.chromeKey) private var chrome = true
    @AppStorage(LiveIconToggles.openAIKey) private var openAI = true
    @AppStorage(LiveIconToggles.claudeKey) private var claude = true
    @AppStorage(LiveIconToggles.percentKey) private var percent = false

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("动态图标"))
                Text(tr("让扩展栏上几个 App 的图标本身动起来，只在有事发生时动。系统开了减弱动态效果时不转、不流动，低电量模式下放慢。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if enabled {
            Group {
                sub($finder, tr("访达"), tr("访达图标整张换成小熊猫：两颗眼珠跟着鼠标指针看，指针停下几秒后慢慢回正，隔几秒眨一下眼。"))
                sub($chrome, tr("Chrome"),
                    tr("当前标签页在加载时 Chrome 图标匀速转，加载完慢慢停回原位。需要允许码头控制 Chrome；不允许时只在启动那一下转一圈。"))
                sub($openAI, tr("ChatGPT/Codex"),
                    tr("图标里的水位是 Codex 还剩多少额度，取 5 小时和每周里更紧的那个，没有数据时不画；Codex 正在干活时一道白光沿图标边缘绕圈。"))
                sub($claude, tr("Claude"),
                    tr("图标里的水位是 Claude 还剩多少额度，取 5 小时和每周里更紧的那个。读本机 Claude 命令行已登录的账号，只读不上传，令牌只发给 Anthropic；没登录时不画。第一次读取时 macOS 可能弹框问是否允许码头使用钥匙串里的这一项。"))
                if openAI || claude {
                    Toggle(tr("水位旁显示剩余百分比"), isOn: $percent)
                        .padding(.leading, 20)
                }
            }
            .padding(.leading, 16)
        }
    }

    private func sub(_ value: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
