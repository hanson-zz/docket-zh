import AppKit
import SwiftUI

/// 快速待办顶部的输入框：一行 `NSTextView`，认出的时间片段（「明天 9 点」）标成主题色。
///
/// 用 AppKit 而不是 SwiftUI 的 `TextField`，是因为要在文字里给一段上色，
/// 而且中文输入法选字时（有 marked text）不能被打断：
/// - 选字期间不改文字、不改颜色，SwiftUI 那边传回来的字和框里不一样也不覆盖；
/// - 回车先交给输入法上屏，只有没在选字时才算“添加”；
/// - 粘贴进来的换行、Tab 换成空格（一条待办只有一行）。
struct TodoInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// 要标色的那一段（UTF-16 位置），没认出时间时为 nil。
    var highlight: NSRange?
    /// 标色用的主题色（深色下原样，浅色下自动加深到看得清）。
    var tint: NSColor
    var enabled: Bool = true
    /// 出现时就把光标放进来。
    var autofocus: Bool = true
    var onSubmit: () -> Void

    static let fontSize: CGFloat = 15

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none

        let view = InputTextView()
        view.autofocus = autofocus
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.font = .systemFont(ofSize: Self.fontSize)
        view.textColor = .labelColor
        view.insertionPointColor = tint
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.lineFragmentPadding = 0
        // 一行，横着往右延伸，超出时跟着光标滚动。
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // 至少铺满输入框（点空白处也能落光标），字多了往右长。
        view.minSize = NSSize(width: 0, height: 22)
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        view.autoresizingMask = [.width, .height]
        view.typingAttributes = Coordinator.base
        view.string = text
        view.setAccessibilityLabel(placeholder)
        scroll.documentView = view
        context.coordinator.view = view
        context.coordinator.restyle()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = context.coordinator.view else { return }
        view.isEditable = enabled
        view.isSelectable = enabled
        view.insertionPointColor = tint
        view.autofocus = autofocus
        // 选字期间框里的字（带拼音）和绑定不一样是正常的，不覆盖。
        guard !view.hasMarkedText() else { return }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        context.coordinator.restyle()
        // 高度跟着滚动框走，宽度至少铺满，点空白处也能落光标。
        let height = scroll.contentSize.height
        if view.frame.height != height || view.frame.width < scroll.contentSize.width {
            view.setFrameSize(NSSize(width: max(view.frame.width, scroll.contentSize.width), height: height))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TodoInputField
        weak var view: InputTextView?
        /// 上一次标色时的字和位置，都没变就不重画（面板每秒刷新一次）。
        private var styled: (text: String, range: NSRange?)?

        static var base: [NSAttributedString.Key: Any] {
            [.font: NSFont.systemFont(ofSize: TodoInputField.fontSize), .foregroundColor: NSColor.labelColor]
        }

        init(_ parent: TodoInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            guard !view.hasMarkedText() else { return }
            let raw = view.string
            if raw.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) {
                let flat = raw.replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                let caret = view.selectedRange()
                view.string = flat
                view.setSelectedRange(NSRange(location: min(caret.location, (flat as NSString).length), length: 0))
            }
            if parent.text != view.string { parent.text = view.string }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:))
                || selector == #selector(NSResponder.insertLineBreak(_:)) {
                guard !textView.hasMarkedText() else { return false }
                parent.onSubmit()
                return true
            }
            return false
        }

        /// 整行回到默认颜色，再给认出的片段上主题色和一层淡底。
        func restyle() {
            guard let view, let storage = view.textStorage, !view.hasMarkedText() else { return }
            let length = storage.length
            var range = parent.highlight
            if let r = range, r.location < 0 || r.location + r.length > length || r.length == 0 { range = nil }
            if let styled, styled.text == view.string, styled.range == range { return }
            styled = (text: view.string, range: range)
            storage.beginEditing()
            storage.setAttributes(Self.base, range: NSRange(location: 0, length: length))
            if let range {
                storage.addAttribute(.foregroundColor, value: parent.tint, range: range)
                storage.addAttribute(.backgroundColor, value: parent.tint.withAlphaComponent(0.14), range: range)
            }
            storage.endEditing()
            view.typingAttributes = Self.base
        }
    }

    /// 出现在窗口里时把光标放进来（面板一打开就能打字）。
    final class InputTextView: NSTextView {
        var autofocus = true

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard autofocus, let window else { return }
            Task { @MainActor [weak self] in
                guard let self, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }
    }
}
