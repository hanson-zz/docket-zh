import AppKit
import SwiftUI

/// The menu bar item: the app's only persistent UI.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let app: AppState
    var onShelfSettingsChanged: (() -> Void)?

    init(app: AppState) {
        self.app = app
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()
    }

    func refreshButton() {
        // The toggle was read by nothing: the status item was always created
        // and always shown. Honoured now, but never to the point of leaving
        // the app unreachable - see `canHideStatusItem`.
        statusItem.isVisible = app.state.menuBar.showIcon || !canHideStatusItem

        guard let button = statusItem.button else { return }
        // 小熊猫头像剪影，和应用图标的小熊猫对上；资源缺失时退回系统符号。
        let style = app.state.menuBar.iconStyle
        let panda = Bundle.main.image(forResource: style.resourceName)
        panda?.size = NSSize(width: style.pointSize.width, height: style.pointSize.height)
        panda?.accessibilityDescription = tr("码头")
        button.image = panda ?? NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled",
                                        accessibilityDescription: tr("码头"))
        button.image?.isTemplate = true
        button.title = labelText.isEmpty ? "" : " \(labelText)"
    }

    /// Whether there is another way into the app if the icon goes.
    ///
    /// Docket is an accessory app: no Dock tile, no window of its own. With
    /// the shelf on screen its context menu reaches Settings, so hiding the
    /// icon is recoverable. Without a shelf it is the only way in, and hiding
    /// it would strand someone in an app they can see no part of and cannot
    /// quit.
    var canHideStatusItem: Bool { app.state.setup != .macOSDockOnly }

    private var labelText: String {
        let native = app.macOSProfile?.name ?? ""
        let custom = app.customProfile?.name ?? ""
        return switch app.state.menuBar.label {
        case .none: ""
        case .native: native
        case .custom: custom
        case .both: [native, custom].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    // MARK: Menu

    /// Short, and in order of use.
    ///
    /// It used to open on two headed lists, "Custom Dock" and "macOS Dock",
    /// each with its own checkmark and a colour dot, which asked you to know
    /// the model before you could read the menu, and put "Restore Original
    /// Dock", which is rare and rewrites the real Dock, beside everyday
    /// actions. Each kind of layout is now one submenu that names the one in
    /// use, and the Dock's rarer tools live inside its own.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let error = app.lastError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let hasShelf = app.state.setup != .macOSDockOnly
        if hasShelf {
            menu.addItem(layoutMenu(.customDock, title: tr("扩展栏布局")))
        }
        menu.addItem(layoutMenu(.macOSDock, title: tr("系统程序坞布局")))
        if hasShelf, let mode = app.placementMode {
            menu.addItem(positionMenu(current: mode))
        }
        // 紧跟「位置」：锁住的就是位置和排列。扩展栏右键、设置页是同一个设置。
        if hasShelf {
            let lock = item(tr("锁定扩展栏"), #selector(toggleShelfLock))
            lock.state = app.shelfLocked ? .on : .off
            menu.addItem(lock)
        }
        menu.addItem(.separator())

        // Only when there is one. An always-present "you are up to date" line
        // is a permanent reminder of something nobody needs reminding of.
        if let update = UpdateService.shared.available {
            let entry = item(tr("更新到 \(update.version)…"), #selector(openUpdate))
            entry.image = NSImage(systemSymbolName: "arrow.down.circle.fill",
                                  accessibilityDescription: nil)
            menu.addItem(entry)
            menu.addItem(.separator())
        }
        if hasShelf {
            if let hidden = hiddenWidgetsMenu() { menu.addItem(hidden) }
            menu.addItem(item(tr("添加小组件…"), #selector(openLibrary)))
        }
        menu.addItem(item(tr("设置…"), #selector(openSettings), key: ","))
        menu.addItem(item(tr("支持码头…"), #selector(openSponsor)))
        menu.addItem(.separator())
        menu.addItem(item(tr("退出码头"), #selector(quit), key: "q"))
    }

    @objc private func openSponsor() { SponsorWindow.shared.show() }

    @objc private func openUpdate() { UpdateService.shared.openReleasePage() }

    /// Widgets a visibility rule has taken off the shelf. Here as well as on
    /// the shelf's own menu, because a shelf of nothing but hidden widgets
    /// has no tile left to right-click.
    private func hiddenWidgetsMenu() -> NSMenuItem? {
        let hidden = WidgetVisibility.hiddenWidgets(app.customProfile?.items ?? [],
                                                    WidgetConditionMonitor.shared.conditions,
                                                    ignoringConditions: app.showsSampleData)
        guard !hidden.isEmpty else { return nil }
        let parent = NSMenuItem(title: tr("已隐藏的小组件"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for widget in hidden {
            let name = WidgetCatalog.entry(widget.kind)?.name ?? widget.kind.rawValue
            let entry = NSMenuItem(title: "\(name)（\(WidgetVisibility.hiddenReason(widget))）",
                                   action: #selector(restoreWidget(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = widget.id
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func restoreWidget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let widget = app.customProfile?.items.compactMap(\.widget).first(where: { $0.id == id })
        else { return }
        app.updateWidget(WidgetVisibility.restored(widget))
    }

    /// One kind of layout: the parent names the one in use, the submenu
    /// switches between them.
    private func layoutMenu(_ kind: ProfileKind, title: String) -> NSMenuItem {
        let profiles = app.profiles(of: kind)
        let activeID = kind == .customDock ? app.state.customDock.profileID : app.state.macOSDock.profileID
        let active = profiles.first { $0.id == activeID }?.name

        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for profile in profiles {
            let entry = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = profile.id
            entry.state = profile.id == activeID ? .on : .off
            submenu.addItem(entry)
        }
        if !profiles.isEmpty { submenu.addItem(.separator()) }
        if kind == .macOSDock {
            submenu.addItem(item(tr("存储当前程序坞"), #selector(captureDock)))
            if app.state.originalMacOSDock != nil {
                submenu.addItem(item(tr("恢复原始程序坞"), #selector(restoreDock)))
            }
            submenu.addItem(.separator())
        }
        submenu.addItem(item(tr("编辑布局…"), #selector(openLayouts)))
        parent.submenu = submenu

        // The layout in use, greyed at the trailing edge the way a menu shows
        // a current value, so the top level still says what is active.
        if let active {
            let label = NSMutableAttributedString(string: title + "  ")
            label.append(NSAttributedString(string: active, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            parent.attributedTitle = label
        }
        return parent
    }

    /// 扩展栏放在哪：五种方式、固定的八个位置、贴哪条边和重置。和设置页
    /// 改的是同一份设置，当前方式由设置推出来打勾，所以两边永远一致。
    private func positionMenu(current: ShelfPlacementMode) -> NSMenuItem {
        let title = tr("位置")
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let modes: [(String, ShelfPlacementMode)] = [
            (tr("和程序坞并排"), .beside),
            (tr("置顶显示"), .top),
            (tr("替换系统程序坞"), .replace),
            (tr("替换并自动隐藏"), .replaceAutoHide),
            (tr("浮动"), .floating),
        ]
        for (name, mode) in modes {
            let entry = NSMenuItem(title: name, action: #selector(selectPlacement(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = PlacementChoice(mode)
            entry.state = mode == current ? .on : .off
            if mode == .replaceAutoHide {
                entry.toolTip = tr("会让系统程序坞自动隐藏且不再弹出，退出码头时恢复。")
            }
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())

        let pinned = NSMenuItem(title: tr("固定", context: "section"), action: nil, keyEquivalent: "")
        let pins = NSMenu()
        for pin in ShelfPin.allCases {
            let entry = NSMenuItem(title: pin.title, action: #selector(selectPlacement(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = PlacementChoice(.pinned(pin))
            entry.state = current == .pinned(pin) ? .on : .off
            pins.addItem(entry)
        }
        pinned.submenu = pins
        if case .pinned = current { pinned.state = .on }
        submenu.addItem(pinned)
        submenu.addItem(.separator())

        // 只在并排和替换里有意义：置顶、固定、浮动各有各的位置，选一条边就是
        // 回到并排（替换里仍是替换）。
        let edgeItem = NSMenuItem(title: tr("贴哪条边"), action: nil, keyEquivalent: "")
        let edges = NSMenu()
        let edgeMatters = ([.beside, .replace, .replaceAutoHide] as [ShelfPlacementMode]).contains(current)
        for (name, edge) in [(tr("底部"), DockPosition.bottom), (tr("左边"), .left), (tr("右边"), .right)] {
            let entry = NSMenuItem(title: name, action: #selector(selectEdge(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = edge.rawValue
            entry.state = edgeMatters && app.effectivePosition == edge ? .on : .off
            edges.addItem(entry)
        }
        edgeItem.submenu = edges
        submenu.addItem(edgeItem)
        submenu.addItem(item(tr("重置位置"), #selector(resetPlacement)))
        parent.submenu = submenu

        // 和布局菜单一样，当前方式灰字放在右侧；并排、替换再带上边。
        var summary = current.summary
        if edgeMatters { summary += " · " + edgeName(app.effectivePosition) }
        let label = NSMutableAttributedString(string: title + "  ")
        label.append(NSAttributedString(string: summary, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        parent.attributedTitle = label
        return parent
    }

    private func edgeName(_ edge: DockPosition) -> String {
        switch edge {
        case .bottom: tr("底部")
        case .top: tr("顶部")
        case .left: tr("左边")
        case .right: tr("右边")
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let profile = app.state.profile(id) else { return }
        app.select(profile)
        refreshButton()
        onShelfSettingsChanged?()
        if profile.kind == .macOSDock {
            Task { await app.applyMacOSProfile() }
        }
    }

    @objc private func selectPlacement(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PlacementChoice else { return }
        app.applyPlacement(choice.mode)
        onShelfSettingsChanged?()
    }

    @objc private func selectEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let edge = DockPosition(rawValue: raw) else { return }
        app.applyPlacementEdge(edge)
        onShelfSettingsChanged?()
    }

    @objc private func toggleShelfLock() {
        app.setShelfLocked(!app.shelfLocked)
    }

    @objc private func resetPlacement() {
        app.resetPlacement()
        onShelfSettingsChanged?()
    }

    @objc private func restoreDock() {
        Task { await app.restoreOriginalDock() }
    }

    @objc private func captureDock() {
        Task { await app.captureCurrentDock() }
    }

    @objc private func openLayouts() {
        SettingsWindow.shared.show(app: app, tab: "Layouts")
    }

    @objc private func openLibrary() {
        LibraryWindow.shared.show(app: app)
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(app: app)
    }

    @objc private func quit() {
        app.saveNow()
        NSApp.terminate(nil)
    }
}

/// 菜单项的 representedObject 要是对象，方式是带关联值的枚举，包一层。
private final class PlacementChoice: NSObject {
    let mode: ShelfPlacementMode
    init(_ mode: ShelfPlacementMode) { self.mode = mode }
}
