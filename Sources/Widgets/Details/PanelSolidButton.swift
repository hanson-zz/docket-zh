import SwiftUI

// MARK: - 面板实心主按钮

/// 面板里实心主按钮的样子（颜色约定和对比度见 Core 的 `PanelButtonLook`）：
/// 可用时实心底（默认 #2563EB）+ 白字；禁用时中性浅灰底（`panelFill`）加细边，
/// 字用次级字色（`panelSecondary`），浅色、深色下都过 4.5。
///
/// 用法：标签里只写字、字号和尺寸，不要自己挂 foregroundStyle 和 background：
///
///     Button(action: send) {
///         Text("发送").font(.system(size: 13, weight: .semibold))
///             .padding(.horizontal, 12).frame(height: 28)
///     }
///     .buttonStyle(PanelSolidButtonStyle())
///     .disabled(!canSend)
///
/// 自己画按钮样式，系统不会再给禁用的按钮整体变淡（plain 样式在 macOS 上会），
/// 禁用的样子完全由这里决定。按钮没有挂 `.disabled`、只是看起来不能点时
/// （比如刘海对话的发送键同时是停止键），传 `enabled`。
struct PanelSolidButtonStyle<S: InsettableShape>: ButtonStyle {
    var fill: Color
    var ink: Color
    var shape: S
    /// nil 时看环境里的 isEnabled（`.disabled(...)`）。
    var enabled: Bool?

    init(fill: Color = Color(hex: PanelButtonLook.solidBlueHex), ink: Color = .white,
         shape: S, enabled: Bool? = nil) {
        self.fill = fill
        self.ink = ink
        self.shape = shape
        self.enabled = enabled
    }

    func makeBody(configuration: Configuration) -> some View {
        PanelSolidButtonBody(configuration: configuration, fill: fill, ink: ink, shape: shape,
                             enabled: enabled)
    }
}

extension PanelSolidButtonStyle where S == Capsule {
    init(fill: Color = Color(hex: PanelButtonLook.solidBlueHex), ink: Color = .white,
         enabled: Bool? = nil) {
        self.init(fill: fill, ink: ink, shape: Capsule(), enabled: enabled)
    }
}

private struct PanelSolidButtonBody<S: InsettableShape>: View {
    var configuration: ButtonStyleConfiguration
    var fill: Color
    var ink: Color
    var shape: S
    var enabled: Bool?
    @Environment(\.isEnabled) private var environmentEnabled

    var body: some View {
        let on = enabled ?? environmentEnabled
        configuration.label
            .foregroundStyle(on ? ink : Color.panelSecondary)
            .background(shape.fill(on ? fill : Color.panelFill))
            .overlay(shape.strokeBorder(Color.panelSeparator.opacity(on ? 0 : 1), lineWidth: 0.6))
            .contentShape(shape)
            .opacity(on && configuration.isPressed ? 0.82 : 1)
    }
}

// MARK: - 面板小芯片

/// 玻璃小芯片（AI 提问那一排「剪贴板」「翻译」）：可用时主文字 0.85，禁用时三级字色
/// （`panelTertiary`，浅色约 3.6:1，深色约 4.2:1），比主按钮淡一档但认得出来。
/// 同样自己画，系统不再额外变淡。
struct PanelChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelChipButtonBody(configuration: configuration)
    }
}

private struct PanelChipButtonBody: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.panelPrimary.opacity(0.85) : Color.panelTertiary)
            .background(Capsule().fill(configuration.isPressed && isEnabled ? Color.panelSelected : Color.panelFill))
            .contentShape(Capsule())
    }
}
