import AppKit
import SwiftUI

/// Where the search is typed. Return opens the web search in the default
/// browser, or lists matching files, which open on a click and drag out.
struct SearchDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var text = ""
    @FocusState private var focused: Bool

    private var files: Bool { instance.config.string("layout", default: "web") == "files" }
    private var engine: SearchEngine {
        SearchEngine(rawValue: instance.config.string("engine", default: "bing")) ?? .bing
    }
    private var search: FileSearch { FileSearch.shared }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.blue))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: files ? "folder" : "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    TextField("", text: $text,
                              prompt: Text(files ? "文件名" : "用\(engine.title)搜索"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onSubmit(submit)
                    Button(action: submit) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.2), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索")
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .glassPane(cornerRadius: 12)

                if files { results }
            }
        }
        .onAppear {
            focused = true
            if files { text = search.query }
        }
    }

    @ViewBuilder
    private var results: some View {
        if search.searching {
            PanelNote(symbol: "magnifyingglass", text: "正在查找…").frame(height: 236)
        } else if search.results.isEmpty {
            PanelNote(symbol: "doc.text.magnifyingglass",
                      text: search.query.isEmpty ? "输入文件名后按下 Return。" : "没有找到“\(search.query)”。")
                .frame(height: 236)
        } else {
            FileRows(files: search.results, now: context.now)
        }
    }

    private func submit() {
        guard !context.isPreview else { return }
        if files {
            search.search(text)
        } else if let url = engine.url(for: text) {
            NSWorkspace.shared.open(url)
            WidgetDetailWindow.shared.close()
            text = ""
        }
    }
}
