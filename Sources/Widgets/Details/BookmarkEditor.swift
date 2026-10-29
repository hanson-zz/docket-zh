import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 图标

/// 书签图标的画法，卡片（圆）、面板（圆角方块）、桌面卡片和表单预览共用。
///
/// - 文字图标：选的颜色上写 1 到 2 个字。
/// - 上传的图片：铺满整个形状。
/// - 网站图标（选了“网站图标”，或者没选过）：本地缓存里有就放在白色底板上，
///   没有就是原来的首字色块（颜色按域名，8 种）。
///
/// 图片都从 `BookmarkIconStore` 内存里拿，重画不联网、不读盘。
struct BookmarkGlyph: View {
    /// `title` 是显示用的名字（首字从这里取）。
    var link: Bookmark
    var icon: BookmarkIcon?
    /// 网页里写的 icon 地址（`LinkPreview.icon`），取网站图标时先试它。
    var pageIcon: String?
    var size: CGFloat
    var round: Bool
    /// 磁盘上没有网站图标时要不要联网取。预览还没读到时传 false。
    var autoFetch: Bool = true

    private static let legacyPalette: [PaletteColor] = [.blue, .orange, .green, .pink, .purple, .teal, .red, .indigo]

    private var shape: AnyShape {
        round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .contentShape(shape)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let store = BookmarkIconStore.shared
        switch icon {
        case .image(let file):
            if let image = store.uploadedIcon(file) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
            } else {
                legacyLetter
            }
        case .text(let text, let color):
            BookmarkTextGlyph(text: text, hex: BookmarkIcons.palette[BookmarkIcons.clampedColor(color)],
                              size: size, round: round)
        case .site, nil:
            if let image = store.siteIcon(for: link.url, pageIcon: pageIcon, autoFetch: autoFetch) {
                BookmarkPlatedImage(image: image, size: size, round: round)
            } else {
                legacyLetter
            }
        }
    }

    /// 原来的首字色块：没选过图标、也没有网站图标时画这个。
    private var legacyLetter: some View {
        let colour = WidgetStyle.tint(Self.legacyPalette[link.paletteIndex(count: Self.legacyPalette.count)])
        return Text(link.initial)
            .font(.system(size: size * (round ? 0.46 : 0.5), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(colour.gradient))
    }
}

/// 文字图标：颜色上 1 到 2 个白字。两个字时字号小一点，最小 13pt。
struct BookmarkTextGlyph: View {
    var text: String
    var hex: String
    var size: CGFloat
    var round: Bool

    var body: some View {
        let two = text.count > 1
        let font = two ? max(13, size * 0.36) : size * (round ? 0.46 : 0.5)
        let shape: AnyShape = round
            ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        Text(verbatim: text)
            .font(.system(size: font, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, two ? 1 : 0)
            .frame(width: size, height: size)
            .background(shape.fill(Color(hex: hex).gradient))
    }
}

/// 网站图标放在白色底板上（不少 favicon 是透明底的深色字），细边让它在浅色玻璃上也看得出轮廓。
struct BookmarkPlatedImage: View {
    var image: NSImage
    var size: CGFloat
    var round: Bool

    var body: some View {
        let shape: AnyShape = round
            ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .padding(size * (round ? 0.2 : 0.16))
            .frame(width: size, height: size)
            .background(shape.fill(Color.white.opacity(0.94)))
            .overlay(shape.stroke(Color.black.opacity(0.1), lineWidth: 0.5))
    }
}

// MARK: - 表单的状态

/// 添加 / 编辑书签表单里填了一半的内容。
///
/// 放在面板外面：上传图片时要先把面板收起来（码头的面板层级比系统的打开面板高，
/// 开着会把它挡住），选完再请扩展栏打开回来，表单原样还在。面板被点外面、Esc
/// 关上时清掉，这一轮上传了却没保存的图片一起删掉。
@MainActor @Observable
final class BookmarkFormState {
    static let shared = BookmarkFormState()

    enum Choice: String, CaseIterable { case site, text, image }

    enum Status: Equatable {
        case idle
        case fetching
        /// 取到了网站图标。
        case got
        /// 页面里的 icon、apple-touch-icon、favicon.ico 都没取到。
        case missed
    }

    struct Draft: Equatable {
        var widget: UUID
        /// 编辑的是哪一个；nil 是新加。
        var original: URL?
        var address = ""
        var name = ""
        var choice: Choice = .site
        /// 用户自己点过图标类型，取图标的结果就不再替他切换。
        var choiceTouched = false
        /// 文字图标的字，空着用名称首字。
        var text = ""
        /// 文字图标的颜色，nil 是按域名的默认色。
        var color: Int?
        /// 上传的图片文件名。
        var upload: String?
        /// 读到的网页标题和图标地址，保存时一起存。
        var preview: LinkPreview?
        /// 上面的预览和网站图标是给哪个网址取的。
        var fetchedFor: String?
        var status: Status = .idle
        /// 表单底下的一行提示（认不出网址、重复、读不出图片）。
        var notice: String?
        /// “保存并继续”之后表单顶上的一行：刚存好的那个叫什么。
        var savedName: String?
    }

    var draft: Draft?
    /// 选图片时面板是自己收起的，这一次关闭不清表单。
    var holdingForPicker = false
    /// 这一轮表单里上传、还没存进书签的图片。取消或换掉时删掉。
    @ObservationIgnored var freshUploads = Set<String>()

    @ObservationIgnored private var closeObserver: NSObjectProtocol?

    private init() {
        closeObserver = NotificationCenter.default.addObserver(
            forName: WidgetDetailWindow.didClose, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { BookmarkFormState.shared.panelClosed() }
        }
    }

    func isOpen(for widget: UUID) -> Bool { draft?.widget == widget }

    func startAdding(in widget: UUID, address: String = "") {
        discardUploads()
        draft = Draft(widget: widget, address: address)
    }

    func startEditing(in widget: UUID, link: Bookmark, preview: LinkPreview?, icon: BookmarkIcon?) {
        discardUploads()
        var next = Draft(widget: widget, original: link.url, address: link.url.absoluteString,
                         name: link.hasOwnTitle ? link.title : "")
        next.preview = preview
        next.fetchedFor = preview == nil ? nil : link.url.absoluteString
        switch icon {
        case .text(let text, let color):
            next.choice = .text
            next.text = text
            next.color = color
        case .image(let file):
            next.choice = .image
            next.upload = file
        case .site, nil:
            next.choice = .site
        }
        // 已有的书签按它现在的样子打开，取图标的结果不再替它换类型。
        next.choiceTouched = icon != nil
        draft = next
    }

    func close() {
        discardUploads()
        draft = nil
    }

    private func panelClosed() {
        guard !holdingForPicker, draft != nil else { return }
        close()
    }

    /// 删掉这一轮上传、没存进去的图片，`keeping` 是要留下的那张。
    func discardUploads(keeping: String? = nil) {
        var drop = freshUploads
        if let keeping { drop.remove(keeping) }
        freshUploads.removeAll()
        if !drop.isEmpty { BookmarkIconStore.shared.removeUploads(drop) }
    }
}

// MARK: - 写回配置

@MainActor
enum BookmarkConfigWriter {
    /// 写书签小组件的配置；写完不再用到的上传图片（删了书签、换了图标）一起删掉。
    static func write(_ instance: WidgetInstance, _ change: (inout WidgetConfig) -> Void) {
        let before = BookmarkIcons.uploadFiles(instance.config)
        var after = before
        WidgetWriter.write(instance) { config in
            change(&config)
            after = BookmarkIcons.uploadFiles(config)
        }
        let unused = before.subtracting(after)
        if !unused.isEmpty { BookmarkIconStore.shared.removeUploads(unused) }
    }
}

// MARK: - 表单

/// 添加 / 编辑书签：网址（带“获取图标”）、名称、图标（网站图标 / 文字 / 上传图片）。
///
/// 一大块液态玻璃面板里分三张玻璃小卡，顶上是实时预览。取图标先读网页（标题和
/// 页面里的 icon），再按 `BookmarkIcons.iconCandidates` 依次试；都没取到就切到
/// 文字图标并提示。文字图标默认取名称首字，可以改成 1 到 2 个字，十种颜色。
struct BookmarkEditorForm: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var accent: Color
    var accentInk: Color
    /// 面板正在看的分组（Pro），新加的书签放进去。
    var group: String?
    var unlocked: Bool
    /// 写过配置之后，面板重读。
    var onSaved: () -> Void

    private var state: BookmarkFormState { BookmarkFormState.shared }
    @FocusState private var focus: Field?

    private enum Field: Hashable { case address, name, text }

    private static let red = Color(red: 1, green: 0.42, blue: 0.35)

    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }

    var body: some View {
        if let draft = state.draft {
            VStack(alignment: .leading, spacing: 10) {
                header(draft)
                previewRow(draft)
                addressSection(draft)
                nameSection(draft)
                iconSection(draft)
                if let notice = draft.notice {
                    Text(notice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Self.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons(draft)
            }
            .onAppear {
                guard draft.address.isEmpty else { return }
                WidgetDetailWindow.shared.focusField { focus = .address }
            }
        }
    }

    // MARK: 顶部

    private func header(_ draft: BookmarkFormState.Draft) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(draft.original == nil ? tr("添加书签") : tr("编辑书签"))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.panelPrimary)
            Spacer(minLength: 0)
            Button { state.close() } label: {
                Text(tr("取消"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.panelFill))
                    .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    /// 存好以后在卡片上的样子：图标、名字、域名。
    private func previewRow(_ draft: BookmarkFormState.Draft) -> some View {
        let url = Bookmark.parseAddress(draft.address)
        let shown = displayName(draft, url: url)
        return HStack(spacing: 12) {
            if let url {
                BookmarkGlyph(link: Bookmark(title: shown, url: url), icon: chosenIcon(draft, url: url),
                              pageIcon: pageIcon(draft, url: url), size: 52, round: false, autoFetch: false)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.panelFill)
                    .overlay {
                        Image(systemName: "globe")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.panelTertiary)
                    }
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: shown.isEmpty ? tr("新书签") : shown)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Text(verbatim: draft.savedName.map { tr("已保存「\($0)」，接着加下一个") }
                     ?? url.map(Bookmark.shortHost) ?? tr("填好网址，回车或点“获取图标”"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassPane(cornerRadius: 14)
    }

    // MARK: 网址

    private func addressSection(_ draft: BookmarkFormState.Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(tr("网址"))
            HStack(spacing: 8) {
                TextField("", text: binding(\.address), prompt: Text(verbatim: "example.com"))
                    .focused($focus, equals: .address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .onSubmit { fetch() }
                    .disabled(context.isPreview)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.panelFill))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(focus == .address ? accent.opacity(0.9) : .panelStroke,
                                      lineWidth: focus == .address ? 1.2 : 0.6))
                Button { fetch() } label: {
                    HStack(spacing: 5) {
                        if draft.status == .fetching {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(tr("获取图标"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .glassPane(cornerRadius: 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(draft.status == .fetching || context.isPreview)
                .help(tr("读网页标题，按顺序试页面图标、apple-touch-icon 和 favicon.ico"))
            }
            if let line = statusLine(draft.status) {
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(draft.status == .missed ? accent.panelReadable : .panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .glassPane(cornerRadius: 14)
    }

    private func statusLine(_ status: BookmarkFormState.Status) -> String? {
        switch status {
        case .idle: nil
        case .fetching: tr("正在读取标题和图标…")
        case .got: tr("已获取网站图标")
        case .missed: tr("没取到图标，可以用文字或上传")
        }
    }

    // MARK: 名称

    private func nameSection(_ draft: BookmarkFormState.Draft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(tr("名称"))
            TextField("", text: binding(\.name), prompt: Text(nameHint(draft)))
                .focused($focus, equals: .name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .onSubmit { save(continuing: false) }
                .disabled(context.isPreview)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.panelFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focus == .name ? accent.opacity(0.9) : .panelStroke,
                                  lineWidth: focus == .name ? 1.2 : 0.6))
        }
        .padding(12)
        .glassPane(cornerRadius: 14)
    }

    private func nameHint(_ draft: BookmarkFormState.Draft) -> String {
        if let title = fetchedTitle(draft, url: Bookmark.parseAddress(draft.address)) { return title }
        return tr("空着就用网页标题")
    }

    // MARK: 图标

    private func iconSection(_ draft: BookmarkFormState.Draft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label(tr("图标"))
            HStack(spacing: 6) {
                choiceChip(.site, title: tr("网站图标"), symbol: "globe", draft: draft)
                choiceChip(.text, title: tr("文字"), symbol: "textformat", draft: draft)
                choiceChip(.image, title: tr("上传"), symbol: "photo", draft: draft)
            }
            switch draft.choice {
            case .site: siteChoice(draft)
            case .text: textChoice(draft)
            case .image: imageChoice(draft)
            }
        }
        .padding(12)
        .glassPane(cornerRadius: 14)
    }

    private func choiceChip(_ choice: BookmarkFormState.Choice, title: String, symbol: String,
                            draft: BookmarkFormState.Draft) -> some View {
        let on = draft.choice == choice
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                state.draft?.choice = choice
                state.draft?.choiceTouched = true
                state.draft?.notice = nil
            }
            if choice == .image, draft.upload == nil { pickImage() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: on ? .bold : .semibold))
            }
            .foregroundStyle(on ? accentInk : .panelPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Capsule().fill(on ? accent : .panelFill))
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.panelStroke, lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func siteChoice(_ draft: BookmarkFormState.Draft) -> some View {
        let url = Bookmark.parseAddress(draft.address)
        let image = url.flatMap {
            BookmarkIconStore.shared.siteIcon(for: $0, pageIcon: pageIcon(draft, url: $0), autoFetch: false)
        }
        HStack(spacing: 10) {
            if let image {
                BookmarkPlatedImage(image: image, size: 36, round: false)
                Text(tr("用网站自己的图标，存在本机，不会每次联网"))
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.panelTertiary)
                    .frame(width: 36, height: 36)
                Text(draft.status == .missed ? tr("这个网站没有可用的图标，卡片上画首字")
                     : tr("点“获取图标”读取网站图标"))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.panelSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func textChoice(_ draft: BookmarkFormState.Draft) -> some View {
        let url = Bookmark.parseAddress(draft.address)
        let selected = draft.color ?? url.map { BookmarkIcons.defaultColor(for: $0) } ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: binding(\.text),
                          prompt: Text(verbatim: BookmarkIcons.defaultText(for: displayName(draft, url: url))))
                    .focused($focus, equals: .text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .multilineTextAlignment(.center)
                    .disabled(context.isPreview)
                    .frame(width: 64, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.panelFill))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(focus == .text ? accent.opacity(0.9) : .panelStroke,
                                      lineWidth: focus == .text ? 1.2 : 0.6))
                Text(tr("1 到 2 个字，空着用名称首字"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: BookmarkIcons.palette.count),
                      spacing: 4) {
                ForEach(BookmarkIcons.palette.indices, id: \.self) { index in
                    swatch(index, on: BookmarkIcons.clampedColor(selected) == index)
                }
            }
        }
    }

    private func swatch(_ index: Int, on: Bool) -> some View {
        Button {
            state.draft?.color = index
            state.draft?.choiceTouched = true
        } label: {
            Circle()
                .fill(Color(hex: BookmarkIcons.palette[index]).gradient)
                .frame(width: 18, height: 18)
                .padding(2)
                .overlay(Circle().strokeBorder(on ? Color.panelPrimary.opacity(0.85) : .clear, lineWidth: 1.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .accessibilityLabel(tr("颜色 \(String(index + 1))"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func imageChoice(_ draft: BookmarkFormState.Draft) -> some View {
        HStack(spacing: 10) {
            if let file = draft.upload, let image = BookmarkIconStore.shared.uploadedIcon(file) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.panelTertiary)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Button { pickImage() } label: {
                    Text(draft.upload == nil ? tr("选择图片…") : tr("换一张…"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(.panelFill))
                        .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                Text(tr("PNG、JPG、ICO 等，缩小后存在本机"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 按钮

    private func buttons(_ draft: BookmarkFormState.Draft) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if draft.original == nil {
                Button { save(continuing: true) } label: {
                    Text(tr("保存并继续"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(.panelFill))
                        .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
            }
            Button { save(continuing: false) } label: {
                Text(tr("保存"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 20)
                    .frame(height: 32)
                    .background(Capsule().fill(accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
    }

    // MARK: 读

    private func binding(_ path: WritableKeyPath<BookmarkFormState.Draft, String>) -> Binding<String> {
        Binding(get: { state.draft?[keyPath: path] ?? "" },
                set: { value in
                    guard state.draft != nil else { return }
                    state.draft?[keyPath: path] = value
                    state.draft?.notice = nil
                })
    }

    /// 预览只在它就是给眼下这个网址读的时候算数。
    private func preview(_ draft: BookmarkFormState.Draft, url: URL?) -> LinkPreview? {
        guard let url, draft.fetchedFor == url.absoluteString, let preview = draft.preview,
              preview.url == url.absoluteString else { return nil }
        return preview
    }

    private func fetchedTitle(_ draft: BookmarkFormState.Draft, url: URL?) -> String? {
        guard let preview = preview(draft, url: url), !preview.failed,
              let title = preview.title, !title.isEmpty else { return nil }
        return title
    }

    private func pageIcon(_ draft: BookmarkFormState.Draft, url: URL) -> String? {
        if let icon = preview(draft, url: url)?.icon { return icon }
        return LinkPreview.stored(current.config)[url.absoluteString]?.icon
    }

    /// 卡片上会显示的名字：自己填的，没填用网页标题，再没有用域名。
    private func displayName(_ draft: BookmarkFormState.Draft, url: URL?) -> String {
        let typed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let title = fetchedTitle(draft, url: url) { return title }
        if let url, let stored = LinkPreview.stored(current.config)[url.absoluteString],
           !stored.failed, let title = stored.title, !title.isEmpty { return title }
        return url.map(Bookmark.shortHost) ?? ""
    }

    /// 眼下表单选中的图标，保存时写进 `icons`。上传还没选图时是 nil。
    private func chosenIcon(_ draft: BookmarkFormState.Draft, url: URL) -> BookmarkIcon? {
        switch draft.choice {
        case .site:
            return .site
        case .text:
            let text = BookmarkIcons.cleanText(draft.text)
                ?? BookmarkIcons.defaultText(for: displayName(draft, url: url))
            return .text(text, color: draft.color ?? BookmarkIcons.defaultColor(for: url))
        case .image:
            return draft.upload.map { .image($0) }
        }
    }

    // MARK: 获取图标

    private func fetch() {
        guard !context.isPreview, let draft = state.draft else { return }
        guard let url = Bookmark.parseAddress(draft.address) else {
            state.draft?.notice = tr("认不出网址，试试 example.com 或 https://…")
            return
        }
        let key = url.absoluteString
        state.draft?.address = key
        state.draft?.status = .fetching
        state.draft?.fetchedFor = key
        state.draft?.notice = nil
        Task {
            let web = LinkPreview.needsFetch(url, stored: nil)
            let preview = web ? await LinkPreviewFetcher.fetch([url]).first : nil
            let image = web ? await BookmarkIconStore.shared.fetchSiteIcon(page: url, pageIcon: preview?.icon) : nil
            guard var next = state.draft, next.fetchedFor == key else { return }
            next.preview = preview
            if image != nil {
                next.status = .got
                if !next.choiceTouched { next.choice = .site }
            } else {
                next.status = .missed
                if next.choice == .site { next.choice = .text }
            }
            withAnimation(.snappy(duration: 0.2)) { state.draft = next }
        }
    }

    // MARK: 上传

    /// 选图片：系统的打开面板。码头的面板层级比它高，先收起面板，选完（或取消）
    /// 再请扩展栏打开回来，填了一半的表单在 `BookmarkFormState` 里（和 AI 助手选 App 一样）。
    private func pickImage() {
        guard !context.isPreview else { return }
        let id = instance.id
        state.holdingForPicker = true
        WidgetDetailWindow.shared.close()
        defer {
            state.holdingForPicker = false
            WidgetPanelOpener.shared.open(id)
        }
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = tr("选一张图片做书签图标")
        panel.prompt = tr("选择")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else {
            if state.draft?.upload == nil, state.draft?.choice == .image {
                state.draft?.choice = state.draft?.status == .got ? .site : .text
            }
            return
        }
        guard let name = BookmarkIconStore.shared.importUpload(from: url) else {
            state.draft?.notice = tr("读不出这张图片，换一张试试")
            return
        }
        // 这一轮之前上传、没存进去的那张换掉了，删掉。
        if let old = state.draft?.upload, state.freshUploads.contains(old) {
            state.freshUploads.remove(old)
            BookmarkIconStore.shared.removeUploads([old])
        }
        state.freshUploads.insert(name)
        state.draft?.upload = name
        state.draft?.choice = .image
        state.draft?.choiceTouched = true
        state.draft?.notice = nil
    }

    // MARK: 保存

    private func save(continuing: Bool) {
        guard !context.isPreview, let draft = state.draft else { return }
        guard let url = Bookmark.parseAddress(draft.address) else {
            state.draft?.notice = tr("认不出网址，试试 example.com 或 https://…")
            return
        }
        guard let icon = chosenIcon(draft, url: url) else {
            state.draft?.notice = tr("先选一张图片，或者换成文字图标")
            return
        }
        let target = current
        let entries = target.config.strings("links")
        let next: [String]
        switch BookmarkList.saving(title: draft.name, url: url, replacing: draft.original, in: entries) {
        case .added(let list): next = list
        case .duplicate:
            state.draft?.notice = tr("已经在书签里了")
            return
        case .full:
            state.draft?.notice = tr("最多 \(Bookmark.maxCount) 个书签，先删掉几个")
            return
        case .invalid:
            state.draft?.notice = tr("认不出网址，试试 example.com 或 https://…")
            return
        }
        let fresh = preview(draft, url: url)
        let groupsNow = BookmarkGroups.groups(target.config)
        // 改了网址的书签留在原来的分组里；在某个分组下新加的放进那个分组。
        let into: String? = {
            guard unlocked else { return nil }
            if let original = draft.original { return BookmarkGroups.group(of: original, in: groupsNow) }
            return group
        }()
        let shown = displayName(draft, url: url)
        BookmarkConfigWriter.write(target) { config in
            config.set("links", .list(next.map { .string($0) }))
            LinkPreview.store(fresh.map { [$0] } ?? [], in: &config)
            BookmarkIcons.store(icon, for: url, in: &config)
            if unlocked, !groupsNow.isEmpty || into != nil {
                var groups = groupsNow
                if let into { groups = BookmarkGroups.moving(url, to: into, in: groups) }
                BookmarkGroups.write(BookmarkGroups.pruned(groups, links: Bookmark.list(next)), into: &config)
            }
        }
        if case .image(let file) = icon {
            state.discardUploads(keeping: file)
        } else {
            state.discardUploads()
        }
        onSaved()
        if continuing {
            var blank = BookmarkFormState.Draft(widget: instance.id)
            blank.savedName = shown
            withAnimation(.snappy(duration: 0.2)) { state.draft = blank }
            WidgetDetailWindow.shared.focusField { focus = .address }
        } else {
            withAnimation(.snappy(duration: 0.2)) { state.close() }
        }
    }
}
