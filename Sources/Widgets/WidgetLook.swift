import Observation
import SwiftUI

/// 通用的小组件外观（设置 ▸ 通用 ▸ 小组件外观）：颜色、背景、色调强度、文字颜色。
/// 没单独设置的小组件都跟它走（判断在 Core `WidgetTint.followsGlobal`）。
/// 存在偏好设置里；改了以后所有卡片和面板跟着重画（`WidgetTile`、面板外框读 `config`）。
@MainActor @Observable
final class WidgetLook {
    static let shared = WidgetLook()

    private static let defaultsKey = "widgetLookGlobal"

    private(set) var config: WidgetConfig

    private init() {
        let saved = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(WidgetConfig.self, from: $0) } ?? WidgetConfig()
        config = saved
        WidgetTint.global = saved
    }

    /// 启动时调一次，让 Core 在第一张卡片画出来之前就拿到通用外观。
    func load() { _ = config }

    func update(_ change: (inout WidgetConfig) -> Void) {
        var next = config
        change(&next)
        // 通用这份自己永远不算「单独设置」。
        next.set(WidgetTint.ownKey, nil)
        guard next != config else { return }
        WidgetTint.global = next
        config = next
        if let data = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// 通用外观在设置里预览、取色用的示意卡片。
    static let sampleKind: WidgetKind = .countdown
    static let sampleID = UUID()
}

/// 设置 ▸ 通用 里的「小组件外观」：一份颜色与背景给所有小组件，单个小组件可以在
/// 设置 ▸ 小组件 里关掉「跟随通用外观」再单独调。
struct WidgetLookSection: View {
    private var look = WidgetLook.shared

    var body: some View {
        Section("小组件外观") {
            WidgetTintPicker(instance: WidgetInstance(id: WidgetLook.sampleID, kind: WidgetLook.sampleKind, config: look.config),
                             isGlobal: true) { change in
                look.update(change)
            }
            // 扩展栏底板不归这里管，说清楚在哪，免得以为和底板颜色重复。
            Text("扩展栏底板颜色在 设置 ▸ 扩展栏 ▸ 外观。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
