import SwiftUI

/// 相册和壁纸两个面板共用的小零件，照效果图：标题 19pt 粗体、副标题 13pt、
/// 右上 28pt 高的胶囊、36pt 高的三个控制键（主键实心配深色字）、13pt 的小标题、
/// 34pt 高的分段、44pt 高的开关行。

/// 面板头部：大标题、可选的 Pro 标、副标题，右边一个按钮。
struct AlbumHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var titlePro = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text(verbatim: title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white.opacity(0.97))
                    if titlePro { AlbumProTag() }
                }
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                        .truncationMode(.middle)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

/// 右上角 28pt 高的胶囊：“设置”“自动换”是浅色玻璃，“完成”是实心强调色配深色字。
struct AlbumHeaderButton: View {
    var title: String
    var solid = false
    var accent: Color = .white
    var ink: Color = .black
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? ink : .white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, solid ? 15 : 13)
                .frame(height: 28)
                .background(Capsule().fill(solid ? accent : .white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(solid ? 0 : 0.18), lineWidth: 0.6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// 36pt 高的控制键：上一张、暂停、下一张这一排。主键实心配深色字。
struct AlbumControlButton: View {
    var title: String
    var symbol: String?
    var prominent = false
    var accent: Color
    var ink: Color
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(verbatim: title)
                    .font(.system(size: 14, weight: prominent ? .bold : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? ink : .white.opacity(0.94))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(prominent ? accent : .white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.18), lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}

/// 13pt 的小标题，右边可选一段说明或一个文字按钮。
struct AlbumSection: View {
    var label: String
    var right: String?
    var rightColor: Color?
    var rightAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let right {
                if let rightAction {
                    Button(action: rightAction) {
                        Text(verbatim: right)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(rightColor ?? .white.opacity(0.62))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(verbatim: right)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rightColor ?? .white.opacity(0.62))
                }
            }
        }
        .lineLimit(1)
    }
}

/// 34pt 高的分段：选中的一格实心强调色配深色字。`selected` 为 nil 时一格都不亮。
struct AlbumSegmented: View {
    var labels: [String]
    var selected: Int?
    var accent: Color
    var ink: Color
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                let on = index == selected
                Button { onSelect(index) } label: {
                    Text(verbatim: labels[index])
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? ink : .white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Capsule().fill(on ? accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(height: 34)
        .background(Capsule().fill(.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
    }
}

/// 一行开关：玻璃底，标题 14pt，可选一行 13pt 的说明。
struct AlbumToggleRow<Note: View>: View {
    var label: String
    var sub: String?
    var isOn: Bool
    var accent: Color
    var enabled = true
    var set: (Bool) -> Void
    @ViewBuilder var note: () -> Note

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                if let sub {
                    Text(verbatim: sub)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                note()
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch)
                .tint(accent)
                .labelsHidden()
                .disabled(!enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, sub == nil ? 0 : 9)
        .frame(minHeight: sub == nil ? 44 : 56)
        .glassPane(cornerRadius: 12)
    }
}

extension AlbumToggleRow where Note == EmptyView {
    init(label: String, sub: String? = nil, isOn: Bool, accent: Color, enabled: Bool = true,
         set: @escaping (Bool) -> Void) {
        self.init(label: label, sub: sub, isOn: isOn, accent: accent, enabled: enabled, set: set) { EmptyView() }
    }
}

/// 圆形勾选框：勾上是实心强调色加深色对勾。
struct AlbumCheck: View {
    var on: Bool
    var accent: Color
    var ink: Color

    var body: some View {
        ZStack {
            if on {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ink)
            } else {
                Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.4)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// 效果图上的 Pro 标：金色小皇冠加“Pro”，13pt，不发光。
struct AlbumProTag: View {
    static let gold = Color(hex: "#F5C451")

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: ProFeatures.badgeTitle)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(Self.gold)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(Self.gold.opacity(0.16)))
        .overlay(Capsule().strokeBorder(Self.gold.opacity(0.55), lineWidth: 0.6))
        .fixedSize()
        .help(ProFeatures.help)
        .accessibilityLabel(ProFeatures.label)
    }
}

/// 一张图片缩略图：文件用 `FileThumb`，照片图库里的用 `PhotoMemories` 的缩略图。
struct AlbumThumb: View {
    var item: PhotoAlbum.Item?
    var pixels = 240

    var body: some View {
        switch item {
        case .file(let file):
            FileThumb(url: file.url, pixels: pixels)
        case .memory(let memory):
            Color.black.opacity(0.25)
                .overlay {
                    if let image = PhotoMemories.shared.image(for: memory) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .clipped()
        case nil:
            Color.white.opacity(0.06)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }
}

/// 列表或大图该在的地方空着时的一句话（13pt），读不了文件夹时再给“打开隐私设置”。
struct AlbumNote: View {
    var symbol: String
    var text: String
    var privacy = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.5))
            Text(verbatim: text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if privacy {
                Button(tr("打开隐私设置")) { FolderFeed.openPrivacySettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .underline()
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
