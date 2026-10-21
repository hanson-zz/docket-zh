import AppKit
import SwiftUI

/// Where the search is typed. Return opens the web search in the default
/// browser, or lists matching files, which open on a click and drag out.
///
/// 网页搜索时，输入框下面是一排搜索站图标（百度、小红书、GitHub……）：
/// 点一个就换成用它搜，框里有字时直接搜；最后一个“添加”可以加内置站或
/// 自己填网址。右键图标可以移除。这一排存在小组件自己的设置里。
struct SearchDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var text = ""
    @State private var adding = false
    @FocusState private var focused: Bool

    private var files: Bool { instance.config.string("layout", default: "web") == "files" }
    private var custom: [SearchSite] { SearchSites.decode(instance.config.string("customSites")) }
    private var sites: [SearchSite] {
        SearchSites.resolve(ids: instance.config.strings("sites"), custom: custom)
    }
    private var engine: SearchSite? {
        SearchSites.selected(instance.config.string("engine", default: "bing"), in: sites)
    }
    private var search: FileSearch { FileSearch.shared }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.blue))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if files {
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.panelSecondary)
                    } else if let engine {
                        SiteBadge(site: engine, size: 22)
                    }
                    TextField("", text: $text,
                              prompt: Text(files ? tr("文件名") : tr("用\(engine?.title ?? tr("网页"))搜索")))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(.panelPrimary)
                        .focused($focused)
                        .onSubmit(submit)
                    Button(action: submit) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.panelPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.panelRaised).panelLift())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("搜索")
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .glassPane(cornerRadius: 12)

                if files { results } else { siteGrid }
            }
        }
        .onAppear {
            focused = true
            if files { text = search.query }
        }
    }

    // MARK: 搜索站

    private var siteGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
            ForEach(sites) { site in
                siteButton(site)
            }
            if sites.count < SearchSites.maxCount {
                Button { adding = true } label: {
                    siteCell(title: tr("添加"), selected: false) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(panelTint.accent(or: Color(hex: "#4C9BFF")).panelReadable)
                            .frame(width: 34, height: 34)
                    }
                }
                .buttonStyle(.plain)
                .help("添加搜索站")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    AddSearchSite(existing: sites.map(\.id), add: add)
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func siteButton(_ site: SearchSite) -> some View {
        let selected = site.id == engine?.id
        return Button { pick(site) } label: {
            siteCell(title: site.title, selected: selected) { SiteBadge(site: site, size: 34) }
        }
        .buttonStyle(.plain)
        .help(text.isEmpty ? tr("用\(site.title)搜索") : tr("用\(site.title)搜索“\(text)”"))
        .accessibilityLabel(site.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button("设为默认") { choose(site) }
            if sites.count > 1 {
                Button("移除", role: .destructive) { remove(site) }
            }
        }
    }

    private func siteCell<Icon: View>(title: String, selected: Bool,
                                      @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 4) {
            icon()
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Color.panelSelected : Color.panelFill))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.panelTertiary : Color.clear, lineWidth: 1))
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary.opacity(selected ? 1 : 0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    /// 点图标：换成这个站；框里有字就直接用它搜。
    private func pick(_ site: SearchSite) {
        guard !context.isPreview else { return }
        choose(site)
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { open(site) }
        else { focused = true }
    }

    private func choose(_ site: SearchSite) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { $0.set("engine", .string(site.id)) }
    }

    private func add(_ site: SearchSite) {
        guard !context.isPreview else { return }
        let ids = sites.map(\.id) + [site.id]
        var custom = self.custom
        if site.isCustom { custom.append(site) }
        WidgetWriter.write(instance) {
            $0.set("sites", .list(ids.map { .string($0) }))
            $0.set("customSites", .string(SearchSites.encode(custom)))
            $0.set("engine", .string(site.id))
        }
        adding = false
    }

    private func remove(_ site: SearchSite) {
        guard !context.isPreview else { return }
        let ids = sites.map(\.id).filter { $0 != site.id }
        let custom = self.custom.filter { $0.id != site.id }
        WidgetWriter.write(instance) {
            $0.set("sites", .list(ids.map { .string($0) }))
            $0.set("customSites", .string(SearchSites.encode(custom)))
        }
    }

    // MARK: 文件

    @ViewBuilder
    private var results: some View {
        if search.searching {
            PanelNote(symbol: "magnifyingglass", text: tr("正在查找…")).frame(height: 236)
        } else if search.results.isEmpty {
            PanelNote(symbol: "doc.text.magnifyingglass",
                      text: search.query.isEmpty ? tr("输入文件名后按下 Return。") : tr("没有找到“\(search.query)”。"))
                .frame(height: 236)
        } else {
            FileRows(files: search.results, now: context.now)
        }
    }

    private func submit() {
        guard !context.isPreview else { return }
        if files {
            search.search(text)
        } else if let engine {
            open(engine)
        }
    }

    private func open(_ site: SearchSite) {
        guard let url = site.url(for: text) else { return }
        NSWorkspace.shared.open(url)
        WidgetDetailWindow.shared.close()
        text = ""
    }
}

/// 搜索站图标：网站自己的图标，读不到时是品牌色底上的首字。
struct SiteBadge: View {
    var site: SearchSite
    var size: CGFloat

    var body: some View {
        let image = SiteIconCache.shared.icon(for: site.home)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color(hex: site.tint))
                Text(site.initial)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.26, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// “添加”弹出的小窗：上面是还没加的内置站，下面自己填名字和网址。
private struct AddSearchSite: View {
    var existing: [String]
    var add: (SearchSite) -> Void

    @State private var name = ""
    @State private var address = ""

    private var available: [SearchSite] { SearchSites.builtIn.filter { !existing.contains($0.id) } }
    private var custom: SearchSite? {
        SearchSites.custom(title: name, address: address, id: String(UUID().uuidString.prefix(8)).lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !available.isEmpty {
                Text(tr("常用", context: "sites")).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 6), count: 4), spacing: 10) {
                    ForEach(available) { site in
                        Button { add(site) } label: {
                            VStack(spacing: 4) {
                                SiteBadge(site: site, size: 30)
                                Text(site.title).font(.caption).lineLimit(1)
                            }
                            .frame(width: 64)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(tr("添加\(site.title)"))
                    }
                }
                Divider()
            }
            Text("自定义").font(.headline)
            TextField("名字，例如 豆瓣", text: $name)
            TextField("搜索网址，用 %s 代表搜索词", text: $address)
            Text("例如 https://www.douban.com/search?q=%s。不写 %s 时搜索词接在网址末尾。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("添加") { if let custom { add(custom) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(custom == nil)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(14)
        .frame(width: 300)
    }
}
