import SwiftUI

/// The sticky note at length: the same paper the shelf shows, at a size a note
/// can be written on rather than glanced at.
///
/// 上面是最上面那张纸，能直接写（字体和字号按这张便签的设置，和卡片一样）；
/// 行首写 `[ ]` 的行不在写字时画成可点的框，点一下勾上或取消（`StickyChecklist`）。
/// 下面依次是字体（手写 / 普通 / 等宽）、字号（小 / 中 / 大）、这张纸的颜色
/// （免费五种，其余带锁的是 Pro）、叠放：“1/10”、翻下一张、新的一张、撕掉这张。
/// 换颜色只改这一张，字体字号整张便签一起。
struct StickyNoteDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var unlocked: Bool { ProAccess.isUnlocked || context.isPreview }

    private var pile: StickyStack.Pile { StickyStack.pile(instance.config) }

    /// 最上面那张实际画的纸色：没解锁码头 Pro 时 Pro 纸色退回柠檬黄。
    private var swatch: PaperColor { pile.front.paper(unlocked: unlocked) }

    /// Every `PaperColor` but the two dark ones is a light swatch, so the ink
    /// is fixed rather than semantic, which would go white and vanish.
    private var ink: Color { Color(hex: swatch.inkHex) }

    /// What is being typed, kept apart from the stored note so the profile is
    /// written once the sentence is finished rather than once per keystroke.
    @State private var draft = ""
    @FocusState private var writing: Bool
    @State private var confirmTear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stored: String { pile.front.text }

    private var noteFont: StickyNoteFont { StickyNoteFont.of(instance.config) }
    private var noteSize: StickyNoteSize { StickyNoteSize.of(instance.config) }
    private var pointSize: CGFloat { CGFloat(StickyNoteType.panel(noteFont, noteSize)) }

    /// 有清单项、又没在写字时，纸上画成能点的框。
    private var showsChecklist: Bool { !writing && StickyChecklist.hasItems(draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheet
            styleRows
            colorRow
            stackRow
            Text(tr("行首打 [ ] 变成可勾的清单"))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    // MARK: 纸

    private var sheet: some View {
        // The same card every other panel is drawn on, with paper as its
        // surface: blank paper is most of the sheet and is where people aim.
        DetailCard {
            ZStack {
                Color(hex: swatch.hex)
                // 右下角的卷角和顶上的胶带，和卡片上那张同一套。
                StickyPaper(color: swatch, tape: true, curl: true, curlSize: 26)
            }
        } content: {
            // Return finishes the note and Shift-Return breaks the line, which
            // is the vertical field's own behaviour: a note is usually one
            // thought, and the panel is open to be written in, not read.
            ZStack(alignment: .topLeading) {
                if showsChecklist { checklist }
                field
            }
        }
        .id(pile.page)
        // 减少动态效果时翻页直接换，不淡入淡出。
        .transition(reduceMotion ? AnyTransition.identity
                    : AnyTransition.opacity.combined(with: AnyTransition.offset(x: 12, y: 0)))
    }

    private var field: some View {
        TextField("", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .focused($writing)
            .font(StickyFont.font(noteFont, size: pointSize))
            .foregroundStyle(ink)
            .lineSpacing(4)
            .onSubmit {
                // 在清单项上回车接着下一项；空的一项上再回车收尾，和备忘录一样。
                let next = StickyChecklist.submitting(draft)
                draft = next.text
                if next.keepWriting {
                    Task { @MainActor in writing = true }
                } else {
                    commit()
                    writing = false
                }
            }
            .onChange(of: writing) { _, active in if !active { commit() } }
            // One panel serves every note in turn, and flipping hands it
            // another sheet; take that sheet's words unless the caret is
            // still mid-sentence in this one.
            .onChange(of: stored) { _, note in if !writing { draft = note } }
            .onAppear {
                draft = stored
                // 有清单项时先让人看见框子、能直接勾；点纸上的空白再写。
                if !StickyChecklist.hasItems(stored) { beginWriting() }
            }
            // Closing the panel hides its window rather than tearing this
            // view down, so whichever of the two happens first, the words
            // are already saved.
            .onDisappear { commit() }
            .accessibilityLabel(tr("便签"))
            // The card forces the dark scheme; the caret has to be ink
            // like the words, or it is white on paper.
            .tint(ink)
            .padding(.top, 6)
            // Tall enough that a short note leaves the rest of the sheet
            // blank, the way paper does.
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            // 画清单时输入框藏起来（还在，焦点和保存照旧），点纸上空白处回来写。
            .opacity(showsChecklist ? 0 : 1)
            .allowsHitTesting(!showsChecklist)
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { beginWriting() }
            }
    }

    // MARK: 清单

    /// 不在写字时的样子：清单项一行一个框，点框勾上或取消；点字或空白处开始写。
    private var checklist: some View {
        let rows = StickyChecklist.lines(draft)
        let box = max(13, pointSize * 0.72)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                switch row {
                case .text(let words):
                    Text(verbatim: words.isEmpty ? " " : words)
                        .font(StickyFont.font(noteFont, size: pointSize))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .onTapGesture { beginWriting() }
                case .item(let done, let words):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button { toggle(index) } label: {
                            checkBox(done, side: box)
                        }
                        .buttonStyle(.plain)
                        .disabled(context.isPreview)
                        .accessibilityLabel(done ? tr("已完成：\(words)") : tr("未完成：\(words)"))
                        Text(verbatim: words.isEmpty ? " " : words)
                            .font(StickyFont.font(noteFont, size: pointSize))
                            .foregroundStyle(ink.opacity(done ? 0.5 : 0.92))
                            .strikethrough(done, color: ink.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                            .onTapGesture { beginWriting() }
                    }
                }
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { beginWriting() }
        }
    }

    private func checkBox(_ done: Bool, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
            .fill(done ? ink.opacity(0.85) : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
                    .strokeBorder(ink.opacity(done ? 0 : 0.7), lineWidth: 1.4)
            }
            .overlay {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.62, weight: .bold))
                        .foregroundStyle(Color(hex: swatch.hex))
                }
            }
            .frame(width: side, height: side)
            .contentShape(.rect)
    }

    /// 勾上或取消第几行，只改那一行的框。
    private func toggle(_ index: Int) {
        guard !context.isPreview else { return }
        let next = StickyChecklist.toggling(line: index, in: draft)
        guard next != draft else { return }
        draft = next
        StickyLog.write(next, in: instance)
    }

    // MARK: 字体和字号

    private var styleRows: some View {
        VStack(spacing: 8) {
            styleRow(tr("字体")) {
                DetailSegmented(pages: StickyNoteFont.allCases, title: \.title, selected: noteFont) { choice in
                    setStyle(StickyNoteFont.key, choice.rawValue)
                }
            }
            styleRow(tr("字号")) {
                DetailSegmented(pages: StickyNoteSize.allCases, title: \.title, selected: noteSize) { choice in
                    setStyle(StickyNoteSize.key, choice.rawValue)
                }
            }
        }
    }

    private func styleRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, alignment: .leading)
            control()
        }
    }

    private func setStyle(_ key: String, _ value: String) {
        guard !context.isPreview else { return }
        commit()
        StickyLog.style(key, value, in: instance)
    }

    // MARK: 颜色

    /// 这张纸的颜色：十五种，免费五种，其余带锁的是 Pro。
    private var colorRow: some View {
        let chosen = PaperColor(rawValue: pile.front.color) ?? .yellow
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("这张纸的颜色"))
                .font(WidgetStyle.label(13))
                .foregroundStyle(.white.opacity(0.85))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 6), count: 8),
                      alignment: .leading, spacing: 6) {
                ForEach(PaperColor.picker, id: \.self) { color in
                    swatchButton(color, selected: color == chosen)
                }
            }
        }
    }

    private func swatchButton(_ color: PaperColor, selected: Bool) -> some View {
        let locked = ProFeatures.isProNoteColor(color.rawValue) && !unlocked
        return Button {
            guard !context.isPreview else { return }
            if locked { PaywallWindow.shared.show(); return }
            commit()
            StickyLog.color(color, in: instance)
        } label: {
            Circle()
                .fill(Color(hex: color.hex))
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .frame(width: 18, height: 18)
                .padding(2)
                .overlay {
                    if selected { Circle().strokeBorder(.white, lineWidth: 1.5) }
                }
                .overlay(alignment: .topTrailing) {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
                            .offset(x: 3, y: -3)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(locked ? "\(color.title) · \(ProFeatures.label)" : color.title)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 叠放

    private var stackRow: some View {
        let pile = self.pile
        return HStack(spacing: 8) {
            if let marker = pile.marker {
                Text(marker)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(0.1)))
                PanelButton(title: tr("下一张"), symbol: "arrow.turn.up.right") {
                    act { $0.flipped() }
                }
            }
            PanelButton(title: tr("新的一张"), symbol: "plus") {
                act { $0.adding(color: StickyStack.nextColor(after: $0)) }
            }
            .disabled(!pile.canAdd || context.isPreview)
            .opacity(pile.canAdd ? 1 : 0.45)
            .help(pile.canAdd ? tr("再贴一张，最多 \(StickyStack.limit) 张") : tr("最多 \(StickyStack.limit) 张"))
            if pile.canRemove {
                PanelButton(title: tr("撕掉"), symbol: "xmark") {
                    if stored.isEmpty && draft.isEmpty {
                        act { $0.removingFront() }
                    } else {
                        confirmTear = true
                    }
                }
                .confirmationDialog(tr("撕掉这张便签？"), isPresented: $confirmTear) {
                    Button(tr("撕掉"), role: .destructive) {
                        act(saving: false) { $0.removingFront() }
                    }
                    Button(tr("取消"), role: .cancel) {}
                } message: {
                    Text(tr("上面写的字会一起扔掉。"))
                }
            }
        }
    }

    /// 先把正在写的字存好，再换一张；换完把输入框里的字换成新那张的，免得
    /// 失去焦点时把上一张的字写到这一张上。
    private func act(saving: Bool = true, _ edit: @escaping (StickyStack.Pile) -> StickyStack.Pile) {
        guard !context.isPreview else { return }
        let saved = WidgetWriter.current(instance.id).map { StickyStack.pile($0.config) } ?? pile
        let before = saving ? saved.writing(draft) : saved
        let after = edit(before)
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        withAnimation(animation) {
            StickyLog.change(instance) { current in edit(saving ? current.writing(draft) : current) }
        }
        draft = after.front.text
        writing = false
    }

    /// The panel takes key status as it opens and the caret may as well be in
    /// the paper: there is nothing else here to click.
    private func beginWriting() {
        guard !context.isPreview else { return }
        writing = true
    }

    /// Focus leaves the paper far more often than the words change, and every
    /// write is a profile save.
    private func commit() {
        guard !context.isPreview, draft != stored else { return }
        StickyLog.write(draft, in: instance)
    }
}
