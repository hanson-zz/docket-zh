import AppKit
import SwiftUI

/// 快捷指令面板：列出卡片上选的那串快捷指令，每个能运行、停止，看上次结果。
///
/// 两个状态：
/// - 浏览：头上写“5 个已选 · 前 4 个放在卡片上”，下面是卡片上那排图标的
///   预览，再往下每个已选的一行：图标、名字、上次运行的时间和结果（已完成、
///   正在运行、失败原因），右边运行或停止。快捷指令往 stdout 打了文字的，
///   行下面多一格“输出”，点开看全文、可以拷贝；拿不到就不显示。
/// - 编辑：右上“编辑”进入。搜索系统里全部快捷指令（名字、拼音、首字母都行），
///   点一行勾选加入或取消；下面“已加入”拖左边把手排序，前 4 个放在卡片上；
///   “外观”展开给每个挑 8 种颜色之一和一个图标，卡片跟着变。
///
/// 系统列表在面板打开时读一次。只能在“快捷指令”App 里改，去那里就离开了
/// 面板，面板也就关了，所以不轮询。勾选了却在系统列表里找不到的（改了名或
/// 删了），浏览时那一行直接说出来，编辑时可以移除。
struct ShortcutDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing = false
    /// 展开了全文输出的那几行。
    @State private var expandedOutput: Set<String> = []
    /// 编辑态里正展开“外观”的那一个。
    @State private var styling: String?
    @State private var query = ""
    @FocusState private var searching: Bool
    /// 正在拖的那一行和它的位移。
    @State private var dragging: String?
    @State private var dragOffset: CGFloat = 0

    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Self.violet) }
    private var accentInk: Color { panelTint.ink(or: Self.violetInk) }

    private var service: ShortcutsService { ShortcutsService.shared }

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var items: [ShortcutItem] { ShortcutDeck.items(current.config) }

    private static let violet = Color(hex: "#C58BFF")
    private static let violetInk = Color(hex: "#22093A")
    private static let red = Color(hex: "#FF6B5A")
    private static let green = Color(hex: "#5BD98A")
    /// 已加入的一行 48 高，行间 6。
    private static let editRowHeight: CGFloat = 48
    private static let editRowStep: CGFloat = 54
    /// 浏览时超过这么多行就在列表里滚动，面板不至于长出屏幕。
    private static let visibleRows = 6

    var body: some View {
        let list = items
        TimelineView(.everyMinute) { tick in
            DetailCard {
                MeshBackdrop(color: Self.violet)
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    header(list)
                    if editing {
                        edit(list)
                    } else {
                        browse(list, now: tick.date)
                    }
                }
            }
        }
        .task { await service.load() }
    }

    // MARK: 头部

    private func header(_ list: [ShortcutItem]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editing ? tr("选择快捷指令") : tr("快捷指令"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(editing ? tr("勾选加入 · 拖动排序") : ShortcutRun.header(count: list.count))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !context.isPreview {
                if editing {
                    Button { switchEditing(false) } label: {
                        Text(tr("完成"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accentInk)
                            .padding(.horizontal, 15)
                            .frame(height: 28)
                            .background(Capsule().fill(accent))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { switchEditing(true) } label: {
                        Text(tr("编辑"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .padding(.horizontal, 13)
                            .frame(height: 28)
                            .background(Capsule().fill(.panelFill))
                            .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(tr("勾选快捷指令、调整顺序、改颜色和图标"))
                }
            }
        }
    }

    private func switchEditing(_ on: Bool) {
        if on { WidgetDetailWindow.shared.focusField {} }
        withAnimation(.snappy(duration: 0.25)) {
            editing = on
            styling = nil
            query = ""
            dragging = nil
            dragOffset = 0
        }
    }

    // MARK: 浏览

    @ViewBuilder
    private func browse(_ list: [ShortcutItem], now: Date) -> some View {
        if list.isEmpty {
            emptyState
        } else {
            tilePreview(list)
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("已选"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                if list.count > Self.visibleRows {
                    ScrollView(.vertical) { rows(list, now: now) }
                        .scrollIndicators(.automatic)
                        .frame(height: CGFloat(Self.visibleRows) * 60)
                } else {
                    rows(list, now: now)
                }
            }
        }
        if let error = service.loadError {
            note(error, tint: Self.red)
        }
        Button(action: openShortcuts) {
            Text(tr("打开快捷指令 App"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(.panelFill))
                .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    /// 一个都没选：一句话加一个实心按钮，直接进编辑。
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.2.layers.3d.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent.panelReadable)
            Text(tr("从系统的快捷指令里挑几个放到卡片上，点一下就跑。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !context.isPreview {
                Button { switchEditing(true) } label: {
                    Text(tr("选择快捷指令"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentInk)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(Capsule().fill(accent))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassPane(cornerRadius: 14)
    }

    /// 卡片上那排的样子：前 4 个。
    private func tilePreview(_ list: [ShortcutItem]) -> some View {
        HStack(spacing: 8) {
            Text(tr("卡片上"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 50, alignment: .leading)
            ForEach(list.prefix(ShortcutDeck.tileLimit)) { item in
                ShortcutIcon(item: item, size: 44, running: service.isRunning(item.name))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 74)
        .glassPane(cornerRadius: 14)
    }

    private func rows(_ list: [ShortcutItem], now: Date) -> some View {
        let gone = ShortcutDeck.missing(list, available: service.loadedAt == nil || service.loadError != nil
                                        ? nil : service.names)
        return VStack(spacing: 6) {
            ForEach(list) { item in
                browseRow(item, missing: gone.contains(item.name), now: now)
            }
        }
    }

    private func browseRow(_ item: ShortcutItem, missing: Bool, now: Date) -> some View {
        let running = service.isRunning(item.name)
        let record = service.record(for: item.name)
        let status = ShortcutRun.line(record: record, running: running, missing: missing, now: now)
        let output = running ? nil : record?.output
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ShortcutIcon(item: item, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                    statusLine(status.text, tone: status.tone)
                }
                Spacer(minLength: 4)
                runButton(item, running: running)
            }
            if let output {
                outputBox(output, name: item.name)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 12)
    }

    private func statusLine(_ text: String, tone: ShortcutRun.Tone) -> some View {
        HStack(spacing: 6) {
            if tone == .success {
                Circle().fill(Self.green).frame(width: 7, height: 7)
            }
            Text(verbatim: text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor(tone))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(text)
    }

    private func statusColor(_ tone: ShortcutRun.Tone) -> Color {
        switch tone {
        case .plain, .success: .panelSecondary
        case .running: accent.panelReadable
        case .failure: Self.red.panelReadable
        }
    }

    /// 运行是实心强调色圆盘、深色三角；正在跑时换成浅色圆盘上的白色方块。
    private func runButton(_ item: ShortcutItem, running: Bool) -> some View {
        Button {
            guard !context.isPreview else { return }
            if running { service.stop(item.name) } else { service.run(item.name) }
        } label: {
            ZStack {
                Circle().fill(running ? Color.panelSelected : accent)
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: running ? 12 : 13, weight: .bold))
                    .foregroundStyle(running ? Color.panelPrimary : accentInk)
                    .offset(x: running ? 0 : 1.5)
            }
            .frame(width: 34, height: 34)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
        .accessibilityLabel(running ? tr("停止“\(item.name)”") : tr("运行“\(item.name)”"))
    }

    /// 上次运行打到 stdout 的文字。收着时一行，点一下展开全文，能选中拷贝。
    private func outputBox(_ output: String, name: String) -> some View {
        let open = expandedOutput.contains(name)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    if open { expandedOutput.remove(name) } else { expandedOutput.insert(name) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(open ? tr("输出") : tr("输出：\(output)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelTertiary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(open ? tr("收起输出") : tr("展开输出"))
            if open {
                Text(verbatim: output)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                } label: {
                    Label(tr("拷贝"), systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.panelShade))
    }

    // MARK: 编辑

    @ViewBuilder
    private func edit(_ list: [ShortcutItem]) -> some View {
        searchField
        results(list)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("已加入 \(list.count)"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                    Spacer(minLength: 0)
                    Text(tr("卡片放前 \(ShortcutDeck.tileLimit) 个"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                }
                addedList(list)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            TextField(tr("搜索快捷指令"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($searching)
            if service.loadedAt != nil, service.loadError == nil {
                Text(tr("全部 \(service.names.count) 个"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.panelFill))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(searching ? accent.opacity(0.9) : .panelStroke, lineWidth: searching ? 1.2 : 0.6)
        }
        .onAppear {
            DispatchQueue.main.async { searching = true }
        }
    }

    /// 搜索结果：点一行勾选或取消。
    @ViewBuilder
    private func results(_ list: [ShortcutItem]) -> some View {
        if let error = service.loadError {
            note(error, tint: Self.red)
        } else if service.loadedAt == nil {
            note(tr("正在读取你的快捷指令。"), tint: nil)
        } else if service.names.isEmpty {
            note(tr("你还没有快捷指令。在“快捷指令”App 中创建一个，它就会显示在这里。"), tint: nil)
        } else {
            let found = ShortcutDeck.search(query, in: service.names)
            if found.isEmpty {
                note(tr("没有名字里带“\(query.trimmingCharacters(in: .whitespaces))”的快捷指令。"), tint: nil)
            } else {
                let added = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
                let content = VStack(spacing: 0) {
                    ForEach(Array(found.enumerated()), id: \.element) { index, name in
                        resultRow(name, item: added[name], full: list.count >= ShortcutDeck.limit,
                                  last: index == found.count - 1)
                    }
                }
                .padding(.vertical, 4)
                Group {
                    if found.count > 5 {
                        ScrollView(.vertical) { content }.frame(height: 5 * 46 + 8)
                    } else {
                        content
                    }
                }
                .glassPane(cornerRadius: 12)
            }
        }
    }

    private func resultRow(_ name: String, item: ShortcutItem?, full: Bool, last: Bool) -> some View {
        let on = item != nil
        let blocked = !on && full
        return Button {
            guard !blocked else { return }
            save(ShortcutDeck.toggling(name, in: items))
        } label: {
            HStack(spacing: 12) {
                if let item {
                    ShortcutIcon(item: item, size: 32)
                } else {
                    // 还没加入的用中性底，加入后才有自己的颜色和图标。
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.panelFill)
                        Image(systemName: "square.2.layers.3d")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.panelSecondary)
                    }
                    .frame(width: 32, height: 32)
                }
                Text(verbatim: name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary.opacity(blocked ? 0.45 : 0.97))
                    .lineLimit(1)
                Spacer(minLength: 4)
                check(on)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(blocked ? tr("最多选 \(ShortcutDeck.limit) 个") : on ? tr("取消勾选") : tr("加入"))
        .accessibilityLabel(name)
        .accessibilityValue(on ? tr("已加入") : tr("未加入"))
        .overlay(alignment: .bottom) {
            if !last {
                Rectangle().fill(.panelSeparator).frame(height: 0.5).padding(.leading, 56).padding(.trailing, 12)
            }
        }
    }

    private func check(_ on: Bool) -> some View {
        ZStack {
            if on {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentInk)
            } else {
                Circle().strokeBorder(.panelTertiary, lineWidth: 1.4)
            }
        }
        .frame(width: 20, height: 20)
    }

    // MARK: 已加入

    private func addedList(_ list: [ShortcutItem]) -> some View {
        let from = dragging.flatMap { name in list.firstIndex { $0.name == name } }
        let target = from.map {
            ShortcutDeck.dropIndex(from: $0, translation: dragOffset, rowHeight: Self.editRowStep, count: list.count)
        }
        let gone = ShortcutDeck.missing(list, available: service.loadedAt == nil || service.loadError != nil
                                        ? nil : service.names)
        return VStack(spacing: 6) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 6) {
                    addedRow(item, index: index, list: list, missing: gone.contains(item.name))
                    if styling == item.name, dragging == nil {
                        appearance(item)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .offset(y: rowShift(index, from: from, target: target))
                .zIndex(item.name == dragging ? 1 : 0)
            }
        }
    }

    /// 拖动时：被拖的那行跟着手走，经过的行让开一格。
    private func rowShift(_ index: Int, from: Int?, target: Int?) -> CGFloat {
        guard let from, let target else { return 0 }
        if index == from { return dragOffset }
        if from < target, (from + 1...target).contains(index) { return -Self.editRowStep }
        if target < from, (target..<from).contains(index) { return Self.editRowStep }
        return 0
    }

    private func addedRow(_ item: ShortcutItem, index: Int, list: [ShortcutItem], missing: Bool) -> some View {
        let lifted = dragging == item.name
        let open = styling == item.name
        return HStack(spacing: 10) {
            handle(item, index: index, list: list, lifted: lifted)
            ShortcutIcon(item: item, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                if missing {
                    Text(tr("找不到了"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Self.red)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if missing {
                pillButton(tr("移除"), tint: Self.red.panelReadable) { remove(item) }
            } else {
                pillButton(open ? tr("收起") : tr("外观"), tint: .panelPrimary) {
                    withAnimation(.snappy(duration: 0.22)) { styling = open ? nil : item.name }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .frame(height: Self.editRowHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(lifted ? Color.panelDynamic(dark: NSColor(srgbRed: 0.23, green: 0.23, blue: 0.26, alpha: 1),
                                         light: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)) : Color.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(lifted ? accent.opacity(0.6) : .panelStroke, lineWidth: lifted ? 1 : 0.6)
                }
                .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 6, y: 4)
        }
        .contextMenu {
            Button(tr("移除"), systemImage: "minus.circle") { remove(item) }
        }
    }

    private func pillButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 28)
                .background(Capsule().fill(.panelFill))
                .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    /// 左边把手：按住拖动排序，松手时落到最近的一格。
    private func handle(_ item: ShortcutItem, index: Int, list: [ShortcutItem], lifted: Bool) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.panelPrimary.opacity(lifted ? 0.85 : 0.5))
            .frame(width: 28, height: Self.editRowHeight)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if dragging != item.name {
                            dragging = item.name
                            styling = nil
                        }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let to = ShortcutDeck.dropIndex(from: index, translation: value.translation.height,
                                                        rowHeight: Self.editRowStep, count: list.count)
                        save(ShortcutDeck.moving(from: index, to: to, in: list))
                        withAnimation(.snappy(duration: 0.2)) {
                            dragging = nil
                            dragOffset = 0
                        }
                    }
            )
            .help(tr("拖动调整顺序"))
            .accessibilityLabel(tr("调整\(item.name)的顺序"))
    }

    /// 展开的“外观”：8 种颜色、6 个图标，卡片上就用选的这一套。
    private func appearance(_ item: ShortcutItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                Text(tr("颜色"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 44, alignment: .leading)
                HStack(spacing: 7) {
                    ForEach(ShortcutColor.allCases, id: \.self) { colour in
                        Button {
                            save(ShortcutDeck.restyling(item.name, color: colour, in: items))
                        } label: {
                            Circle()
                                .fill(Color(hex: colour.hex))
                                .frame(width: 20, height: 20)
                                .padding(3.5)
                                .overlay {
                                    if colour == item.color {
                                        Circle().strokeBorder(.panelPrimary, lineWidth: 1.6)
                                    }
                                }
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .help(colour.name)
                        .accessibilityLabel(colour.name)
                        .accessibilityAddTraits(colour == item.color ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: 0) {
                Text(tr("图标"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 44, alignment: .leading)
                HStack(spacing: 7) {
                    ForEach(ShortcutSymbol.allCases, id: \.self) { symbol in
                        let selected = symbol == item.symbol
                        Button {
                            save(ShortcutDeck.restyling(item.name, symbol: symbol, in: items))
                        } label: {
                            Image(systemName: symbol.systemName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .frame(width: 30, height: 30)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selected ? Color.panelSelected : Color.panelFill)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(selected ? Color.panelPrimary : Color.panelStroke,
                                                              lineWidth: selected ? 1.2 : 0.6)
                                        }
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(symbol.name)
                        .accessibilityLabel(symbol.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            HStack {
                Text(tr("卡片上就用这个颜色和图标"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 0)
                Button(tr("移除")) { remove(item) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.panelStroke, lineWidth: 0.6)
                }
        }
    }

    // MARK: 写入

    private func save(_ list: [ShortcutItem]) {
        withAnimation(.snappy(duration: 0.22)) {
            WidgetWriter.write(current) { ShortcutDeck.write(list, into: &$0) }
        }
    }

    private func remove(_ item: ShortcutItem) {
        if styling == item.name { styling = nil }
        save(items.filter { $0.name != item.name })
    }

    private func note(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(tint?.panelReadable ?? .panelSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }
}
