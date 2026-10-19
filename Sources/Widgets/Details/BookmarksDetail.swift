import AppKit
import SwiftUI

/// Every link with the title and summary its page gave, or its address when
/// the page could not be read. A click opens it; a secondary click copies
/// the address or reads the page again. A field at the top adds a link, and
/// a 小宇宙 show or episode link offers "加到播客".
struct BookmarksDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @FocusState private var addingFocused: Bool
    @State private var newLink = ""
    @State private var refreshing: Set<String> = []
    @State private var podcastStatus: [String: String] = [:]
    @State private var addingPodcast: Set<String> = []

    private var links: [Bookmark] { Bookmark.list(instance.config.strings("links")) }
    private var previews: [String: LinkPreview] { LinkPreview.stored(instance.config) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.orange))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    PanelHeader(symbol: "bookmark", title: tr("书签"), subtitle: tr("\(links.count) 个网址 · 用默认浏览器打开"))
                    if !links.isEmpty, !context.isPreview {
                        Button {
                            refresh(links)
                        } label: {
                            if refreshing.isEmpty {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            } else {
                                ProgressView().controlSize(.mini)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!refreshing.isEmpty)
                        .help("刷新全部预览")
                        .accessibilityLabel("刷新全部预览")
                    }
                }
                addField
                if links.isEmpty {
                    PandaEmptyState(empty: .bookmarks, title: tr("添加书签"), panel: true) {
                        WidgetDetailWindow.shared.focusField { addingFocused = true }
                    }
                        .frame(height: 120)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(links.enumerated()), id: \.offset) { _, link in row(link) }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(280, CGFloat(links.count) * 60))
                }
                Text("在 设置 ▸ 小组件 中编辑网址：每项可写成“标题 网址”，用逗号分隔。添加后会自动读取网页的标题和摘要。")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Adding

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            TextField("", text: $newLink, prompt: Text("粘贴网址，回车添加"))
                .focused($addingFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit { add() }
                .disabled(context.isPreview)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .glassPane(cornerRadius: 10)
    }

    private func add() {
        let text = newLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isPreview, let link = Bookmark(parsing: text) else { return }
        newLink = ""
        guard !links.contains(where: { $0.url == link.url }) else { return }
        // Commas separate entries in Settings, so none may survive inside one.
        let entry = text.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "，", with: " ")
        WidgetWriter.write(instance) { config in
            config.set("links", .list((config.strings("links") + [entry]).map { .string($0) }))
        }
    }

    // MARK: Rows

    private func row(_ link: Bookmark) -> some View {
        let key = link.url.absoluteString
        let preview = previews[key]
        let title = link.displayTitle(preview)
        let summary = preview?.hasContent == true ? preview?.summary : nil
        return HStack(alignment: .top, spacing: 10) {
            BookmarkIcon(link: Bookmark(title: title, url: link.url),
                         icon: preview?.failed == false ? preview?.icon : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(summary == nil ? key : Bookmark.shortHost(link.url))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let xyz = link.xiaoyuzhou { podcastButton(xyz, key: key) }
            }
            Spacer(minLength: 0)
            if refreshing.contains(key) {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        }
        .contextMenu {
            Button("打开") { NSWorkspace.shared.open(link.url) }
            Button("拷贝网址") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
            }
            if LinkPreview.needsFetch(link.url, stored: nil) {
                Button("刷新预览") { refresh([link]) }
            }
        }
        .help([title, summary, key].compactMap { $0 }.joined(separator: "\n"))
    }

    /// "加到播客" under a 小宇宙 link: subscribes the 播客 widgets to its show.
    @ViewBuilder
    private func podcastButton(_ link: XiaoyuzhouLink, key: String) -> some View {
        HStack(spacing: 6) {
            if PodcastService.shared.isSubscribed(link) {
                Label("已在播客中", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.6))
            } else if addingPodcast.contains(key) {
                ProgressView().controlSize(.mini)
                Text("正在加到播客…").foregroundStyle(.white.opacity(0.6))
            } else {
                Button {
                    addToPodcast(link, key: key)
                } label: {
                    Label("加到播客", systemImage: "plus.circle.fill")
                        .foregroundStyle(panelTint.accent(or: PodcastCover.accent))
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
            }
            if let status = podcastStatus[key] {
                Text(status).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.top, 2)
    }

    private func addToPodcast(_ link: XiaoyuzhouLink, key: String) {
        addingPodcast.insert(key)
        podcastStatus[key] = nil
        Task {
            let result = await PodcastService.shared.add(link)
            addingPodcast.remove(key)
            switch result {
            case .success(let show):
                podcastStatus[key] = tr("已加入「\(show.title)」")
            case .failure(let failure):
                podcastStatus[key] = failure.message
            }
        }
    }

    // MARK: Refresh

    private func refresh(_ chosen: [Bookmark]) {
        let urls = chosen.map(\.url).filter { LinkPreview.needsFetch($0, stored: nil) }
        guard !urls.isEmpty, !context.isPreview else { return }
        for url in urls { refreshing.insert(url.absoluteString) }
        Task {
            let fetched = await LinkPreviewFetcher.fetch(urls)
            for url in urls { refreshing.remove(url.absoluteString) }
            // A refresh that failed keeps what was read before.
            let stored = LinkPreview.stored(instance.config)
            let kept = fetched.filter { !$0.failed || stored[$0.url]?.hasContent != true }
            if !kept.isEmpty { BookmarkPreviews.save(kept, in: instance) }
        }
    }
}

/// A link's icon from its page when there is one, its letter otherwise.
private struct BookmarkIcon: View {
    var link: Bookmark
    var icon: String?

    var body: some View {
        Group {
            if let icon, let url = URL(string: icon) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .padding(4)
                            .background(Circle().fill(.white.opacity(0.9)))
                            .clipShape(Circle())
                    } else {
                        BookmarkBadge(link: link, size: 28)
                    }
                }
            } else {
                BookmarkBadge(link: link, size: 28)
            }
        }
        .frame(width: 28, height: 28)
    }
}
