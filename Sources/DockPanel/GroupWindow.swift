import AppKit
import SwiftUI

/// An opened group, in a window of its own.
///
/// Same reasoning as the hover label: drawing it inside the shelf would mean
/// reserving space for the largest group anyone might make. A separate panel
/// costs nothing when closed and can be as large as it needs to be.
@MainActor
final class GroupWindow {
    static let shared = GroupWindow()

    private var panel: PopupPanel?
    private var hosting: FirstMouseHostingView<GroupSheet>?
    /// Which group is open, so clicking the same tile again closes it.
    private(set) var openGroupID: UUID?
    /// Changes on every open, to restart the sheet's entrance.
    private var session = UUID()
    /// 这次打开时的位置和回调，组里加了东西以后原地重画、重新算大小要用。
    private var placement: (anchor: CGPoint, edge: DockPosition, iconSide: CGFloat)?
    private var actions: Actions?
    /// 点窗口外面、按 Esc 收起。见 PopupDismisser。
    private let dismisser = PopupDismisser()
    /// 收起淡出的号：淡出中途又打开时，旧淡出走完不收窗口、把透明度补回 1。
    private var fade = PopupToggle.Fade()
    /// 窗口里有能先退一步的东西（改名改了一半、展开的选择列表），GroupSheet 报上来。
    private var backable = false
    /// Esc 先退一步：每按一次加一，GroupSheet 看到变化就撤销改名或收起选择列表。
    private var backOutTick = 0
    /// 锁定扩展栏：组里的图标不能拖出到扩展栏（拖动只抖一下）。锁只管扩展栏
    /// 本身，组里的「从分组中移除」、从访达拖进组窗口照常。
    /// 扩展栏在设置变化时写进来；开着的窗口原地换成新的一份。
    var locked = false {
        didSet {
            guard locked != oldValue, isOpen, let current = hosting?.rootView.group else { return }
            hosting?.rootView = sheet(for: current)
        }
    }

    private struct Actions {
        var open: (DockItem) -> Void
        var remove: (DockItem) -> Void
        var rename: (String) -> Void
        var add: ([URL]) -> Void
        /// 给组里一项起显示名（nil 是恢复原名），第三个参数是原名。
        var renameItem: (DockItem, String?, String) -> Void
        var showNames: (Bool) -> Void
    }

    /// 小组件库新建一个空组以后要扩展栏立刻打开它：userInfo["id"] 是组的 id 字符串。
    static let openRequest = Notification.Name("com.docket-zh.app-group.open")

    private init() {
        dismisser.visibleFrame = { [weak self] in
            guard let self, self.isOpen, let panel = self.panel else { return nil }
            // 窗口四周那圈透明的拖拽余量看不见，点在上面算外面。
            let room = GroupSheet.dragRoom
            return panel.frame.insetBy(dx: room, dy: room)
        }
        dismisser.hoverFrame = { [weak self] in
            guard let self, self.isOpen, let panel = self.panel else { return nil }
            // 和 contains 一样：看得见的那块再放宽一点。
            let slack = GroupSheet.dragRoom - 14
            return panel.frame.insetBy(dx: slack, dy: slack)
        }
        dismisser.window = { [weak self] in self?.panel }
        dismisser.currentID = { [weak self] in self?.openGroupID }
        dismisser.inner = { [weak self] in self?.backable ?? false }
        dismisser.backOut = { [weak self] in self?.stepBack() }
        dismisser.dismiss = { [weak self] in self?.close() }
    }

    /// Opens `group`, or closes it if it is already the one showing.
    ///
    /// - Parameters:
    ///   - anchor: the point on the tile to grow away from, in screen coordinates.
    ///   - edge: which way the shelf is docked.
    func toggle(_ group: DockGroup, anchor: CGPoint, edge: DockPosition,
                iconSide: CGFloat, host: CGRect = .zero,
                open: @escaping (DockItem) -> Void,
                remove: @escaping (DockItem) -> Void,
                rename: @escaping (String) -> Void,
                add: @escaping ([URL]) -> Void,
                renameItem: @escaping (DockItem, String?, String) -> Void,
                showNames: @escaping (Bool) -> Void) {
        // 只认真的在显示的：记着开着却没显示时直接重新打开，不去「关」一个看不见的
        // 窗口（以前会一直点不开）。刚打开紧跟着的连点不关；点外面收起它的正是点
        // 这个格子的那一下，结果是收起，不再打开。见 Core 的 PopupToggle。
        let decision = PopupToggle.decide(
            requested: group.id, openID: openGroupID, visible: panel?.isVisible == true,
            repeatOfOpen: dismisser.isRepeatOfOpen(id: group.id),
            swallow: { dismisser.swallowsOpen(id: group.id) })
        switch decision {
        case .ignore: return
        case .close: return close()
        case .open: break
        }
        // 没拿到格子位置（指针还没在格子上停过）时从扩展栏外沿正中长出来，
        // 不跑到屏幕角落或另一块屏幕上。
        let anchor = anchor == .zero && host != .zero
            ? DetailPanelFit.fallbackAnchor(edge: edge, shelf: host) : anchor
        show(group, anchor: anchor, edge: edge, iconSide: iconSide,
             actions: Actions(open: open, remove: remove, rename: rename, add: add,
                              renameItem: renameItem, showNames: showNames))
    }

    /// 组里的东西变了（「＋」选了 App、从访达拖进来、改了名）：开着的就是它时
    /// 原地换成新的一份，不重放入场动画，窗口跟着内容改大小。
    func refresh(_ group: DockGroup) {
        guard isOpen, openGroupID == group.id else { return }
        hosting?.rootView = sheet(for: group)
        refit()
    }

    /// 按内容重新算窗口大小和位置（「＋」展开选择列表、加了一排图标时）。
    func refit() {
        guard isOpen, let panel, let placement else { return }
        place(panel, anchor: placement.anchor, edge: placement.edge)
    }

    /// Whether a group is showing, so the shelf can stay put while it is.
    var isOpen: Bool { openGroupID != nil && panel?.isVisible == true }

    /// 开着的、真的在显示的是不是这个组（两指滑动、新建空组打开前用，
    /// 记着开着却没显示的不算）。
    func isShowing(_ id: UUID) -> Bool { isOpen && openGroupID == id }

    /// 扩展栏自动隐藏时每次看指针调用，离开窗口和扩展栏 0.5 秒收起。见
    /// PopupDismisser.pointerTick。
    func pointerTick(_ point: CGPoint, overShelf: Bool, holding: Bool) {
        guard isOpen else { return }
        dismisser.pointerTick(point, overShelf: overShelf, holding: holding)
    }

    /// The sheet's area in screen coordinates, for hit-free pointer tests.
    func contains(_ point: CGPoint) -> Bool {
        guard isOpen, let panel else { return false }
        // The visible sheet plus a little slack, so crossing the gap between
        // tile and sheet does not read as leaving. The window itself is much
        // larger than what is drawn - see GroupSheet.dragRoom.
        let slack = GroupSheet.dragRoom - 14
        return panel.frame.insetBy(dx: slack, dy: slack).contains(point)
    }

    /// Moves the open sheet up or down with a top shelf stepping aside for
    /// 灵动提示, inside the shelf's own animation. See
    /// DockPanelController.islandMoved.
    func shift(by dy: CGFloat) {
        guard isOpen, let panel, dy != 0 else { return }
        panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: dy), display: false)
    }

    func close() {
        dismisser.stop()
        // 记着的先清掉，窗口没在显示也清：不然下次点这个格子会被当成「再点一次关掉」。
        guard openGroupID != nil else { return }
        openGroupID = nil
        backable = false
        guard panel?.isVisible == true else { return }
        // orderOut alone is a vanish. The window fades while the sheet inside
        // it scales back toward the tile it came from.
        let token = fade.begin()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 淡出中途又打开了（连点、从一个组直接点另一个组）：不收，透明度
                // 补回 1，旧淡出可能已经把它落到 0，窗口开着却看不见。
                switch self.fade.finish(token, isOpen: self.openGroupID != nil) {
                case .orderOut:
                    self.panel?.orderOut(nil)
                    self.panel?.alphaValue = 1
                case .restore:
                    self.panel?.alphaValue = 1
                case .nothing:
                    break
                }
            }
        }
    }

    /// Esc 先退一步：撤销改了一半的名字，或者清空、收起展开的选择列表。
    private func stepBack() {
        guard isOpen, let current = hosting?.rootView.group else { return }
        backOutTick += 1
        hosting?.rootView = sheet(for: current)
    }

    private func sheet(for group: DockGroup) -> GroupSheet {
        let actions = self.actions
        let placement = self.placement
        return GroupSheet(group: group, edge: placement?.edge ?? .bottom, session: session,
                          iconSide: placement?.iconSide ?? 48, locked: locked,
                          backOut: backOutTick,
                          open: { [weak self] item in
            actions?.open(item)
            self?.close()
        }, remove: { [weak self] item in
            actions?.remove(item)
            self?.close()
        }, rename: { actions?.rename($0) },
           add: { actions?.add($0) },
           renameItem: { actions?.renameItem($0, $1, $2) },
           showNames: { actions?.showNames($0) },
           resized: { [weak self] in
            // 下一轮再量：这一轮 SwiftUI 还没把新内容排好。
            Task { @MainActor in self?.refit() }
        }, backableChanged: { [weak self] in self?.backable = $0 })
    }

    private func show(_ group: DockGroup, anchor: CGPoint, edge: DockPosition,
                      iconSide: CGFloat, actions: Actions) {
        let panel = existingOrNew()
        // A fresh token per open: the hosting view is reused, so its state
        // survives being ordered out and would otherwise start already-shown.
        session = UUID()
        self.actions = actions
        placement = (anchor, edge, iconSide)
        hosting?.rootView = sheet(for: group)
        openGroupID = group.id
        backable = false

        present(panel, group: group.id, attempt: 1)
    }

    /// 摆上去并显示。内容这一轮还量不出大小时下一轮再试一次，还不行就放弃并
    /// 清掉「开着的是谁」（以前直接返回，记着开着却没显示，之后一直点不开）。
    private func present(_ panel: PopupPanel, group id: UUID, attempt: Int, rebuilt: Bool = false) {
        guard openGroupID == id, let placement else { return }
        guard place(panel, anchor: placement.anchor, edge: placement.edge) else {
            switch PopupToggle.Placement.afterFailure(attempt: attempt) {
            case .retry:
                Task { @MainActor [weak self] in
                    self?.present(panel, group: id, attempt: attempt + 1, rebuilt: rebuilt)
                }
            case .giveUp:
                openGroupID = nil
                backable = false
            }
            return
        }
        // 作废还没走完的收起淡出（连点、从一个组直接点另一个组时同一个窗口
        // 正在淡出）：新的透明度动画顶掉旧的，旧淡出走完时也会补回 1。
        let wasVisible = panel.isVisible
        fade.cancel()
        if wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
        panel.orderFrontRegardless()
        // 系统把窗口钉在了另一个桌面（设了出现在所有桌面也会）：在这个桌面点开
        // 等于没反应。丢掉旧窗口、新建一个重摆，新窗口落在当前桌面。
        if PanelSpaceRescue.shouldRebuild(isOnActiveSpace: panel.isOnActiveSpace, alreadyRebuilt: rebuilt),
           let group = hosting?.rootView.group {
            panel.orderOut(nil)
            self.panel = nil
            hosting = nil
            let fresh = existingOrNew()
            hosting?.rootView = sheet(for: group)
            return present(fresh, group: id, attempt: attempt, rebuilt: true)
        }
        // Needed for the name field; the shelf itself still never takes key,
        // so clicking a tile does not pull focus out of the user's app.
        // 也是 Esc 能收到的前提。
        panel.makeKey()
        dismisser.start()
        dismisser.noteOpened(id: id)
    }

    /// 按现在的内容把窗口放到格子旁边。内容还量不出大小时返回 false。
    @discardableResult
    private func place(_ panel: NSPanel, anchor: CGPoint, edge: DockPosition) -> Bool {
        let size = hosting?.fittingSize ?? .zero
        let room = GroupSheet.dragRoom
        let visible = CGSize(width: size.width - room * 2, height: size.height - room * 2)
        guard visible.width > 1, visible.height > 1 else { return false }

        // Everything is positioned against the sheet the user can see; the
        // panel is then offset so its invisible margin falls outside that.
        // Opens downwards from a top shelf; see Geometry.popupOrigin.
        let sheet = Geometry.popupOrigin(edge: edge, anchor: anchor, size: visible, gap: 12)
        let placed = clamped(sheet, size: visible)

        let frame = CGRect(origin: CGPoint(x: placed.x - room, y: placed.y - room), size: size)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        return true
    }

    /// Keeps the sheet on screen when the group sits near a corner.
    private func clamped(_ origin: CGPoint, size: NSSize) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) })
                ?? NSScreen.main else { return origin }
        let visible = screen.visibleFrame
        return CGPoint(
            x: min(max(origin.x, visible.minX + 6), max(visible.minX, visible.maxX - size.width - 6)),
            y: min(max(origin.y, visible.minY + 6), max(visible.minY, visible.maxY - size.height - 6))
        )
    }

    private func existingOrNew() -> PopupPanel {
        if let panel { return panel }
        let hosting = FirstMouseHostingView(rootView: GroupSheet(group: DockGroup(name: ""),
                                                                  edge: .bottom, session: session,
                                                                  iconSide: 48,
                                                                  open: { _ in }, remove: { _ in },
                                                                  rename: { _ in }, add: { _ in },
                                                                  renameItem: { _, _, _ in },
                                                                  showNames: { _ in },
                                                                  resized: {}))
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = PopupPanel(contentRect: .zero,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.onEscape = { [weak self, weak panel] in
            guard let self, let panel, self.isOpen else { return false }
            return self.dismisser.escape(in: panel)
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // The sheet holds an editable name, and a panel that can never become
        // key would show a caret that accepts no typing.
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // One above the shelf, so an opened group is never behind the tile it
        // came from.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

        self.panel = panel
        self.hosting = hosting
        return panel
    }
}

/// The opened group's contents: its name, then every item at full size.
struct GroupSheet: View {
    var group: DockGroup
    /// Which way the shelf is docked, so the sheet grows from the tile's side.
    var edge: DockPosition
    /// Identifies one opening, so the entrance replays each time.
    var session: UUID
    /// The shelf's icon size, so a dragged icon becomes what it is about to be.
    var iconSide: CGFloat
    /// 锁定扩展栏时不能把图标拖出到扩展栏；拖进组窗口、组里移除照常。
    var locked = false
    /// Esc 先退一步的计数，变了就撤销改名或交给选择列表退一步。
    var backOut = 0
    var open: (DockItem) -> Void
    var remove: (DockItem) -> Void
    var rename: (String) -> Void
    /// 「＋」选好的、从访达拖进来的 App（只会是 .app）。
    var add: ([URL]) -> Void
    /// 给组里一项起显示名（nil 是恢复原名），第三个参数是原名。只是显示名，
    /// 锁定扩展栏时也能改。
    var renameItem: (DockItem, String?, String) -> Void
    /// 「显示名字」开关。
    var showNames: (Bool) -> Void
    /// 内容大小变了（展开、收起选择列表），窗口要跟着改。
    var resized: () -> Void
    /// 有没有能让 Esc 先退一步的东西（改名改了一半、展开着选择列表）。
    var backableChanged: (Bool) -> Void = { _ in }

    @State private var appeared = false
    @State private var draft = ""
    @FocusState private var editing: Bool
    /// 「＋」展开的选择 App 列表。
    @State private var picking = false
    /// 有 App 从访达拖到窗口上。
    @State private var dropTargeted = false
    /// 交给选择列表的 Esc 退一步计数。
    @State private var pickerBackOut = 0
    /// 正在改显示名的那一项和改到一半的字。
    @State private var renamingItemID: UUID?
    @State private var itemDraft = ""

    /// 改名框里的字改过了还没确认。
    private var renaming: Bool { editing && draft != group.name }

    /// Wraps rather than growing without limit - a group with thirty apps
    /// should not produce a sheet wider than the screen. 最后一格是「＋」。
    private var columns: Int { min(5, max(1, group.items.count + 1)) }
    private let side: CGFloat = 52
    /// 名字那一行的宽度：比图标宽一些，「Illustrator」「Photoshop」这类一行放得下，
    /// 放不下的折成两行，再长才在尾部省略。
    static let labelWidth: CGFloat = 72

    /// 每一项显示的名字：自定义名优先，App 用短名，见 AppGroups.displayNames。
    private var titles: [UUID: String] {
        AppGroups.displayNames(in: group, original: Self.originalName)
    }

    /// 一项原来的名字：App、文件是文件名（不带扩展名），链接是标题。
    static func originalName(_ item: DockItem) -> String {
        if let url = item.fileRef?.resolve() {
            return url.deletingPathExtension().lastPathComponent
        }
        if let url = item.fileRef?.url {
            return url.deletingPathExtension().lastPathComponent
        }
        if case .link(_, _, let title) = item { return title }
        return tr("项目")
    }

    /// Named so a dragged icon can tell when it has left the sheet.
    static let space = "group-sheet"

    /// Invisible room around the sheet for an icon being dragged out.
    ///
    /// The panel's frame is its clip: without this the icon vanished at the
    /// sheet's edge exactly as it started to leave, which is the moment the
    /// gesture most needs to be visible. The margin draws nothing and takes
    /// no clicks, so it costs only window area.
    static let dragRoom: CGFloat = 90

    @State private var bounds: CGSize = .zero

    var body: some View {
        VStack(spacing: 10) {
            // Editable in place. A group's name is the one thing you always
            // want to change right after making one, and burying it in a
            // submenu behind a modal is why it read as not being possible.
            TextField("名称", text: $draft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(editing ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .focused($editing)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(editing ? Color.primary.opacity(0.10) : .clear)
                }
                .onSubmit { commit() }
                .onChange(of: editing) { _, focused in if !focused { commit() } }

            if picking {
                GroupAppPicker(group: group,
                               backOut: pickerBackOut,
                               onAdd: { urls in
                                   picking = false
                                   add(urls)
                               },
                               onCancel: { picking = false })
            } else if group.items.isEmpty {
                emptyState
            } else {
                let titles = self.titles
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(row) { item in
                                let original = Self.originalName(item)
                                let custom = group.customName(for: item.id)
                                GroupSheetItem(item: item, side: side, sheet: bounds,
                                               dockSide: iconSide, group: group.id,
                                               locked: locked,
                                               title: titles[item.id] ?? original,
                                               fullName: custom.map { "\($0) (\(original))" } ?? original,
                                               showsName: group.showsNames,
                                               hasCustomName: custom != nil,
                                               editing: renamingItemID == item.id,
                                               draft: $itemDraft,
                                               open: { open(item) },
                                               remove: { remove(item) },
                                               startRename: {
                                                   itemDraft = titles[item.id] ?? original
                                                   renamingItemID = item.id
                                               },
                                               commitRename: { commitItem(item, original: original,
                                                                          shown: titles[item.id] ?? original) },
                                               restoreName: { renameItem(item, nil, original) },
                                               showsNames: group.showsNames,
                                               toggleNames: { showNames(!group.showsNames) },
                                               canAddToGroup: !picking
                                                   && ShelfLock.allows(.dropIntoGroupWindow, locked: locked),
                                               addApps: { urls in add(urls) })
                            }
                            if index == rows.count - 1, row.count < columns {
                                addCell
                            }
                        }
                    }
                    if rows.last?.count == columns {
                        HStack(spacing: 10) { addCell }
                    }
                }
            }
        }
        .padding(14)
        // 从访达拖 .app 进来就加进组；别的东西不接。
        .onDrop(of: FileDropDelegate.types,
                delegate: FileDropDelegate(enabled: !picking
                                               && ShelfLock.allows(.dropIntoGroupWindow, locked: locked),
                                           update: { over, _ in dropTargeted = over },
                                           receive: { urls in
                                               let apps = urls.filter(AppGroups.isAppBundle)
                                               if !apps.isEmpty { add(apps) }
                                           }))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
            }
        }
        .coordinateSpace(name: Self.space)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { bounds = proxy.size }
                    .onChange(of: proxy.size) { _, new in
                        bounds = new
                        resized()
                    }
            }
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                // 右键空白处：「显示名字」开关。图标上的右键菜单里也有。
                .contextMenu {
                    Toggle(tr("显示名字"), isOn: Binding(get: { group.showsNames },
                                                        set: { showNames($0) }))
                }
        }
        .fixedSize()
        // Scales out of the tile it belongs to instead of appearing at full
        // size in place. Anchored on the docked edge, so it reads as the tile
        // opening rather than a panel arriving.
        .scaleEffect(appeared ? 1 : 0.88, anchor: growthAnchor)
        .opacity(appeared ? 1 : 0)
        .padding(Self.dragRoom)
        .onAppear {
            draft = group.name
            enter()
        }
        .onChange(of: session) { _, _ in
            draft = group.name
            picking = false
            renamingItemID = nil
            appeared = false
            // Next runloop, or setting and clearing in one pass animates nothing.
            Task { @MainActor in enter() }
        }
        .onChange(of: renaming || picking || renamingItemID != nil, initial: true) { _, now in
            backableChanged(now)
        }
        .onChange(of: backOut) { _, _ in
            if renamingItemID != nil {
                // 撤销改了一半的显示名：先清掉，失焦时的提交就什么也不做。
                renamingItemID = nil
            } else if renaming {
                // 撤销：先把字改回去，失焦时的提交就什么也不做。
                draft = group.name
                editing = false
            } else if picking {
                pickerBackOut += 1
            }
        }
    }

    /// 空组：一句说明加一个大「＋」。
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(tr("把 App 拖进来，或点 ＋ 选择"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220)
            Button { picking = true } label: {
                Label(tr("选择 App"), systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelOnPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.panelPrimary))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("选择 App"))
        }
        .padding(.vertical, 8)
    }

    /// 格子最后的「＋」，和图标一样大，点了展开选择列表。
    private var addCell: some View {
        Button { picking = true } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.panelTertiary,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.panelSecondary)
                    }
                    .frame(width: side, height: side)
                if group.showsNames {
                    Text(tr("添加"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .frame(width: Self.labelWidth)
                }
            }
            .padding(4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("选择要加进分组的 App"))
        .accessibilityLabel(tr("添加 App"))
    }

    /// 确认显示名：没改（还是现在显示的名字）什么也不做，空的是恢复原名。
    private func commitItem(_ item: DockItem, original: String, shown: String) {
        guard renamingItemID == item.id else { return }
        renamingItemID = nil
        let name = itemDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != shown else { return }
        renameItem(item, name.isEmpty ? nil : name, original)
    }

    /// Ignores an empty name rather than leaving a group with none.
    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != group.name else {
            draft = group.name
            return
        }
        rename(name)
    }

    private func enter() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) { appeared = true }
    }

    private var growthAnchor: UnitPoint {
        switch edge {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    private var rows: [[DockItem]] {
        stride(from: 0, to: group.items.count, by: columns).map {
            Array(group.items[$0 ..< min($0 + columns, group.items.count)])
        }
    }
}

private struct GroupSheetItem: View {
    var item: DockItem
    var side: CGFloat
    /// The sheet's size, so the icon knows when it has been pulled outside it.
    var sheet: CGSize
    /// What size it becomes once it is over the shelf.
    var dockSide: CGFloat
    /// The group it would be leaving.
    var group: UUID
    /// 锁定扩展栏：拖动时只抖一下，不离开分组（拖出会落到扩展栏上，是扩展栏
    /// 的布局）；右键「从分组中移除」照常。
    var locked = false
    /// 图标下面显示的名字（自定义名或短名）。
    var title: String
    /// 悬停提示里的完整名字（有自定义名时带上原名）。
    var fullName: String
    /// 「显示名字」关掉时只显示图标。
    var showsName = true
    var hasCustomName = false
    /// 正在改这一项的显示名。
    var editing = false
    @Binding var draft: String
    var open: () -> Void
    var remove: () -> Void
    var startRename: () -> Void = {}
    var commitRename: () -> Void = {}
    var restoreName: () -> Void = {}
    var showsNames = true
    var toggleNames: () -> Void = {}
    /// 拖 App 到图标上（不按 Option）照旧加进组，和拖到窗口空白处一样；锁定、选择列表
    /// 开着时不收。
    var canAddToGroup = false
    var addApps: ([URL]) -> Void = { _ in }

    @FocusState private var fieldFocused: Bool
    @State private var hovering = false
    @State private var shakeTick = 0
    @State private var nudged = false
    @State private var offset: CGSize = .zero
    @State private var leaving = false
    /// This icon's own centre in the sheet, so a drag can pin to the pointer.
    @State private var centre: CGPoint = .zero
    /// Released outside: shrinking away at the drop point before the shelf
    /// grows it back in, so the icon travels instead of blinking out.
    @State private var departing = false
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    /// Dragging an icon past the edge of the sheet takes it out of the group,
    /// the way dragging one off a folder does on iOS. A cross-window drag
    /// session would be the general answer, but the only destination here is
    /// "not in this group", so leaving the sheet is the whole gesture.
    private func outside(_ point: CGPoint) -> Bool {
        GroupDrag.leavesSheet(point, sheet: sheet)
    }

    /// Once it is over the shelf it is a dock icon, so it becomes one - the
    /// sheet draws at its own size, and an icon that kept it would land at the
    /// wrong scale and snap.
    private var carriedSide: CGFloat { leaving ? dockSide : side }

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: carriedSide, height: carriedSide)
                // 拖文件上去用它打开；按住 Option 拖图片或 App 上去换显示图标（Pro）。
                .modifier(DockIconDropTarget(bundleID: DockIconDrop.appBundleID(of: item),
                                             ref: item.fileRef,
                                             place: .groupWindow,
                                             edge: .bottom,
                                             canAddToGroup: canAddToGroup,
                                             addToGroup: { urls in
                                                 let apps = urls.filter(AppGroups.isAppBundle)
                                                 if !apps.isEmpty { addApps(apps) }
                                             }))
            if editing {
                TextField(tr("名称"), text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                    .focused($fieldFocused)
                    .lineLimit(1)
                    .frame(width: GroupSheet.labelWidth)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    }
                    .onAppear { fieldFocused = true }
                    .onSubmit(commitRename)
                    .onChange(of: fieldFocused) { _, focused in if !focused { commitRename() } }
            } else if showsName {
                // 放不下先折成两行，再长才在尾部省略（不在中间省略，开头最好认）。
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: GroupSheet.labelWidth)
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.10) : .clear)
        }
        .background {
            GeometryReader { proxy in
                let box = proxy.frame(in: .named(GroupSheet.space))
                Color.clear
                    .onAppear { centre = CGPoint(x: box.midX, y: box.midY) }
                    .onChange(of: box) { _, new in
                        // Only while at rest: the frame moves as the icon is
                        // dragged, and following it would chase its own tail.
                        if offset == .zero { centre = CGPoint(x: new.midX, y: new.midY) }
                    }
            }
        }
        .offset(offset)
        .scaleEffect(departing ? 0.25 : 1)
        .opacity(departing ? 0 : (leaving ? 0.8 : 1))
        .zIndex(offset == .zero ? 0 : 1)
        .contentShape(.rect)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.14)) { hovering = inside }
        }
        .onTapGesture { if !editing { open() } }
        .help(fullName)
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named(GroupSheet.space))
                .onChanged { value in
                    guard !editing else { return }
                    guard ShelfLock.allows(.dragOutOfGroup, locked: locked) else {
                        if ShelfLock.shouldShake(locked: true, alreadyNudged: nudged) {
                            nudged = true
                            shakeTick += 1
                        }
                        return
                    }
                    // Pinned to the pointer, not displaced by it. Offsetting
                    // by the translation leaves the icon wherever the cursor
                    // happened to grab it - press near an edge and the icon
                    // trails the pointer by that much for the whole drag.
                    offset = GroupDrag.offset(cursor: value.location, centre: centre)
                    let out = outside(value.location)
                    if DragOut.shared.item == nil { DragOut.shared.begin(item, from: group) }
                    // The pointer in screen coordinates, which is what the
                    // shelf needs and what no SwiftUI space in this window can
                    // give it. `mouseLocation` is already exactly that.
                    DragOut.shared.update(location: NSEvent.mouseLocation, outside: out)
                    if out != leaving {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                            leaving = out
                        }
                    }
                }
                .onEnded { value in
                    guard !editing else { return }
                    let wasNudged = nudged
                    nudged = false
                    if wasNudged { return }
                    defer { DragOut.shared.end() }
                    if outside(value.location) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            departing = true
                        }
                        // Hands over once the icon has gone, so the shelf's own
                        // entrance picks up where this leaves off.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(150))
                            remove()
                        }
                        return
                    }
                    // Dropped back inside: nothing changes, so it springs home.
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                        offset = .zero
                        leaving = false
                    }
                }
        )
        .lockShake(shakeTick)
        .contextMenu {
            // 只是显示名，锁定扩展栏时也能改。
            Button(tr("重命名…"), action: startRename)
            if hasCustomName {
                Button(tr("恢复原名"), action: restoreName)
            }
            Toggle(tr("显示名字"), isOn: Binding(get: { showsNames }, set: { _ in toggleNames() }))
            if case .app(_, let bundleID, let ref) = item {
                Divider()
                // 换显示图标（Pro），和扩展栏上的右键菜单同一套。
                Button(DockAppIconPicker.menuTitle(tr("更换图标…"))) {
                    Task { @MainActor in DockAppIconPicker.choose(bundleID: bundleID, ref: ref) }
                }
                if DockAppIconStore.shared.hasCustomIcon(bundleID) {
                    Button(tr("恢复默认图标")) { DockAppIconStore.shared.resetIcon(for: bundleID) }
                }
            }
            Divider()
            Button("从分组中移除") { remove() }
                .disabled(!ShelfLock.allows(.removeInGroup, locked: locked))
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(fullName)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = item.fileRef?.resolve() {
            Image(nsImage: DockAppIconDisplay.image(for: item, fallback: AppCatalog.shared.icon(for: url),
                                                    unlocked: licenseUnlocked || supporter))
                .resizable().interpolation(.high)
        } else if case .app(_, let bundleID, _) = item,
                  let image = AppCatalog.shared.icon(forBundleID: bundleID) {
            Image(nsImage: DockAppIconStore.shared.icon(for: bundleID, fallback: image,
                                                        unlocked: licenseUnlocked || supporter))
                .resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.3))
        }
    }
}

// MARK: - 选择 App

/// 选择列表里的一个 App。
struct GroupAppCandidate: Identifiable, Sendable, Hashable {
    var url: URL
    var name: String
    var bundleID: String
    var running = false

    var id: String { url.standardizedFileURL.path(percentEncoded: false) }

    var item: DockItem {
        .app(id: UUID(), bundleID: bundleID, ref: .capture(url))
    }
}

/// 读应用程序文件夹里的 App：/Applications、~/Applications、系统自带的
/// /System/Applications（各带一层子文件夹，比如「实用工具」），再加访达。
/// 不碰主线程，几百个 App 也只是列目录。
enum GroupAppScan {
    nonisolated static func installed() -> [GroupAppCandidate] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appending(path: "Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        var urls: [URL] = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                if AppGroups.isAppBundle(child) {
                    urls.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          let inner = try? fm.contentsOfDirectory(
                              at: child, includingPropertiesForKeys: nil,
                              options: [.skipsHiddenFiles]) {
                    urls.append(contentsOf: inner.filter(AppGroups.isAppBundle))
                }
            }
        }
        var seen = Set<String>()
        var result: [GroupAppCandidate] = []
        for url in urls where fm.fileExists(atPath: url.path(percentEncoded: false)) {
            let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
            let key = bundleID.isEmpty ? url.standardizedFileURL.path : bundleID.lowercased()
            guard seen.insert(key).inserted else { continue }
            let name = WidgetLibraryGroups.appTitle(fm.displayName(atPath: url.path(percentEncoded: false)))
            result.append(GroupAppCandidate(url: url, name: name, bundleID: bundleID))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 正在运行的排前面（不在应用程序文件夹里的也算），其余按名字。
    @MainActor
    static func merged(installed: [GroupAppCandidate], running: [RunningApp]) -> [GroupAppCandidate] {
        var runningIDs = Set<String>()
        var extra: [GroupAppCandidate] = []
        for app in running {
            guard let url = app.url, AppGroups.isAppBundle(url) else { continue }
            runningIDs.insert(app.id.lowercased())
            if !installed.contains(where: { $0.bundleID.lowercased() == app.id.lowercased() }) {
                extra.append(GroupAppCandidate(url: url, name: app.name, bundleID: app.id, running: true))
            }
        }
        let marked = installed.map { candidate -> GroupAppCandidate in
            var copy = candidate
            copy.running = !candidate.bundleID.isEmpty && runningIDs.contains(candidate.bundleID.lowercased())
            return copy
        }
        let all = (marked + extra).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return all.filter(\.running) + all.filter { !$0.running }
    }
}

/// 组窗口里「＋」展开的选择列表：可多选，带图标和搜索，正在运行的排前面，
/// 已经在组里的打勾、不能再选。
struct GroupAppPicker: View {
    var group: DockGroup
    /// 窗口的 Esc 退一步计数：搜索有字先清空，没字就收起列表。
    var backOut = 0
    var onAdd: ([URL]) -> Void
    var onCancel: () -> Void

    @State private var candidates: [GroupAppCandidate]?
    @State private var chosen: [String] = []
    @State private var query = ""
    @FocusState private var searching: Bool

    private static let width: CGFloat = 300
    private static let listHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 8) {
            searchField
            list
                .frame(width: Self.width, height: Self.listHeight)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.panelFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 8) {
                Button(tr("取消"), action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.panelFill))
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button { confirm() } label: {
                    Text(chosen.isEmpty ? tr("添加") : tr("添加 \(chosen.count) 个"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelOnPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(chosen.isEmpty ? Color.panelTertiary : Color.panelPrimary))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(chosen.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: Self.width)
        }
        .onExitCommand(perform: onCancel)
        .onChange(of: backOut) { _, _ in
            if query.isEmpty { onCancel() } else { query = "" }
        }
        .task {
            searching = true
            let installed = await Task.detached(priority: .userInitiated) {
                GroupAppScan.installed()
            }.value
            candidates = GroupAppScan.merged(installed: installed, running: AppCatalog.shared.running)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
            TextField(tr("搜索 App"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searching)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.panelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("清除搜索"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: Self.width)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.panelFill))
    }

    @ViewBuilder
    private var list: some View {
        if let candidates {
            let shown = candidates.filter {
                AppGroups.matches(query, name: $0.name, bundleID: $0.bundleID)
            }
            if candidates.isEmpty {
                note(tr("在应用程序文件夹里没有找到 App。"))
            } else if shown.isEmpty {
                note(tr("没有匹配的 App"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let running = shown.filter(\.running)
                        if !running.isEmpty {
                            header(tr("正在运行的 App"))
                            ForEach(running) { row($0) }
                            header(tr("所有 App"))
                        }
                        ForEach(shown.filter { !$0.running }) { row($0) }
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("正在读取 App…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func row(_ candidate: GroupAppCandidate) -> some View {
        let already = AppGroups.contains(candidate.item, in: group)
        let selected = chosen.contains(candidate.id)
        return Button {
            if selected { chosen.removeAll { $0 == candidate.id } } else { chosen.append(candidate.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: already || selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(already ? AnyShapeStyle(.panelTertiary)
                                     : selected ? AnyShapeStyle(Color.accentColor)
                                     : AnyShapeStyle(.panelTertiary))
                Image(nsImage: AppCatalog.shared.icon(for: candidate.url))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                Text(candidate.name)
                    .font(.system(size: 13))
                    .foregroundStyle(already ? Color.panelTertiary : Color.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if already {
                    Text(tr("已在分组中"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(.panelSelected) : AnyShapeStyle(.clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(already)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 按勾选的先后加进组。
    private func confirm() {
        guard let candidates, !chosen.isEmpty else { return }
        let byID = Dictionary(candidates.map { ($0.id, $0.url) }, uniquingKeysWith: { a, _ in a })
        onAdd(chosen.compactMap { byID[$0] })
    }
}
