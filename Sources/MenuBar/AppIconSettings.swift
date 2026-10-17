import AppKit
import SwiftUI

/// 设置 ▸ 通用 ▸ 应用图标：每个图标一张可点选的缩略图卡片，选中的打勾。
struct AppIconSection: View {
    @AppStorage(AppIconCatalog.key) private var choice = AppIconCatalog.defaultOption.id
    @AppStorage(Supporter.key) private var supporter = false
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    private var unlocked: Bool { supporter || licenseUnlocked }
    @AppStorage("appIcon.finderFailed") private var finderFailed = false

    var body: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(AppIconCatalog.all) { option in
                    let locked = option.isSupporterOnly && !unlocked
                    AppIconCard(option: option,
                                selected: AppIconCatalog.shown(choice, unlocked: unlocked) == option,
                                locked: locked) {
                        guard !locked else { return }
                        AppIconSwitcher.choose(option)
                        choice = option.id
                    }
                }
                // 只有两张时别撑满整行，卡片保持方正。
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        } header: {
            Text("应用图标")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("访达“应用程序”文件夹、程序坞、应用切换器和设置的“关于”里都会换成所选图标。访达偶尔要过一会儿才刷新；启动台由系统缓存，可能要重新登录后才变。")
                    .foregroundStyle(.secondary)
                if finderFailed {
                    Text("访达里的图标没换成：码头所在的文件夹不可写。把码头放进“应用程序”文件夹后再选一次即可。")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppIconCard: View {
    let option: AppIconOption
    let selected: Bool
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: AppIconSwitcher.thumbnail(for: option))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .opacity(locked ? 0.45 : 1)
                HStack(spacing: 3) {
                    if locked {
                        Image(systemName: "lock.fill").font(.caption2)
                    }
                    Text(option.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(width: 112)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(locked ? "码头 Pro 专属图标，现在在“支持码头”窗口解锁，正式版推出后需要激活码解锁。" : option.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
