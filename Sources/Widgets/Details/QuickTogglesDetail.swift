import SwiftUI

/// 快速开关面板（效果图 panel-practicality-a 第 1 列「改后」），两个状态：
///
/// - 浏览：卡片上那几个开关的大按钮，三列，每个写名字和状态（开、关、保持唤醒
///   剩多久、一次性动作点了会怎样），点了就生效，和点卡片圆钮一样。下面「保持
///   唤醒多久」：30 分钟、1 小时、2 小时、一直，存在卡片的 `keepAwakeFor`，正开着
///   时从现在起按新时长重新计。
/// - 编辑：21 个开关的「可拖动勾选列表」（`ReorderableChecklist`），勾选决定卡片
///   上有哪些，拖动排序；最下面「卡片圆钮下显示名字」。
///
/// 5 个 Pro 工具照旧：没解锁时大按钮画暗、带 Pro 标识，点了弹付费墙；勾选时也弹。
struct QuickTogglesDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing = false

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.panelTint) private var panelTint

    static let accentHex = "#FFB547"
    static let accentInkHex = "#2E1A00"

    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var ink: Color { panelTint.ink(or: Color(hex: Self.accentInkHex)) }
    private var unlocked: Bool { licenseUnlocked || supporter || context.isPreview }

    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var actions: QuickActions { QuickActions.shared }
    private var chosen: [QuickToggle] { QuickToggle.chosen(current.config) }
    private var awakeMinutes: Int { KeepAwakeTimer.minutes(current.config) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        // 每 30 秒重画一次，保持唤醒的剩余时间跟着走。
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            DetailCard {
                ZStack {
                    Color(hex: SystemActivityStyle.base)
                    RadialGradient(colors: [accent.opacity(0.13), .clear],
                                   center: UnitPoint(x: 0.95, y: 0), startRadius: 0, endRadius: 200)
                }
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if editing { edit } else { browse(now: tick.date) }
                }
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tr("快速开关"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(verbatim: editing ? tr("勾选 + 拖动排序 · \(QuickToggle.allCases.count) 个可选")
                     : tr("\(chosen.count) 个开关 · 点一下就生效"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !context.isPreview {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { editing.toggle() }
                } label: {
                    Text(verbatim: editing ? tr("完成") : tr("编辑"))
                        .font(.system(size: 13, weight: editing ? .bold : .semibold))
                        .foregroundStyle(editing ? ink : .white.opacity(0.92))
                        .padding(.horizontal, editing ? 15 : 13)
                        .frame(height: 28)
                        .background(Capsule().fill(editing ? accent : .white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(.white.opacity(editing ? 0 : 0.18), lineWidth: 0.6))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 浏览

    private func browse(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 21 个全勾上也只占三行半左右的高度，多出来的在格子里滚。
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(chosen) { toggle in bigButton(toggle, now: now) }
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: chosen.count > 9 ? 300 : nil)
            .fixedSize(horizontal: false, vertical: chosen.count <= 9)

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: tr("保持唤醒多久"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                HStack(spacing: 6) {
                    ForEach(KeepAwakeTimer.choices, id: \.self) { minutes in durationChip(minutes) }
                }
            }
        }
    }

    private func bigButton(_ toggle: QuickToggle, now: Date) -> some View {
        let on = !context.isPreview && toggle.hasState && actions.isOn(toggle)
        let locked = !ProLicenseGate.canUseTool(toggle, isOn: on, unlocked: unlocked)
        let state = locked ? ProFeatures.label
            : (toggle == .keepAwake && on ? KeepAwakeTimer.remaining(until: actions.keepAwakeUntil, now: now, minutesOnly: true)
               : toggle.caption(on: on))
        return Button {
            guard !context.isPreview else { return }
            if locked {
                PaywallWindow.shared.show()
            } else if toggle == .keepAwake {
                actions.toggleKeepAwake(minutes: awakeMinutes)
            } else {
                actions.perform(toggle)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: toggle.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? ink : .white.opacity(locked ? 0.5 : 0.95))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(on ? accent : .white.opacity(0.14)))
                    Spacer(minLength: 0)
                    if ProFeatures.isProTool(toggle.rawValue) { ProBadge() }
                }
                Spacer(minLength: 6)
                Text(verbatim: toggle.panelTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(locked ? 0.6 : 1))
                    .lineLimit(1)
                    // 中文在 13pt 下放得下（见 `panelTitle`），英文名字长时才缩一点。
                    .minimumScaleFactor(0.85)
                Text(verbatim: state)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? accent : .white.opacity(0.62))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(on ? accent.opacity(0.2) : .white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(on ? accent.opacity(0.75) : .white.opacity(0.14), lineWidth: on ? 1 : 0.6))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(locked ? tr("\(toggle.title)：码头 Pro 专属，点一下解锁") : tr("\(toggle.title)：\(toggle.help)"))
        .accessibilityLabel(toggle.title)
        .accessibilityValue(state)
    }

    private func durationChip(_ minutes: Int) -> some View {
        let selected = awakeMinutes == minutes
        return Button {
            guard !context.isPreview, !selected else { return }
            WidgetWriter.write(current) { $0.set(KeepAwakeTimer.key, .string(String(minutes))) }
            actions.changeKeepAwakeDuration(minutes: minutes)
        } label: {
            Text(verbatim: KeepAwakeTimer.title(minutes))
                .font(.system(size: 13, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? ink : .white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Capsule().fill(selected ? accent : .white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0 : 0.14), lineWidth: 0.6))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 编辑

    private var edit: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical) {
                ReorderableChecklist(
                    choices: QuickToggle.allCases.map {
                        ReorderableChecklist.Choice(value: $0.rawValue, title: $0.title,
                                                    isPro: ProFeatures.isProTool($0.rawValue))
                    },
                    saved: chosen.map(\.rawValue),
                    look: .panel(accent: accent, ink: ink),
                    canEnable: { value in
                        guard ProLicenseGate.canEnableListChoice(key: QuickToggle.key, value: value, unlocked: unlocked) else {
                            PaywallWindow.shared.show()
                            return false
                        }
                        return true
                    },
                    write: { list in
                        WidgetWriter.write(current) { $0.set(QuickToggle.key, .list(list.map { .string($0) })) }
                    })
            }
            .frame(height: 340)

            Toggle(isOn: Binding(
                get: { QuickToggle.showsNames(current.config) },
                set: { on in WidgetWriter.write(current) { $0.set(QuickToggle.showNamesKey, .bool(on)) } })) {
                Text(verbatim: tr("卡片圆钮下显示名字"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
            }
            .toggleStyle(.switch)
            .tint(accent)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.06)))
        }
    }
}
