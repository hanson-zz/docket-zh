import AppKit
import SwiftUI

/// 截图工具面板，照第三批效果图（H2）：
/// - 顶上是卡片上那几个动作的大按钮（第一个实心），点了收起面板再截；
/// - 「截完后」存文件 / 拷贝 / 两者 / 标注，「格式」PNG / JPG，「延时」不延时 / 3 / 5 / 10 秒，
///   改了直接写进这张卡片的设置（设置页里也是这几项）；
/// - 「最近截图」三张缩略图，点了在面板里进标注（和最近截图面板同一个标注）；
/// - 「卡片上的按钮」默认收起：勾选放哪几个（最多 4 个）、左右挪顺序。
/// 识字仍是 Pro（快速开关的同一个工具），没解锁时点了弹付费墙。
struct CaptureDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    @State private var markup: URL?
    @State private var buttonsNote: String?

    private var feed: FolderFeed { FolderFeed.shared(.screenshots) }
    private var recording: ScreenRecording { ScreenRecording.shared }
    private var inbox: CaptureMarkupInbox { CaptureMarkupInbox.shared }

    private var palette: FilePanelPalette {
        FilePanelPalette(accent: panelTint.accent(or: Color(hex: "#B9A0FF")),
                         ink: panelTint.ink(or: Color(hex: "#1B0B3D")))
    }

    private var config: WidgetConfig { instance.config }
    private var options: CaptureOptions { CaptureOptions(config: config) }
    private var actions: [CaptureAction] { CaptureButtons.from(config) }

    private var shots: [ListedFile] {
        context.isPreview ? [] : Array(feed.files.filter(\.isImage).prefix(3))
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.purple))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let markup {
                    ScreenshotMarkupView(url: markup, palette: palette, feed: feed) {
                        withAnimation(.snappy(duration: 0.25)) { self.markup = nil }
                    }
                } else {
                    FilePanelHeader(title: tr("截图工具"), subtitle: options.summary, palette: palette)
                    bigButtons
                    afterSection
                    formatRow
                    delaySection
                    recentSection
                    buttonsFold
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            feed.start()
            feed.refresh(force: true)
            takePending()
        }
        .onChange(of: inbox.pending[instance.id]) { _, _ in takePending() }
        .onChange(of: feed.files.map(\.url)) { _, urls in
            // 正在标注的那张被删了或移走了，回到面板。
            if let markup, !urls.contains(markup) { self.markup = nil }
        }
    }

    private func takePending() {
        guard let url = inbox.take(instance.id) else { return }
        markup = url
    }

    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance, change)
    }

    // MARK: 大按钮

    private func isLocked(_ action: CaptureAction) -> Bool {
        guard let toggle = action.quickToggle else { return false }
        let unlocked = licenseUnlocked || supporter || context.isPreview
        return !ProLicenseGate.canUseTool(toggle, isOn: false, unlocked: unlocked)
    }

    private func isLive(_ action: CaptureAction) -> Bool {
        action.isRecording && !context.isPreview && recording.isRecording
    }

    private var bigButtons: some View {
        HStack(spacing: 6) {
            let list = actions
            ForEach(list) { action in
                bigButton(action, solid: action == list.first)
            }
        }
    }

    private func bigButton(_ action: CaptureAction, solid: Bool) -> some View {
        let live = isLive(action)
        let locked = isLocked(action)
        let fill: Color = live ? Color(hex: "#FF6B5A") : (solid ? palette.accent : .panelFill)
        let ink: Color = live ? .white : (solid ? palette.ink : .panelPrimary)
        return Button {
            run(action, locked: locked, live: live)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: live ? "stop.fill" : action.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                if live, let started = recording.startedAt {
                    Text(verbatim: RecordingClock.text(context.now.timeIntervalSince(started)))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                } else {
                    Text(verbatim: action.title)
                        .font(.system(size: 13, weight: solid ? .bold : .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .foregroundStyle(ink.opacity(locked ? 0.5 : 1))
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.panelStroke.opacity(solid || live ? 0 : 1), lineWidth: 0.6)
            }
            .overlay(alignment: .topTrailing) {
                if action.quickToggle != nil {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#F5C451"))
                        .padding(5)
                        .help(ProFeatures.help)
                        .accessibilityLabel(ProFeatures.label)
                }
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(locked ? tr("\(action.title)：码头 Pro 专属，点一下解锁")
              : (live ? tr("正在录屏，点一下停止") : action.help))
        .accessibilityLabel(action.title)
        .accessibilityValue(locked ? ProFeatures.label : (live ? tr("正在录屏") : ""))
    }

    private func run(_ action: CaptureAction, locked: Bool, live: Bool) {
        guard !context.isPreview else { return }
        if locked {
            PaywallWindow.shared.show()
            return
        }
        if live {
            recording.stop()
            return
        }
        // 先收起面板，免得截进去；等它淡出再开始。
        let options = self.options
        let id = instance.id
        WidgetDetailWindow.shared.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            ScreenCapture.perform(action, options: options, widget: id)
        }
    }

    // MARK: 设置

    private func sectionTitle(_ text: String, trailing: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(verbatim: text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 0)
            if let trailing, let action {
                Button(action: action) {
                    Text(verbatim: trailing)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var afterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("截完后"))
            CaptureSegments(items: CaptureAfter.allCases, title: \.title, selected: options.after,
                            palette: palette, height: 32) { value in
                write { $0.set(CaptureAfter.key, .string(value.rawValue)) }
            }
        }
    }

    private var formatRow: some View {
        HStack(spacing: 12) {
            sectionTitle(tr("格式"))
                .frame(width: 92, alignment: .leading)
            CaptureSegments(items: CaptureFormat.allCases, title: \.title, selected: options.format,
                            palette: palette, height: 30) { value in
                write { $0.set(CaptureFormat.key, .string(value.rawValue)) }
            }
        }
    }

    private var delaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("延时"))
            CaptureSegments(items: CaptureDelay.choices, title: { CaptureDelay.title($0) },
                            selected: options.delay, palette: palette, height: 30, gap: 6) { value in
                write { $0.set(CaptureDelay.key, .string("\(value)")) }
            }
        }
    }

    // MARK: 最近截图

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("最近截图"), trailing: context.isPreview ? nil : tr("全部 ›")) {
                FileActions.openFolder(feed.folder)
            }
            if context.isPreview {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        SamplePicture(symbol: "macwindow")
                            .frame(height: 56)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 7, style: .continuous))
                    }
                }
            } else if shots.isEmpty {
                Text(verbatim: feed.error == nil ? tr("还没有截图，截一张就会出现在这里") : tr("读不到截图文件夹"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        if index < shots.count {
                            thumb(shots[index])
                        } else {
                            Color.clear.frame(height: 56).frame(maxWidth: .infinity)
                        }
                    }
                }
                Text(verbatim: tr("点缩略图直接进标注"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
        }
    }

    private func thumb(_ file: ListedFile) -> some View {
        FileThumb(url: file.url, pixels: 240)
            .id(file.url)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Color.panelFill)
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.panelStroke, lineWidth: 0.6)
            }
            .contentShape(.rect(cornerRadius: 7))
            .onTapGesture {
                withAnimation(.snappy(duration: 0.25)) { markup = file.url }
            }
            .onDrag { FileActions.dragProvider(file.url) }
            .contextMenu {
                Button(tr("标注")) { markup = file.url }
                Button(tr("打开")) { FileActions.open(file.url) }
                Button(tr("拷贝图像")) { FileActions.copyImage(file.url) }
                Button(tr("在访达中显示")) { FileActions.reveal([file.url]) }
            }
            .help(file.name)
            .accessibilityLabel(file.name)
            .accessibilityHint(tr("点按进入标注"))
    }

    // MARK: 卡片上的按钮

    private var buttonsFold: some View {
        DetailFold(key: DetailPanelSections.foldKey(.capture, "buttons")) {
            Text(verbatim: tr("卡片上的按钮"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(CaptureAction.allCases) { action in
                    buttonRow(action)
                }
                Text(verbatim: buttonsNote ?? tr("最多放 \(CaptureButtons.limit) 个，箭头调整左右顺序"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary.opacity(buttonsNote == nil ? 0.55 : 0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func buttonRow(_ action: CaptureAction) -> some View {
        let current = actions
        let on = current.contains(action)
        let index = current.firstIndex(of: action)
        return HStack(spacing: 10) {
            Button {
                guard let next = CaptureButtons.toggling(action, in: current) else {
                    buttonsNote = on ? tr("至少留一个按钮") : tr("卡片上最多放 \(CaptureButtons.limit) 个，先去掉一个")
                    return
                }
                buttonsNote = nil
                write { $0.set(CaptureButtons.key, .list(next.map { .string($0.rawValue) })) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(on ? palette.accent : .panelTertiary)
                    Image(systemName: action.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 18)
                    Text(verbatim: action.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                    if action.quickToggle != nil {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#F5C451"))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(on ? tr("已显示") : tr("未显示"))
            if let index {
                arrow("chevron.left", enabled: index > 0, label: tr("左移")) {
                    move(action, by: -1)
                }
                arrow("chevron.right", enabled: index < current.count - 1, label: tr("右移")) {
                    move(action, by: 1)
                }
            }
        }
        .frame(height: 28)
    }

    private func arrow(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(enabled ? 0.85 : 0.25))
                .frame(width: 26, height: 24)
                .background(Capsule().fill(.panelFill.opacity(enabled ? 1 : 0.45)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func move(_ action: CaptureAction, by offset: Int) {
        let next = CaptureButtons.moving(action, by: offset, in: actions)
        buttonsNote = nil
        write { $0.set(CaptureButtons.key, .list(next.map { .string($0.rawValue) })) }
    }
}

/// 一排等宽的选项，选中的实心强调色、深色字，其余深色玻璃。
private struct CaptureSegments<Item: Hashable>: View {
    var items: [Item]
    var title: (Item) -> String
    var selected: Item
    var palette: FilePanelPalette
    var height: CGFloat
    var gap: CGFloat = 0
    var onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: gap) {
            ForEach(items, id: \.self) { item in
                let on = item == selected
                Button {
                    withAnimation(.snappy(duration: 0.2)) { onSelect(item) }
                } label: {
                    Text(verbatim: title(item))
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? palette.ink : .panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: gap > 0 ? height / 2 : 8, style: .continuous)
                                    .fill(palette.accent)
                                    .padding(gap > 0 ? 0 : 2)
                            } else if gap > 0 {
                                Capsule().fill(.panelFill)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .frame(height: height)
        .background {
            if gap == 0 {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.panelFill)
            }
        }
        .overlay {
            if gap == 0 {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.panelStroke, lineWidth: 0.8)
            }
        }
    }
}
