import AppKit
import SwiftUI
import Observation

/// Which Settings tab is showing.
///
/// Outside the view because the window is reused: raising an existing one
/// runs no `onAppear`, so a view holding this in `@State` could never be told
/// to go anywhere.
@MainActor @Observable
final class SettingsSelection {
    static let shared = SettingsSelection()
    var current = "Shelf"
    private init() {}
}

/// Docket's Settings window.
///
/// It owns no state: the app passes a binding to the single `PersistedState`
/// it already persists, so every edit here is saved by the same code path that
/// saves everything else.
struct SettingsView: View {
    @Binding var state: PersistedState
    /// Which tab opens first. The menu bar and the Dock's own menu both land
    /// on Shelf; a caller with something specific to show can say so.
    var initialTab: String = "Shelf"
    var onApplyMacOSProfile: () -> Void
    var onCaptureCurrentDock: () -> Void
    /// Sizing the shelf goes through `AppState.setScale`, which also writes
    /// the active profile and records that the size is now the user's. The
    /// slider used to bind straight to the stored value and do neither.
    var onSetScale: (Double) -> Void
    /// Undoing that, and the same for the app list. Both overrides used to be
    /// one directional, with nothing in the app able to clear them.
    var onResumeFollowingScale: () -> Void
    var onResumeMirroringApps: () -> Void
    /// Both present a file panel, which is AppKit's job rather than a view's.
    var onBackUp: () -> Void
    var onRestore: () -> Void
    /// Profile management. Through closures for the same reason as the rest:
    /// this view owns no state and every one of these has to reach AppState,
    /// which also decides what is allowed.
    var onCreateProfile: (ProfileKind) -> Void
    var onRenameProfile: (UUID, String) -> Void
    var onDuplicateProfile: (UUID?) -> Void
    var onDeleteProfile: (UUID?) -> Void
    /// The last Dock-apply failure, and a way to be rid of it. Read rather
    /// than bound because it belongs to AppState and this view holds only the
    /// persisted state.
    var lastError: String?
    var onClearError: () -> Void
    /// Puts Apple's Dock back the way it was before Docket first wrote to it.
    /// Only offered once there is something to go back to.
    var onRestoreOriginalDock: () -> Void

    /// Which tab is showing, held outside the view.
    ///
    /// It was `@State` set from `initialTab` in `onAppear`, and `onAppear`
    /// does not fire again for a window that is merely being raised. So
    /// "Widget Settings…" opened the Widgets tab exactly once, and every time
    /// after that raised whatever tab was last looked at while claiming to go
    /// somewhere specific.
    @State private var selection = SettingsSelection.shared

    /// The size the shelf is actually drawn at, which is the Dock's while
    /// following and the stored one once overridden. Showing the stored value
    /// unconditionally meant the readout disagreed with the shelf.
    private var shownScale: Double {
        DockFollowing.scale(overridden: state.customDock.scaleOverridden == true,
                            custom: state.customDock.scale,
                            system: SystemDockSettings.shared.matchedScale,
                            following: state.customDock.followSystemDock)
    }

    /// Both overrides only mean anything while following: with following off,
    /// the shelf's size and app list are the user's by definition and there is
    /// nothing to hand back.
    private var scaleOverridden: Bool {
        state.customDock.followSystemDock && state.customDock.scaleOverridden == true
    }

    private var adoptedApps: Bool {
        state.customDock.followSystemDock && state.customDock.mirrorSystemApps == false
    }


    /// The sections, in the order the sidebar lists them.
    ///
    /// Ordered by how often each is wanted. The shelf is what people come
    /// here to change; General, which used to open first, held the setup and
    /// the profiles, the two least general things in the app, under a name
    /// that promised neither. Plain glyphs rather than tinted tiles: four
    /// rows need no colour to be told apart, and the tiles made a small
    /// window read as a phone's settings screen.
    private static let sections: [(id: String, title: String, symbol: String)] = [
        ("Shelf", "扩展栏", "rectangle.bottomthird.inset.filled"),
        ("Widgets", "小组件", "square.grid.2x2"),
        ("Layouts", "布局", "square.stack.3d.up"),
        ("General", "通用", "gearshape"),
    ]

    var body: some View {
        // A sidebar rather than a segmented strip along the top: a strip
        // says nothing about where you are in a scroll, and it cannot grow.
        NavigationSplitView {
            List(selection: Binding(
                get: { selection.current },
                set: { selection.current = $0 ?? "Shelf" })) {
                ForEach(Array(Self.sections.enumerated()), id: \.element.id) { index, section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section.id)
                        .staggered(index, step: 0.05)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 200)
        } detail: {
            pane
                // Opens at the top. The Shelf pane landed scrolled past its
                // own setup cards, onto whichever control took focus.
                .defaultScrollAnchor(.top)
                // Keyed on the section, so switching sections replays the
                // stagger instead of swapping a finished pane for another
                // finished pane.
                .id(selection.current)
                .navigationTitle(Self.sections.first { $0.id == selection.current }?.title ?? "设置")
        }
        // A minimum rather than a fixed size: the window is resizable, and a
        // hard frame here would win against it.
        .frame(minWidth: 640, minHeight: 440)
        .onAppear { selection.current = initialTab }
    }

    @ViewBuilder private var pane: some View {
        switch selection.current {
        case "Widgets": widgets
        case "Layouts": layouts
        case "General": general
        default: shelf
        }
    }

    // MARK: - Shelf

    /// The setup first, as three pictures rather than three paragraphs: which
    /// Dock is on screen is a spatial question, and a sketch of the screen
    /// answers it before the caption is read. With no shelf, nothing below
    /// it applies, so nothing below it is shown.
    private var shelf: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(DockSetup.allCases, id: \.self) { setup in
                        ChoiceCard(title: title(setup), caption: detail(setup),
                                   selected: state.setup == setup) {
                            withAnimation(.smooth(duration: 0.2)) { state.setup = setup }
                        } picture: {
                            SetupSketch(setup: setup).frame(height: 58)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if state.setup == .macOSDockOnly {
                Section {
                    Text("扩展栏已关闭。系统程序坞的布局位于“布局”中。")
                        .foregroundStyle(.secondary)
                }
            } else {
                shelfSections
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Layouts

    /// Every saved layout, for both Docks, as lists you act on in place.
    ///
    /// These were a picker, a name field and a row of buttons per kind, which
    /// is the model's API drawn as a form: you had to pick a layout in one
    /// control to rename it in a second and delete it with a third. Now each
    /// layout is a row: click to use it, type to rename it, and its menu does
    /// the rest.
    private var layouts: some View {
        Form {
            layoutList(.customDock, title: "扩展栏",
                       selection: $state.customDock.profileID, allowsNone: false)
                .disabled(state.setup == .macOSDockOnly)

            layoutList(.macOSDock, title: "系统程序坞",
                       selection: $state.macOSDock.profileID, allowsNone: true)

            Section {
                HStack {
                    Button("应用到程序坞", action: onApplyMacOSProfile)
                        .disabled(state.activeMacOSProfile == nil)
                        .help("将所选布局写入系统程序坞。")
                    Button("存储当前程序坞", action: onCaptureCurrentDock)
                        .help("将系统程序坞的当前状态存储为新布局。")
                    Spacer()
                    if state.originalMacOSDock != nil {
                        Button("恢复原始状态", action: onRestoreOriginalDock)
                            .help("将系统程序坞恢复到码头首次修改之前的样子。")
                    }
                }

                // In the window holding the button that caused it, so pressing
                // Apply and having nothing happen does not look like a broken
                // button, and dismissable, so it does not describe something
                // that happened once for ever.
                if let failure = lastError {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(failure)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("忽略", action: onClearError)
                            .buttonStyle(.link)
                    }
                }
            }

            switching

            Section {
                HStack {
                    Button("备份…", action: onBackUp)
                        .disabled(state.profiles.isEmpty)
                    Button("恢复…", action: onRestore)
                }
            } header: {
                Text("备份")
            } footer: {
                Text("备份包含你的布局、其中的项目以及小组件设置，但不包含它们指向的应用或文件。恢复时会添加到现有内容中，而不是替换现有内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// The three ways to change layout without opening the menu.
    ///
    /// The Focus part is a paragraph rather than a control because there is
    /// nothing to set here: macOS keeps a Focus filter's choices in System
    /// Settings, and this is the only place that can say so.
    private var switching: some View {
        Section {
            Toggle(isOn: $state.customDock.switchLayoutsByGesture) {
                subtitled("在扩展栏上用 ⌘ + 滚轮或双指左右轻扫切换布局",
                          "指针位于扩展栏上时生效，在扩展栏布局之间循环切换。扩展栏内容超出屏幕时，左右轻扫仍用于滚动扩展栏。")
            }
            .disabled(state.setup == .macOSDockOnly)

            VStack(alignment: .leading, spacing: 6) {
                Text("快捷键：点按布局右侧的按钮，然后按下组合键。组合键须包含 ⌃、⌥ 或 ⌘ 之一；按 Esc 取消，按删除键清除。")
                Text("专注模式：打开“系统设置 ▸ 专注模式”，选择一个专注模式，在“专注模式过滤条件”中点按“添加过滤条件”，选择码头并挑选一个布局。该专注模式开启时会切换到这个布局，结束时恢复之前的布局。")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("切换布局")
        }
    }

    @ViewBuilder
    private func layoutList(_ kind: ProfileKind, title: String,
                            selection: Binding<UUID?>, allowsNone: Bool) -> some View {
        let mine = state.profiles(of: kind)
        Section {
            // "None" is the documented "leave the live Dock completely alone"
            // state, which has to stay reachable after the first capture.
            if allowsNone {
                LayoutRow(name: .constant("无"), editable: false,
                          active: selection.wrappedValue == nil,
                          onUse: { selection.wrappedValue = nil }) { EmptyView() }
            }
            ForEach(mine) { profile in
                LayoutRow(
                    name: Binding(get: { profile.name },
                                  set: { onRenameProfile(profile.id, $0) }),
                    editable: true,
                    active: selection.wrappedValue == profile.id,
                    onUse: { selection.wrappedValue = profile.id },
                    onDuplicate: { onDuplicateProfile(profile.id) },
                    // The shelf has to point at something: deleting its last
                    // layout would leave it empty with no way back.
                    onDelete: kind == .customDock && mine.count <= 1
                        ? nil : { onDeleteProfile(profile.id) }) {
                    strip(profile.items)
                    ShortcutRecorder(combo: profile.shortcut) { combo in
                        state.assignShortcut(combo, to: profile.id)
                    }
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button {
                    onCreateProfile(kind)
                } label: {
                    Label("新建布局", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    /// The first few things in a layout, as their icons: two layouts with
    /// similar names are told apart at a glance by what is in them.
    private func strip(_ items: [DockItem]) -> some View {
        HStack(spacing: 3) {
            ForEach(items.prefix(7)) { item in
                icon(for: item).frame(width: 18, height: 18)
            }
            if items.count > 7 {
                Text("+\(items.count - 7)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        ChoiceCard(title: title(option), selected: state.appearance == option) {
                            state.appearance = option
                        } picture: {
                            AppearanceSketch(appearance: option).frame(height: 52)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Section("菜单栏") {
                // Refused when there is no shelf, because the icon is then the
                // only way into an app with no Dock tile and no window of its
                // own. Disabled and explained rather than accepted and ignored.
                Toggle("显示菜单栏图标", isOn: $state.menuBar.showIcon)
                    .disabled(state.setup == .macOSDockOnly)
                    .help(state.setup == .macOSDockOnly
                          ? "屏幕上没有扩展栏时，这是访问码头的唯一途径。"
                          : "关闭此项后，仍可通过扩展栏自身的菜单打开设置。")
                Picker("在旁边显示", selection: $state.menuBar.label) {
                    ForEach(MenuBarLabelMode.allCases, id: \.self) { Text(title($0)).tag($0) }
                }
            }

            islandSection

            Section("更新") {
                // The consent alert promises this control exists, so it does.
                // Binding through a default of false means a state file that
                // predates the question reads as off rather than as answered.
                Toggle("检查新版本", isOn: Binding(
                    get: { state.checkForUpdates == true },
                    set: { state.checkForUpdates = $0 }))
                    .help("码头每天向 GitHub 查询一次最新版本号，如果有更新版本，会在菜单栏项中提示你。不会自动安装任何内容，也不会发送其他任何信息。")
            }

            // About, folded in. A whole section in the sidebar for an icon and
            // a version number was a fifth place to look for four things.
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("码头 \(shortVersion)")
                            .font(.headline)
                            .monospacedDigit()
                        Text("所有数据都保存在这台 Mac 上 Application Support 中的一个文件里，不会同步。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }

            SupportSections()
        }
        .formStyle(.grouped)
    }

    /// 灵动提示. All off by default; each source starts only when its switch
    /// is on, and the capsule window exists only while something is shown.
    private var islandSection: some View {
        Section {
            Toggle("音量提示", isOn: $state.island.volume)
                .help("调节系统音量或静音时，在屏幕顶部中央显示当前音量。")
            Toggle("亮度提示", isOn: $state.island.brightness)
                .disabled(!brightnessAvailable && !state.island.brightness)
                .help(brightnessAvailable
                      ? "调节内建显示器亮度时，在屏幕顶部中央显示当前亮度。"
                      : "这台 Mac 没有可读取亮度的内建显示器。")
            Toggle("会议倒计时", isOn: $state.island.meeting)
                .help("日程开始前，在屏幕顶部中央显示“X 分钟后：日程标题”。需要日历权限。")
            if state.island.meeting {
                Picker("提前显示", selection: Binding(
                    get: { state.island.leadMinutes },
                    set: { state.island.meetingMinutes = $0 })) {
                    ForEach(IslandSettings.minuteChoices, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
            }
        } header: {
            Text("灵动提示")
        } footer: {
            Text("在屏幕顶部中央（刘海下方）短暂显示一个小胶囊。只读取音量、亮度和日程，不拦截按键，系统自带的音量和亮度提示照常出现。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var brightnessAvailable: Bool { DisplayBrightness.isAvailable }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    // MARK: - Shelf settings

    /// Everything about the shelf itself, shown under the setup cards while
    /// there is a shelf to set up.
    ///
    /// Four groups, each one idea: where it sits, how it looks, how it
    /// behaves, and what is on it. It was six, with a toggle, a "Currently"
    /// row and a footnote all spent on following the Dock, and two controls
    /// spent on one choice of material.
    @ViewBuilder private var shelfSections: some View {
        Section {
            Toggle(isOn: $state.customDock.followSystemDock) {
                // What is being inherited, under the switch that inherits it,
                // rather than in a row and a footnote of its own.
                subtitled("与系统程序坞保持一致", state.customDock.followSystemDock
                          ? SystemDockSettings.shared.summary
                          : "自行设置扩展栏的位置和大小。")
            }

            // Hidden while the Dock dictates them, not greyed: following is
            // the default, so greyed controls here were permanently dead for
            // anyone who never turned it off.
            if !state.customDock.followSystemDock {
                HStack(spacing: 10) {
                    ForEach(DockPosition.allCases, id: \.self) { edge in
                        ChoiceCard(title: title(edge), selected: state.customDock.position == edge) {
                            state.customDock.position = edge
                        } picture: {
                            EdgeSketch(edge: edge).frame(height: 44)
                        }
                    }
                }
                .padding(.vertical, 2)

                Picker("显示器", selection: $state.customDock.displayID) {
                    Text("指针所在的显示器").tag(UInt32?.none)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = screen.docketDisplayID {
                            Text(screen.localizedName).tag(UInt32?.some(id))
                        }
                    }
                }

                LabeledContent("大小") {
                    HStack {
                        // Through setScale, not around it. Binding straight to
                        // the stored value skipped the override flag and never
                        // wrote the profile, so the size silently reverted.
                        Slider(value: Binding(get: { shownScale }, set: onSetScale),
                               in: Geometry.scaleRange)
                        Text("\(Int((shownScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            // The way back from sizing the shelf with its grip while
            // following, which used to set an override nothing could clear.
            if scaleOverridden {
                LabeledContent {
                    Button("保持一致", action: onResumeFollowingScale)
                } label: {
                    subtitled("大小", "已手动设置。其他设置仍跟随程序坞。")
                }
            }
        }

        Section("外观") {
            // One choice, not a material and then a style of that material:
            // these are what anyone is actually choosing between. Drawn in
            // the real materials over a scrap of wallpaper, because the
            // difference between them is only visible over something.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(ShelfLook.ordered, id: \.self) { option in
                    ChoiceCard(title: option.title, selected: look.wrappedValue == option) {
                        look.wrappedValue = option
                    } picture: {
                        MaterialSample(look: option).frame(height: 44)
                    }
                }
            }
            .padding(.vertical, 2)
            .help("“透明”不绘制底板，每个小组件保留自己的卡片。")

            SupporterColorPicker(selection: $state.customDock.shelfColor)

            Picker(selection: $state.customDock.widgetColor) {
                Text("原色").tag(WidgetColorMode.original)
                Text("单色").tag(WidgetColorMode.monochrome)
            } label: {
                subtitled("小组件颜色", "单色只把扩展栏上的小组件画成灰阶，应用图标不受影响。")
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $state.customDock.reduceTransparency) {
                subtitled("降低透明度",
                          "使用不透明的底板。系统设置 ▸ 辅助功能 ▸ 显示 中开启“降低透明度”时会自动生效。")
            }

            if !state.customDock.followSystemDock {
                Toggle("放大指针下方的项目", isOn: $state.customDock.magnification)
            }
        }

        Section("行为") {
            Picker(selection: $state.customDock.overflow) {
                Text("横向滚动").tag(ShelfOverflow.scroll)
                Text("自动缩小").tag(ShelfOverflow.shrink)
            } label: {
                subtitled("放不下时",
                          "自动缩小会把扩展栏整体缩小到能放下为止，最小为所选大小的一半；仍放不下时再滚动。")
            }
            .pickerStyle(.segmented)

            // While following, hiding comes from the Dock's own setting.
            if !state.customDock.followSystemDock {
                Toggle("隐藏，直到指针移到屏幕边缘", isOn: $state.customDock.autoHide)
            }
            // Only means anything while something is hiding.
            if state.customDock.followSystemDock || state.customDock.autoHide {
                Toggle(isOn: $state.customDock.showHandleWhenHidden) {
                    subtitled("隐藏时保留一条细边", "便于看到它的位置。")
                }
            }
            LabeledContent {
                HStack {
                    Slider(value: $state.customDock.edgeGap, in: 0...40, step: 1)
                    Text("\(Int(state.customDock.edgeGap.rounded())) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            } label: {
                subtitled("距屏幕边缘", "扩展栏与所在屏幕边缘之间的距离，设为 0 即贴边。")
            }
            Toggle(isOn: $state.customDock.reserveSystemDockSpace) {
                subtitled("为系统程序坞留出空间",
                          "系统程序坞与扩展栏在同一边缘时，把扩展栏抬到程序坞之外。关闭后扩展栏会贴边并盖在系统程序坞上方。")
            }
            Toggle(isOn: $state.customDock.hideWhenMacOSDockAppears) {
                subtitled("为系统程序坞让位",
                          "两者位于同一边缘时，移向其中一个会让另一个显露出来。")
            }
            Toggle(isOn: $state.customDock.useAsDesktopWidget) {
                subtitled("置于窗口之后", "像桌面小组件一样停留在桌面上。")
            }
        }

        soundSection

        itemList
    }

    /// 添加和移除小组件时的音效. The style and volume only show while the
    /// switch is on; 试听 plays both sounds whatever the switch says.
    private var soundSection: some View {
        Section {
            Toggle(isOn: $state.widgetSounds.enabled) {
                subtitled("添加和移除小组件时播放音效",
                          "添加时一声轻响，移除时像程序坞一样“噗”一声。系统设置里关闭了“播放用户界面音效”时不会播放。")
            }
            if state.widgetSounds.enabled {
                Picker("音效风格", selection: $state.widgetSounds.style) {
                    ForEach(WidgetSoundStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("“码头”是码头自带的合成音效；“系统”使用这台 Mac 的程序坞音效，没有时改用系统提示音。")
                LabeledContent("音量") {
                    HStack {
                        Slider(value: $state.widgetSounds.volume, in: 0...1)
                        Text("\(Int((state.widgetSounds.volume * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            LabeledContent("添加和移除的声音") {
                Button("试听") {
                    WidgetSoundEffects.shared.preview(settings: state.widgetSounds)
                }
            }
        } header: {
            Text("音效")
        }
    }

    /// A control's label with one line of explanation under it, the way
    /// System Settings does it, in place of a tooltip nobody hovers for.
    private func subtitled(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var look: Binding<ShelfLook> {
        Binding(
            get: { ShelfLook(state.customDock) },
            set: { $0.apply(to: &state.customDock) })
    }

    // MARK: - Widgets

    /// Whether any widget on the active shelf is a Focus Timer.
    private var hasFocusTimer: Bool {
        guard let id = state.customDock.profileID,
              let profile = state.profiles.first(where: { $0.id == id })
        else { return false }
        return profile.items.contains { $0.widget?.kind == .timer }
    }

    /// A minute count that shows the number it is set to.
    private func minutes(_ title: String, _ value: Binding<Int>,
                         in range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title) { Text("\(value.wrappedValue) 分钟") }
        }
    }

    /// What is actually on the shelf, in order.
    ///
    /// Everything about the shelf's contents used to be a toggle: whether to
    /// show running apps, whether to mirror the Dock's. The list itself was
    /// only visible on the shelf, and only editable by dragging on it, so
    /// there was no way to see what was pinned without going and looking, and
    /// no way to remove something you could not reach.
    ///
    /// Reordering stays on the shelf, where dragging is the obvious gesture
    /// and already works. This is for seeing the list and taking things off
    /// it.
    @ViewBuilder private var itemList: some View {
        let items = activeItems
        Section {
            // What the shelf holds, beside the list of what it holds.
            Toggle("仅小组件", isOn: $state.customDock.widgetsOnly)
            // Both add apps, so neither is a question a widgets-only shelf
            // is asking.
            if !state.customDock.widgetsOnly {
                Toggle("显示正在运行的应用", isOn: $state.customDock.showRunningApps)
                Toggle("显示废纸篓", isOn: $state.customDock.showTrash)
                if state.customDock.showTrash {
                    Toggle("废纸篓图标上显示苍蝇", isOn: $state.customDock.showTrashFlies)
                    if state.customDock.showTrashFlies {
                        Picker("苍蝇出现的大小", selection: $state.customDock.trashFliesThreshold) {
                            ForEach(TrashFlies.thresholds.indices, id: \.self) { index in
                                Text(TrashFlies.thresholds[index].label)
                                    .tag(TrashFlies.thresholds[index].value)
                            }
                        }
                    }
                }
            }
            // Rearranging a mirrored app takes the list over, which is right,
            // but there has to be a way to give it back.
            if adoptedApps {
                LabeledContent {
                    Button("重新同步", action: onResumeMirroringApps)
                } label: {
                    subtitled("应用", "使用你自己的排序，不再跟随程序坞的变化。")
                }
            }

            if items.isEmpty {
                Label("扩展栏上还没有任何项目。", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 9) {
                        icon(for: item)
                            .frame(width: 20, height: 20)
                        Text(item.displayName)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.kindName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            remove(item.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("从扩展栏移除")
                    }
                    .staggered(index)
                }
            }
        } header: {
            Text("扩展栏上的项目")
        } footer: {
            Text("在扩展栏上直接拖动即可重新排序，点按末端的 + 可添加项目。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func icon(for item: DockItem) -> some View {
        if let image = item.listIcon {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Image(systemName: item.listSymbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var activeProfileIndex: Int? {
        guard let id = state.customDock.profileID else { return nil }
        return state.profiles.firstIndex { $0.id == id }
    }

    private var activeItems: [DockItem] {
        guard let index = activeProfileIndex else { return [] }
        return state.profiles[index].items
    }

    private func remove(_ id: UUID) {
        guard let index = activeProfileIndex else { return }
        let before = state.profiles[index].items
        withAnimation(.smooth(duration: 0.22)) {
            state.profiles[index].items.removeAll { $0.id == id }
        }
        WidgetSoundEffects.shared.shelfChanged(from: before, to: state.profiles[index].items,
                                               settings: state.widgetSounds)
    }

    private var widgets: some View {
        Form {
            WidgetSettingsSections(state: $state)

            // Only when there is one to configure. These are settings for a
            // widget, and showing them to somebody whose shelf has no Focus
            // Timer on it is the same noise as any other control that does
            // nothing.
            if hasFocusTimer {
                Section {
                    // Every one of these showed a label and a pair of arrows
                    // and no number, so the only way to find out what the
                    // focus length was set to was to click an arrow and
                    // watch the tile change. A Stepper with a title draws
                    // the title, never the value; the value has to be put
                    // there. Same shape the per-widget number controls use.
                    minutes("专注", $state.timer.work, in: 1...180)
                    minutes("休息", $state.timer.rest, in: 1...60)
                    minutes("长休息", $state.timer.longBreak, in: 1...180)
                    Stepper(value: $state.timer.sessions, in: 1...12) {
                        LabeledContent("长休息前的专注次数") {
                            Text("\(state.timer.sessions)")
                        }
                    }
                    LabeledContent("颜色") { swatches }
                    Toggle("提醒", isOn: $state.timer.alerts)
                        .help("专注或休息结束时发出通知。")
                } header: {
                    Text("专注计时")
                } footer: {
                    Text("所有专注计时小组件共用这些设置，码头将它们视为同一个计时器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var swatches: some View {
        HStack(spacing: 10) {
            ForEach(PaletteColor.picker, id: \.self) { colour in
                Button {
                    state.timer.color = colour
                } label: {
                    Circle()
                        .fill(Color(hex: colour.hex))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(state.timer.color == colour ? 0.7 : 0), lineWidth: 2)
                                .padding(-3)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(docketColourName(colour.rawValue))
            }
        }
    }
}

// MARK: - Labels

private func title(_ value: AppAppearance) -> String {
    switch value {
    case .system: "跟随系统"
    case .light: "浅色"
    case .dark: "深色"
    }
}

private func title(_ value: DockSetup) -> String {
    switch value {
    case .macOSDockOnly: "系统程序坞"
    case .both: "程序坞和扩展栏"
    case .customReplacement: "仅扩展栏"
    }
}

private func detail(_ value: DockSetup) -> String {
    switch value {
    case .macOSDockOnly: "只使用系统程序坞，并可切换已存储的布局。"
    case .both: "系统程序坞放应用，另一侧边缘放一条小组件扩展栏。"
    case .customReplacement: "用一条扩展栏同时放应用和小组件，系统程序坞保持隐藏。"
    }
}

private func title(_ value: DockPosition) -> String {
    switch value {
    case .left: "左侧"
    case .bottom: "底部"
    case .right: "右侧"
    }
}

private func title(_ value: MenuBarLabelMode) -> String {
    switch value {
    case .none: "不显示"
    case .native: "系统程序坞布局"
    case .custom: "扩展栏布局"
    case .both: "两种布局"
    }
}

private extension NSScreen {
    /// `CGDirectDisplayID` for this screen, which is what `displayID` stores.
    var docketDisplayID: UInt32? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
    }
}


// MARK: - Pieces

/// A choice shown as a picture of its result, with its name under it.
///
/// Used wherever the options differ in how something looks. A segmented
/// control of three words asks you to imagine each one; a picture shows it.
private struct ChoiceCard<Picture: View>: View {
    let title: String
    var caption: String?
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                picture()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(caption == nil ? 8 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.08),
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A screen with the shelf along one edge.
private struct EdgeSketch: View {
    let edge: DockPosition

    var body: some View {
        let vertical = edge != .bottom
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.primary.opacity(0.06))
            .overlay(alignment: edge == .left ? .leading : edge == .right ? .trailing : .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: vertical ? 6 : 44, height: vertical ? 26 : 6)
                    .padding(4)
            }
    }
}

/// The shelf's material, for real, over a scrap of colour.
private struct MaterialSample: View {
    let look: ShelfLook

    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .indigo],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Something behind the shelf for the material to act on.
            Circle().fill(.yellow.opacity(0.9)).frame(width: 22).offset(x: -18, y: 6)
            slab
        }
    }

    private var ink: Color {
        switch look.forcedAppearance {
        case .light?: .black.opacity(0.55)
        default: .white.opacity(0.9)
        }
    }

    @ViewBuilder private var slab: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let tiles = HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3).fill(ink).frame(width: 12, height: 12)
            }
        }
        .padding(6)
        switch look {
        case .frosted: tiles.background(.regularMaterial, in: shape)
        case .glass: tiles.glassEffect(.regular, in: shape)
        case .clearGlass: tiles.glassEffect(.clear, in: shape)
        case .lightGlass: tiles.glassEffect(MaterialBackground.glassValue(.regular, tint: .light), in: shape)
        case .darkGlass: tiles.glassEffect(MaterialBackground.glassValue(.regular, tint: .dark), in: shape)
        case .white:
            tiles.background(Color(hex: "#F6F6F6"), in: shape)
                .overlay { shape.strokeBorder(.black.opacity(0.1), lineWidth: 1) }
        case .black:
            tiles.background(Color(hex: "#161616"), in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
        case .transparent: tiles
        }
    }
}

/// A window in each appearance, and System as both at once.
private struct AppearanceSketch: View {
    let appearance: AppAppearance

    var body: some View {
        switch appearance {
        case .light: window(dark: false)
        case .dark: window(dark: true)
        case .system:
            HStack(spacing: 0) {
                window(dark: false)
                window(dark: true)
            }
        }
    }

    private func window(dark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(dark ? Color(white: 0.16) : Color(white: 0.93))
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(dark ? Color(white: 0.35) : Color(white: 0.75))
                    .frame(width: 34, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 5)
            }
            .padding(8)
        }
    }
}

/// A thumbnail of the screen: Apple's Dock in grey along the bottom, the
/// shelf in the accent colour wherever it goes.
private struct SetupSketch: View {
    let setup: DockSetup

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.primary.opacity(0.06))
            .overlay(alignment: .bottom) {
                if setup != .customReplacement {
                    bar(tiles: 5, colour: .primary.opacity(0.35))
                        .padding(.bottom, 5)
                }
            }
            .overlay(alignment: setup == .both ? .trailing : .bottom) {
                if setup != .macOSDockOnly {
                    // Beside Apple's Dock it takes a free edge, which is what
                    // the shelf does rather than stack on the Dock's.
                    shelf(vertical: setup == .both)
                        .padding(setup == .both ? .trailing : .bottom, 5)
                }
            }
    }

    private func bar(tiles: Int, colour: Color) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<tiles, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5).fill(colour).frame(width: 6, height: 6)
            }
        }
        .padding(3)
        .background(.primary.opacity(0.1), in: .rect(cornerRadius: 3.5))
    }

    /// Apps and one wide widget, so it reads as the shelf and not a second
    /// Dock.
    private func shelf(vertical: Bool) -> some View {
        let tile = RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor.opacity(0.85))
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 2.5)) : AnyLayout(HStackLayout(spacing: 2.5))
        return layout {
            tile.frame(width: vertical ? 6 : 14, height: vertical ? 14 : 6)
            tile.frame(width: 6, height: 6)
            tile.frame(width: 6, height: 6)
        }
        .padding(3)
        .background(Color.accentColor.opacity(0.18), in: .rect(cornerRadius: 3.5))
    }
}

/// A saved layout: click to use it, type to rename it.
private struct LayoutRow<Preview: View>: View {
    @Binding var name: String
    let editable: Bool
    let active: Bool
    let onUse: () -> Void
    var onDuplicate: (() -> Void)?
    var onDelete: (() -> Void)?
    @ViewBuilder var preview: () -> Preview

    /// Renaming is asked for, not always on. An always-live field took focus
    /// when the pane opened and showed the first name selected, as if it was
    /// about to be typed over.
    @State private var renaming = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onUse) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help(active ? "使用中" : "使用此布局")
            .accessibilityLabel(active ? "使用中" : "使用“\(name)”")

            if renaming {
                // Unlabelled and leading: inside a form a titled field draws
                // its title as a row label and pushes the name to the far
                // edge, so every row read "Name ... Everyday".
                TextField("名称", text: $name)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($focused)
                    .onSubmit { renaming = false }
                    .onChange(of: focused) { _, now in if !now { renaming = false } }
                    .onAppear { focused = true }
            } else if editable {
                Text(name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) { renaming = true }
                    .onTapGesture(perform: onUse)
            } else {
                Text(name)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture(perform: onUse)
            }

            preview()

            if onDuplicate != nil || onDelete != nil {
                Menu {
                    if editable { Button("重命名") { renaming = true } }
                    if let onDuplicate { Button("复制", action: onDuplicate) }
                    if let onDelete { Button("删除", role: .destructive, action: onDelete) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }
}

/// Records a layout's global shortcut: click, then press the combination.
///
/// A button that turns into a prompt, the way the shortcut fields in System
/// Settings behave, rather than a text field: a field would show characters
/// for the keys, and typing into it would be indistinguishable from naming
/// the layout.
private struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var recorder = ShortcutKeyRecorder()

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start(onChange)
            }
        } label: {
            Text(title)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(recorder.isRecording || combo != nil ? Color.primary : Color.secondary)
                .frame(minWidth: 72)
        }
        .controlSize(.small)
        .help(recorder.isRecording
              ? "按下组合键；按 Esc 取消，按删除键清除。"
              : "点按以录制切换到此布局的快捷键。")
        .accessibilityLabel(Text(spokenTitle))
        // Leaving the pane mid-recording must not leave the hotkeys switched
        // off, or every layout shortcut would stay dead until a relaunch.
        .onDisappear { recorder.stop() }
    }

    private var spokenTitle: String {
        guard let combo else { return "录制快捷键" }
        return "快捷键 " + combo.displayString
    }

    private var title: String {
        if recorder.isRecording {
            return recorder.rejected ? "须含 ⌃⌥⌘" : "请按快捷键…"
        }
        return combo?.displayString ?? "录制快捷键"
    }
}

/// The key monitor behind `ShortcutRecorder`.
///
/// A class because the monitor is a token that has to be removed later, and
/// a view's state cannot hold a closure that outlives the view safely.
@MainActor
@Observable
final class ShortcutKeyRecorder {
    private(set) var isRecording = false
    /// The last press lacked a required modifier, so the prompt says why
    /// nothing happened.
    private(set) var rejected = false
    @ObservationIgnored private var monitor: Any?

    func start(_ commit: @escaping (KeyCombo?) -> Void) {
        stop()
        isRecording = true
        rejected = false
        HotKeyService.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event, commit)
            // Swallowed, or the key would also reach whatever has focus.
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        rejected = false
        HotKeyService.shared.resume()
    }

    private func handle(_ event: NSEvent, _ commit: (KeyCombo?) -> Void) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let bare = flags.intersection([.control, .option, .shift, .command]).isEmpty
        let code = UInt32(event.keyCode)

        if bare, code == KeyCombo.Key.escape {
            stop()
            return
        }
        if bare, code == KeyCombo.Key.delete || code == KeyCombo.Key.forwardDelete {
            commit(nil)
            stop()
            return
        }

        let combo = KeyCombo(keyCode: code,
                             modifiers: KeyCombo.modifiers(control: flags.contains(.control),
                                                           option: flags.contains(.option),
                                                           shift: flags.contains(.shift),
                                                           command: flags.contains(.command)))
        guard combo.hasRequiredModifier else {
            rejected = true
            NSSound.beep()
            return
        }
        commit(combo)
        stop()
    }
}

/// 赞助者专属配色: swatches that tint the plate, locked until the sponsor
/// window's thank-you button has been pressed on this Mac.
private struct SupporterColorPicker: View {
    @Binding var selection: String
    @AppStorage(Supporter.key) private var unlocked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("专属配色")
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !unlocked {
                    Button("支持码头后解锁…") { SponsorWindow.shared.show() }
                        .controlSize(.small)
                }
            }
            HStack(spacing: 10) {
                swatch(nil)
                ForEach(ShelfColor.allCases) { swatch($0) }
            }
            .disabled(!unlocked)
            .opacity(unlocked ? 1 : 0.45)
            Text(unlocked ? "给扩展栏底板染一层颜色，“透明”外观下不生效。" : "赞助者专属：给扩展栏换上小熊猫橙、樱花粉等配色。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func swatch(_ color: ShelfColor?) -> some View {
        let chosen = ShelfColor.parse(selection) == color
        return Button {
            selection = color?.rawValue ?? ""
        } label: {
            ZStack {
                Circle()
                    .fill(color.map { Color(hex: $0.hex) } ?? Color.secondary.opacity(0.15))
                    .frame(width: 26, height: 26)
                if color == nil {
                    Image(systemName: "nosign")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .opacity(chosen ? 1 : 0)
            }
            .frame(width: 34, height: 34)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(color?.title ?? "无")
        .accessibilityLabel(color?.title ?? "无配色")
    }
}
