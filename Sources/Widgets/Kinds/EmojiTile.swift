import AppKit
import SwiftUI

/// The emoji you reach for most, one click from the pasteboard, and a door
/// to the panel for the rest.
///
/// 卡片上是收藏的前 9 个（面板里整理，设置页也能写逗号列表），按默认肤色或
/// 单个另选的肤色显示；收藏清空了就放最近用过，也没有就放默认的。点一下拷贝
/// 并记进最近用过，末尾“＋”打开面板（搜索、整理、系统表情面板都在里面）。
struct EmojiTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// 刚拷贝的那一格，亮约一秒就灭（不再一直亮着）。
    @State private var copied: String?
    /// 每点一次加一，连点同一格也重新亮满一秒。
    @State private var copyCount = 0

    private var prefs: EmojiPrefs { EmojiPrefs(instance.config) }

    /// 卡片上的 9 个：存的写法（不带肤色），显示时再加。
    private var emoji: [String] {
        let p = prefs
        let source = !p.favorites.isEmpty ? p.favorites
            : !p.recent.isEmpty ? p.recent : EmojiPrefs.defaultFavorites
        return Array(source.prefix(9))
    }

    var body: some View {
        let column = context.position.isVertical
        let perRow = column ? 2 : 5
        let cells = emoji.map { Optional($0) } + [nil]
        let rows = stride(from: 0, to: cells.count, by: perRow).map {
            Array(cells[$0..<min($0 + perRow, cells.count)])
        }
        return WidgetSurface {
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(rows[row].indices, id: \.self) { index in
                            cell(rows[row][index])
                        }
                    }
                }
            }
        }
        .task(id: copyCount) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copied = nil }
        }
    }

    @ViewBuilder
    private func cell(_ item: String?) -> some View {
        if let item {
            let shown = prefs.display(item)
            Button {
                guard !context.isPreview else { return }
                ColorSampling.copy(shown)
                copied = item
                copyCount &+= 1
                let latest = WidgetWriter.current(instance.id) ?? instance
                WidgetWriter.write(latest) { config in
                    let next = EmojiPrefs(config).recording(item)
                    next.store(in: &config)
                }
            } label: {
                Text(verbatim: shown)
                    .font(.system(size: 17))
                    .frame(width: 26, height: 24)
                    .background(WidgetStyle.primary.opacity(copied == item ? 0.16 : 0),
                                in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("拷贝 \(shown)"))
        } else {
            Button {
                guard !context.isPreview else { return }
                WidgetPanelOpener.shared.open(instance.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .frame(width: 26, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("搜索、整理收藏、更多表情"))
            .accessibilityLabel(tr("打开表情面板"))
        }
    }
}
