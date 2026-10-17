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

/// 拖入时的颜色：默认是隔空投送那种系统蓝；废纸篓扔东西是删除，用红。
enum DropTint {
    case blue, destructive

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .blue: WidgetStyle.dropBlue(scheme)
        case .destructive: scheme == .dark ? Color(hex: "#FF453A") : Color(hex: "#FF3B30")
        }
    }
}

extension View {
    /// 拖着东西停在卡片上时的虚线框，底下垫一层很淡的同色。
    ///
    /// 从隔空投送卡片抽出来的，文件暂存、废纸篓、翻译和它们的面板都用这一个，
    /// 拖入的样子全货架一致。`corner` 默认是卡片圆角，面板里的投放区可以传自己的。
    func dropTargetOutline(_ active: Bool, tint: DropTint = .blue,
                           corner: CGFloat = WidgetStyle.corner) -> some View {
        overlay { DropTargetOutline(active: active, tint: tint, corner: corner) }
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = tint.color(scheme)
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color.opacity(scheme == .dark ? DockMetrics.dropFillDark : DockMetrics.dropFillLight))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(color.opacity(DockMetrics.dropStrokeOpacity),
                                  style: StrokeStyle(lineWidth: DockMetrics.dropLineWidth,
                                                     dash: DockMetrics.dropDash.map { CGFloat($0) }))
            }
            .opacity(active ? 1 : 0)
            .dockAnimation(.snappy(duration: 0.15), value: active)
            .allowsHitTesting(false)
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
