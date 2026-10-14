import AppKit
import ApplicationServices
import SwiftUI

/// Starred snippets first, then the last twenty copies, with a search field
/// over both. A click puts one back on the pasteboard, and with 点按后直接粘贴
/// on, pastes it into the app in front as well.
///
/// Any text, starred or recent, can be edited in place: the edit is saved
/// back where it was (a star stays starred, a recent copy stays in the
/// history) and can then be copied again like any other entry.
///
/// The history is kept in memory only and gone when Docket quits; the
/// footnote says so. Starred texts are the exception, because keeping them
/// is the point: they are saved with the widget (see `ClipboardPins`).
struct ClipboardDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var history: ClipboardHistory { ClipboardHistory.shared }
    @State private var copied: String?
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var editing: EditTarget?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    /// What the editor is changing: a starred text by its words, or a
    /// recent copy by its id.
    private enum EditTarget: Equatable {
        case pin(String)
        case entry(UUID)

        var isPin: Bool {
            if case .pin = self { return true }
            return false
        }
    }

    private var pins: [String] { ClipboardPins.pins(instance.config) }
    private var pastes: Bool { instance.config.bool("pasteOnClick", default: false) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.indigo))
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if let editing {
                    PanelHeader(symbol: "pencil", title: "编辑",
                                subtitle: editing.isPin ? "保存后仍在星标里" : "保存后回到历史，可再次拷贝")
                    editor
                    HStack(spacing: 8) {
                        PanelButton(title: "取消", symbol: "xmark") { endEditing() }
                        PanelButton(title: "保存", symbol: "checkmark") { saveEdit(copy: false) }
                            .disabled(draftIsEmpty)
                        PanelButton(title: "保存并拷贝", symbol: "doc.on.doc", prominent: true) {
                            saveEdit(copy: true)
                        }
                        .disabled(draftIsEmpty)
                    }
                } else {
                    PanelHeader(symbol: "list.clipboard", title: "剪贴板",
                                subtitle: pastes ? "点按即可粘贴到前台应用" : "点按即可重新拷贝 · 星标保留常用文本")
                    searchField
                    list
                    HStack(spacing: 8) {
                        PanelButton(title: "清除历史", symbol: "trash") {
                            guard !context.isPreview else { return }
                            history.clear()
                        }
                    }
                }
                Text("历史只保存在内存中，退出码头后即清除；加了星标的文本会保存下来。密码管理器标记为隐藏的内容不会被记录。")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if !context.isPreview { history.start() } }
    }

    // MARK: Editing

    private var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draftLimit: Int {
        editing?.isPin == true ? ClipboardPins.maxLength : 20_000
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $draft)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($editorFocused)
                .disabled(context.isPreview)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                Text(draftIsEmpty ? "内容不能为空" : "\(draft.count) 字")
                    .font(WidgetStyle.caption(10).monospacedDigit())
                    .foregroundStyle(.white.opacity(draft.count > draftLimit || draftIsEmpty ? 0.9 : 0.5))
                Spacer(minLength: 0)
                Text("Esc 取消")
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 286)
        .glassPane(cornerRadius: 12)
        .onExitCommand { endEditing() }
    }

    private func beginEditing(_ target: EditTarget, text: String) {
        guard !context.isPreview else { return }
        draft = text
        searching = false
        withAnimation(.snappy(duration: 0.2)) { editing = target }
        DispatchQueue.main.async { editorFocused = true }
    }

    private func endEditing() {
        editorFocused = false
        withAnimation(.snappy(duration: 0.2)) { editing = nil }
    }

    /// Saves the edit where it came from, and with 保存并拷贝 puts it on
    /// the pasteboard as well (never pasting: the editor was in front, so
    /// there is no app to paste into that you meant).
    private func saveEdit(copy: Bool) {
        guard let target = editing, !context.isPreview, !draftIsEmpty else { return }
        let text = draft
        switch target {
        case .pin(let old):
            let next = ClipboardPins.replacing(old, with: text, in: pins)
            savePins(next)
            if copy {
                let saved = ClipboardPins.clip(text)
                put(saved, paste: false)
                copied = "pin:" + saved
            }
        case .entry(let id):
            guard let edited = history.edit(id, text: text) else { return }
            if copy {
                history.copy(edited)
                copied = history.entries.first?.id.uuidString
            }
        }
        endEditing()
    }

    private func editButton(_ target: EditTarget, text: String) -> some View {
        Button {
            beginEditing(target, text: text)
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("编辑")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            TextField("", text: $query, prompt: Text("搜索剪贴板"))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($searching)
                .disabled(context.isPreview)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .glassPane(cornerRadius: 9)
    }

    @ViewBuilder
    private var list: some View {
        let shownPins = pins.filter { ClipboardPins.matches($0, query: query) }
        let shownEntries = context.isPreview ? [] : history.entries.filter { entry in
            if case .text(let text) = entry.content, ClipboardPins.isPinned(text, in: pins) { return false }
            return ClipboardPins.matches(entry.preview, query: query)
        }
        if shownPins.isEmpty && shownEntries.isEmpty {
            PanelNote(symbol: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                      text: query.isEmpty ? "拷贝的文本和图片会显示在这里。点星标可以把常用文本留下来。" : "没有找到“\(query)”。")
                .frame(height: 248)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !shownPins.isEmpty {
                        sectionLabel("星标")
                        ForEach(shownPins, id: \.self) { pinRow($0) }
                    }
                    if !shownEntries.isEmpty {
                        if !shownPins.isEmpty { sectionLabel("最近") }
                        ForEach(shownEntries) { entryRow($0) }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 248)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.leading, 4)
            .padding(.top, 2)
    }

    private func pinRow(_ text: String) -> some View {
        rowShell(id: "pin:" + text) {
            Image(systemName: "text.quote")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.1))
        } title: {
            text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        } caption: {
            "星标"
        } star: {
            editButton(.pin(text), text: text)
            starButton(text, pinned: true)
        } tap: {
            put(text)
            copied = "pin:" + text
        }
        .contextMenu {
            Button("拷贝") { put(text, paste: false) }
            Button("编辑") { beginEditing(.pin(text), text: text) }
            Button("上移") { savePins(ClipboardPins.moving(text, by: -1, in: pins)) }
            Button("下移") { savePins(ClipboardPins.moving(text, by: 1, in: pins)) }
            Button("取消星标") { savePins(ClipboardPins.toggling(text, in: pins)) }
        }
    }

    private func entryRow(_ entry: ClipboardHistory.Entry) -> some View {
        let text = Self.text(of: entry)
        return rowShell(id: entry.id.uuidString) {
            thumbnail(entry)
        } title: {
            entry.preview
        } caption: {
            RelativeAge.caption(entry.date, now: context.now)
        } star: {
            if let text {
                editButton(.entry(entry.id), text: text)
                starButton(text, pinned: false)
            }
        } tap: {
            history.copy(entry)
            if pastes { Self.pasteSoon() }
            copied = history.entries.first?.id.uuidString
        }
        .contextMenu {
            Button("拷贝") { history.copy(entry) }
            if let text {
                Button("编辑") { beginEditing(.entry(entry.id), text: text) }
                Button("加星标") { savePins(ClipboardPins.toggling(text, in: pins)) }
            }
            Button("删除") { history.remove(entry) }
        }
    }

    private func rowShell<Thumb: View, Star: View>(
        id: String,
        @ViewBuilder thumb: () -> Thumb,
        title: () -> String,
        caption: () -> String,
        @ViewBuilder star: () -> Star,
        tap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            thumb()
                .frame(width: 30, height: 30)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title())
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(copied == id ? (pastes ? "已粘贴" : "已拷贝") : caption())
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) { star() }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture(perform: tap)
    }

    private func starButton(_ text: String, pinned: Bool) -> some View {
        Button {
            guard !context.isPreview else { return }
            withAnimation(.snappy(duration: 0.25)) { savePins(ClipboardPins.toggling(text, in: pins)) }
        } label: {
            Image(systemName: pinned ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pinned ? Color.yellow : .white.opacity(0.5))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(pinned ? "取消星标" : "加星标，退出后也保留")
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

    private static func text(of entry: ClipboardHistory.Entry) -> String? {
        if case .text(let value) = entry.content { return value }
        return nil
    }

    private func savePins(_ next: [String]) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance) { ClipboardPins.store(next, in: &$0) }
    }

    private func put(_ text: String, paste: Bool? = nil) {
        guard !context.isPreview else { return }
        history.copyText(text)
        if paste ?? pastes { Self.pasteSoon() }
    }

    /// ⌘V into the app in front, a moment after the copy so the pasteboard
    /// is settled. Posting keystrokes needs Accessibility; without it macOS
    /// is asked to show its prompt and the text is simply left copied.
    static func pasteSoon() {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let v: CGKeyCode = 9
            let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
