import AppKit
import SwiftUI

/// The files being held, to drag back out one at a time.
///
/// Dropping works here too, so a second batch can be added without hunting
/// for the card under the panel.
struct FileShelfDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var targeted = false

    private var files: [ListedFile] { context.isPreview ? [] : FileShelf.files(instance) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.teal))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "tray.full", title: "文件暂存",
                            subtitle: files.isEmpty ? "把文件拖到这里" : "\(files.count) 个文件 · 拖出即可使用")
                if files.isEmpty {
                    PanelNote(symbol: "tray.and.arrow.down",
                              text: "把文件从访达或其他应用拖到扩展栏上的小组件或这里，稍后再拖出。只会记住文件的位置，不会复制文件。")
                        .frame(height: 236)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(targeted ? 0 : 0.2),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                        .dropTargetOutline(targeted, corner: 12)
                } else {
                    FileRows(files: files, now: context.now,
                             onRemove: { FileShelf.remove($0.url, from: instance) })
                        .dropTargetOutline(targeted, corner: 12)
                }
                HStack(spacing: 8) {
                    PanelButton(title: "在访达中显示", symbol: "folder", prominent: true) {
                        FileActions.reveal(files.map(\.url))
                    }
                    PanelButton(title: "全部清除", symbol: "xmark") {
                        guard !context.isPreview else { return }
                        FileShelf.clear(instance)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !context.isPreview else { return false }
            return FileShelf.add(urls, to: instance)
        } isTargeted: { targeted = $0 }
    }
}
