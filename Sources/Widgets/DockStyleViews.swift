import AppKit
import SwiftUI

// 全局视觉规矩的画法。数字和规则在 Core 的 `DockMetrics`、`TileState`、
// `TilePermission`、`PandaEmpty`，这里只负责把它们画出来，每张卡片
// 用同一套修饰器，不再各写一份。

extension WidgetStyle {
    /// 主数字：24pt 粗体。
    static var figure: Font { value(DockMetrics.figureSize) }
    /// 标题：13pt 半粗。
    static var title: Font { label(DockMetrics.titleSize) }
    /// 说明：11pt 常规。
    static var note: Font { caption(DockMetrics.captionSize) }

    /// 拖入态的系统蓝，浅色外观用深一点的那档。
    static func dropBlue(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? DockMetrics.dropBlueDark : DockMetrics.dropBlueLight)
    }
}

// MARK: - 拖入态

/// 拖入时的颜色，颜色就是结果：系统蓝是发出去（隔空投送、翻译），红是扔进
/// 废纸篓，青是先暂存，橙是记成待办。数值在 Core 的 `DropPrompt.Tint`。
enum DropTint {
    case blue, destructive, teal, orange

    init(_ tint: DropPrompt.Tint) {
        switch tint {
        case .blue: self = .blue
        case .red: self = .destructive
        case .teal: self = .teal
        case .orange: self = .orange
        }
    }

    var core: DropPrompt.Tint {
        switch self {
        case .blue: .blue
        case .destructive: .red
        case .teal: .teal
        case .orange: .orange
        }
    }

    func color(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? core.darkHex : core.lightHex)
    }
}

extension View {
    /// 拖着东西停在卡片上时的虚线框，底下垫一层很淡的同色。
    ///
    /// 从隔空投送卡片抽出来的，文件暂存、废纸篓、快速待办、翻译和它们的面板都用
    /// 这一个，拖入的样子全货架一致。`corner` 默认是卡片圆角，面板里的投放区可以
    /// 传自己的。
    ///
    /// 给了 `prompt` 时框里还写明放下去会怎样：同色的图标，第一行结果，第二行
    /// 数量或后果，颜色跟着 `prompt` 走。卡片自己的内容要用 `dropHidden` 让开，
    /// 松手后回到平时的样子。`compact` 是竖排或窄卡：图标在上，结果拆两行。
    func dropTargetOutline(_ active: Bool, tint: DropTint = .blue,
                           corner: CGFloat = WidgetStyle.corner,
                           prompt: DropPrompt? = nil, compact: Bool = false) -> some View {
        overlay {
            DropTargetOutline(active: active, tint: prompt.map { DropTint($0.tint) } ?? tint,
                              corner: corner, prompt: prompt, compact: compact)
        }
    }

    /// 拖入提示出现时把卡片自己的内容藏起来（只淡掉内容，卡片底还在）。
    func dropHidden(_ active: Bool) -> some View {
        opacity(active ? 0 : 1)
            .dockAnimation(.snappy(duration: 0.15), value: active)
    }

    /// 禁用：内容降透明度。
    func tileDisabled(_ disabled: Bool) -> some View {
        opacity(disabled ? DockMetrics.disabledOpacity : 1)
    }

    /// 缺权限：卡片右上角一把小锁，点按去开启（能弹系统授权框的先弹，
    /// 否则打开“系统设置”里对应的隐私页）。`permission` 为 nil 时什么都不画。
    func permissionLock(_ permission: String?, preview: Bool = false) -> some View {
        overlay(alignment: .topTrailing) {
            if let permission, !preview {
                PermissionLockButton(permission: permission)
                    .padding(6)
            }
        }
    }

    /// 动画，但打开“减少动态效果”时换成很短的淡入淡出。
    func dockAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(DockAnimation(animation: animation, value: value))
    }
}

private struct DockAnimation<V: Equatable>: ViewModifier {
    var animation: Animation
    var value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion
                              ? .easeInOut(duration: TileState.transitionDuration(reduceMotion: true))
                              : animation,
                          value: value)
    }
}

struct DropTargetOutline: View {
    var active: Bool
    var tint: DropTint = .blue
    var corner: CGFloat = WidgetStyle.corner
    var prompt: DropPrompt?
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = tint.color(scheme)
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color.opacity(tint.core.fillOpacity(dark: scheme == .dark)))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(color.opacity(DockMetrics.dropStrokeOpacity),
                                  style: StrokeStyle(lineWidth: DockMetrics.dropLineWidth,
                                                     dash: DockMetrics.dropDash.map { CGFloat($0) }))
            }
            .overlay {
                if let prompt {
                    DropPromptLabel(prompt: prompt, color: color, compact: compact)
                }
            }
            .opacity(active ? 1 : 0)
            .dockAnimation(.snappy(duration: 0.15), value: active)
            .allowsHitTesting(false)
            .accessibilityHidden(!active)
    }
}

/// 虚线框里的字：同色图标，结果一行，数量或后果一行。
private struct DropPromptLabel: View {
    var prompt: DropPrompt
    var color: Color
    var compact: Bool

    var body: some View {
        Group {
            if compact {
                VStack(spacing: 3) {
                    badge(size: WidgetStyle.badgeColumn)
                    Text(prompt.compactTitle)
                        .font(WidgetStyle.label(11))
                        .foregroundStyle(color)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4)
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.title)
                            .font(WidgetStyle.label(15))
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(prompt.caption)
                            .font(WidgetStyle.note)
                            .foregroundStyle(WidgetStyle.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, WidgetStyle.inset)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func badge(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: CGFloat(DockMetrics.badgeCorner(Double(size))), style: .continuous)
                .fill(color.opacity(0.18))
            if case .airDrop(_) = prompt {
                AirDropGlyph()
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.4, size * 0.05), lineCap: .round))
                    .frame(width: size * 0.56, height: size * 0.56)
                    .overlay {
                        Circle()
                            .fill(color)
                            .frame(width: size * 0.1, height: size * 0.1)
                            .offset(y: size * 0.56 * 0.08)
                    }
            } else {
                Image(systemName: prompt.symbol)
                    .font(.system(size: size * CGFloat(DockMetrics.badgeGlyphRatio), weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 缺权限

/// 卡片角上的小锁。
struct PermissionLockButton: View {
    var permission: String

    var body: some View {
        Button {
            Task { @MainActor in await OnboardingPermissions.request(permission) }
        } label: {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WidgetStyle.secondary)
                .frame(width: 16, height: 16)
                .background(WidgetStyle.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(TilePermission.prompt(permission))
        .accessibilityLabel(TilePermission.accessibilityLabel(permission))
    }
}

/// 卡片正文里的一行：小锁加「需要 xx 权限 · 去开启」，整行可点。
struct PermissionLockNote: View {
    var permission: String
    var compact = false
    /// 竖排时锁在上、字在下。
    var stacked = false
    var preview = false

    var body: some View {
        Button {
            guard !preview else { return }
            Task { @MainActor in await OnboardingPermissions.request(permission) }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(preview)
        .help(TilePermission.prompt(permission))
        .accessibilityLabel(TilePermission.accessibilityLabel(permission))
    }

    @ViewBuilder
    private var label: some View {
        let text = TilePermission.prompt(permission, compact: compact)
        if stacked {
            VStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(WidgetStyle.caption(10))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(WidgetStyle.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .contentShape(.rect)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(text)
                    .font(WidgetStyle.note)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(WidgetStyle.secondary)
            .contentShape(.rect)
        }
    }
}

// MARK: - 空状态的小熊猫

/// 小熊猫的图，读一次就留着。
@MainActor
enum PandaArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard !missing.contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }
}

/// 空状态放在方底里的小熊猫。图读不到时退回给定的符号，卡片不会空一块。
struct PandaEmptyBadge: View {
    var empty: PandaEmpty
    var size: CGFloat
    var fallback: String

    var body: some View {
        if let image = PandaArt.image(empty.imageName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.08)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * DockMetrics.badgeGlyphRatio, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
        }
    }
}

/// 大面板和小卡共用同一张小熊猫，放不下时依次让说明和插图让位给可执行按钮。
struct PandaEmptyState: View {
    var empty: PandaEmpty
    var title: String
    var compact = false
    var panel = false
    var action: () -> Void

    private var badge: some View {
        PandaEmptyBadge(empty: empty, size: panel ? 64 : 32, fallback: "plus")
            .frame(width: panel ? 64 : 32, height: panel ? 64 : 32)
    }

    private var button: some View {
        Button(action: action) { Text(title).fixedSize() }
            .buttonStyle(.plain)
            .font(.system(size: panel ? 12 : 10, weight: .semibold))
            .foregroundStyle(panel ? .white : WidgetStyle.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.12), in: Capsule())
    }

    var body: some View {
        ViewThatFits {
            if panel || compact {
                VStack(spacing: panel ? 8 : 3) {
                    badge
                    Text(empty.line(compact: compact))
                        .font(.system(size: panel ? 12 : 10))
                        .foregroundStyle(panel ? .white.opacity(0.75) : WidgetStyle.secondary)
                        .fixedSize()
                    button
                }
                .fixedSize()
            } else {
                HStack(spacing: 8) {
                    badge
                    VStack(alignment: .leading, spacing: 3) {
                        Text(empty.line()).font(.system(size: 11)).fixedSize()
                        button
                    }
                }
                .fixedSize()
            }
            button.fixedSize()
            Button(action: action) { Image(systemName: "plus.circle.fill").font(.system(size: 18)) }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .help(title)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: panel ? nil : .infinity)
    }
}

struct PandaEmptyTile: View {
    var empty: PandaEmpty
    var title: String
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        PandaEmptyState(empty: empty, title: title, compact: context.position.isVertical) {
            guard !context.isPreview else { return }
            WidgetDetailWindow.shared.openFloating(WidgetWriter.current(instance.id) ?? instance, now: context.now)
        }
    }
}

// MARK: - 常量的 CGFloat 版本

extension WidgetStyle {
    /// 横排卡片打头的方底（40pt）。
    static let badge = CGFloat(DockMetrics.badge)
    /// 小一号的方底（34pt）。
    static let badgeCompact = CGFloat(DockMetrics.badgeCompact)
    /// 竖排货架里的方底（32pt）。
    static let badgeColumn = CGFloat(DockMetrics.badgeColumn)
    /// 卡片里嵌套小块的圆角。
    static let innerCorner = CGFloat(DockMetrics.innerCorner)
    /// 方底和右边文字之间。
    static let rowSpacing = CGFloat(DockMetrics.rowSpacing)
    /// 竖排时方底和下面文字之间。
    static let columnSpacing = CGFloat(DockMetrics.columnSpacing)
}
