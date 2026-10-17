import SwiftUI

/// The pet big, how it is doing, its four needs, the four things to do for
/// it, the days in a row it was looked after, and who it is.
///
/// One page rather than tabs: everything here is glanced at together, and it
/// is short enough to sit beside its neighbours.
struct PetDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var accent: Color { PetStyle.accent }

    private var character: WaterCharacter {
        WaterCharacter.shown(instance.config, unlocked: Supporter.isUnlocked || context.isPreview)
    }

    var body: some View {
        // A schedule rather than `context.now`, which is frozen while the
        // panel is open: the needs run down, and an act lasts four seconds.
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: context.isPreview ? context.now : tick.date)
        }
    }

    private func content(now: Date) -> some View {
        let state = context.isPreview
            ? VirtualPet.sample(now: now)
            : VirtualPet.advanced(VirtualPet.state(instance.config, now: now), to: now)
        let melted = !context.isPreview && PetMelt.now
        let look = VirtualPet.look(state, now: now, dried: dried, melted: melted)
        return DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                hero(state, look: look, now: now, melted: melted)
                needs(state)
                if VirtualPet.isSick(state) { healButton }
                actions(state)
                Text("喝一杯水、完成一项习惯打卡或一轮专注，都会喂它一点；有几只宠物就每只都喂。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                notifyToggle
                dryToggle
                characterPicker
            }
        }
    }

    // MARK: Hero

    private func hero(_ state: PetState, look: PetLook, now: Date, melted: Bool) -> some View {
        let streak = VirtualPet.streak(state, today: now)
        return HStack(alignment: .center, spacing: 14) {
            PetFigure(character: character, look: look, height: 110,
                      effect: VirtualPet.effect(state, now: now))
            VStack(alignment: .leading, spacing: 3) {
                Text("电子宠物")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(character.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(VirtualPet.statusLine(state, now: now, dried: dried, melted: melted))
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(look == .sick || look == .hungry || look == .dried || look == .melted
                                     ? Color(hex: PaletteColor.red.hex).mix(with: .white, by: 0.25)
                                     : .white.opacity(0.85))
                Text("整体 \(Int(state.health.rounded()))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            Label("\(streak) 天", systemImage: "flame.fill")
                .font(WidgetStyle.label(11))
                .foregroundStyle(streak > 0 ? Color(hex: PaletteColor.orange.hex) : .white.opacity(0.45))
                .monospacedDigit()
                .help("连续照顾 \(streak) 天")
        }
    }

    // MARK: Needs

    private func needs(_ state: PetState) -> some View {
        VStack(spacing: 7) {
            ForEach(PetNeed.allCases) { need in
                HStack(spacing: 8) {
                    Image(systemName: need.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 14)
                    Text(need.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30, alignment: .leading)
                    PetBar(value: state[need], height: 6)
                    Text("\(Int(state[need].rounded()))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(need.title) \(Int(state[need].rounded()))")
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    // MARK: Actions

    private func actions(_ state: PetState) -> some View {
        HStack(spacing: 6) {
            ForEach(PetAction.buttons) { action in
                let title = action == .sleep && state.isSleeping ? "叫醒" : action.title
                let symbol = action == .sleep && state.isSleeping ? "sun.max.fill" : action.symbol
                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.3)) { PetLog.act(action, in: instance) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.55)))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(context.isPreview)
                .accessibilityLabel(title)
            }
        }
    }

    /// Shown only while it is sick, above the four, in red: the one thing
    /// that gets it better at once.
    private var healButton: some View {
        Button {
            guard !context.isPreview else { return }
            withAnimation(.snappy(duration: 0.3)) { PetLog.act(.heal, in: instance) }
        } label: {
            Label("带它看病", systemImage: PetAction.heal.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: PaletteColor.red.hex).opacity(0.8)))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help("生病了：看病后四项状态至少回到 \(Int(VirtualPet.healTo))")
    }

    @AppStorage(VirtualPet.missedDaysDefault) private var missedDays = 0

    private var dried: Bool {
        !context.isPreview && VirtualPet.isDried(instance.config, missedDays: missedDays)
    }

    private var dryToggle: some View {
        Toggle(isOn: Binding(
            get: { instance.config.bool(VirtualPet.dryKey) },
            set: { on in
                guard !context.isPreview else { return }
                PetLog.set(VirtualPet.dryKey, .bool(on), in: instance)
            })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("喝水不达标会渴成骷髅")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                Text("喝水小组件连续 \(VirtualPet.dryDays) 天没喝够，它就变成骷髅；喝够一天马上复活。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private var notifyToggle: some View {
        Toggle(isOn: Binding(
            get: { instance.config.bool("notify") },
            set: { on in
                guard !context.isPreview else { return }
                PetLog.set("notify", .bool(on), in: instance)
            })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("需要照顾时通知")
                    .font(WidgetStyle.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                Text("饿了、脏了、困了或生病时发一条通知，夜里不打扰。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    // MARK: Character

    /// Six faces in a row, as in 喝水; the chosen one sits on the accent.
    private var characterPicker: some View {
        let chosen = character
        return VStack(alignment: .leading, spacing: 6) {
            Text("角色")
                .font(WidgetStyle.label(12))
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 4) {
                ForEach(WaterCharacter.allCases) { option in
                    let selected = option == chosen
                    let locked = option.isSupporterOnly && !Supporter.isUnlocked && !context.isPreview
                    Button {
                        guard !context.isPreview else { return }
                        if locked { SponsorWindow.shared.show(); return }
                        withAnimation(.snappy(duration: 0.25)) {
                            PetLog.set("character", .string(option.rawValue), in: instance)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            PetFigure(character: option, look: .idle, height: 28)
                                .opacity(locked ? 0.55 : 1)
                                .overlay(alignment: .topTrailing) {
                                    if locked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(2.5)
                                            .background(Circle().fill(Color(hex: ShelfColor.redPanda.hex)))
                                    }
                                }
                            Text(option.title)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? accent.opacity(0.75) : Color.white.opacity(0.08)))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(context.isPreview)
                    .help(locked ? "\(option.title)（赞助者专属）" : option.title)
                    .accessibilityLabel(locked ? "角色：\(option.title)，赞助者专属" : "角色：\(option.title)")
                }
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }
}
