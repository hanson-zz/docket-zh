import AppKit
import SwiftUI

/// The sticky note at length: the same paper the shelf shows, at a size a note
/// can be written on rather than glanced at.
///
/// 便签 v3（瘦身）：便签是「随手纸」，没有日期、没有提醒，不做待办那一套。
///
/// 从上到下：顶栏（叠放「2/3」、一闪而过的「已保存」、带角标的垃圾桶）、最上面那张纸
/// （固定高度，长了在纸里滚，工具条不被推走）、工具条（「清单」⌘⇧L、「Aa」弹层收着
/// 字体字号纸色、清单进度、「⋯」菜单）、底栏（上一张 ⌘[、下一张 ⌘]、「新一张」⌘N、
/// 「撕掉」）。
///
/// 打开面板光标就在末尾（有清单也一样），新一张、翻页后同样直接能写。清单项写字时也是
/// 圆圈（见 `StickyNoteEditor`），点圆圈即勾，勾掉的淡墨划线，不挪位置、不弹撤销。
/// 回车在这一条后面接下一条，⇧↩ 普通换行，⌘↩ 收起编辑。停手半秒自动保存，顶栏淡淡
/// 显示一下「已保存」。右键一行「发到快速待办」，原行保留。
///
/// 撕掉：不弹确认，纸从胶带下撕开、右下角卷起、飞进顶栏的垃圾桶（约 0.5 秒，减少
/// 动态效果时直接淡出），底部 5 秒撤销；撕下的纸在垃圾桶里留 7 天、最多 30 张。
/// 换颜色只改这一张，字体字号整张便签一起。
struct StickyNoteDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    init(instance: WidgetInstance, context: WidgetContext) {
        self.instance = instance
        self.context = context
        // 一开始就是这张的字：编辑器造出来时就把光标放到真正的末尾。
        _draft = State(initialValue: StickyStack.pile(instance.config).front.text)
    }

    private var unlocked: Bool { ProAccess.isUnlocked || context.isPreview }

    private var pile: StickyStack.Pile { StickyStack.pile(instance.config) }

    /// 最上面那张实际画的纸色：没解锁码头 Pro 时 Pro 纸色退回柠檬黄。
    private var swatch: PaperColor { pile.front.paper(unlocked: unlocked) }

    /// Every `PaperColor` but the two dark ones is a light swatch, so the ink
    /// is fixed rather than semantic, which would go white and vanish.
    private var ink: Color { Color(hex: swatch.inkHex) }

    /// What is being typed, kept apart from the stored note so the profile is
    /// written once the sentence is finished rather than once per keystroke.
    /// 输入法组字时编辑器不往外报字，这里永远没有没上屏的拼音。
    @State private var draft = ""
    /// 光标在不在纸上（编辑器报上来的）。
    @State private var editing = false
    /// 换一个就把光标放到纸的末尾：新一张、翻页、撕掉之后。
    @State private var focusToken = UUID()
    @State private var editor = StickyEditorHandle()
    @State private var showingTrash = false
    @State private var showingStyle = false
    @State private var undo: StickyUndo?
    /// 每记一步换一个，撤销提示从最后一次改动起停 5 秒。
    @State private var undoToken = UUID()
    /// 顶栏一闪而过的小字：「已保存」「已发到快速待办」。
    @State private var hint: StickyHint?
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

    /// 纸里写字的那块固定高，长文本在里面滚。
    static let paperHeight: CGFloat = 236

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
        .onAppear { draft = stored }
        .onDisappear { commitLater() }
        // One panel serves every note in turn, and flipping hands it
        // another sheet; take that sheet's words unless the caret is
        // still mid-sentence in this one.
        .onChange(of: stored) { _, note in if !editing { draft = note } }
        // 边打边存：停手半秒就写进去，不只等失焦。每次写都是一次配置保存，所以等停手，
        // 不逐字写；组字时编辑器不报字，拼音不会存进去。存了顶栏淡淡显示「已保存」。
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, !editor.isComposing, commit() else { return }
            flash(.saved)
        }
        .task(id: hint?.id) {
            guard let hint else { return }
            try? await Task.sleep(for: .seconds(hint.kind.seconds))
            guard !Task.isCancelled, self.hint?.id == hint.id else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { self.hint = nil }
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

    // 几何回调是 Sendable 闭包，名字不随主线程隔离。
    nonisolated private static let space = "sticky-note"

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
            if let hint {
                Label(hint.kind.title, systemImage: hint.kind.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
                    .id(hint.id)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button {
                guard !context.isPreview else { return }
                commit()
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
            VStack(alignment: .leading, spacing: 10) {
                StickyNoteEditor(
                    text: $draft,
                    look: .init(font: noteFont, size: pointSize, ink: swatch.inkHex,
                                faded: PaperInk.faded(on: swatch.hex), paper: swatch.hex),
                    editable: !context.isPreview,
                    focusToken: focusToken,
                    handle: editor,
                    onEditingChanged: { focused in
                        editing = focused
                        if !focused { commitLater() }
                    },
                    onCollapse: collapse,
                    onSend: send)
                .frame(maxWidth: .infinity)
                .frame(height: Self.paperHeight)
                askBar
            }
        }
        .id(pile.page)
        // 减少动态效果时翻页直接换，不淡入淡出。
        .transition(reduceMotion ? AnyTransition.identity
                    : AnyTransition.opacity.combined(with: AnyTransition.offset(x: 12, y: 0)))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { sheetFrame = $0 }
    }

    /// ⌘↩：存好，收起编辑（光标离开纸，面板留着）。
    private func collapse() {
        guard !context.isPreview else { return }
        if commit() { flash(.saved) }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// 右键「发到快速待办」：加到扩展栏上第一个快速待办（和全局快捷键小框同一个，
    /// 见 `QuickTodoCapture.target()`），便签上原行保留。
    private func send(_ line: Int) {
        guard !context.isPreview, let words = StickyEditing.sendable(line: line, in: draft) else { return }
        guard let target = QuickTodoCapture.shared.target() else {
            NSSound.beep()
            flash(.noTodo)
            return
        }
        TodoLog.add(words, to: target)
        flash(.sent)
    }

    private func flash(_ kind: StickyHint.Kind) {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.15)) { hint = StickyHint(kind: kind) }
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
            Button { showingStyle.toggle() } label: {
                Text(verbatim: "Aa")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 34, height: 30)
                    .background(Capsule().fill(showingStyle ? Color.panelSelected : Color.panelFill))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help(tr("字体、字号和纸色"))
            .accessibilityLabel(tr("字体、字号和纸色"))
            .popover(isPresented: $showingStyle, arrowEdge: .bottom) { stylePopover }
            if progress.total > 0 {
                Text(verbatim: "\(progress.done)/\(progress.total)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.panelSecondary)
                    .accessibilityLabel(tr("完成 \(progress.done) 项，共 \(progress.total) 项"))
            }
            Spacer(minLength: 0)
            Menu {
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

    /// 清单键：选中的几行（编辑器失焦时用最近一次选区，都没有就最后一行）变成清单项，
    /// 都已经是清单项时去掉框子。空纸或空行上放一个空框，接着写。
    private func makeChecklist() {
        guard !context.isPreview else { return }
        let rows = draft.split(separator: "\n", omittingEmptySubsequences: false).count
        let fallback: ClosedRange<Int> = (rows - 1)...(rows - 1)
        let lines = editor.selectedLines() ?? fallback
        let next = StickyChecklist.togglingItems(draft, lines: lines)
        guard next != draft else { return }
        draft = next
        StickyLog.write(next, in: instance)
        if next.hasSuffix("[ ] ") { focusToken = UUID() }
    }

    /// 清除已完成项：5 秒内可以撤销。
    private func clearDone() {
        guard !context.isPreview else { return }
        let before = draft
        let result = StickyChecklist.removingDone(draft)
        guard result.removed > 0 else { return }
        draft = result.text
        StickyLog.write(result.text, in: instance)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            undo = .cleared(before: before, after: result.text, count: result.removed)
        }
        undoToken = UUID()
    }

    // MARK: Aa 弹层：字体、字号、纸色

    /// 字体、字号、这张纸的颜色收进一个弹层，面板主体留给纸。颜色免费五种，其余带锁的是
    /// Pro（划分不变）。
    private var stylePopover: some View {
        let chosen = PaperColor(rawValue: pile.front.color) ?? .yellow
        return VStack(alignment: .leading, spacing: 12) {
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
            VStack(alignment: .leading, spacing: 6) {
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
        .padding(14)
        .frame(width: 268)
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
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!pile.canAdd || context.isPreview)
            .opacity(pile.canAdd ? 1 : 0.45)
            .help(pile.canAdd ? tr("再贴一张，最多 \(StickyStack.limit) 张") + "  ⌘N" : tr("最多 \(StickyStack.limit) 张"))
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
        draft = WidgetWriter.current(instance.id).map { StickyStack.pile($0.config).front.text } ?? ""
        if frame.width > 0 {
            let target = CGSize(width: binFrame.midX - frame.midX, height: binFrame.midY - frame.midY)
            flight = StickyFlight(paper: paper, text: words, font: noteFont, size: pointSize,
                                  frame: frame, target: target)
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { undo = .tore(torn) }
        undoToken = UUID()
        focusToken = UUID()
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
        // 新一张、翻页之后直接能写：光标放到这张的末尾。
        focusToken = UUID()
    }

    /// Focus leaves the paper far more often than the words change, and every
    /// write is a profile save. 真写了返回 true（顶栏据此闪一下「已保存」）。
    @discardableResult
    private func commit() -> Bool {
        guard !context.isPreview, draft != stored else { return false }
        StickyLog.write(draft, in: instance)
        return true
    }

    /// 失焦和消失时的保存放到下一轮：这两个回调在 SwiftUI 更新视图的中途触发，
    /// 当场写会同步换掉面板的根视图（`WidgetDetailWindow.refresh`），让 AppKit 重入布局。
    /// 写的是当时的字，写进去的是那时最上面那张（`StickyLog` 按现在保存着的那份改）。
    private func commitLater() {
        guard !context.isPreview, draft != stored else { return }
        let words = draft
        let target = instance
        Task { @MainActor in StickyLog.write(words, in: target) }
    }
}

// MARK: - 顶栏小字

/// 顶栏一闪而过的小字。每次换一个 `id`，连着存几次也重新计时。
struct StickyHint: Equatable {
    enum Kind: Equatable {
        case saved, sent, noTodo

        var title: String {
            switch self {
            case .saved: tr("已保存")
            case .sent: tr("已发到快速待办")
            case .noTodo: tr("扩展栏上没有快速待办")
            }
        }

        var symbol: String {
            switch self {
            case .saved: "checkmark"
            case .sent: "paperplane"
            case .noTodo: "exclamationmark.circle"
            }
        }

        /// 「已保存」淡淡一下就走，另外两句多留一会儿好读完。
        var seconds: Double { self == .saved ? 1.4 : 2.6 }
    }

    var kind: Kind
    var id = UUID()
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
