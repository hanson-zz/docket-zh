import SwiftUI

/// 详情面板顶部的分段：深色玻璃上一条 28pt 高的槽，选中那一格淡白底、白字，
/// 其余半透明。最高的几个面板用它把次要内容分页（见 `DetailPanelSections`）。
///
/// `selected` 为 nil 时一格都不亮（收音机下半截全部收起）。
struct DetailSegmented<Page: Hashable>: View {
    var pages: [Page]
    var title: (Page) -> String
    var selected: Page?
    var onSelect: (Page) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages, id: \.self) { page in
                let on = page == selected
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { onSelect(page) }
                } label: {
                    Text(verbatim: title(page))
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.66))
                        .lineLimit(1)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(.white.opacity(0.16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
                                    }
                                    .padding(2)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.07)))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
        }
    }
}

/// 可折叠的一段：标题一行（右边一个箭头）总在，点一下展开或收起下面的内容。
/// 默认收起，展开状态按 `key` 记在 UserDefaults 里，下次打开面板照旧。
struct DetailFold<Label: View, Content: View>: View {
    @AppStorage private var expanded: Bool
    private let label: () -> Label
    private let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(key: String, @ViewBuilder label: @escaping () -> Label,
         @ViewBuilder content: @escaping () -> Content) {
        _expanded = AppStorage(wrappedValue: false, key)
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    label()
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 24)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? tr("已展开") : tr("已收起"))
            .accessibilityHint(expanded ? tr("收起") : tr("展开"))
            if expanded {
                content()
                    .transition(.opacity)
            }
        }
    }
}
