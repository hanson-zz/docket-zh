import AppKit
import SwiftUI

/// 环境音面板：我的组合、点亮的声音各自的音量、总音量、定时关闭、播放。
///
/// 选择都写回小组件设置（`sounds`、`levels`、`mixes`、`volume`），卡片、设置页
/// 和这里看到的总是同一个组合。面板自己也留一份改过的设置（`edited`），连着
/// 点几下时不会拿旧的设置覆盖刚改的；小组件从外面变了（卡片右键换了组合）就丢掉它。
struct AmbientDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private var player: AmbientPlayer { AmbientPlayer.shared }

    @State private var edited: WidgetConfig?
    /// 拖滑杆时的值，松手才写设置，免得拖一下写六十次。
    @State private var dragging: Double?
    @State private var levelDrag: (sound: AmbientSound, value: Double)?
    /// 「存为组合」框里的名字；nil 是没在存。
    @State private var newMixName: String?
    /// 正在改名的组合和框里的字。
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var customOpen = false
    @State private var customMinutes = AmbientCustomTimer.fallback

    private var config: WidgetConfig { edited ?? instance.config }
    private var sounds: [AmbientSound] {
        AmbientSound.parse(config.strings("sounds", default: ["rain"]))
    }
    private var levels: [AmbientSound: Int] {
        var stored = AmbientLevels.parse(config.strings(AmbientLevels.key, default: []))
        if let levelDrag { stored[levelDrag.sound] = Int(levelDrag.value.rounded()) }
        return stored
    }
    private var mixes: [AmbientMix] { AmbientMixes.all(config.strings(AmbientMixes.key, default: [])) }
    private var currentMix: AmbientMix? { AmbientMixes.matching(sounds: sounds, levels: levels, in: mixes) }
    private var volume: Double { dragging ?? config.double("volume", default: 50) }
    private var playing: Bool { context.isPreview || player.isPlaying }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
        .onChange(of: instance.config) { _, _ in edited = nil }
    }

    private func content(now: Date) -> some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(now: now)
                mixSection
                levelSection
                masterVolume
                timerSection
                playButton
                BreathPacerView(isPreview: context.isPreview, collapsible: true)
            }
        }
    }

    // MARK: 标题

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playing ? tr("正在播放") : tr("环境音"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Text(currentMix?.name ?? AmbientSound.summary(sounds))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let end = player.stopAt, player.isPlaying {
                Text(tr("\(AmbientTimer.remaining(until: end, now: now)) 后自动停止"))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func sectionTitle(_ title: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            if let note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 我的组合

    private var mixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(tr("我的组合"), note: mixes.isEmpty ? tr("调好了存一下，下次一点就回来") : nil)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(mixes, id: \.name) { mix in mixChip(mix) }
                    saveChip
                }
            }
            .scrollIndicators(.never)
            if let name = newMixName { nameEditor(name) }
            if let old = renaming { renameEditor(old) }
        }
    }

    private func mixChip(_ mix: AmbientMix) -> some View {
        let on = mix.name == currentMix?.name
        return Button {
            apply(mix)
        } label: {
            Text(mix.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? Color.panelOnPrimary : .panelPrimary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(on ? Color.panelPrimary : Color.panelFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(tr("换到这个组合；右键可改名或删除"))
        .accessibilityAddTraits(on ? .isSelected : [])
        .contextMenu {
            Button(tr("用现在的声音覆盖")) { saveMix(named: mix.name) }
                .disabled(sounds.isEmpty)
            Button(tr("改名…")) {
                newMixName = nil
                renameText = mix.name
                renaming = mix.name
            }
            Button(tr("删除"), role: .destructive) { removeMix(mix.name) }
        }
    }

    /// 「＋ 存为组合」；满 6 个时变成一句提示，先删一个才能再存。
    private var saveChip: some View {
        let full = mixes.count >= AmbientMixes.limit
        let blocked = full || sounds.isEmpty
        return Button {
            renaming = nil
            newMixName = AmbientMixes.suggestedName(existing: mixes)
        } label: {
            Text(full ? tr("已满 \(AmbientMixes.limit) 个") : tr("＋ 存为组合"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.panelPrimary.opacity(blocked ? 0.45 : 0.85))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().strokeBorder(.panelQuaternary, style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview || blocked)
        .help(full ? tr("最多存 \(AmbientMixes.limit) 个组合，右键删掉一个再存") : tr("把点亮的声音和各自音量存成一个组合"))
    }

    private func nameEditor(_ name: String) -> some View {
        HStack(spacing: 6) {
            TextField("", text: Binding(get: { newMixName ?? name }, set: { newMixName = $0 }),
                      prompt: Text(tr("组合名，比如 雨夜篝火")))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { saveMix(named: newMixName ?? name) }
            Button(tr("取消")) { newMixName = nil }
            Button(tr("存")) { saveMix(named: newMixName ?? name) }
                .keyboardShortcut(.defaultAction)
                .disabled(AmbientMixes.cleanName(newMixName ?? name).isEmpty)
        }
        .controlSize(.small)
    }

    private func renameEditor(_ old: String) -> some View {
        let result = AmbientMixes.renaming(old, to: renameText, in: config.strings(AmbientMixes.key, default: []))
        return HStack(spacing: 6) {
            TextField("", text: $renameText, prompt: Text(tr("新名字")))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { commitRename(old, result) }
            Button(tr("取消")) { renaming = nil }
            Button(tr("改名")) { commitRename(old, result) }
                .keyboardShortcut(.defaultAction)
                .disabled(result == nil)
        }
        .controlSize(.small)
    }

    private func saveMix(named name: String) {
        let raw = config.strings(AmbientMixes.key, default: [])
        switch AmbientMixes.saving(name: name, sounds: sounds, levels: levels, in: raw) {
        case .saved(let list):
            update { $0.set(AmbientMixes.key, .list(list.map { .string($0) })) }
            newMixName = nil
        case .full, .emptyName, .noSounds:
            NSSound.beep()
        }
    }

    private func commitRename(_ old: String, _ result: [String]?) {
        guard let result else { NSSound.beep(); return }
        update { $0.set(AmbientMixes.key, .list(result.map { .string($0) })) }
        renaming = nil
    }

    private func removeMix(_ name: String) {
        let left = AmbientMixes.removing(name, in: config.strings(AmbientMixes.key, default: []))
        update { $0.set(AmbientMixes.key, .list(left.map { .string($0) })) }
        if renaming == name { renaming = nil }
    }

    private func apply(_ mix: AmbientMix) {
        let next = AmbientMixes.applying(mix, levels: levels)
        write(sounds: next.sounds, levels: next.levels)
    }

    // MARK: 各自音量

    private var levelSection: some View {
        let off = AmbientSound.allCases.filter { !sounds.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("各自音量"), note: sounds.isEmpty ? tr("点下面的声音放起来") : tr("点图标关掉这种声音"))
            ForEach(sounds) { sound in levelRow(sound) }
            if !off.isEmpty {
                HStack(spacing: 6) {
                    ForEach(off) { sound in addChip(sound) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func levelRow(_ sound: AmbientSound) -> some View {
        let level = AmbientLevels.level(sound, in: levels)
        return HStack(spacing: 8) {
            Button {
                toggle(sound)
            } label: {
                Image(systemName: sound.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(accent.opacity(0.55)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help(tr("关掉\(sound.title)"))
            Text(sound.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 58, alignment: .leading)
            Slider(value: Binding(
                get: { Double(level) },
                set: { value in
                    levelDrag = (sound, value)
                    if !context.isPreview { player.apply(sounds: sounds, levels: levels, volume: volume) }
                }), in: 0...100, onEditingChanged: { editing in
                    guard !editing, let drag = levelDrag else { return }
                    var next = AmbientLevels.parse(config.strings(AmbientLevels.key, default: []))
                    next[drag.sound] = Int(drag.value.rounded())
                    levelDrag = nil
                    save { $0.set(AmbientLevels.key, .list(AmbientLevels.encode(next).map { .string($0) })) }
                })
                .controlSize(.small)
                .tint(accent)
                .disabled(context.isPreview)
                .accessibilityLabel(tr("\(sound.title)音量"))
            Text("\(level)%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.panelPrimary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .glassPane(cornerRadius: 10)
    }

    private func addChip(_ sound: AmbientSound) -> some View {
        Button {
            toggle(sound)
        } label: {
            Image(systemName: sound.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .frame(maxWidth: 38)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.panelFill))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.panelStroke, lineWidth: 0.5)
                }
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(tr("加上\(sound.title)"))
        .accessibilityLabel(tr("加上\(sound.title)"))
    }

    private func toggle(_ sound: AmbientSound) {
        guard !context.isPreview else { return }
        var next = sounds
        if next.contains(sound) { next.removeAll { $0 == sound } } else { next.append(sound) }
        let stored = AmbientLevels.parse(config.strings(AmbientLevels.key, default: []))
        write(sounds: AmbientSound.parse(next.map(\.rawValue)), levels: stored)
    }

    private func write(sounds next: [AmbientSound], levels nextLevels: [AmbientSound: Int]) {
        guard !context.isPreview else { return }
        update { config in
            config.set("sounds", .list(next.map { .string($0.rawValue) }))
            config.set(AmbientLevels.key, .list(AmbientLevels.encode(nextLevels).map { .string($0) }))
        }
        player.apply(sounds: next, levels: nextLevels, volume: volume)
    }

    // MARK: 总音量

    private var masterVolume: some View {
        HStack(spacing: 8) {
            Text(tr("总音量"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Slider(value: Binding(
                get: { volume },
                set: { value in
                    dragging = value
                    if !context.isPreview { player.apply(sounds: sounds, levels: levels, volume: value) }
                }), in: 0...100, onEditingChanged: { editing in
                    if !editing, let value = dragging {
                        save { $0.set("volume", .number(value.rounded())) }
                        dragging = nil
                    }
                })
                .controlSize(.small)
                .tint(accent)
                .disabled(context.isPreview)
            Text("\(Int(volume.rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.panelSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: 定时关闭

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(tr("定时关闭"))
            HStack(spacing: 6) {
                ForEach(AmbientTimer.choices, id: \.self) { minutes in timerChip(minutes) }
                customChip
            }
            if customOpen {
                HStack(spacing: 8) {
                    Stepper(value: $customMinutes, in: AmbientCustomTimer.range, step: AmbientCustomTimer.step) {
                        Text(AmbientTimer.title(customMinutes))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.panelPrimary)
                    }
                    Spacer(minLength: 0)
                    Button(tr("开始计时")) {
                        guard !context.isPreview else { return }
                        player.setTimer(minutes: AmbientCustomTimer.clamp(customMinutes))
                        customOpen = false
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func timerChip(_ minutes: Int) -> some View {
        chip(AmbientTimer.title(minutes), on: player.timerMinutes == minutes) {
            guard !context.isPreview else { return }
            customOpen = false
            player.setTimer(minutes: minutes)
        }
    }

    private var customChip: some View {
        let custom = AmbientCustomTimer.isCustom(player.timerMinutes)
        return chip(custom ? AmbientTimer.title(player.timerMinutes) : tr("自定义"), on: custom || customOpen) {
            guard !context.isPreview else { return }
            if custom { customMinutes = player.timerMinutes }
            customOpen.toggle()
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? .panelPrimary : .panelSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Capsule().fill(on ? Color.panelFillStrong : Color.panelFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 播放

    private var playButton: some View {
        Button {
            guard !context.isPreview else { return }
            player.toggle(sounds: sounds, levels: levels, volume: volume)
        } label: {
            Label(playing ? tr("暂停") : tr("播放"), systemImage: playing ? "pause.fill" : "play.fill")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Capsule().fill(.panelFillStrong))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(sounds.isEmpty)
        .accessibilityLabel(playing ? tr("暂停环境音") : tr("播放环境音"))
    }

    // MARK: 写设置

    /// 改设置：面板先用改过的，再写回小组件（拿最新存的那份改，不覆盖别处刚改的）。
    private func update(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        var next = config
        change(&next)
        edited = next
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance, change)
    }

    private func save(_ change: (inout WidgetConfig) -> Void) { update(change) }

    private var accent: Color {
        panelTint.accent(or: WidgetCatalog.accentHex(.ambient).map { Color(hex: $0) } ?? WidgetStyle.primary)
    }
}
