import SwiftUI

/// 扩展栏上的 Pro 小组件在没解锁时盖的一层：小锁加“Pro 专属 · 解锁”，点一下弹付费墙。
///
/// 试用结束后小组件不删除，只是盖住，解锁后自动揭开。要不要盖由
/// `ProLicenseGate.needsLockOverlay` 决定；两个 `@AppStorage` 让试用到期、
/// 激活或解绑时立刻重画。
struct ProLockOverlay: ViewModifier {
    var instance: WidgetInstance
    var isPreview: Bool

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    func body(content: Content) -> some View {
        let locked = ProLicenseGate.needsLockOverlay(instance, unlocked: licenseUnlocked || supporter,
                                                     isPreview: isPreview)
        content
            .blur(radius: locked ? 3 : 0)
            .opacity(locked ? 0.55 : 1)
            .allowsHitTesting(!locked)
            .overlay {
                if locked {
                    Button { PaywallWindow.shared.show() } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(ProLicenseGate.lockTitle)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: ShelfColor.redPanda.hex).opacity(0.9)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("码头 Pro 专属。点一下购买、输入激活码或开始试用。")
                    .accessibilityLabel(ProLicenseGate.lockTitle)
                }
            }
    }
}

extension View {
    /// 没解锁时给 Pro 小组件盖小锁遮罩。
    func proLocked(_ instance: WidgetInstance, isPreview: Bool = false) -> some View {
        modifier(ProLockOverlay(instance: instance, isPreview: isPreview))
    }
}
