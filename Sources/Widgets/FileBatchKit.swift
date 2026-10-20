import AppKit
import SwiftUI

// 「下载」和「最近截图」两个面板共用的零件：标题行、搜索框、筛选胶囊、
// 文件类型小标，以及多选组件 `FileSelectList`（勾选、双击改名、底部
// 「移到… / 压缩 / 删除」和移到的文件夹菜单）。照第二批效果图：深色玻璃、
// 正文 13pt 起、实心按钮深色字，强调色只用在小面积上。

/// 面板的强调色和实心按钮上的深色字。
struct FilePanelPalette {
    var accent: Color
    var ink: Color

    static let red = Color(hex: "#FF6B5A")
}

/// 标题、一行说明、右上角一个胶囊按钮（「多选」或实心的「完成」）。
struct FilePanelHeader: View {
    var title: String
    var subtitle: String
    var button: String?
    var prominent = false
    var palette: FilePanelPalette
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(verbatim: subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let button {
                Button(action: action) {
                    Text(verbatim: button)
                        .font(.system(size: 13, weight: prominent ? .bold : .semibold))
                        .foregroundStyle(prominent ? palette.ink : .white.opacity(0.92))
                        .padding(.horizontal, prominent ? 15 : 13)
                        .frame(height: 28)
                        .background(Capsule().fill(prominent ? palette.accent : .white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.18), lineWidth: 0.6))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 放大镜加输入框；输入时描一圈强调色，右边一个清空。
struct FileSearchField: View {
    @Binding var text: String
    var prompt: String
    var palette: FilePanelPalette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            TextField("", text: $text, prompt: Text(verbatim: prompt).foregroundStyle(.white.opacity(0.45)))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($focused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(tr("清空搜索"))
                .accessibilityLabel(tr("清空搜索"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused || !text.isEmpty ? palette.accent.opacity(0.9) : .white.opacity(0.14),
                              lineWidth: focused || !text.isEmpty ? 1.2 : 0.6)
        }
        .contentShape(.rect)
        .onTapGesture { WidgetDetailWindow.shared.focusField { focused = true } }
    }
}

/// 一排筛选胶囊，选中的实心。
struct FileFilterChips<Item: Hashable>: View {
    var items: [Item]
    var title: (Item) -> String
    @Binding var selected: Item
    var palette: FilePanelPalette

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                ForEach(items, id: \.self) { item in
                    let on = item == selected
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selected = item }
                    } label: {
                        Text(verbatim: title(item))
                            .font(.system(size: 13, weight: on ? .bold : .semibold))
                            .foregroundStyle(on ? palette.ink : .white.opacity(0.88))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .background(Capsule().fill(on ? palette.accent : .white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.14), lineWidth: 0.6))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }
}

/// 折角纸上写类型（PDF、ZIP、DMG…），颜色按类型；文件夹画文件夹。
struct FileTypeBadgeView: View {
    var file: ListedFile
    var size: CGFloat = 32

    var body: some View {
        let badge = FileBadge.of(file)
        Group {
            if file.isDirectory {
                Image(systemName: "folder.fill")
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(Color(hex: badge.colorHex))
            } else {
                ZStack {
                    FoldedPaper(fold: size * 0.28)
                        .fill(Color(hex: badge.colorHex))
                    FoldedCorner(fold: size * 0.28)
                        .fill(.black.opacity(0.25))
                    Text(verbatim: badge.label)
                        .font(.system(size: badge.label.count > 3 ? 8.5 : 9.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .offset(y: size * 0.12)
                }
                .frame(width: size * 0.8, height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct FoldedPaper: Shape {
    var fold: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c: CGFloat = 3
        p.move(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct FoldedCorner: Shape {
    var fold: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX - fold, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
        p.closeSubpath()
        return p
    }
}

/// 行首的图：截图用缩略图，下载用类型小标。
enum FileRowIcon {
    case badge, thumbnail
}

/// 一行的第二行小字：「2.1 MB · 10:05」。
@MainActor
enum FileRowCaption {
    static func text(_ file: ListedFile, now: Date) -> String {
        let when = FileDate.short(file.date, now: now)
        if file.isDirectory { return "\(tr("文件夹")) · \(when)" }
        guard let size = FileActions.size(file.size) else { return when }
        return "\(size) · \(when)"
    }
}

// MARK: - 多选组件

/// 两个面板的多选态：勾选行、双击改名，底下「移到… / 压缩 / 删除」。
/// 删除进废纸篓；移到和压缩撞名自动编号，不覆盖。
struct FileSelectList: View {
    var files: [ListedFile]
    @Binding var selection: MultiSelection<URL>
    /// 外面（浏览态右键「重命名」）带进来要改名的那一个。
    @Binding var renaming: URL?
    var feed: FolderFeed
    var icon: FileRowIcon
    var palette: FilePanelPalette
    var now: Date
    var emptyText: String

    @State private var renameText = ""
    @State private var menuOpen = false
    @State private var compressing = false
    @State private var notice: String?
    @State private var noticeID = 0
    @FocusState private var renameFocused: Bool

    private static let rowHeight: CGFloat = 50
    private static let rowGap: CGFloat = 6
    private static let maxRows: CGFloat = 4.5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: tr("\(files.count) 个"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                if !files.isEmpty {
                    Button(selection.allSelected(files.map(\.url)) ? tr("全不选") : tr("全选")) {
                        selection.toggleAll(files.map(\.url))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
                }
            }
            if files.isEmpty {
                Text(verbatim: emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                list
            }
            if menuOpen { moveMenu.transition(.opacity.combined(with: .move(edge: .bottom))) }
            if let notice {
                Text(verbatim: notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionBar
        }
        // 只去掉真的不在了的（删掉、移走、改名前的旧名字）；搜索、筛选藏起来的照样勾着，
        // 刚改名还没轮询到的新名字也不丢。
        .onChange(of: feed.files.map(\.url)) { old, new in
            let gone = Set(old).subtracting(new)
            guard !gone.isEmpty else { return }
            selection.prune(keeping: selection.ids.subtracting(gone))
            if let renaming, gone.contains(renaming) { self.renaming = nil }
        }
        .onChange(of: renaming) { _, url in
            guard let url else { return }
            renameText = url.lastPathComponent
            WidgetDetailWindow.shared.focusField { renameFocused = true }
        }
        .onChange(of: renameFocused) { old, new in
            if old, !new { commitRename() }
        }
        .onAppear {
            if let renaming {
                renameText = renaming.lastPathComponent
                WidgetDetailWindow.shared.focusField { renameFocused = true }
            }
        }
        .task(id: noticeID) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { notice = nil }
        }
    }

    private var list: some View {
        let height = min(CGFloat(files.count), Self.maxRows) * (Self.rowHeight + Self.rowGap) - Self.rowGap
        return ScrollView {
            LazyVStack(spacing: Self.rowGap) {
                ForEach(files) { file in row(file) }
            }
        }
        .scrollIndicators(.never)
        .frame(height: max(Self.rowHeight, height))
    }

    private func row(_ file: ListedFile) -> some View {
        let on = selection.contains(file.url)
        let editing = renaming == file.url
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(on ? palette.accent : .clear)
                    .overlay(Circle().strokeBorder(on ? .clear : .white.opacity(0.45), lineWidth: 1.4))
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette.ink)
                }
            }
            .frame(width: 20, height: 20)
            rowIcon(file)
            VStack(alignment: .leading, spacing: 2) {
                if editing {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .focused($renameFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.accent.opacity(0.9), lineWidth: 1.2))
                } else {
                    Text(verbatim: file.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(verbatim: FileRowCaption.text(file, now: now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(on ? 0.12 : 0.06))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(on ? 0.2 : 0.1), lineWidth: 0.6))
        }
        .contentShape(.rect(cornerRadius: 12))
        // 双击在前、单击在后，SwiftUI 才分得清。
        .onTapGesture(count: 2) { startRename(file) }
        .onTapGesture {
            guard !editing else { return }
            selection.toggle(file.url)
        }
        .onDrag { FileActions.dragProvider(file.url) }
        .contextMenu {
            Button(tr("重命名")) { startRename(file) }
            Button(tr("在访达中显示")) { FileActions.reveal([file.url]) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityAction(named: Text(tr("重命名"))) { startRename(file) }
    }

    @ViewBuilder
    private func rowIcon(_ file: ListedFile) -> some View {
        switch icon {
        case .badge:
            FileTypeBadgeView(file: file)
        case .thumbnail:
            FileThumb(url: file.url, pixels: 96, fill: file.isImage)
                .frame(width: 40, height: 30)
                .background(Color.white.opacity(0.06))
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: 改名

    private func startRename(_ file: ListedFile) {
        guard renaming != file.url else { return }
        commitRename()
        renaming = file.url
    }

    private func cancelRename() {
        renaming = nil
        renameFocused = false
    }

    private func commitRename() {
        guard let url = renaming else { return }
        renaming = nil
        let proposed = renameText
        switch FileBatch.rename(url, to: proposed) {
        case .failure(let problem):
            say(problem.message)
            NSSound.beep()
        case .success(nil):
            break
        case .success(let target?):
            if selection.contains(url) {
                selection.toggle(url)
                selection.toggle(target)
            }
            feed.forget([url])
        }
    }

    // MARK: 底部操作

    private var chosen: [URL] { selection.ordered(files.map(\.url)) }

    private var actionBar: some View {
        let none = chosen.isEmpty
        return HStack(spacing: 8) {
            barButton(tr("移到…"), solid: true, disabled: none) {
                withAnimation(.snappy(duration: 0.2)) { menuOpen.toggle() }
            }
            barButton(compressing ? tr("压缩中…") : tr("压缩"), disabled: none || compressing) { compress() }
            barButton(tr("删除"), tint: FilePanelPalette.red, disabled: none) { trash() }
        }
    }

    private func barButton(_ title: String, solid: Bool = false, tint: Color = .white,
                           disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: solid ? .bold : .semibold))
                .foregroundStyle(solid ? palette.ink : tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Capsule().fill(solid ? palette.accent : .white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(.white.opacity(solid ? 0 : 0.14), lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private var moveMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: tr("移到"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            ForEach(FileBatch.destinations(excluding: feed.folder)) { place in
                menuRow(place.title) { move(to: place.url) }
            }
            menuRow(tr("选择文件夹…")) {
                guard let folder = FileActions.chooseFolder(title: tr("把选中的文件移到哪个文件夹"),
                                                            startingAt: nil) else { return }
                FileBatch.remember(folder)
                move(to: folder)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#34343A")))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    private func menuRow(_ title: String, action: @escaping () -> Void) -> some View {
        MenuRow(title: title, palette: palette, action: action)
    }

    private func move(to folder: URL) {
        let urls = chosen
        withAnimation(.snappy(duration: 0.2)) { menuOpen = false }
        guard !urls.isEmpty else { return }
        let outcome = FileBatch.move(urls, to: folder)
        feed.forget(Set(outcome.done))
        let name = FileManager.default.displayName(atPath: folder.path)
        if outcome.failed > 0 {
            say(tr("移到「\(name)」\(outcome.done.count) 个，\(outcome.failed) 个没移成（可能没有权限）"))
        } else if outcome.done.isEmpty {
            say(tr("它们已经在「\(name)」里了"))
        } else {
            say(tr("已移到「\(name)」\(outcome.done.count) 个"))
        }
    }

    private func compress() {
        let urls = chosen
        guard !urls.isEmpty, !compressing else { return }
        compressing = true
        Task {
            let archive = await FileBatch.compress(urls)
            compressing = false
            if let archive {
                say(tr("已压缩为「\(archive.lastPathComponent)」"))
                feed.refresh(force: true)
            } else {
                say(tr("压缩没成功"))
            }
        }
    }

    private func trash() {
        let urls = chosen
        guard !urls.isEmpty else { return }
        menuOpen = false
        let outcome = FileBatch.trash(urls)
        feed.forget(Set(outcome.done))
        if outcome.failed > 0 {
            say(tr("移到废纸篓 \(outcome.done.count) 个，\(outcome.failed) 个没删掉"))
        } else {
            say(tr("已移到废纸篓 \(outcome.done.count) 个，在废纸篓里能找回"))
        }
    }

    private func say(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        noticeID += 1
    }
}

/// 「移到」菜单里的一行，悬停变亮。
private struct MenuRow: View {
    var title: String
    var palette: FilePanelPalette
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(hovered ? palette.accent : .white.opacity(0.6))
                Text(verbatim: title)
                    .font(.system(size: 14, weight: hovered ? .semibold : .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovered ? palette.accent.opacity(0.2) : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
