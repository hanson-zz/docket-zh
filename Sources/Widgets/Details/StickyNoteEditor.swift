import AppKit
import SwiftUI

/// 便签面板里写字的那张纸（便签 v3）：写字时和不写字时是同一个样子。
///
/// 一个 `NSTextView`（TextKit 1，自己搭存储、排版和容器），原文里认得的框子换成一个
/// 附件字画成圆圈（`StickyEditing`），圆圈能直接点勾，写字时也不露出 `[ ]` 这类原始字。
/// 勾掉的项框后的字换淡墨、划线，不挪位置。
///
/// - 回车：清单项上在这一条后面插下一条；空的一条上再回车退出清单；普通行照常换行。
///   ⇧↩ 普通换行，⌘↩ 存好、收起编辑。
/// - 输入法组字（有 marked text）时什么都不改：回车交给输入法上屏，不插行；不重画字、
///   不改颜色、不往外报字（2e38f63 修过组字闪退，这里只读 `NSRange` 整数，不碰外来的
///   `String.Index`）。
/// - 拷贝出去的是原文（圆圈还原成 `[ ] `），粘贴进来的 `[ ] ` 自动变圆圈。
/// - 固定高度，长了在纸里滚，工具条不被推走。
/// - 右键一行「发到快速待办」。
struct StickyNoteEditor: NSViewRepresentable {
    @Binding var text: String
    var look: Look
    var editable: Bool
    /// 每换一个就把光标放到末尾：打开面板、新一张、翻页。
    var focusToken: UUID
    var handle: StickyEditorHandle
    var onEditingChanged: (Bool) -> Void
    var onCollapse: () -> Void
    var onSend: (Int) -> Void

    /// 字体、字号和纸上的三种颜色。
    struct Look: Equatable {
        var font: StickyNoteFont
        var size: CGFloat
        var ink: String
        var faded: String
        var paper: String
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        // TextKit 1：圆圈是附件格（NSTextAttachmentCell），点它要按字形位置算。
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = StickyTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = NSSize(width: 0, height: 4)
        view.isEditable = editable
        view.isSelectable = editable
        view.setAccessibilityLabel(tr("便签"))
        view.setAccessibilityHelp(tr("回车接着写下一条，Shift 加回车换行，Command 加回车收起"))
        scroll.documentView = view

        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.look = look
        coordinator.focusToken = focusToken
        handle.coordinator = coordinator
        view.coordinator = coordinator
        coordinator.applyLook()
        coordinator.render(text, caret: .end)
        if editable { coordinator.focusAtEnd() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        handle.coordinator = coordinator
        guard let view = coordinator.view else { return }
        view.isEditable = editable
        view.isSelectable = editable
        // 至少铺满纸：点短便签下面的空白也落光标。
        let height = scroll.contentSize.height
        if view.minSize.height != height { view.minSize = NSSize(width: 0, height: height) }
        // 组字时一个字都不动，等上屏后下一次再对。
        guard !view.hasMarkedText() else { return }
        if look != coordinator.look {
            coordinator.look = look
            coordinator.applyLook()
        }
        if text != coordinator.raw {
            coordinator.render(text, caret: .keep)
        }
        if focusToken != coordinator.focusToken {
            coordinator.focusToken = focusToken
            if editable { coordinator.focusAtEnd() }
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StickyNoteEditor
        weak var view: StickyTextView?
        var look: Look
        var focusToken = UUID()
        /// 编辑器里现在这段字对应的原文，和绑定比对用。
        private(set) var raw = ""
        /// 自己在改字（换圆圈、插下一条），这时的变更通知不再处理一遍。
        private var patching = false

        init(_ parent: StickyNoteEditor) {
            self.parent = parent
            self.look = parent.look
        }

        private var storage: NSTextStorage? { view?.textStorage }

        // MARK: 样子

        private var font: NSFont { StickyFont.nsFont(look.font, size: look.size) }
        private var ink: NSColor { NSColor(Color(hex: look.ink)) }
        private var faded: NSColor { NSColor(Color(hex: look.faded)) }
        private var paperColor: NSColor { NSColor(Color(hex: look.paper)) }

        private var paragraph: NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            return style
        }

        private var base: [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        }

        func applyLook() {
            guard let view, let storage else { return }
            view.insertionPointColor = ink
            view.typingAttributes = base
            let circle = circleLook
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                (( value as? NSTextAttachment)?.attachmentCell as? StickyCircleCell)?.look = circle
            }
            restyle()
        }

        private var circleLook: StickyCircleCell.Look {
            let side = max(14, look.size * 0.72)
            return .init(side: side, gap: max(6, look.size * 0.34), capHeight: font.capHeight,
                         ink: ink, faded: faded, paper: paperColor)
        }

        private func circle(_ box: StickyEditing.Box) -> NSAttributedString {
            let attachment = NSTextAttachment()
            attachment.attachmentCell = StickyCircleCell(box: box, look: circleLook)
            let string = NSMutableAttributedString(attachment: attachment)
            string.addAttributes(base, range: NSRange(location: 0, length: string.length))
            return string
        }

        private func line(_ piece: StickyEditing.Piece) -> NSAttributedString {
            let out = NSMutableAttributedString(string: piece.prefix, attributes: base)
            if let box = piece.box { out.append(circle(box)) }
            out.append(NSAttributedString(string: piece.rest, attributes: base))
            return out
        }

        private func attributed(_ text: String) -> NSAttributedString {
            let out = NSMutableAttributedString()
            for (index, piece) in StickyEditing.pieces(text).enumerated() {
                if index > 0 { out.append(NSAttributedString(string: "\n", attributes: base)) }
                out.append(line(piece))
            }
            return out
        }

        // MARK: 整段换字

        enum Caret { case end, keep }

        /// 换成另一段原文（打开、翻页、撤销撕掉、菜单里的全部取消勾选）。撤销记录清掉：
        /// 旧记录的位置对不上新字。
        func render(_ text: String, caret: Caret) {
            guard let view, let storage else { return }
            let oldDisplay = storage.string
            let anchor = StickyEditing.caretAnchor(in: oldDisplay, utf16: view.selectedRange().location)
            patching = true
            storage.setAttributedString(attributed(text))
            patching = false
            raw = text
            restyle()
            view.undoManager?.removeAllActions()
            let display = storage.string
            let location: Int
            switch view.wantsFocusAtEnd ? .end : caret {
            case .end: location = (display as NSString).length
            case .keep: location = StickyEditing.location(in: display, line: anchor.line, fromEnd: anchor.fromEnd)
            }
            view.setSelectedRange(NSRange(location: min(location, (display as NSString).length), length: 0))
        }

        /// 光标放到末尾（有清单也一样）。还没进窗口时等进了窗口再放。
        func focusAtEnd() {
            guard let view else { return }
            view.wantsFocusAtEnd = true
            Task { @MainActor [weak view] in view?.focusAtEndIfWanted() }
        }

        // MARK: 读字

        /// 一行（不含换行）的字和圆圈。
        private func runs(_ range: NSRange) -> [StickyEditing.Run] {
            guard let storage else { return [] }
            var out: [StickyEditing.Run] = []
            let string = storage.string as NSString
            storage.enumerateAttribute(.attachment, in: range) { value, part, _ in
                if let cell = (value as? NSTextAttachment)?.attachmentCell as? StickyCircleCell {
                    for _ in 0..<part.length { out.append(.box(cell.box)) }
                } else {
                    out.append(.text(string.substring(with: part)))
                }
            }
            return out
        }

        /// 每一行（不含换行）的范围，空字也有一行。
        private func lineRanges() -> [NSRange] {
            guard let storage else { return [] }
            let string = storage.string as NSString
            var out: [NSRange] = []
            var start = 0
            while true {
                let rest = NSRange(location: start, length: string.length - start)
                let newline = string.range(of: "\n", options: [], range: rest)
                if newline.location == NSNotFound {
                    out.append(rest)
                    return out
                }
                out.append(NSRange(location: start, length: newline.location - start))
                start = newline.location + 1
            }
        }

        private func currentRaw() -> String {
            lineRanges().map { StickyEditing.rawLine(runs($0)) }.joined(separator: "\n")
        }

        /// 一段选中的字还原成原文（拷贝、拖出去用）：圆圈换回框子字，别的照原样。
        func rawText(of range: NSRange) -> String {
            var out = ""
            for run in runs(range) {
                switch run {
                case .text(let words): out += words
                case .box(let box): out += box.token
                }
            }
            return out
        }

        /// 光标在第几行，这一行是什么。有选区时不算在某一行上。
        private func caretLine() -> (index: Int, piece: StickyEditing.Piece)? {
            guard let view else { return nil }
            let selection = view.selectedRange()
            guard selection.location != NSNotFound, selection.length == 0 else { return nil }
            let line = StickyEditing.caretAnchor(in: view.string, utf16: selection.location).line
            let pieces = StickyEditing.pieces(raw)
            guard pieces.indices.contains(line) else { return nil }
            return (line, pieces[line])
        }

        func selectedLines() -> ClosedRange<Int>? {
            guard let view, view.window?.firstResponder === view else { return nil }
            let range = view.selectedRange()
            guard range.location != NSNotFound else { return nil }
            return StickyChecklist.lineRange(in: view.string, utf16Location: range.location, length: range.length)
        }

        func line(at point: NSPoint) -> Int? {
            guard let view else { return nil }
            let index = view.characterIndexForInsertion(at: point)
            return StickyEditing.caretAnchor(in: view.string, utf16: index).line
        }

        var currentText: String { raw }

        // MARK: 改字之后

        func textDidChange(_ notification: Notification) {
            guard !patching, let view, !view.hasMarkedText() else { return }
            normalize(undoing: view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true)
            restyle()
            raw = currentRaw()
            if parent.text != raw { parent.text = raw }
        }

        /// 打出来、粘贴进来的框子换成圆圈，被挪到行中间的圆圈去掉。只换对不上的那几行，
        /// 光标按离行尾的距离放回去。撤销、重做时不换，免得撤销一下又被换回来。
        private func normalize(undoing: Bool) {
            guard !undoing, let view, let storage else { return }
            let text = currentRaw()
            let wanted = StickyEditing.pieces(text)
            guard storage.string != StickyEditing.display(text) else { return }
            let ranges = lineRanges()
            guard ranges.count == wanted.count else { return }
            let caret = view.selectedRange()
            let anchor = StickyEditing.caretAnchor(in: storage.string, utf16: caret.location)
            patching = true
            // 从后往前换，前面的位置不受影响。
            for index in ranges.indices.reversed() {
                let range = ranges[index]
                let piece = wanted[index]
                guard (storage.string as NSString).substring(with: range) != piece.display else { continue }
                let replacement = line(piece)
                if view.shouldChangeText(in: range, replacementString: replacement.string) {
                    storage.replaceCharacters(in: range, with: replacement)
                    view.didChangeText()
                }
            }
            patching = false
            if caret.length == 0 {
                let location = StickyEditing.location(in: storage.string, line: anchor.line, fromEnd: anchor.fromEnd)
                view.setSelectedRange(NSRange(location: location, length: 0))
            }
        }

        /// 只改属性：底色墨、行距；勾掉的项框后的字淡墨加划线。
        func restyle() {
            guard let view, let storage, !view.hasMarkedText() else { return }
            let attributes = base
            let fadedInk = faded
            storage.beginEditing()
            for range in lineRanges() where range.length > 0 {
                storage.addAttributes(attributes, range: range)
                storage.removeAttribute(.strikethroughStyle, range: range)
                guard let mark = leadingCircle(in: range), mark.cell.box.done else { continue }
                let after = NSRange(location: mark.index + 1, length: NSMaxRange(range) - mark.index - 1)
                guard after.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: fadedInk, range: after)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: after)
                storage.addAttribute(.strikethroughColor, value: fadedInk, range: after)
            }
            storage.endEditing()
            view.typingAttributes = attributes
        }

        /// 行首（缩进、列表符号之后）的圆圈。
        private func leadingCircle(in range: NSRange) -> (index: Int, cell: StickyCircleCell)? {
            guard let storage else { return nil }
            let string = storage.string as NSString
            var index = range.location
            while index < NSMaxRange(range) {
                if string.character(at: index) == StickyEditing.markUnit {
                    let prefix = string.substring(with: NSRange(location: range.location, length: index - range.location))
                    guard StickyEditing.isPrefix(prefix),
                          let cell = (storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?
                            .attachmentCell as? StickyCircleCell else { return nil }
                    return (index, cell)
                }
                index += 1
            }
            return nil
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                      toCharacterRange proposed: NSRange) -> NSRange {
            guard proposed.length == 0, !textView.hasMarkedText() else { return proposed }
            let location = StickyEditing.adjustedCaret(in: textView.string, from: old.location, to: proposed.location)
            return NSRange(location: location, length: 0)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view, !view.hasMarkedText() else { return }
            view.typingAttributes = base
            if let lines = selectedLines() { lastLines = lines }
        }

        /// 最近一次选区落在的几行：点「清单」按钮时编辑器可能已经失焦。
        private(set) var lastLines: ClosedRange<Int>?

        // MARK: 点圆圈、回车

        func circleIsLeading(at index: Int) -> Bool {
            lineRanges().contains { range in
                NSLocationInRange(index, range) && leadingCircle(in: range)?.index == index
            }
        }

        /// 点圆圈：换成勾上（或取消）的那个，字不动。走 shouldChangeText，⌘Z 能撤销。
        func toggle(at index: Int) {
            guard let view, let storage, parent.editable, !view.hasMarkedText(),
                  index < storage.length,
                  let cell = (storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?
                    .attachmentCell as? StickyCircleCell else { return }
            let range = NSRange(location: index, length: 1)
            let replacement = circle(cell.box.toggled)
            let selection = view.selectedRange()
            guard view.shouldChangeText(in: range, replacementString: replacement.string) else { return }
            storage.replaceCharacters(in: range, with: replacement)
            view.didChangeText()
            view.setSelectedRange(selection)
        }

        func handleReturn(command: Bool, shift: Bool, option: Bool) -> Bool {
            guard let view else { return false }
            let line = caretLine()
            switch StickyEditing.returnAction(command: command, shift: shift, option: option,
                                              composing: view.hasMarkedText(), line: line?.piece) {
            case .passThrough:
                return false
            case .newline:
                view.insertNewlineIgnoringFieldEditor(nil)
            case .nextItem:
                if let line { insertNextItem(after: line.index, piece: line.piece) }
            case .endItem:
                if let line { endItem(line.index, piece: line.piece) }
            case .collapse:
                parent.onCollapse()
            }
            return true
        }

        /// 在第 `index` 行后面插一条空的清单项，光标放进去。
        private func insertNextItem(after index: Int, piece: StickyEditing.Piece) {
            guard let view, let storage else { return }
            let ranges = lineRanges()
            guard ranges.indices.contains(index) else { return }
            let at = NSMaxRange(ranges[index])
            let insertion = NSMutableAttributedString(string: "\n", attributes: base)
            insertion.append(line(StickyEditing.nextItem(after: piece)))
            let range = NSRange(location: at, length: 0)
            guard view.shouldChangeText(in: range, replacementString: insertion.string) else { return }
            patching = true
            storage.replaceCharacters(in: range, with: insertion)
            patching = false
            view.didChangeText()
            let caret = NSRange(location: at + insertion.length, length: 0)
            view.setSelectedRange(caret)
            view.scrollRangeToVisible(caret)
        }

        /// 空的一条上再回车：去掉圆圈和列表符号，留下缩进，退出清单。
        private func endItem(_ index: Int, piece: StickyEditing.Piece) {
            guard let view, let storage else { return }
            let ranges = lineRanges()
            guard ranges.indices.contains(index), let mark = leadingCircle(in: ranges[index]) else { return }
            let head = NSRange(location: ranges[index].location, length: mark.index + 1 - ranges[index].location)
            let indent = StickyEditing.endingItem(piece).prefix
            guard view.shouldChangeText(in: head, replacementString: indent) else { return }
            patching = true
            storage.replaceCharacters(in: head, with: NSAttributedString(string: indent, attributes: base))
            patching = false
            view.didChangeText()
            view.setSelectedRange(NSRange(location: NSMaxRange(ranges[index]) - head.length + (indent as NSString).length,
                                          length: 0))
        }

        // MARK: 焦点

        func focusChanged(_ focused: Bool) {
            let report = parent.onEditingChanged
            // 不在 AppKit 切第一响应者的半中间改 SwiftUI 状态。
            Task { @MainActor in report(focused) }
        }
    }
}

/// 面板拿编辑器的现状用：最近选区落在哪几行、组没组字。
@MainActor
final class StickyEditorHandle {
    weak var coordinator: StickyNoteEditor.Coordinator?

    func selectedLines() -> ClosedRange<Int>? { coordinator?.selectedLines() ?? coordinator?.lastLines }

    var isComposing: Bool { coordinator?.view?.hasMarkedText() == true }
}

/// 写字的那个 NSTextView：点圆圈勾、回车分去向、右键「发到快速待办」、拷出原文。
final class StickyTextView: NSTextView {
    weak var coordinator: StickyNoteEditor.Coordinator?
    /// 打开面板、新一张时要把光标放到末尾，等进了窗口再放。
    var wantsFocusAtEnd = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusAtEndIfWanted()
    }

    func focusAtEndIfWanted() {
        guard wantsFocusAtEnd, let window, isEditable else { return }
        wantsFocusAtEnd = false
        window.makeFirstResponder(self)
        guard !hasMarkedText() else { return }
        let end = NSRange(location: (string as NSString).length, length: 0)
        setSelectedRange(end)
        scrollRangeToVisible(end)
    }

    // MARK: 点圆圈

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isEditable, !hasMarkedText(), let index = circleIndex(at: point) {
            coordinator?.toggle(at: index)
            return
        }
        super.mouseDown(with: event)
    }

    /// 指针下是不是行首的圆圈（按字形框算，四周放宽几点好点中）。
    private func circleIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let inner = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: inner, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length,
              (storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?
                .attachmentCell is StickyCircleCell,
              coordinator?.circleIsLeading(at: index) == true else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        return rect.insetBy(dx: -3, dy: -4).contains(inner) ? index : nil
    }

    // MARK: 回车

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        // 组字时原样交给输入法（回车上屏），不插行。
        guard isReturn, !hasMarkedText() else { return super.keyDown(with: event) }
        let flags = event.modifierFlags
        if coordinator?.handleReturn(command: flags.contains(.command), shift: flags.contains(.shift),
                                     option: flags.contains(.option)) != true {
            super.keyDown(with: event)
        }
    }

    /// ⌘↩ 也可能先走快捷键这条路。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.contains(.command), window?.firstResponder === self, !hasMarkedText() {
            return coordinator?.handleReturn(command: true, shift: false, option: false) == true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// NSTextView 默认把 Esc 当「补全」。交给面板（关面板）；组字时 Esc 归输入法。
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { return super.cancelOperation(sender) }
        window?.cancelOperation(sender)
    }

    // MARK: 拷贝出原文

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, let coordinator else { return super.writeSelection(to: pboard, type: type) }
        let text = selectedRanges.map { coordinator.rawText(of: $0.rangeValue) }.joined(separator: "\n")
        pboard.setString(text, forType: .string)
        return true
    }

    // MARK: 右键

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard isEditable, let coordinator else { return menu }
        let point = convert(event.locationInWindow, from: nil)
        guard let line = coordinator.line(at: point) else { return menu }
        let item = NSMenuItem(title: tr("发到快速待办"), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
        if StickyEditing.sendable(line: line, in: coordinator.currentText) != nil {
            item.action = #selector(sendLine(_:))
            item.target = self
            item.tag = line
        }
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func sendLine(_ sender: NSMenuItem) {
        coordinator?.parent.onSend(sender.tag)
    }

    // MARK: 焦点

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { coordinator?.focusChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { coordinator?.focusChanged(false) }
        return accepted
    }
}

/// 清单项行首的圆圈：没勾是一圈墨线，勾上是淡墨实心加纸色对勾。
final class StickyCircleCell: NSTextAttachmentCell {
    struct Look {
        var side: CGFloat
        var gap: CGFloat
        var capHeight: CGFloat
        var ink: NSColor
        var faded: NSColor
        var paper: NSColor
    }

    let box: StickyEditing.Box
    var look: Look

    init(box: StickyEditing.Box, look: Look) {
        self.box = box
        self.look = look
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize { NSSize(width: look.side + look.gap, height: look.side) }

    /// 圆心对着大写字母的半高，和字的中线齐。
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: (look.capHeight - look.side) / 2) }

    override func wantsToTrackMouse() -> Bool { false }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let side = look.side
        let rect = NSRect(x: cellFrame.minX + 1, y: cellFrame.minY + (cellFrame.height - side) / 2 + 1,
                          width: side - 2, height: side - 2)
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
        if box.done {
            look.faded.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let tick = NSBezierPath()
            let flipped = controlView?.isFlipped ?? true
            func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + rect.width * x,
                        y: flipped ? rect.minY + rect.height * y : rect.maxY - rect.height * y)
            }
            tick.move(to: at(0.27, 0.52))
            tick.line(to: at(0.44, 0.69))
            tick.line(to: at(0.74, 0.33))
            tick.lineWidth = max(1.5, side * 0.12)
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            look.paper.setStroke()
            tick.stroke()
        } else {
            look.ink.withAlphaComponent(0.75).setStroke()
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}
