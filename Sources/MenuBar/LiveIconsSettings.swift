import SwiftUI

/// 设置 ▸ 扩展栏：动态图标。默认关，打开后访达悬停冒出小脸、Chrome 启动时转一圈。
struct LiveIconsSettingRow: View {
    @AppStorage("liveIcons.enabled") private var enabled = false

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("动态图标"))
                Text(tr("鼠标停在访达上冒出一张跟着看你的小脸，Chrome 启动时图标转一圈。系统开了减弱动态效果时不转。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
