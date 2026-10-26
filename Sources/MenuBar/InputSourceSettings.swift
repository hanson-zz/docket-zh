import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置 ▸ 输入法，照效果图 design/input-source/settings-*.png：
///
/// - 头图：字形徽章、标题、总开关（默认关），右边一张分镜示意（切到 App → 从刘海落下提示
///   → 停一下收回），小熊猫；
/// - 「没有规则的 App」：用默认输入法 / 记住上次两张卡，下面选默认输入法；
/// - 「按 App 规则」（码头 Pro）：App 图标大卡片网格，右下角是输入法的字形徽章，点卡片换输入法，
///   悬停 ⋯ 删除，「添加 App」从「应用程序」选或从正在运行的 App 里选，也能把 App 拖进网格。
///   输入法被删了的卡片写灰色「已删除，暂用 XX」，装回后自动恢复。没解锁时盖模糊遮罩和小锁，
///   「解锁码头 Pro」打开付费墙，不改配置；
/// - 「切换提示」：刘海下 / 光标旁 / 关闭三张卡和停留时间；选光标旁且没授权时多一行「去授权」；
/// - 页脚写清楚用到什么权限。
///
/// 液态玻璃跟随浅色 / 深色，不用大面积蓝色发光，字至少 13pt。
struct InputSourceSettingsPane: View {
    @Binding var settings: InputSourceSettings

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    @State private var sources: [InputSourceInfo] = []
    @State private var currentID: String?
    @State private var dropTargeted = false

    private var unlocked: Bool {
        ProLicenseGate.inputSourceRulesActive(unlocked: licenseUnlocked || supporter)
    }

    var body: some View {
        Form {
            Section {
                InputSourceHero(enabled: $settings.enabled, seconds: settings.hintSeconds)
                    .listRowInsets(EdgeInsets())
            }

            fallbackSection
            rulesSection
            hintSection
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .task {
            // 用户可能开着设置去系统设置里加减输入法：隔几秒再读一次（读一次很便宜）。
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                refresh()
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: InputSourceService.changeNotifications[0])) { _ in refresh() }
    }

    private func refresh() {
        let next = InputSourceService.available()
        if next != sources { sources = next }
        currentID = InputSourceService.currentID()
    }

    // MARK: 没有规则的 App

    private var fallbackSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(InputSourceFallback.allCases, id: \.self) { mode in
                    InputChoiceCard(title: mode.title, caption: mode.caption, selected: settings.fallback == mode) {
                        withAnimation(.smooth(duration: 0.2)) { settings.fallback = mode }
                    } picture: {
                        fallbackPicture(mode)
                    }
                }
            }
            .padding(.vertical, 2)

            LabeledContent(tr("默认输入法")) {
                SourceMenu(sources: sources, selectedID: effectiveDefault?.id) { id in
                    settings.defaultSourceID = id
                } label: {
                    SourceLabel(source: effectiveDefault)
                }
                .fixedSize()
            }
        } header: {
            Text(tr("没有规则的 App"))
        }
    }

    /// 设的默认输入法还在就是它，否则是系统第一个（和切换时的回退一致）。
    private var effectiveDefault: InputSourceInfo? {
        let target = InputSourceResolver.defaultTarget(settings, available: sources)
        return InputSourceCatalog.find(target?.sourceID, in: sources)
    }

    @ViewBuilder private func fallbackPicture(_ mode: InputSourceFallback) -> some View {
        switch mode {
        case .defaultSource:
            HStack(spacing: 12) {
                InputSourceGlyphBadge(glyph: effectiveDefault.map(InputSourceGlyph.of) ?? .missing, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(effectiveDefault?.name ?? tr("没有输入法"))
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(tr("每次都回到它"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        case .remember:
            HStack(spacing: 22) {
                ForEach(Array(SampleApp.remember.enumerated()), id: \.offset) { _, sample in
                    AppIconWithGlyph(icon: sample.icon, glyph: sample.glyph, size: 40, badge: 20)
                }
            }
        }
    }

    // MARK: 按 App 规则

    private var rulesSection: some View {
        Section {
            ZStack {
                ruleGrid
                    .blur(radius: unlocked ? 0 : 9)
                    .allowsHitTesting(unlocked)
                    .accessibilityHidden(!unlocked)
                if !unlocked { lockOverlay }
            }
            if unlocked {
                Text(tr("点卡片换输入法。同一个 App 的所有窗口共用一条规则。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 8) {
                Text(tr("按 App 规则"))
                ProBadge()
                Spacer()
                if unlocked {
                    addMenu {
                        Label(tr("添加 App"), systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
                } else {
                    Button { PaywallWindow.shared.show() } label: {
                        Label(tr("添加 App"), systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 12)]

    private var ruleGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            if unlocked {
                ForEach(settings.rules) { rule in
                    RuleCard(rule: rule, status: InputSourceRuleStatus.of(rule, settings: settings, available: sources),
                             sources: sources,
                             change: { id in
                                 settings.setRule(bundleID: rule.bundleID, appName: rule.appName, sourceID: id)
                             },
                             remove: {
                                 withAnimation(.smooth(duration: 0.2)) { settings.removeRule(bundleID: rule.bundleID) }
                             })
                }
                addMenu { AddCard(targeted: dropTargeted) }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
            } else {
                // 没解锁：模糊遮罩下面放已有的规则，没有时放几张示意卡（不进配置）。
                ForEach(lockedSamples) { sample in
                    SampleCard(sample: sample)
                }
            }
        }
        .padding(.vertical, 4)
        .dropDestination(for: URL.self) { urls, _ in
            guard unlocked else { return false }
            let apps = urls.filter { $0.pathExtension.lowercased() == "app" }
            for url in apps { addApp(at: url) }
            return !apps.isEmpty
        } isTargeted: { dropTargeted = $0 && unlocked }
    }

    private var lockedSamples: [SampleApp] {
        let existing = settings.rules.prefix(8).map { rule in
            SampleApp(id: rule.bundleID, name: rule.appName, icon: AppIconLookup.icon(bundleID: rule.bundleID),
                      glyph: InputSourceCatalog.find(rule.sourceID, in: sources).map(InputSourceGlyph.of) ?? .missing,
                      caption: InputSourceRuleStatus.of(rule, settings: settings, available: sources).caption)
        }
        return existing.isEmpty ? SampleApp.lockedGrid : existing
    }

    private var lockOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
            Text(tr("每个 App 记住自己的输入法"))
                .font(.system(size: 17, weight: .bold))
            Text(tr("按 App 规则属于码头 Pro，其余免费"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button { PaywallWindow.shared.show() } label: {
                Text(tr("解锁码头 Pro"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(hex: "#C2410C")))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: 添加 App

    private func addMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            Button(tr("从「应用程序」选…")) { chooseApps() }
            let running = runningApps
            if !running.isEmpty {
                Section(tr("正在运行的 App")) {
                    ForEach(running, id: \.bundleID) { app in
                        Button {
                            addRule(bundleID: app.bundleID, name: app.name)
                        } label: {
                            if let icon = app.icon {
                                Label { Text(app.name) } icon: { Image(nsImage: Self.menuIcon(icon)) }
                            } else {
                                Text(app.name)
                            }
                        }
                    }
                }
            }
        } label: {
            label()
        }
    }

    private struct RunningApp {
        var bundleID: String
        var name: String
        var icon: NSImage?
    }

    /// 正在运行、有界面的 App，去掉码头自己和已经有规则的，按名字排。
    private var runningApps: [RunningApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, !InputSourceResolver.isOwn(id),
                  settings.rule(for: id) == nil, seen.insert(id.lowercased()).inserted else { return nil }
            return RunningApp(bundleID: id, name: app.localizedName ?? id, icon: app.icon)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func menuIcon(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = tr("选择 App")
        panel.prompt = tr("添加")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addApp(at: url) }
    }

    private func addApp(at url: URL) {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
        addRule(bundleID: id, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }

    /// 新规则先用现在的输入法（打开设置时一般就是要给它的那个），点卡片再换。
    private func addRule(bundleID: String, name: String) {
        refresh()
        let source = InputSourceCatalog.find(currentID, in: sources) ?? effectiveDefault ?? sources.first
        guard let source else { return }
        withAnimation(.smooth(duration: 0.2)) {
            settings.setRule(bundleID: bundleID, appName: name, sourceID: source.id)
        }
    }

    // MARK: 切换提示

    private var hintSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach(InputSourceHintPosition.allCases, id: \.self) { position in
                    InputChoiceCard(title: position.title, caption: position.caption,
                                    selected: settings.hint == position) {
                        withAnimation(.smooth(duration: 0.2)) { settings.hint = position }
                    } picture: {
                        HintSketch(position: position)
                    }
                }
            }
            .padding(.vertical, 2)

            if settings.hint.needsAccessibility {
                CursorAccessibilityRow()
            }

            if settings.hint != .off {
                Picker(tr("停留时间"), selection: Binding(
                    get: { settings.hintSeconds },
                    set: { settings.seconds = $0 })) {
                    ForEach(InputSourceSettings.secondChoices, id: \.self) { seconds in
                        Text(tr("\(InputSourceSettings.secondsText(seconds)) 秒")).tag(seconds)
                    }
                }
            }
        } header: {
            Text(tr("切换提示"))
        } footer: {
            Text(tr("读取和切换输入法用系统接口，不需要任何权限。只有「光标旁」要辅助功能权限，用来找到光标的位置。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 头图

private struct InputSourceHero: View {
    @Binding var enabled: Bool
    var seconds: Double

    var body: some View {
        // 窗口窄时分镜挪到下面。
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                intro.frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                HeroStoryboard(seconds: seconds)
                    .frame(minWidth: 260, maxWidth: 340)
                    .frame(height: 176)
            }
            VStack(alignment: .leading, spacing: 14) {
                intro
                HeroStoryboard(seconds: seconds)
                    .frame(height: 176)
            }
        }
        .padding(18)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(SampleApp.heroGlyphs.enumerated()), id: \.offset) { _, glyph in
                    InputSourceGlyphBadge(glyph: glyph, size: 28)
                }
            }
            Text(tr("输入法自动切换"))
                .font(.system(size: 26, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("切到哪个 App，就换成它的输入法"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom) {
                HStack(spacing: 10) {
                    Toggle(tr("输入法自动切换"), isOn: $enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text(enabled ? tr("已开启") : tr("已关闭"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.bottom, 6)
                Spacer(minLength: 8)
                PandaImage()
                    .frame(width: 72, height: 72)
            }
        }
    }
}

/// 小熊猫（Resources/Pet/pet-panda-idle.png），读不到时不画。
private struct PandaImage: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "pet-panda-idle", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

/// 右边的分镜：屏幕顶上的刘海、落下的提示胶囊、底下一排 App，旁边三个编号小标签。静态。
private struct HeroStoryboard: View {
    var seconds: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: scheme == .dark
                                         ? [Color(hex: "#3A3354"), Color(hex: "#5A3A44")]
                                         : [Color(hex: "#E4E0F6"), Color(hex: "#F6E1DA")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                // 刘海
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8,
                                       bottomTrailingRadius: 8, topTrailingRadius: 0, style: .continuous)
                    .fill(.black)
                    .frame(width: w * 0.34, height: 20)
                // 落下的提示
                HStack(spacing: 6) {
                    InputSourceGlyphBadge(glyph: InputSourceGlyph("拼", .chinese), size: 22)
                    Text(tr("简体拼音"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let icon = SampleApp.notes.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 16,
                                                                          bottomTrailingRadius: 16, topTrailingRadius: 6,
                                                                          style: .continuous))
                .offset(y: 20)
                // 底下一排 App，备忘录在前台
                HStack(spacing: 8) {
                    ForEach(Array(SampleApp.dock.enumerated()), id: \.offset) { index, sample in
                        VStack(spacing: 3) {
                            if let icon = sample.icon {
                                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                            }
                            Circle().fill(.primary.opacity(index == 0 ? 0.7 : 0)).frame(width: 4, height: 4)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
                .offset(y: h - 52)

                StepChip(number: 1, text: tr("切到备忘录"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .offset(y: h - 100)
                StepChip(number: 2, text: tr("落下提示"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
                    .offset(y: 64)
                StepChip(number: 3, text: tr("\(InputSourceSettings.secondsText(seconds)) 秒收回"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .offset(y: 64)
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("切到 App 时，提示从刘海落下，停一下后收回"))
    }
}

private struct StepChip: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: "\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(hex: "#C2410C")))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 9)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - 卡片

/// 带图的单选卡，右上角选中时打勾。
private struct InputChoiceCard<Picture: View>: View {
    let title: String
    let caption: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                picture()
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background(.primary.opacity(0.045), in: .rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.08), lineWidth: selected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(8)
                }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// 一条规则：App 图标，右下角字形徽章，名字，输入法。点卡片换输入法，悬停 ⋯ 删除。
private struct RuleCard: View {
    let rule: InputSourceRule
    let status: InputSourceRuleStatus
    let sources: [InputSourceInfo]
    let change: (String) -> Void
    let remove: () -> Void

    @State private var hovering = false

    private var glyph: InputSourceGlyph {
        switch status {
        case .ok(let source): InputSourceGlyph.of(source)
        case .missing(let fallback):
            InputSourceGlyph(fallback.map(InputSourceGlyph.of)?.text ?? "?", .missing)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SourceMenu(sources: sources, selectedID: status.isMissing ? nil : rule.sourceID, choose: change) {
                VStack(spacing: 6) {
                    AppIconWithGlyph(icon: AppIconLookup.icon(bundleID: rule.bundleID), glyph: glyph, size: 56, badge: 26)
                        .padding(.top, 14)
                    Text(rule.appName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(status.caption)
                        .font(.system(size: 13, weight: status.isMissing ? .semibold : .regular))
                        .foregroundStyle(status.isMissing ? AnyShapeStyle(Color(nsColor: .systemRed).panelReadable)
                                         : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(hovering ? 0.55 : 0.35), in: .rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.primary.opacity(0.07), lineWidth: 0.8)
                }
                .contentShape(.rect(cornerRadius: 14))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(tr("点一下换输入法"))

            Menu {
                Button(tr("删除"), role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 22)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(6)
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel(tr("更多"))
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("\(rule.appName)，\(status.caption)"))
    }
}

/// 虚线框的「添加 App / 或拖进图标」。
private struct AddCard: View {
    var targeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.primary.opacity(0.07)))
                .padding(.top, 16)
            Text(tr("添加 App"))
                .font(.system(size: 15, weight: .semibold))
            Text(tr("或拖进图标"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(targeted ? 0.08 : 0), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : .primary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
        .contentShape(.rect(cornerRadius: 14))
    }
}

/// 没解锁时模糊遮罩下面的示意卡。
private struct SampleCard: View {
    let sample: SampleApp

    var body: some View {
        VStack(spacing: 6) {
            AppIconWithGlyph(icon: sample.icon, glyph: sample.glyph, size: 56, badge: 26)
                .padding(.top, 14)
            Text(sample.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Text(sample.caption)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// App 图标，右下角压一个字形徽章。
private struct AppIconWithGlyph: View {
    let icon: NSImage?
    let glyph: InputSourceGlyph
    let size: CGFloat
    let badge: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(.primary.opacity(0.1))
                        .overlay { Image(systemName: "app.dashed").foregroundStyle(.secondary) }
                }
            }
            .frame(width: size, height: size)
            InputSourceGlyphBadge(glyph: glyph, size: badge)
                .overlay {
                    RoundedRectangle(cornerRadius: badge * 0.26, style: .continuous)
                        .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2)
                }
                .offset(x: badge * 0.3, y: badge * 0.2)
        }
        .padding(.trailing, badge * 0.3)
        .accessibilityHidden(true)
    }
}

/// 输入法菜单：每项前面是字形，打勾的是选中的。
private struct SourceMenu<Label: View>: View {
    let sources: [InputSourceInfo]
    let selectedID: String?
    let choose: (String) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if sources.isEmpty {
                Text(tr("没有可用的键盘输入法"))
            }
            ForEach(sources) { source in
                Toggle(isOn: Binding(get: { source.id == selectedID }, set: { _ in choose(source.id) })) {
                    Text(verbatim: "\(InputSourceGlyph.of(source).text)  \(source.name)")
                }
            }
        } label: {
            label()
        }
    }
}

/// 菜单上显示的：字形徽章加名字。
private struct SourceLabel: View {
    let source: InputSourceInfo?

    var body: some View {
        HStack(spacing: 6) {
            InputSourceGlyphBadge(glyph: source.map(InputSourceGlyph.of) ?? .missing, size: 20)
            Text(source?.name ?? tr("没有输入法"))
                .font(.system(size: 13, weight: .medium))
        }
    }
}

/// 三张提示位置卡上的小示意。
private struct HintSketch: View {
    let position: InputSourceHintPosition

    var body: some View {
        ZStack(alignment: .top) {
            switch position {
            case .notch:
                notchBar
                pill(glyph: InputSourceGlyph("拼", .chinese), text: tr("拼音"))
                    .offset(y: 20)
            case .cursor:
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(.primary.opacity(0.14)).frame(width: 96, height: 5)
                    HStack(spacing: 2) {
                        Capsule().fill(.primary.opacity(0.14)).frame(width: 70, height: 5)
                        Rectangle().fill(.primary).frame(width: 1.5, height: 14)
                    }
                    pill(glyph: InputSourceGlyph("A", .latin), text: "ABC")
                        .padding(.leading, 40)
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            case .off:
                notchBar
                Image(systemName: "nosign")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    private var notchBar: some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 5,
                               bottomTrailingRadius: 5, topTrailingRadius: 0, style: .continuous)
            .fill(.black)
            .frame(width: 70, height: 14)
    }

    private func pill(glyph: InputSourceGlyph, text: String) -> some View {
        HStack(spacing: 5) {
            InputSourceGlyphBadge(glyph: glyph, size: 20)
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.6) }
    }
}

/// 选「光标旁」时的辅助功能权限行（同消息灵动岛的写法）：给了写「已授权」，没给时一句
/// 说明加「去授权」。每两秒看一次。
private struct CursorAccessibilityRow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let trusted = AppWindows.isTrusted
            LabeledContent {
                if trusted {
                    Text(tr("已授权"))
                        .foregroundStyle(.secondary)
                } else {
                    Button(tr("去授权")) { AppWindows.requestAccess() }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("辅助功能权限"))
                    Text(tr("找光标的位置需要辅助功能权限，没给时提示临时改到刘海下。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 示意用的 App

/// 示意图和没解锁时的示意卡用系统自带 App 的图标（每台 Mac 都有）。
private struct SampleApp: Identifiable {
    var id: String
    var name: String
    var icon: NSImage?
    var glyph: InputSourceGlyph
    var caption: String

    @MainActor private static func system(_ path: String, _ id: String, _ name: String, _ glyph: InputSourceGlyph,
                               _ caption: String) -> SampleApp {
        let icon = FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
        return SampleApp(id: id, name: name, icon: icon, glyph: glyph, caption: caption)
    }

    static let pinyin = InputSourceGlyph("拼", .chinese)
    static let latin = InputSourceGlyph("A", .latin)
    static let kana = InputSourceGlyph("あ", .japanese)
    static let hangul = InputSourceGlyph("한", .korean)

    static let heroGlyphs = [pinyin, latin, kana, hangul]

    @MainActor static let notes = system("/System/Applications/Notes.app", "notes", tr("备忘录"), kana, tr("日语假名"))
    @MainActor static let terminal = system("/System/Applications/Utilities/Terminal.app", "terminal", tr("终端"),
                                            latin, "ABC")
    @MainActor static let safari = system("/Applications/Safari.app", "safari", "Safari", pinyin, tr("简体拼音"))
    @MainActor static let mail = system("/System/Applications/Mail.app", "mail", tr("邮件"), hangul, tr("韩语"))
    @MainActor static let finder = system("/System/Library/CoreServices/Finder.app", "finder", tr("访达"), latin, "ABC")

    @MainActor static var remember: [SampleApp] {
        [SampleApp(id: "n", name: "", icon: notes.icon, glyph: pinyin, caption: ""),
         SampleApp(id: "t", name: "", icon: terminal.icon, glyph: latin, caption: ""),
         SampleApp(id: "s", name: "", icon: safari.icon, glyph: kana, caption: "")]
    }

    @MainActor static var dock: [SampleApp] { [notes, terminal, safari, mail] }

    @MainActor static var lockedGrid: [SampleApp] { [safari, terminal, notes, mail, finder] }
}

/// 按 bundle id 找 App 的图标，找不到（卸载了）时 nil。
@MainActor
enum AppIconLookup {
    private static var cache: [String: NSImage] = [:]

    static func icon(bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}
