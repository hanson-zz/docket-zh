import SwiftUI

/// The sticky note at length: the same paper the shelf shows, at a size a note
/// can be written on rather than glanced at.
///
/// 上面是最上面那张纸，能直接写（手写字，和卡片一样）；下面一行选这张纸的颜色
/// （免费五种，其余带锁的是 Pro），再一行是叠放：“1/3”、翻下一张、新的一张、
/// 撕掉这张。换颜色只改这一张。颜色原来是添加面板里的一排样式卡，现在挪到这里
/// 和设置里选。
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheet
            colorRow
            stackRow
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
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($writing)
                .font(StickyFont.hand(size: 22))
                .foregroundStyle(ink)
                .lineSpacing(4)
                .onSubmit {
                    commit()
                    writing = false
                }
                .onChange(of: writing) { _, active in if !active { commit() } }
                // One panel serves every note in turn, and flipping hands it
                // another sheet; take that sheet's words unless the caret is
                // still mid-sentence in this one.
                .onChange(of: stored) { _, note in if !writing { draft = note } }
                .onAppear {
                    draft = stored
                    beginWriting()
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
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { beginWriting() }
                }
        }
        .id(pile.page)
        .transition(reduceMotion ? AnyTransition.opacity
                    : AnyTransition.opacity.combined(with: AnyTransition.offset(x: 12, y: 0)))
    }

    // MARK: 颜色

    /// 这张纸的颜色：十五种，免费五种，其余带锁的是 Pro。
    private var colorRow: some View {
        let chosen = PaperColor(rawValue: pile.front.color) ?? .yellow
        return VStack(alignment: .leading, spacing: 6) {
            Text(tr("这张纸的颜色"))
                .font(WidgetStyle.label(12))
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
                    .font(.system(size: 11, weight: .bold))
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
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.12) : .snappy(duration: 0.25)
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
