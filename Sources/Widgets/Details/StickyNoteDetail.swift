import SwiftUI

/// The sticky note at length: the same paper the shelf shows, at a size a note
/// can be written on rather than glanced at.
///
/// 从上到下：顶栏（叠放「2/3」、带角标的垃圾桶）、最上面那张纸（能直接写，字体和
/// 字号按这张便签的设置）、工具条（「清单」⌘⇧L 和「⋯」菜单）、字体、字号、这张纸的
/// 颜色（免费五种，其余带锁的是 Pro）、底栏（上一张 ⌘[、下一张 ⌘] 两个纯图标，
/// 「新一张」「撕掉」图标加短字，13pt，中英文都不截断）。
///
/// 清单：行首的各种框（见 `StickyChecklist`）不在写字时画成可点的圆圈，点一下即完成，
/// 划线、换成淡墨（对比度约 5.0，不低于 4.5），默认沉到「已完成」下面（「⋯」里可关），
/// 标题旁显示进度 2/5。这一版保留 `TextField`：写字时照原样显示框子的字，失焦后才画圆圈。
/// 认不出的框（`[1]`）不偷改，纸底问一次「变成清单」。
///
/// 撕掉：不弹确认，纸从胶带下撕开、右下角卷起、飞进顶栏的垃圾桶（约 0.5 秒，减少
/// 动态效果时直接淡出），底部 5 秒撤销；撕下的纸在垃圾桶里留 7 天、最多 30 张。
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
    /// 勾掉的项用的淡墨，对比度约 5.0（见 `PaperInk.faded`）。
    private var fadedInk: Color { Color(hex: PaperInk.faded(on: swatch.hex)) }

    /// What is being typed, kept apart from the stored note so the profile is
    /// written once the sentence is finished rather than once per keystroke.
    @State private var draft = ""
    @FocusState private var writing: Bool
    /// 输入框里的选区，清单键按它找要转的几行。
    @State private var selection: TextSelection?
    /// 最近一次选区落在的几行：点「清单」按钮时输入框可能已经失焦。
    @State private var lastLines: ClosedRange<Int>?
    @State private var showingTrash = false
    @State private var undo: StickyUndo?
    /// 每记一步换一个，撤销提示从最后一次改动起停 5 秒。
    @State private var undoToken = UUID()
    /// 正在飞进垃圾桶的那张纸。
    @State private var flight: StickyFlight?
    /// 认不出的框问过、点了“✕”的那几张（按第几张记，这次打开面板里不再问）。
    @State private var askedAway: Set<Int> = []
    /// 纸和垃圾桶在面板里的位置，撕纸动画从纸飞到垃圾桶。
    @State private var sheetFrame: CGRect = .zero
    @State private var binFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stored: String { pile.front.text }

    private var noteFont: StickyNoteFont { StickyNoteFont.of(instance.config) }
    private var noteSize: StickyNoteSize { StickyNoteSize.of(instance.config) }
    private var pointSize: CGFloat { CGFloat(StickyNoteType.panel(noteFont, noteSize)) }
    private var sinkDone: Bool { StickyChecklist.sinksDone(instance.config) }

    /// 有清单项、又没在写字时，纸上画成能点的圆圈。
    private var showsChecklist: Bool { !writing && StickyChecklist.hasItems(draft) }

    private var trash: [StickyTrash.Entry] {
        context.isPreview ? [] : StickyTrash.entries(instance.config, now: Date())
    }

    var body: some View {
        if showingTrash {
            StickyTrashPanel(instance: instance, back: {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { showingTrash = false }
            })
            .transition(.opacity)
        } else {
            notePage
                .transition(.opacity)
        }
    }

    private var notePage: some View {
        VStack(alignment: .leading, spacing: 12) {
            topBar
            sheet
            toolbar
            styleRows
            colorRow
            stackRow
            if let undo {
                StickyUndoBar(caption: undo.caption) { revert(undo) }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) {
            if let flight {
                StickyTearFlight(flight: flight, reduceMotion: reduceMotion)
                    .frame(width: flight.frame.width, height: flight.frame.height)
                    .offset(x: flight.frame.minX, y: flight.frame.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task(id: undoToken) {
            guard undo != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { undo = nil }
        }
        .task(id: flight?.id) {
            guard let flight else { return }
            try? await Task.sleep(for: .seconds(StickyTearFlight.duration(reduceMotion) + 0.05))
            guard !Task.isCancelled, self.flight?.id == flight.id else { return }
            self.flight = nil
        }
    }

    private static let space = "sticky-note"

    // MARK: 顶栏

    private var topBar: some View {
        let pile = self.pile
        let count = trash.count
        return HStack(spacing: 8) {
            if let marker = pile.marker {
                Text(marker)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(.panelFill))
                    .accessibilityLabel(tr("第 \(pile.page + 1) 张，共 \(pile.count) 张"))
            }
            Spacer(minLength: 0)
            Button {
                guard !context.isPreview else { return }
                commit()
                writing = false
                StickyLog.purgeTrash(instance)
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { showingTrash = true }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.panelFill))
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text(verbatim: "\(count)")
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.panelOnPrimary)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(.panelPrimary))
                                .offset(x: 7, y: -6)
                        }
                    }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help(tr("最近撕掉"))
            .accessibilityLabel(count > 0 ? tr("最近撕掉，\(count) 张") : tr("最近撕掉"))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { binFrame = $0 }
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
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if showsChecklist { checklist }
                    field
                }
                .overlay(alignment: .topTrailing) {
                    // 第一行就是清单项、没有标题时，进度放右上角。
                    if showsChecklist, StickyChecklist.titleLine(draft) == nil { progressPill }
                }
                askBar
            }
        }
        .id(pile.page)
        // 减少动态效果时翻页直接换，不淡入淡出。
        .transition(reduceMotion ? AnyTransition.identity
                    : AnyTransition.opacity.combined(with: AnyTransition.offset(x: 12, y: 0)))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { sheetFrame = $0 }
    }

    private var field: some View {
        TextField("", text: $draft, selection: $selection, axis: .vertical)
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
            .onChange(of: selection) { _, _ in
                if let lines = selectedLines() { lastLines = lines }
            }
            // One panel serves every note in turn, and flipping hands it
            // another sheet; take that sheet's words unless the caret is
            // still mid-sentence in this one.
            .onChange(of: stored) { _, note in if !writing { draft = note } }
            .onAppear {
                draft = stored
                // 有清单项时先让人看见圆圈、能直接勾；点纸上的空白再写。
                if !StickyChecklist.hasItems(stored) { beginWriting() }
            }
            // Closing the panel hides its window rather than tearing this
            // view down, so whichever of the two happens first, the words
            // are already saved.
            .onDisappear { commit() }
            .accessibilityLabel(tr("便签"))
            // The caret has to be ink like the words, or it is the accent
            // colour on paper.
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

    /// 不在写字时的样子：清单项一行一个圆圈，点圆圈即完成；勾掉的划线、变淡，
    /// 默认沉到「已完成」下面。点字或空白处开始写。
    private var checklist: some View {
        let layout = StickyChecklist.layout(draft, sinkDone: sinkDone)
        let title = StickyChecklist.titleLine(draft)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(layout.open, id: \.index) { row in
                rowView(row, isTitle: row.index == title)
            }
            if !layout.done.isEmpty {
                HStack(spacing: 8) {
                    Text(tr("已完成 \(layout.done.count)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(fadedInk)
                    Rectangle()
                        .fill(ink.opacity(0.18))
                        .frame(height: 1)
                }
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
                ForEach(layout.done, id: \.index) { row in
                    rowView(row, isTitle: false)
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

    @ViewBuilder
    private func rowView(_ row: StickyChecklist.Row, isTitle: Bool) -> some View {
        switch row.line {
        case .text(let words):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: words.isEmpty ? " " : words)
                    .font(StickyFont.font(noteFont, size: pointSize))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                if isTitle { progressPill }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .onTapGesture { beginWriting() }
        case .item(let done, let words):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { toggle(row.index) } label: {
                    checkCircle(done)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .accessibilityLabel(done ? tr("已完成：\(words)") : tr("未完成：\(words)"))
                Text(verbatim: words.isEmpty ? " " : words)
                    .font(StickyFont.font(noteFont, size: pointSize))
                    .foregroundStyle(done ? fadedInk : ink)
                    .strikethrough(done, color: fadedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { beginWriting() }
            }
        }
    }

    private var circleSide: CGFloat { max(14, pointSize * 0.72) }

    private func checkCircle(_ done: Bool) -> some View {
        let side = circleSide
        return Circle()
            .fill(done ? fadedInk : .clear)
            .overlay {
                Circle().strokeBorder(ink.opacity(done ? 0 : 0.75), lineWidth: 1.5)
            }
            .overlay {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: side * 0.55, weight: .bold))
                        .foregroundStyle(Color(hex: swatch.hex))
                }
            }
            .frame(width: side, height: side)
            .padding(3)
            .contentShape(.circle)
    }

    /// 标题旁的进度「2/5」。
    private var progressPill: some View {
        let progress = StickyChecklist.progress(draft)
        return Text(verbatim: "\(progress.done)/\(progress.total)")
            .font(.system(size: 13, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(ink.opacity(0.1)))
            .accessibilityLabel(tr("完成 \(progress.done) 项，共 \(progress.total) 项"))
    }

    /// 勾上或取消第几行，只改那一行的框。
    private func toggle(_ index: Int) {
        guard !context.isPreview else { return }
        let next = StickyChecklist.toggling(line: index, in: draft)
        guard next != draft else { return }
        // 沉底时轻轻挪过去；减少动态效果时直接换。
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { draft = next }
        StickyLog.write(next, in: instance)
    }

    // MARK: 认不出的框

    /// 纸底问一次：认不出的框（`[1]` 这种）要不要变成清单。点「✕」这张不再问。
    @ViewBuilder
    private var askBar: some View {
        let lines = StickyChecklist.ambiguousLines(draft)
        if !lines.isEmpty, !askedAway.contains(pile.page), !context.isPreview {
            HStack(spacing: 8) {
                Text(lines.count == 1 ? tr("这行变成可勾项？") : tr("这 \(lines.count) 行变成可勾项？"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    let next = StickyChecklist.convertingAmbiguous(draft)
                    draft = next
                    StickyLog.write(next, in: instance)
                } label: {
                    Text(tr("变成清单"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: swatch.hex))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(ink))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                Button {
                    askedAway.insert(pile.page)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("不用了"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(swatch.isDark ? 0.12 : 0.45)))
        }
    }

    // MARK: 工具条

    private var toolbar: some View {
        let progress = StickyChecklist.progress(draft)
        return HStack(spacing: 8) {
            Button { makeChecklist() } label: {
                StickyPill(symbol: "checklist", title: tr("清单"))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(context.isPreview)
            .help(tr("把这一行变成可勾项") + "  ⌘⇧L")
            Spacer(minLength: 0)
            Menu {
                Toggle(tr("已完成沉到底部"), isOn: Binding(
                    get: { sinkDone },
                    set: { on in
                        guard !context.isPreview else { return }
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { StickyLog.setSink(on, in: instance) }
                    }))
                Divider()
                Button(tr("全部取消勾选")) {
                    let next = StickyChecklist.uncheckingAll(draft)
                    draft = next
                    StickyLog.write(next, in: instance)
                }
                .disabled(progress.done == 0)
                Button(tr("清除已完成项"), role: .destructive) { clearDone() }
                    .disabled(progress.done == 0)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.panelFill))
                    .contentShape(.circle)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(context.isPreview)
            .help(tr("更多"))
            .accessibilityLabel(tr("更多"))
        }
    }

    /// 清单键：选中的几行（没在写字时用最近一次选区，都没有就最后一行）变成清单项，
    /// 都已经是清单项时去掉框子。空纸或空行上放一个空框，接着写。
    private func makeChecklist() {
        guard !context.isPreview else { return }
        let rows = draft.split(separator: "\n", omittingEmptySubsequences: false).count
        let fallback: ClosedRange<Int> = (rows - 1)...(rows - 1)
        let lines = (writing ? selectedLines() : nil) ?? lastLines ?? fallback
        let next = StickyChecklist.togglingItems(draft, lines: lines)
        guard next != draft else { return }
        draft = next
        StickyLog.write(next, in: instance)
        if next.hasSuffix("[ ] ") { beginWriting() }
    }

    /// 选区落在第几行到第几行。选区按 UTF-16 位置换成字符数，免得旧的下标越界。
    private func selectedLines() -> ClosedRange<Int>? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            return StickyChecklist.lineRange(in: draft, from: characters(before: range.lowerBound),
                                             to: characters(before: range.upperBound))
        default:
            return nil
        }
    }

    private func characters(before index: String.Index) -> Int {
        let utf16 = Array(draft.utf16)
        let offset = min(max(0, index.utf16Offset(in: draft)), utf16.count)
        return String(decoding: utf16[..<offset], as: UTF16.self).count
    }

    /// 清除已完成项：5 秒内可以撤销。
    private func clearDone() {
        guard !context.isPreview else { return }
        let before = draft
        let result = StickyChecklist.removingDone(draft)
        guard result.removed > 0 else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { draft = result.text }
        StickyLog.write(result.text, in: instance)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            undo = .cleared(before: before, after: result.text, count: result.removed)
        }
        undoToken = UUID()
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
                .foregroundStyle(.panelPrimary)
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
                .foregroundStyle(.panelPrimary)
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
                .overlay { Circle().strokeBorder(.panelQuaternary, lineWidth: 0.5) }
                .frame(width: 18, height: 18)
                .padding(2)
                .overlay {
                    if selected { Circle().strokeBorder(.panelPrimary, lineWidth: 1.5) }
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

    // MARK: 底栏

    /// 上一张、下一张是纯图标（悬停提示快捷键），「新一张」「撕掉」图标加短字。
    /// 都按内容宽，不平分，中英文都不截断。
    private var stackRow: some View {
        let pile = self.pile
        let flippable = pile.count > 1 && !context.isPreview
        return HStack(spacing: 8) {
            Button { act { $0.flipped(by: -1) } } label: {
                StickyRoundIcon(symbol: "chevron.left")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!flippable)
            .opacity(pile.count > 1 ? 1 : 0.4)
            .help(tr("上一张") + "  ⌘[")
            .accessibilityLabel(tr("上一张"))
            Button { act { $0.flipped(by: 1) } } label: {
                StickyRoundIcon(symbol: "chevron.right")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!flippable)
            .opacity(pile.count > 1 ? 1 : 0.4)
            .help(tr("下一张") + "  ⌘]")
            .accessibilityLabel(tr("下一张"))
            Spacer(minLength: 6)
            Button { act { $0.adding(color: StickyStack.nextColor(after: $0)) } } label: {
                StickyPill(symbol: "plus", title: tr("新一张"))
            }
            .buttonStyle(.plain)
            .disabled(!pile.canAdd || context.isPreview)
            .opacity(pile.canAdd ? 1 : 0.45)
            .help(pile.canAdd ? tr("再贴一张，最多 \(StickyStack.limit) 张") : tr("最多 \(StickyStack.limit) 张"))
            Button { tear() } label: {
                StickyPill(symbol: "scissors", title: tr("撕掉"))
            }
            .buttonStyle(.plain)
            .disabled(!canTear || context.isPreview)
            .opacity(canTear ? 1 : 0.45)
            .help(tr("撕掉这张，放进垃圾桶"))
        }
    }

    /// 正在写的字也算：刚写了字还没存，也能撕。
    private var canTear: Bool { pile.writing(draft).canTear }

    /// 撕掉最上面那张：不弹确认。先存好正在写的字，写字的纸进垃圾桶，飞过去的
    /// 动画画在上面，下面直接露出下一张；底部 5 秒撤销。
    private func tear() {
        guard !context.isPreview else { return }
        let words = draft
        let paper = swatch
        let frame = sheetFrame
        var torn: StickyTrash.Torn?
        StickyLog.mutate(instance) { config in
            StickyStack.store(StickyStack.pile(config).writing(words), in: &config)
            torn = StickyTrash.tear(&config, now: Date(), id: UUID().uuidString)
        }
        guard let torn else { return }
        writing = false
        draft = WidgetWriter.current(instance.id).map { StickyStack.pile($0.config).front.text } ?? ""
        if frame.width > 0 {
            let target = CGSize(width: binFrame.midX - frame.midX, height: binFrame.midY - frame.midY)
            flight = StickyFlight(paper: paper, text: words, font: noteFont, size: pointSize,
                                  frame: frame, target: target)
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { undo = .tore(torn) }
        undoToken = UUID()
    }

    /// 撤销最近的一步。
    private func revert(_ step: StickyUndo) {
        guard !context.isPreview else { return }
        switch step {
        case .tore(let torn):
            StickyLog.mutate(instance) { config in
                _ = StickyTrash.undo(torn, in: &config, now: Date())
            }
            draft = WidgetWriter.current(instance.id).map { StickyStack.pile($0.config).front.text } ?? draft
        case .cleared(let before, let after, _):
            // 清除后又改过字就不硬改回去，免得把新写的冲掉。
            guard stored == after || draft == after else { break }
            draft = before
            StickyLog.write(before, in: instance)
        }
        flight = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { undo = nil }
    }

    /// 先把正在写的字存好，再换一张；换完把输入框里的字换成新那张的，免得
    /// 失去焦点时把上一张的字写到这一张上。
    private func act(_ edit: @escaping (StickyStack.Pile) -> StickyStack.Pile) {
        guard !context.isPreview else { return }
        let saved = WidgetWriter.current(instance.id).map { StickyStack.pile($0.config) } ?? pile
        let after = edit(saved.writing(draft))
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.25)
        withAnimation(animation) {
            StickyLog.change(instance) { current in edit(current.writing(draft)) }
        }
        draft = after.front.text
        writing = false
        lastLines = nil
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

// MARK: - 撤销

/// 底部撤销提示能退回的一步。
enum StickyUndo {
    case tore(StickyTrash.Torn)
    case cleared(before: String, after: String, count: Int)

    var caption: String {
        switch self {
        case .tore: tr("已撕掉")
        case .cleared(_, _, let count): tr("已清除 \(count) 项")
        }
    }
}

/// 底部「已撕掉 · 撤销」，5 秒后自己收起。
struct StickyUndoBar: View {
    var caption: String
    var undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Text(caption)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button(tr("撤销"), action: undo)
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(Color(hex: PaletteColor.orange.hex).panelReadable)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassPane(cornerRadius: WidgetStyle.innerCorner)
    }
}

// MARK: - 按钮

/// 图标加短字的胶囊按钮，按内容宽，不截断。
struct StickyPill: View {
    var symbol: String
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(WidgetStyle.label(13))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(.panelPrimary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(.panelFill))
        .contentShape(.capsule)
    }
}

/// 只有图标的圆按钮：上一张、下一张。
struct StickyRoundIcon: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelPrimary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(.panelFill))
            .contentShape(.circle)
    }
}
