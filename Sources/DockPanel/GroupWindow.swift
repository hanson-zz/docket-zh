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

    private var panel: NSPanel?
    private var hosting: FirstMouseHostingView<GroupSheet>?
    /// Which group is open, so clicking the same tile again closes it.
    private(set) var openGroupID: UUID?
    /// Changes on every open, to restart the sheet's entrance.
    private var session = UUID()
    /// 这次打开时的位置和回调，组里加了东西以后原地重画、重新算大小要用。
    private var placement: (anchor: CGPoint, edge: DockPosition, iconSide: CGFloat)?
    private var actions: Actions?
    /// 锁定扩展栏：组里的图标不能拖出、不能从访达拖进来，「从分组中移除」变灰。
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
    }

    /// 小组件库新建一个空组以后要扩展栏立刻打开它：userInfo["id"] 是组的 id 字符串。
    static let openRequest = Notification.Name("com.docket-zh.app-group.open")

    private init() {}

    /// Opens `group`, or closes it if it is already the one showing.
    ///
    /// - Parameters:
    ///   - anchor: the point on the tile to grow away from, in screen coordinates.
    ///   - edge: which way the shelf is docked.
    func toggle(_ group: DockGroup, anchor: CGPoint, edge: DockPosition,
                iconSide: CGFloat,
                open: @escaping (DockItem) -> Void,
                remove: @escaping (DockItem) -> Void,
                rename: @escaping (String) -> Void,
                add: @escaping ([URL]) -> Void) {
        if openGroupID == group.id { return close() }
        show(group, anchor: anchor, edge: edge, iconSide: iconSide,
             actions: Actions(open: open, remove: remove, rename: rename, add: add))
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
        guard panel?.isVisible == true, openGroupID != nil else { return }
        openGroupID = nil
        // orderOut alone is a vanish. The window fades while the sheet inside
        // it scales back toward the tile it came from.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Only if nothing reopened it while the fade was running.
                guard let self, self.openGroupID == nil else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    private func sheet(for group: DockGroup) -> GroupSheet {
        let actions = self.actions
        let placement = self.placement
        return GroupSheet(group: group, edge: placement?.edge ?? .bottom, session: session,
                          iconSide: placement?.iconSide ?? 48, locked: locked,
                          open: { [weak self] item in
            actions?.open(item)
            self?.close()
        }, remove: { [weak self] item in
            actions?.remove(item)
            self?.close()
        }, rename: { actions?.rename($0) },
           add: { actions?.add($0) },
           resized: { [weak self] in
            // 下一轮再量：这一轮 SwiftUI 还没把新内容排好。
            Task { @MainActor in self?.refit() }
        })
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

        guard place(panel, anchor: anchor, edge: edge) else { return }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Needed for the name field; the shelf itself still never takes key,
        // so clicking a tile does not pull focus out of the user's app.
        panel.makeKey()
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

    private func existingOrNew() -> NSPanel {
        if let panel { return panel }
        let hosting = FirstMouseHostingView(rootView: GroupSheet(group: DockGroup(name: ""),
                                                                  edge: .bottom, session: session,
                                                                  iconSide: 48,
                                                                  open: { _ in }, remove: { _ in },
                                                                  rename: { _ in }, add: { _ in },
                                                                  resized: {}))
        hosting.sizingOptions = [.intrinsicContentSize]

        let panel = KeyablePanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.contentView = hosting
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
    /// 锁定扩展栏时不能拖出、拖进。
    var locked = false
    var open: (DockItem) -> Void
    var remove: (DockItem) -> Void
    var rename: (String) -> Void
    /// 「＋」选好的、从访达拖进来的 App（只会是 .app）。
    var add: ([URL]) -> Void
    /// 内容大小变了（展开、收起选择列表），窗口要跟着改。
    var resized: () -> Void

    @State private var appeared = false
    @State private var draft = ""
    @FocusState private var editing: Bool
    /// 「＋」展开的选择 App 列表。
    @State private var picking = false
    /// 有 App 从访达拖到窗口上。
    @State private var dropTargeted = false

    /// Wraps rather than growing without limit - a group with thirty apps
    /// should not produce a sheet wider than the screen. 最后一格是「＋」。
    private var columns: Int { min(5, max(1, group.items.count + 1)) }
    private let side: CGFloat = 52

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
                               onAdd: { urls in
                                   picking = false
                                   add(urls)
                               },
                               onCancel: { picking = false })
            } else if group.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 10) {
                            ForEach(row) { item in
                                GroupSheetItem(item: item, side: side, sheet: bounds,
                                               dockSide: iconSide, group: group.id,
                                               locked: locked,
                                               open: { open(item) },
                                               remove: { remove(item) })
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
                delegate: FileDropDelegate(enabled: !picking && ShelfLock.allows(.dropIn, locked: locked),
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
            appeared = false
            // Next runloop, or setting and clearing in one pass animates nothing.
            Task { @MainActor in enter() }
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
                Text(tr("添加"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .frame(width: side + 8)
            }
            .padding(4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("选择要加进分组的 App"))
        .accessibilityLabel(tr("添加 App"))
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
    /// 锁定扩展栏：拖动时只抖一下，不离开分组；右键移除变灰。
    var locked = false
    var open: () -> Void
    var remove: () -> Void

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
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: side + 8)
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
        .onTapGesture(perform: open)
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named(GroupSheet.space))
                .onChanged { value in
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
            Button("从分组中移除") { remove() }
                .disabled(!ShelfLock.allows(.remove, locked: locked))
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(name)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = item.fileRef?.resolve() {
            Image(nsImage: AppCatalog.shared.icon(for: url)).resizable().interpolation(.high)
        } else if case .app(_, let bundleID, _) = item,
                  let image = AppCatalog.shared.icon(forBundleID: bundleID) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.3))
        }
    }

    private var name: String {
        if let url = item.fileRef?.resolve() {
            return url.deletingPathExtension().lastPathComponent
        }
        if case .link(_, _, let title) = item { return title }
        return tr("项目")
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
