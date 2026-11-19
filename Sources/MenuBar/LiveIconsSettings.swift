import SwiftUI

/// 设置 ▸ 扩展栏：动态图标。总开关默认关；打开后访达、Chrome 各有子开关，
/// 下面是「AI 额度水位」：一个总开关，ChatGPT、Claude、Codex 三个勾选，
/// 和「显示：」5 小时 / 每周 / 取更紧的（默认取更紧的）。
struct LiveIconsSettingRow: View {
    @AppStorage(LiveIconToggles.masterKey) private var enabled = false
    @AppStorage(LiveIconToggles.finderKey) private var finder = true
    @AppStorage(LiveIconToggles.chromeKey) private var chrome = true
    @AppStorage(LiveIconToggles.openAIKey) private var chatGPT = true
    @AppStorage(LiveIconToggles.codexKey) private var codex = true
    @AppStorage(LiveIconToggles.claudeKey) private var claude = true
    @AppStorage(LiveIconToggles.quotaKey) private var quota = true
    @AppStorage(LiveIconToggles.percentKey) private var percent = true
    @AppStorage(LiveQuotaPreference.key) private var window = LiveQuotaPreference.default.rawValue

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
                sub($quota, tr("AI 额度水位"),
                    tr("ChatGPT、Claude、Codex 图标下部灌水，水位是还剩多少额度，没有数据时不画；鼠标停在图标上时，名称下面显示多久后重置。ChatGPT 和 Codex 共用同一份 Codex 额度数据。"))
                VStack(alignment: .leading, spacing: 6) {
                    aiApp($chatGPT, "ChatGPT", bundleID: LiveIconApp.chatGPTBundleID)
                    aiApp($claude, "Claude", bundleID: LiveIconApp.claudeBundleID)
                    aiApp($codex, "Codex", bundleID: LiveIconApp.codexBundleIDs[0])
                    Text(tr("勾掉的 App 图标不动。Codex 正在干活时，ChatGPT 和 Codex 图标边缘有一道白光绕圈。Claude 读本机 Claude 命令行已登录的账号，只读不上传，令牌只发给 Anthropic；没登录时不画。第一次读取时 macOS 可能弹框问是否允许码头使用钥匙串里的这一项。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 20)
                if quota && (chatGPT || claude || codex) {
                    Picker(selection: $window) {
                        Text(tr("5 小时")).tag(LiveQuotaPreference.session.rawValue)
                        Text(tr("每周")).tag(LiveQuotaPreference.weekly.rawValue)
                        Text(tr("取更紧的")).tag(LiveQuotaPreference.tighter.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("显示："))
                            Text(tr("取更紧的：哪个窗口剩得少就看哪个。固定 5 小时或每周时，那个窗口没有数据就不画。"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.leading, 20)
                    Toggle(tr("水位左下角显示剩余百分比"), isOn: $percent)
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

    /// 一个 AI App 的勾选：App 自己的图标（没装时不画）、名字、行尾勾选框。
    private func aiApp(_ value: Binding<Bool>, _ name: String, bundleID: String) -> some View {
        HStack(spacing: 8) {
            if let image = AppCatalog.shared.icon(forBundleID: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            Text(verbatim: name)
            Spacer(minLength: 8)
            Toggle(name, isOn: value)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
    }
}
