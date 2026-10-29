import AppKit
import SwiftUI

/// 自己打开系统颜色面板（`NSColorPanel`），代替 SwiftUI 的 `ColorPicker`。
///
/// 卡片详情面板是不激活 App 的面板，层级在程序坞之上（`dockWindow + 2`）。
/// 在里面点 `ColorPicker`：码头没在前台，颜色面板默认失去前台就藏起来，
/// 就算出来了也是 `.floating` 层级，被详情面板和程序坞压在下面，看起来就是
/// 「点了没反应、不能选」。这里打开前先激活 App，把颜色面板的层级放到点击
/// 所在窗口之上，失去前台也不藏，选的颜色连续写回。
///
/// 同一时间只有一个使用者：换了使用者、详情面板关掉或换到别的卡片时调用
/// `closeIfOwned()`，旧的回调不再收到颜色，免得写到别的卡片上。
@MainActor
final class SystemColorPanel: NSObject {
    static let shared = SystemColorPanel()

    private var onPick: ((Color) -> Void)?
    private var owned = false

    /// 打开颜色面板。`initial` 是面板里先选中的颜色；`onPick` 在用户每次改颜色时调用。
    func open(initial: Color, onPick: @escaping (Color) -> Void) {
        let panel = NSColorPanel.shared
        // 先断开旧的目标再设初始颜色，设颜色不会回调给任何人。
        panel.setTarget(nil)
        panel.setAction(nil)
        self.onPick = nil
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.hidesOnDeactivate = false
        panel.color = NSColor(initial)
        panel.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        // 放到点击所在的窗口（详情面板或设置窗口）之上，至少 `.floating`。
        let host = NSApp.currentEvent?.window ?? NSApp.keyWindow
        let base = max(host?.level.rawValue ?? 0, NSWindow.Level.floating.rawValue)
        panel.level = NSWindow.Level(rawValue: base + 1)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        self.onPick = onPick
        owned = true
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// 颜色面板还是这里打开的：断开回调、收起面板、层级放回 `.floating`。
    func closeIfOwned() {
        guard owned else { return }
        owned = false
        onPick = nil
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
        panel.level = .floating
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard owned, let onPick else { return }
        onPick(Color(nsColor: sender.color))
    }
}

/// 一个彩虹圆的小按钮，点了用 `SystemColorPanel` 打开系统颜色面板。
/// 给详情面板里原来放 `ColorPicker` 的地方用。
struct SystemColorWell: View {
    /// 打开面板时先选中的颜色。
    var color: Color
    var size: CGFloat = 18
    var help: String = tr("自定义颜色")
    var onPick: (Color) -> Void

    var body: some View {
        Button {
            SystemColorPanel.shared.open(initial: color, onPick: onPick)
        } label: {
            Circle()
                .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                                      center: .center))
                .frame(width: size, height: size)
                .overlay {
                    Circle().fill(color)
                        .frame(width: size * 0.45, height: size * 0.45)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                }
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                .padding(2)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
