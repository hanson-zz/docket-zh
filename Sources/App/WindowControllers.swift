import AppKit
import SwiftUI

/// A plain window host for a SwiftUI view.
///
/// The shelf lives in a non-activating `NSPanel`, which cannot present sheets
/// - a `.sheet` attached to it silently does nothing. Anything modal-ish
/// therefore needs a real window of its own.
@MainActor
class HostedWindow {
    var window: NSWindow?

    /// - Parameter chromeless: presents a floating rounded panel with no
    ///   system title bar, the way the shipped app's widget browser appears.
    ///   The view must then supply its own header and close control.
    func present(_ view: some View, title: String, size: NSSize,
                 resizable: Bool = false, chromeless: Bool = false) {
        if let window {
            raise(window)
            return
        }

        let corner: CGFloat = 16
        let root: AnyView = chromeless
            ? AnyView(view.clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous)))
            : AnyView(view)

        let controller = NSHostingController(rootView: root)
        let window = EditKeyWindow(contentViewController: controller)
        window.title = title
        window.setContentSize(size)

        if chromeless {
            // Kept `.titled` rather than `.borderless`: a borderless window
            // cannot become key, which would leave the search field dead.
            // The title bar is made invisible instead.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.hasShadow = true
        } else {
            window.styleMask = resizable
                ? [.titled, .closable, .miniaturizable, .resizable]
                : [.titled, .closable, .miniaturizable]
        }

        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        raise(window)
    }

    /// Brings a window to the front from an accessory app.
    ///
    /// `LSUIElement` apps are never "active" in the usual sense, so
    /// `makeKeyAndOrderFront` plus `activate()` quietly opens the window
    /// *behind* whatever the user is looking at - it exists, it is just
    /// invisible. `orderFrontRegardless` is the call that actually raises it,
    /// and a floating level keeps it from sinking again on the next click.
    ///
    /// 排到最前还不够：App 没激活时窗口是 key 也显示成非激活的灰色（红绿灯、标题、
    /// 侧边栏选中项、开关都发灰）。激活交给 `AccessoryActivation`，它会一步步升级，
    /// 见 Core 的 `WindowActivationPlan`。
    private func raise(_ window: NSWindow) {
        window.level = .floating
        AccessoryActivation.shared.bringForward(window)
    }

    func close() {
        window?.close()
        window = nil
    }
}

/// 设置、小组件库这类普通窗口：码头没有「编辑」菜单，搜索框、API 密钥框里的
/// ⌘A ⌘C ⌘X ⌘V ⌘Z ⌘⇧Z 由窗口自己派给输入框，见 `EditKeyRouting`。
final class EditKeyWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        EditKeyRouting.perform(event, in: self) { super.performKeyEquivalent(with: event) }
    }

    /// 点到窗口时 App 还没激活（之前的激活请求被系统忽略，或者键盘一直在码头的
    /// 非激活面板手里，点普通窗口只是在 App 里换了 key）：借这次点击再激活一次。
    /// 这是用户自己的点击，协作式激活这时最容易被系统放行。
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if WindowActivationPlan.activateOnClick(isActive: NSApp.isActive) {
                AccessoryActivation.shared.bringForward(self, fromClick: true)
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// 把码头（accessory App）连同一个普通窗口一起带到前台，让窗口显示正常的激活外观。
///
/// 步骤见 Core 的 `WindowActivationPlan`：先 `NSApp.activate()` 请求；过一会儿还没激活
/// 就 `activate(ignoringOtherApps:)`；还不成就临时切成 `.regular` 再激活（这时程序坞
/// 里会出现码头的图标），等这类普通窗口全关了再切回 `.accessory`。激活成功后再把
/// 窗口设为 key 一次：激活时系统可能把 key 还给上次那个面板。
@MainActor
final class AccessoryActivation {
    static let shared = AccessoryActivation()

    /// 打开着的普通窗口。全关了才把临时的 `.regular` 切回去。
    private var openWindows: Set<ObjectIdentifier> = []
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    /// 这次是自己临时切成 `.regular` 的，切回时只切这一种。
    private var promoted = false
    /// 正在走的那一轮，新一轮开始时旧的作废。
    private var generation = 0
    private weak var target: NSWindow?
    /// 激活回来时补设 key 只管刚带到前台的这一小会儿；之后别的面板激活码头时不去抢它的 key。
    private var settleUntil = Date.distantPast
    private var activeObserver: NSObjectProtocol?

    private init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AccessoryActivation.shared.becameActive() }
        }
    }

    func bringForward(_ window: NSWindow, fromClick: Bool = false) {
        track(window)
        target = window
        generation += 1
        settleUntil = Date().addingTimeInterval(1.5)
        if !fromClick {
            window.orderFrontRegardless()
        }
        window.makeKeyAndOrderFront(nil)
        step(attempt: 0, generation: generation)
    }

    private func step(attempt: Int, generation: Int) {
        guard generation == self.generation, let window = target, window.isVisible,
              let step = WindowActivationPlan.step(attempt: attempt, isActive: NSApp.isActive) else { return }
        switch step {
        case .request:
            NSApp.activate()
        case .force:
            NSApp.activate(ignoringOtherApps: true)
        case .promote:
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                promoted = true
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        let wait = WindowActivationPlan.wait(after: step)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            MainActor.assumeIsolated {
                AccessoryActivation.shared.step(attempt: attempt + 1, generation: generation)
            }
        }
    }

    /// 激活成功：系统可能把 key 还给了激活前的那个窗口（扩展栏弹出的面板），
    /// 刚要带到前台的普通窗口还开着就再设一次 key。
    private func becameActive() {
        guard Date() < settleUntil else { return }
        settleUntil = .distantPast
        guard let window = target, window.isVisible, !window.isKeyWindow else { return }
        window.makeKeyAndOrderFront(nil)
    }

    private func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        openWindows.insert(id)
        guard closeObservers[id] == nil else { return }
        closeObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AccessoryActivation.shared.closed(id) }
        }
    }

    private func closed(_ id: ObjectIdentifier) {
        openWindows.remove(id)
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        guard WindowActivationPlan.shouldRestoreAccessory(promoted: promoted, openWindows: openWindows.count) else { return }
        promoted = false
        // 关窗这一拍里切回，系统可能还没把 key 交出去；下一拍再切。
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let me = AccessoryActivation.shared
                guard !me.promoted, me.openWindows.isEmpty else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// 码头自己的普通窗口（设置、小组件库…）此刻是不是 key。浮动面板悬停时看这个，
    /// 免得指针路过就把设置窗口的 key 抢走。
    var regularWindowIsKey: Bool {
        guard let key = NSApp.keyWindow else { return false }
        return key is EditKeyWindow
    }
}

@MainActor
final class LibraryWindow: HostedWindow {
    static let shared = LibraryWindow()
    var openFromEmptyState: @MainActor () -> Void = {}

    /// Whether the library is up. The shelf stays out while it is: adding a
    /// widget is done by looking at the shelf it lands on, and an auto-hidden
    /// shelf slid away the moment the pointer went to the library to pick
    /// one, so every addition happened somewhere out of sight.
    var isOpen: Bool { window?.isVisible == true }

    func show(app: AppState) {
        present(
            WidgetLibraryView(
                onAdd: { [weak self] widget in
                    withAnimation(.snappy(duration: 0.25)) { app.addItem(.widget(widget)) }
                    // Adding is a repeated action - people add three widgets at
                    // a time - so the library stays open, like Shortcuts' own.
                    _ = self
                },
                onAddItem: { item in
                    withAnimation(.snappy(duration: 0.25)) { app.addItem(item) }
                },
                onAddGroup: {
                    let made = withAnimation(.snappy(duration: 0.25)) {
                        app.addEmptyGroup(named: tr("分组"))
                    }
                    guard let id = made else { return }
                    // 等新格子长出来、扩展栏按新内容排好，再从它那里打开组窗口。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: GroupWindow.openRequest, object: nil,
                                                        userInfo: ["id": id.uuidString])
                    }
                },
                onAddFolderGroup: {
                    let made = withAnimation(.snappy(duration: 0.25)) {
                        app.addEmptyFolderGroup(named: tr("文件夹分组"))
                    }
                    guard let id = made else { return }
                    // 同应用分组：格子长出来以后从它那里打开（扩展栏按组的种类开文件夹小窗）。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: GroupWindow.openRequest, object: nil,
                                                        userInfo: ["id": id.uuidString])
                    }
                },
                placed: { app.effectiveItems.compactMap(\.widget) },
                onRemove: { id in
                    withAnimation(.snappy(duration: 0.25)) { app.removeItem(id) }
                },
                onClose: { [weak self] in self?.close() }
            ),
            title: tr("添加小组件"),
            size: NSSize(width: 760, height: 470),
            chromeless: true
        )
    }
}

@MainActor
final class SettingsWindow: HostedWindow {
    static let shared = SettingsWindow()

    func show(app: AppState, tab: String = "Shelf") {
        // Set before presenting, so a window that is only being raised still
        // lands on the tab the caller asked for.
        SettingsSelection.shared.current = tab
        @Bindable var bindable = app
        present(
            SettingsView(
                state: $bindable.state,
                initialTab: tab,
                onApplyMacOSProfile: { Task { await app.applyMacOSProfile() } },
                onCaptureCurrentDock: { Task { await app.captureCurrentDock() } },
                onSetScale: { app.setScale($0) },
                onResumeFollowingScale: { app.resumeFollowingScale() },
                onResumeMirroringApps: { app.resumeMirroringApps() },
                onBackUp: { Self.backUp(app) },
                onRestore: { Self.restore(app) },
                onCreateProfile: { kind in
                    app.createProfile(kind: kind,
                                      named: kind == .customDock ? tr("新扩展栏") : tr("新程序坞"))
                },
                onRenameProfile: { app.renameProfile($0, to: $1) },
                onDuplicateProfile: { if let id = $0 { app.duplicateProfile(id) } },
                onDeleteProfile: { if let id = $0 { app.deleteProfile(id) } },
                lastError: app.lastError,
                onClearError: { app.clearError() },
                onRestoreOriginalDock: { Task { await app.restoreOriginalDock() } },
                onShowOnboarding: { OnboardingWindow.shared.show(app: app) },
                onAddWidget: { app.addItem(.widget($0)) }
            ),
            title: tr("码头设置"),
            // Taller and resizable, because the Widgets tab is not a fixed
            // form: it grows by one section per widget on the shelf. At the
            // old fixed 520x460 a shelf with four widgets showed two of them
            // and scrolled the rest inside a box nobody could enlarge.
            // Wide enough for a sidebar and a form beside it without the
            // form's controls crowding their labels.
            size: NSSize(width: 720, height: 600),
            resizable: true
        )
    }

    // MARK: Backup

    /// Writes the profiles to a file the user picks.
    ///
    /// The panel is AppKit's rather than SwiftUI's `fileExporter`, because an
    /// accessory app has no window for a sheet to attach to: a modal panel is
    /// the only kind that reliably comes forward here.
    private static func backUp(_ app: AppState) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Backup.suggestedName()
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        panel.message = tr("保存你的布局、其中的项目以及小组件设置。")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Backup.encode(app.state).write(to: url, options: .atomic)
        } catch {
            report(tr("无法保存备份。"), error)
        }
    }

    /// Reads a backup and merges it in.
    private static func restore(_ app: AppState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = tr("选择一个码头布局备份文件。")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let payload = try Backup.decode(Data(contentsOf: url))
            var state = app.state
            let before = state.profiles.count
            Backup.merge(payload, into: &state)
            app.state = state

            let added = state.profiles.count - before
            let updated = payload.profiles.count - added
            let alert = NSAlert()
            alert.messageText = tr("已恢复 \(payload.profiles.count) 个布局。")
            // Says what it did rather than just that it worked: a merge that
            // replaced something should not look identical to one that only
            // added.
            alert.informativeText = updated > 0
                ? tr("从备份中新增 \(added) 个，替换 \(updated) 个。")
                : tr("新增 \(added) 个。")
            alert.runModal()
        } catch {
            report(tr("无法读取该备份。"), error)
        }
    }

    private static func report(_ message: String, _ error: any Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
