import AppKit
import SwiftUI

/// 「文件暂存」面板，照第三批效果图（M2）：
/// - 浏览：一行一个文件，点开、拖出去用，右边的叉移出暂存（只移出列表）；原文件
///   被挪走或删了的标灰写「找不到了」，下面「清掉找不到的 N 个」一键清。
/// - 多选：右上「多选」进入，点行勾选，底下「全部拖出」（按住拖走，一次拖好几个）、
///   「隔空投送」「压缩」「移到…」。移到以后暂存跟着文件走到新位置。
/// - 底部「放进来多久后自动移出」：1 天 / 3 天 / 7 天 / 不移出。
/// 只记位置：这里没有任何操作会删除文件，压缩只新建一个压缩包。
/// 拖文件进面板照样能放进来。
struct FileShelfDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint

    @State private var targeted = false
    @State private var selecting = false
    @State private var selection = MultiSelection<String>()
    @State private var menuOpen = false
    @State private var compressing = false
    @State private var notice: String?
    @State private var noticeID = 0

    private static let rowHeight: CGFloat = 40
    private static let rowGap: CGFloat = 4
    private static let maxRows: CGFloat = 5.5

    private var palette: FilePanelPalette {
        FilePanelPalette(accent: panelTint.accent(or: Color(hex: "#62CBD9")),
                         ink: panelTint.ink(or: Color(hex: "#032227")))
    }

    private var entries: [FileShelf.Entry] { context.isPreview ? [] : FileShelf.entries(instance) }
    private var expiry: FileShelfList.Expiry { FileShelfList.expiry(instance.config) }

    var body: some View {
        let entries = self.entries
        let missing = entries.filter(\.missing)
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.teal))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(entries, missing: missing.count)
                if entries.isEmpty {
                    emptyDrop
                } else {
                    list(entries)
                        .dropTargetOutline(targeted, tint: .teal, corner: 12)
                    if selecting {
                        selectBar(entries)
                    } else {
                        if !missing.isEmpty {
                            wideButton(FileShelfList.clearMissingTitle(missing.count)) {
                                FileShelf.remove(missing.map(\.item.path), from: instance)
                                say(tr("已清掉 \(missing.count) 个，只是移出列表"))
                            }
                        }
                        HStack(spacing: 8) {
                            wideButton(tr("在访达中显示")) {
                                FileActions.reveal(entries.compactMap(\.file).map(\.url))
                            }
                            wideButton(tr("全部清除")) {
                                guard !context.isPreview else { return }
                                FileShelf.clear(instance)
                            }
                        }
                    }
                }
                if let notice {
                    Text(verbatim: notice)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !selecting { expirySection }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !context.isPreview else { return false }
            return FileShelf.add(urls, to: instance)
        } isTargeted: { targeted = $0 }
        .onAppear {
            guard !context.isPreview else { return }
            FileShelf.sweep(instance)
        }
        // 文件被移出列表（自动到期、清掉）以后，勾着的旧条目去掉。
        .onChange(of: entries.map(\.id)) { _, ids in
            selection.prune(keeping: ids)
            if ids.isEmpty, selecting {
                selecting = false
                menuOpen = false
            }
        }
        .task(id: noticeID) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { notice = nil }
        }
    }

    // MARK: 标题

    private func header(_ entries: [FileShelf.Entry], missing: Int) -> some View {
        let present = entries.filter { !$0.missing }.map(\.id)
        let chosen = selection.ordered(present).count
        return FilePanelHeader(
            title: selecting ? tr("已选 \(chosen) 个") : tr("文件暂存"),
            subtitle: FileShelfList.subtitle(count: entries.count, missing: missing, selecting: selecting),
            button: selecting ? tr("完成") : (present.isEmpty ? nil : tr("多选")),
            prominent: selecting,
            palette: palette
        ) {
            withAnimation(.snappy(duration: 0.25)) {
                selecting.toggle()
                selection.clear()
                menuOpen = false
            }
        }
    }

    // MARK: 空的时候

    private var emptyDrop: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 24))
                .foregroundStyle(.panelTertiary)
            Text(verbatim: tr("把文件从访达或其他应用拖到这里或扩展栏上的卡片，稍后再拖出。只记住文件的位置，不会复制、移动或删除文件。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.panelQuaternary.opacity(targeted ? 0 : 1), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .dropTargetOutline(targeted, tint: .teal, corner: 12)
    }

    // MARK: 列表

    private func list(_ entries: [FileShelf.Entry]) -> some View {
        let height = min(CGFloat(entries.count), Self.maxRows) * (Self.rowHeight + Self.rowGap) - Self.rowGap
        return ScrollView {
            LazyVStack(spacing: Self.rowGap) {
                ForEach(entries) { entry in row(entry) }
            }
        }
        .scrollIndicators(.never)
        .frame(height: max(Self.rowHeight, height))
    }

    private func row(_ entry: FileShelf.Entry) -> some View {
        let on = selection.contains(entry.id)
        return HStack(spacing: 10) {
            if selecting {
                checkCircle(on: on).opacity(entry.missing ? 0.35 : 1)
            }
            Group {
                if let file = entry.file {
                    FileTypeBadgeView(file: file, size: 24)
                } else {
                    FileTypeBadgeView(file: ListedFile(url: entry.url, date: .distantPast), size: 24)
                }
            }
            .opacity(entry.missing ? 0.4 : 1)
            Text(verbatim: entry.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(entry.missing ? 0.5 : 0.95))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if entry.missing {
                Text(verbatim: tr("找不到了"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelDynamic(dark: NSColor(srgbRed: 1, green: 0.702, blue: 0.667, alpha: 1),
                                                       light: NSColor(srgbRed: 0.702, green: 0.149, blue: 0.118, alpha: 1)))
                    .lineLimit(1)
                    .fixedSize()
            }
            if !selecting {
                Button {
                    FileShelf.remove(entry.url, from: instance)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("移出暂存（不删文件）"))
                .accessibilityLabel(tr("移出暂存"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? Color.panelSelected : Color.panelFill)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.panelStroke, lineWidth: 0.6))
        }
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture {
            if selecting {
                guard !entry.missing else { return }
                selection.toggle(entry.id)
            } else if let file = entry.file {
                FileActions.open(file.url)
            }
        }
        .modifier(ShelfDragOut(url: entry.missing ? nil : entry.url))
        .contextMenu { menu(entry) }
        .help(entry.missing ? tr("原文件被移走或删掉了，可以移出暂存") : entry.item.path)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func menu(_ entry: FileShelf.Entry) -> some View {
        if let file = entry.file {
            Button(tr("打开")) { FileActions.open(file.url) }
            Button(tr("在访达中显示")) { FileActions.reveal([file.url]) }
            Divider()
            if file.isImage {
                Button(tr("拷贝图像")) { FileActions.copyImage(file.url) }
            }
            Button(tr("拷贝文件")) { FileActions.copyFile(file.url) }
        }
        Button(tr("拷贝路径")) { copyPaths([entry.item.path]) }
        Divider()
        Button(tr("移出暂存")) { FileShelf.remove(entry.url, from: instance) }
    }

    private func checkCircle(on: Bool) -> some View {
        ZStack {
            Circle()
                .fill(on ? palette.accent : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : Color.panelTertiary, lineWidth: 1.4))
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.ink)
            }
        }
        .frame(width: 18, height: 18)
    }

    // MARK: 多选的操作

    private func chosen(_ entries: [FileShelf.Entry]) -> [URL] {
        let present = entries.filter { !$0.missing }
        return selection.ordered(present.map(\.id)).map { URL(fileURLWithPath: $0) }
    }

    @ViewBuilder
    private func selectBar(_ entries: [FileShelf.Entry]) -> some View {
        let urls = chosen(entries)
        let none = urls.isEmpty
        let present = entries.filter { !$0.missing }.map(\.id)
        HStack {
            Text(verbatim: tr("\(present.count) 个可选"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 0)
            Button(selection.allSelected(present) ? tr("全不选") : tr("全选")) {
                selection.toggleAll(present)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.accent.panelReadable)
        }
        if menuOpen { moveMenu(urls).transition(.opacity.combined(with: .move(edge: .bottom))) }
        HStack(spacing: 6) {
            // 「全部拖出」是个拖拽把手：按住拖到要放的地方，选中的一起过去。
            barLabel(tr("全部拖出"), solid: true, disabled: none)
                .overlay {
                    if !none {
                        MultiFileDragSource(urls: urls) { say(tr("按住「全部拖出」拖到要放的地方")) }
                    }
                }
                .help(tr("按住拖到访达或其他应用"))
            barButton(tr("隔空投送"), disabled: none || !AirDropSender.available) {
                _ = AirDropSender.send(urls, recordInto: nil)
            }
            barButton(compressing ? tr("压缩中…") : tr("压缩"), disabled: none || compressing) { compress(urls) }
            barButton(tr("移到…"), disabled: none) {
                withAnimation(.snappy(duration: 0.2)) { menuOpen.toggle() }
            }
        }
    }

    private func barLabel(_ title: String, solid: Bool = false, disabled: Bool) -> some View {
        Text(verbatim: title)
            .font(.system(size: 13, weight: solid ? .bold : .semibold))
            .foregroundStyle(solid ? palette.ink : .panelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(solid ? palette.accent : .panelFill))
            .overlay(Capsule().strokeBorder(Color.panelStroke.opacity(solid ? 0 : 1), lineWidth: 0.6))
            .contentShape(Capsule())
            .opacity(disabled ? 0.45 : 1)
    }

    private func barButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(title, disabled: disabled) }
            .buttonStyle(.plain)
            .disabled(disabled)
    }

    private func wideButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().fill(.panelFill))
                .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func moveMenu(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: tr("移到"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            ForEach(FileBatch.destinations(excluding: URL(fileURLWithPath: "/", isDirectory: true))) { place in
                menuRow(place.title) { move(urls, to: place.url) }
            }
            menuRow(tr("选择文件夹…")) {
                guard let folder = FileActions.chooseFolder(title: tr("把选中的文件移到哪个文件夹"),
                                                            startingAt: nil) else { return }
                FileBatch.remember(folder)
                move(urls, to: folder)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelDynamic(
            dark: NSColor(srgbRed: 0.204, green: 0.204, blue: 0.227, alpha: 1),
            light: NSColor(srgbRed: 0.972, green: 0.972, blue: 0.98, alpha: 1))))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    private func menuRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func move(_ urls: [URL], to folder: URL) {
        withAnimation(.snappy(duration: 0.2)) { menuOpen = false }
        guard !urls.isEmpty else { return }
        let outcome = FileBatch.move(urls, to: folder)
        // 暂存跟着文件走：移走的换成新位置，不变成「找不到了」。
        FileShelf.relocate(zip(outcome.done, outcome.created).map { (from: $0.path, to: $1.path) }, in: instance)
        selection.clear()
        let name = FileManager.default.displayName(atPath: folder.path)
        if outcome.failed > 0 {
            say(tr("移到「\(name)」\(outcome.done.count) 个，\(outcome.failed) 个没移成（可能没有权限）"))
        } else if outcome.done.isEmpty {
            say(tr("它们已经在「\(name)」里了"))
        } else {
            say(tr("已移到「\(name)」\(outcome.done.count) 个"))
        }
    }

    private func compress(_ urls: [URL]) {
        guard !urls.isEmpty, !compressing else { return }
        compressing = true
        Task {
            let archive = await ShelfArchive.compress(urls)
            compressing = false
            if let archive {
                FileShelf.add([archive], to: instance)
                say(tr("已压缩为「\(archive.lastPathComponent)」，放在暂存最上面"))
            } else {
                say(tr("压缩没成功"))
            }
        }
    }

    private func copyPaths(_ paths: [String]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(paths.joined(separator: "\n"), forType: .string)
        say(tr("已拷贝路径"))
    }

    // MARK: 自动移出

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: tr("放进来多久后自动移出"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            HStack(spacing: 0) {
                ForEach(FileShelfList.Expiry.allCases, id: \.self) { choice in
                    let on = choice == expiry
                    Button {
                        guard !context.isPreview, !on else { return }
                        FileShelf.setExpiry(choice, for: instance)
                    } label: {
                        Text(verbatim: choice.title)
                            .font(.system(size: 13, weight: on ? .bold : .semibold))
                            .foregroundStyle(on ? palette.ink : .panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(Capsule().fill(on ? palette.accent : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(.panelFill))
            .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
            Text(verbatim: tr("只移出列表，不删文件"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
        }
    }

    private func say(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        noticeID += 1
    }
}

/// 还在的文件能拖出去；找不到的不给拖。
private struct ShelfDragOut: ViewModifier {
    var url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.onDrag { FileActions.dragProvider(url) }
        } else {
            content
        }
    }
}
