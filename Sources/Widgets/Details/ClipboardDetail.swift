import AppKit
import SwiftUI

/// The last twenty copies. A click puts one back on the pasteboard.
///
/// Kept in memory only and gone when Docket quits; the footnote says so,
/// because a list of everything you copied is exactly the kind of thing
/// people want to know is not being written down.
struct ClipboardDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var history: ClipboardHistory { ClipboardHistory.shared }
    @State private var copied: UUID?

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.indigo))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "list.clipboard", title: "剪贴板",
                            subtitle: "最近 \(ClipboardHistory.limit) 条 · 点按即可重新拷贝")
                if context.isPreview || history.entries.isEmpty {
                    PanelNote(symbol: "doc.on.clipboard", text: "拷贝的文本和图片会显示在这里。")
                        .frame(height: 248)
                } else {
                    list
                }
                HStack(spacing: 8) {
                    PanelButton(title: "全部清除", symbol: "trash") {
                        guard !context.isPreview else { return }
                        history.clear()
                    }
                }
                Text("记录只保存在内存中，退出 Docket 后即清除。密码管理器标记为隐藏的内容不会被记录。")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if !context.isPreview { history.start() } }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(history.entries) { entry in
                    row(entry)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: 248)
    }

    private func row(_ entry: ClipboardHistory.Entry) -> some View {
        HStack(spacing: 10) {
            thumbnail(entry)
                .frame(width: 30, height: 30)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.preview)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(copied == entry.id ? "已拷贝" : RelativeAge.caption(entry.date, now: context.now))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture {
            history.copy(entry)
            copied = history.entries.first?.id
        }
        .contextMenu {
            Button("拷贝") { history.copy(entry) }
            Button("删除") { history.remove(entry) }
        }
    }

    @ViewBuilder
    private func thumbnail(_ entry: ClipboardHistory.Entry) -> some View {
        switch entry.content {
        case .image(let image, _, _):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        case .files(let urls):
            Image(nsImage: Thumbnails.shared.icon(for: urls[0])).resizable().aspectRatio(contentMode: .fit)
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.1))
        }
    }
}
