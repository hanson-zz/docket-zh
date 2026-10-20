import Foundation
import SwiftUI

/// 喝水：今天喝了多少。三种样式各管一件事（见 `WaterLayout`）：
///
/// - 圆环（免费，新放的默认）：Codex 卡片那种进度环，环心是百分比，旁边
///   “1200 / 2000 毫升”。超过目标时画第二圈。
/// - 角色（Pro）：主角是选的角色（默认小熊猫），按今天的进度换姿势
///   （还渴着、小口喝着、快喝饱了、达标啦，见 `WaterPose`），下面八节竹子
///   是进度；不再画杯子涨水。提醒时段里 2 小时没喝“渴了”，5 小时渴成骷髅
///   （见 `WaterParched`）。点 + 时角色举起竹筒喝一口约 0.8 秒并飘一个 +N。
/// - 液态（Pro）：整张卡片是一杯水，水更浓、有气泡，点 + 时水面晃一下溅
///   几颗水珠，满了顶上一道高光。没有角色。
///
/// 没解锁时角色和液态都画成圆环、不盖锁，配置照旧存着，解锁或试用时自动
/// 回来（见 `ProLicenseGate.waterLayout`）。三种样式一样大。
///
/// Like the other reminder tiles, the "+" is the only control: it logs one
/// cup of water (`cupSize`), and the card's own click opens the panel, where
/// other amounts and drinks, the day's list, the goal and the history live.
///
/// 提醒不再由卡片排：`TimedAlertDriver` 从启动起每秒看着所有布局里的喝水小组件，
/// 交给 `WaterNotifier` 排，卡片在文件夹里、别的布局里也照样提醒。
struct WaterTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // 和时间进度一样读 @AppStorage：购买或试用到期时卡片马上换样式，不用等下次重绘。
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporterUnlocked = false

    /// 点 + 后飘起的量（显示用的数字），nil 时不飘；角色同时举起竹筒喝一口。
    @State private var gulp: String?
    /// 每点一次 + 加一，晚到的收尾不会把下一次的那一帧提前收掉。
    @State private var gulpToken = 0

    private var unlocked: Bool { licenseUnlocked || supporterUnlocked || context.isPreview }

    /// 实际画的样式：角色和液态是 Pro，没解锁时退回圆环（预览照常画）。
    private var layout: WaterLayout { ProLicenseGate.waterLayout(config: instance.config, unlocked: unlocked) }
    /// 很久没喝或进度很低时角色渴成骷髅（见 `WaterParched`），喝一杯就复活。
    private var parched: Bool {
        !context.isPreview && WaterParched.isParched(instance.config, now: context.now)
    }
    /// 只有角色样式画骷髅。
    private var showsSkeleton: Bool { layout == .character && parched }
    private var ounces: Bool { WaterIntake.usesOunces(instance.config) }
    /// The library's preview draws the sample week against its own 2000 ml.
    private var goal: Int {
        context.isPreview ? WaterIntake.defaultGoal : WaterIntake.goal(instance.config, now: context.now)
    }
    /// A locked Pro 专属 character is drawn as the red panda; the library's
    /// preview shows the real one, as the clock's supporter faces do.
    private var character: WaterCharacter {
        WaterCharacter.shown(instance.config, unlocked: unlocked)
    }

    /// Re-read every tick: the liquid's surface glows gold for the few seconds
    /// after the drink that meets the goal.
    private var mood: WaterMood {
        context.isPreview ? .idle : WaterMood.at(context.now, config: instance.config)
    }

    /// 液态水面晃一下的起点：最近一次记录的时刻（`WaterLog.drink` 写的 loggedAt）。
    private var loggedAt: Date? {
        guard !context.isPreview else { return nil }
        let seconds = instance.config.double("loggedAt")
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    private var today: WaterDay {
        if context.isPreview {
            return WaterIntake.today(WaterSamples.days(today: context.now), goal: goal, now: context.now)
        }
        return WaterIntake.today(instance.config, now: context.now)
    }

    private var missedDays: Int {
        WaterIntake.missedDays(WaterIntake.days(instance.config), goal: goal, today: context.now)
    }

    private func publishMissed() {
        guard !context.isPreview else { return }
        UserDefaults.standard.set(missedDays, forKey: VirtualPet.missedDaysDefault)
    }

    /// 角色这一刻的样子：分档、渴了、骷髅，或刚点了 + 的那一帧。
    private func look(_ day: WaterDay) -> WaterPose.Look {
        let stage = WaterPose.stage(total: day.total, goal: day.goal)
        let dry = context.isPreview ? nil : WaterPose.dryHours(instance.config, now: context.now)
        return WaterPose.look(stage: stage, dryHours: dry, parched: parched, gulping: gulp != nil)
    }

    var body: some View {
        let day = today
        let done = day.isMet
        // 圆环超过目标时画第二圈。
        let lap = RingLap.progress(total: day.total, goal: day.goal)
        return WidgetSurface {
            Group {
                switch layout {
                case .liquid:
                    liquid(day, done: done)
                case .character:
                    if context.position.isVertical { characterColumn(day) } else { characterWide(day) }
                case .ring:
                    if context.position.isVertical { ringColumn(day, lap: lap, done: done) } else { ringWide(day, lap: lap, done: done) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("喝水，\(showsSkeleton ? tr("渴成骷髅了，") : "")\(WaterIntake.tally(total: day.total, goal: day.goal, ounces: ounces))"))
        // The pet's 渴成骷髅 reads this; written from here so it needs no
        // way to find the 喝水 widget itself.
        .onAppear {
            publishMissed()
            if !context.isPreview { WaterLog.migrateLegacyFactor(instance) }
        }
        .onChange(of: missedDays) { _, _ in publishMissed() }
    }

    // MARK: 圆环

    private func ringWide(_ day: WaterDay, lap: Double, done: Bool) -> some View {
        HStack(spacing: 10) {
            ring(level: lap, done: done, diameter: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(WaterIntake.figure(day.total, ounces: ounces)) / \(WaterIntake.figure(day.goal, ounces: ounces))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(day.total)
                Text(done ? tr("今天达标啦")
                     : "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                    .font(.system(size: 12))
                    .foregroundStyle(done ? WaterStyle.water : WidgetStyle.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            drinkButton(size: 12)
        }
    }

    /// 竖排 56pt 宽：圆环、数字、目标（11pt）、+。
    private func ringColumn(_ day: WaterDay, lap: Double, done: Bool) -> some View {
        VStack(spacing: 3) {
            ring(level: lap, done: done, diameter: 34)
            VStack(spacing: 0) {
                Text(WaterIntake.figure(day.total, ounces: ounces))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(day.total)
                Text(done ? tr("达标啦") : "/ \(WaterIntake.figure(day.goal, ounces: ounces))")
                    .font(WidgetStyle.caption(11))
                    .foregroundStyle(done ? WaterStyle.water : WidgetStyle.secondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            drinkButton(size: 10)
        }
    }

    // MARK: 角色

    /// 角色在左，右边大数字和目标、八节竹子、一句状态，最右是 +。
    private func characterWide(_ day: WaterDay) -> some View {
        let pose = look(day)
        let stage = WaterPose.stage(total: day.total, goal: day.goal)
        return HStack(spacing: 8) {
            WaterPoseFigure(character: character, look: pose, height: 44, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(WaterIntake.figure(day.total, ounces: ounces))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .rollingValue(day.total)
                    Text("/\(WaterIntake.figure(day.goal, ounces: ounces))")
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                }
                BambooRow(filled: WaterPetCards.filledCups(total: day.total, goal: day.goal),
                          slots: WaterPose.bambooSlots, segment: 6.5, spacing: 2.5)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: day.total)
                Text(WaterPose.caption(pose, stage: stage))
                    .font(.system(size: 11, weight: pose == .stage(.done) ? .semibold : .regular))
                    .foregroundStyle(captionColor(pose))
                    .contentTransition(.opacity)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            drinkButton(size: 12)
        }
    }

    /// 竖排 56pt 宽：角色、数字、八节竹子、+。
    private func characterColumn(_ day: WaterDay) -> some View {
        VStack(spacing: 3) {
            WaterPoseFigure(character: character, look: look(day), height: 36, reduceMotion: reduceMotion)
            Text(WaterIntake.figure(day.total, ounces: ounces))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .rollingValue(day.total)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            BambooRow(filled: WaterPetCards.filledCups(total: day.total, goal: day.goal),
                      slots: WaterPose.bambooSlots, segment: 4.5, spacing: 1.5)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: day.total)
            drinkButton(size: 10)
        }
    }

    private func captionColor(_ look: WaterPose.Look) -> Color {
        switch look {
        case .stage(.done): Color(hex: PaletteColor.yellow.hex)
        case .dry, .parched: Color(hex: "#FF8A80")
        default: WidgetStyle.secondary
        }
    }

    // MARK: 液态

    /// 整张卡片是一杯水：水位是今天的进度，满了水面盖过上沿、顶上一道高光，
    /// 达标的那一刻起水面闪几秒金光。点 + 时水面晃一下溅几颗水珠。数字和 +
    /// 浮在水上，白字带一圈淡黑描边，水多水少都看得清。
    private func liquid(_ day: WaterDay, done: Bool) -> some View {
        let level = LiquidLooks.waterLevel(total: day.total, goal: day.goal)
        let vertical = context.position.isVertical
        return ZStack {
            // 液态的水用卡片的颜色主题（喝水默认青蓝，见 `WidgetTint`）。
            LiquidWater(level: level, tint: theme?.main(dark: scheme == .dark) ?? WaterStyle.water,
                        visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen,
                        golden: done && mood == .drink, shine: true, bubbles: vertical ? 4 : 6,
                        density: LiquidLooks.waterDensity, sloshAt: loggedAt,
                        splashOrigin: LiquidLooks.waterSplashOrigin(vertical: vertical),
                        fullHighlight: true)
                .fillingCard()
            if vertical {
                VStack(spacing: 3) {
                    Text(WaterIntake.figure(day.total, ounces: ounces))
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .rollingValue(day.total)
                        .liquidInk()
                    Text(done ? tr("达标啦") : "\(WaterIntake.percent(total: day.total, goal: day.goal))%")
                        .font(WidgetStyle.caption(11))
                        .monospacedDigit()
                        .liquidInk(0.85)
                    drinkButton(size: 10, onWater: true)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(WaterIntake.figure(day.total, ounces: ounces)) / \(WaterIntake.figure(day.goal, ounces: ounces))")
                            .font(.system(size: 17, weight: .semibold))
                            .monospacedDigit()
                            .rollingValue(day.total)
                            .liquidInk()
                        Text(done ? tr("今天达标啦") : "\(WaterIntake.unitLabel(ounces: ounces)) · \(WaterIntake.percent(total: day.total, goal: day.goal))%")
                            .font(.system(size: 12))
                            .liquidInk(0.85)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    drinkButton(size: 12, onWater: true)
                }
            }
        }
    }

    // MARK: Pieces

    /// The Codex tile's ring, in the water's blue, with the percentage inside;
    /// a check when the day is done. 超过目标时不封顶：满圈上面再画第二圈，
    /// `level` 是不封顶的进度（见 `RingLap`）。
    private func ring(level: Double, done: Bool, diameter: CGFloat) -> some View {
        let tint = WaterStyle.water
        return MetricProgressRing(progress: level, tint: tint, track: tint.opacity(0.16),
                                  diameter: diameter, lineWidth: diameter > 36 ? 4.5 : 4,
                                  laps: true) {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.32, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: done)
            } else {
                Text("\(min(99, Int((level * 100).rounded(.down))))")
                    .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
    }

    /// One cup of water. The number rolling (and the character's sip, the
    /// liquid's slosh) is the confirmation, so the write is animated rather
    /// than the press. 角色和液态另外飘一个 +N；减少动态效果时不飘、不举竹筒。
    private func drinkButton(size: CGFloat, onWater: Bool = false) -> some View {
        let cup = WaterIntake.cupSize(instance.config)
        return TileGlyph(symbol: "plus", size: size, tint: onWater ? .white : WaterStyle.water,
                         action: context.isPreview ? nil : {
            withAnimation(.snappy(duration: 0.35)) {
                WaterLog.drink(.water, amount: cup, in: instance)
            }
            if layout != .ring, !reduceMotion { startGulp(WaterIntake.figure(cup, ounces: ounces)) }
        })
        .overlay(alignment: .top) {
            if let gulp {
                Text("+\(gulp)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(WaterStyle.water))
                    .fixedSize()
                    .offset(y: -size * 1.55)
                    .transition(.asymmetric(insertion: .offset(y: 6).combined(with: .opacity),
                                            removal: .offset(y: -6).combined(with: .opacity)))
                    .allowsHitTesting(false)
            }
        }
        .help(tr("喝了一杯水（\(WaterIntake.amount(cup, ounces: ounces))）"))
        .accessibilityLabel(tr("记录一杯水，\(WaterIntake.amount(cup, ounces: ounces))"))
    }

    /// 举起竹筒喝一口那一帧，约 0.8 秒后回到当前档位。
    private func startGulp(_ amount: String) {
        gulpToken += 1
        let token = gulpToken
        withAnimation(.easeOut(duration: 0.18)) { gulp = amount }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(WaterPose.gulpSeconds))
            guard token == gulpToken else { return }
            withAnimation(.easeIn(duration: 0.25)) { gulp = nil }
        }
    }
}

/// 角色样式的角色：按 `WaterPose.Look` 换图，换的时候淡入淡出。图都用原来
/// 宠物和喝水的那几张，小熊猫多两张抱竹筒的（`pet-panda-sip`、`pet-panda-drink`）。
/// 框按最宽的角色图留（宽是高的 0.95），换姿势时旁边的字不会挪。
struct WaterPoseFigure: View {
    var character: WaterCharacter
    var look: WaterPose.Look
    var height: CGFloat
    var reduceMotion: Bool

    private var isDry: Bool {
        if case .dry = look { return true }
        return false
    }

    var body: some View {
        let name = WaterPose.imageName(character, look)
        ZStack(alignment: .bottom) {
            if let image = WaterArt.named(name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // 渴了：口渴图降饱和、略压暗，像打蔫。
                    .saturation(isDry ? 0.45 : 1)
                    .brightness(isDry ? -0.06 : 0)
                    .id(name)
                    .transition(.opacity)
            } else {
                // 截图工具里没有图：一滴水代替。
                Image(systemName: "drop.fill")
                    .font(.system(size: height * 0.6))
                    .foregroundStyle(WaterStyle.water)
            }
        }
        .frame(width: height * 0.95, height: height, alignment: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: name)
        .overlay(alignment: .topLeading) {
            if isDry {
                Text(WaterPose.dryBubble)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                    .fixedSize()
                    .offset(x: -2, y: -3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            // 小熊猫达标那张图没有彩带，补几条；其他角色的欢呼图自带。
            if look == .stage(.done), character == .redPanda {
                Confetti(reduceMotion: reduceMotion)
                    .frame(width: height * 1.05, height: height * 0.5)
                    .offset(y: -height * 0.08)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 达标时小熊猫头上几条小彩带，慢慢闪；减少动态效果时不动。
private struct Confetti: View {
    var reduceMotion: Bool

    private static let pieces: [(x: CGFloat, y: CGFloat, angle: Double, hex: String)] = [
        (0.08, 0.55, -30, "#FFD36B"), (0.22, 0.15, 25, "#FF7AA2"), (0.4, 0.0, -10, "#6FDC9A"),
        (0.62, 0.05, 35, "#7FC4E8"), (0.8, 0.2, -25, "#FFD36B"), (0.94, 0.6, 15, "#FF7AA2"),
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Self.pieces.indices, id: \.self) { index in
                let piece = Self.pieces[index]
                Capsule()
                    .fill(Color(hex: piece.hex))
                    .frame(width: 1.8, height: 4.5)
                    .rotationEffect(.degrees(piece.angle))
                    .position(x: piece.x * proxy.size.width, y: piece.y * proxy.size.height)
            }
        }
        .phaseAnimator(reduceMotion ? [false] : [false, true]) { view, up in
            view.opacity(up ? 1 : 0.65).offset(y: up ? -1 : 0.5)
        } animation: { _ in .easeInOut(duration: 0.9) }
    }
}

/// 八节竹子：喝够的那几节是竹子的绿，带一道竹节；没到的淡淡一节空的。
struct BambooRow: View {
    var filled: Int
    var slots: Int
    /// 一节的宽度，高是宽的 1.3 倍。
    var segment: CGFloat
    var spacing: CGFloat

    private static let green = Color(hex: "#86C26A")
    private static let node = Color(hex: "#4F8B3C")

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<slots, id: \.self) { index in
                let full = index < filled
                let shape = RoundedRectangle(cornerRadius: segment * 0.28, style: .continuous)
                shape
                    .fill(full ? Self.green : WidgetStyle.primary.opacity(0.1))
                    .overlay(alignment: .top) {
                        // 竹节：上面三成处一道深色细线。
                        Rectangle()
                            .fill(full ? Self.node : WidgetStyle.primary.opacity(0.14))
                            .frame(height: max(0.8, segment * 0.14))
                            .padding(.top, segment * 1.3 * 0.3)
                    }
                    .overlay(shape.stroke(WidgetStyle.primary.opacity(full ? 0 : 0.14), lineWidth: 0.6))
                    .clipShape(shape)
                    .frame(width: segment, height: segment * 1.3)
            }
        }
        .accessibilityHidden(true)
    }
}

private extension View {
    /// 浮在液态水上的白字：一圈淡黑描边（阴影），水多水少都看得清。
    func liquidInk(_ opacity: Double = 1) -> some View {
        foregroundStyle(Color.white.opacity(opacity))
            .shadow(color: .black.opacity(0.3), radius: 0.8)
    }
}

/// The writes the tile and the panel both make, from the instance's current
/// log so the two can never disagree.
@MainActor
enum WaterLog {
    static func change(_ instance: WidgetInstance, _ edit: ([WaterDay], Int) -> [WaterDay]) {
        WidgetWriter.write(instance) { config in
            WaterIntake.store(edit(WaterIntake.days(config), WaterIntake.goal(config)), in: &config)
            pruneDrinks(&config)
        }
    }

    static func drink(_ type: DrinkType, amount: Int, factor: Double? = nil, drinkID: String? = nil,
                      in instance: WidgetInstance) {
        let now = Date.now
        WidgetWriter.write(instance) { config in
            let days = WaterIntake.logging(type, amount: amount, factor: factor, drinkID: drinkID,
                                           in: WaterIntake.days(config), goal: WaterIntake.goal(config), now: now)
            WaterIntake.store(days, in: &config, now: now)
            pruneDrinks(&config)
            noteEarned(&config, now: now)
            // The log keeps minutes; the cup in the character's paws needs the second.
            config.set("loggedAt", .number(now.timeIntervalSince1970))
            // A drink answers a hand-picked reminder; the schedule resumes.
            config.set(WaterReminder.overrideKey, nil)
        }
        PetTreats.give(.water)
    }

    static func undo(_ instance: WidgetInstance) {
        change(instance) { days, goal in WaterIntake.undoingLast(in: days, goal: goal, now: .now) }
    }

    static func remove(at index: Int, in instance: WidgetInstance) {
        change(instance) { days, goal in WaterIntake.removing(at: index, in: days, goal: goal, now: .now) }
    }

    /// A goal picked by hand, replacing the recommendation.
    static func setGoal(_ goal: Int, in instance: WidgetInstance) {
        profile(instance) { config, _ in WaterGoal.settingManual(goal, in: &config) }
    }

    /// 恢复推荐: the hand-picked goal goes, the recommendation is back.
    static func useRecommended(in instance: WidgetInstance) {
        profile(instance) { config, _ in WaterGoal.followingRecommendation(in: &config) }
    }

    /// Changes something the goal is worked out from, then moves today's
    /// stored goal along with it so the day is frozen at the right number
    /// once it is over. Finished days are left alone.
    static func profile(_ instance: WidgetInstance, _ edit: (inout WidgetConfig, Date) -> Void) {
        let now = Date.now
        WidgetWriter.write(instance) { config in
            edit(&config, now)
            let goal = WaterIntake.goal(config, now: now)
            WaterIntake.store(WaterIntake.settingGoal(goal, in: WaterIntake.days(config), now: now),
                              in: &config, now: now)
            // A lower goal can make today count.
            noteEarned(&config, now: now)
        }
    }

    /// The key the panel reads to say, once, that a character was just
    /// earned. A line in the panel rather than a notification.
    static let earnedNoticeKey = "earnedNotice"

    /// Writes down any character the log has just earned and leaves every
    /// one of them for the panel to mention (a long-time drinker can earn the
    /// shiba and the cat with the same cup).
    private static func noteEarned(_ config: inout WidgetConfig, now: Date) {
        let fresh = WaterCharacter.recordingEarned(in: &config, now: now)
        guard !fresh.isEmpty else { return }
        let text = WaterCharacter.addingNotices(fresh, to: config.string(earnedNoticeKey))
        config.set(earnedNoticeKey, text.map(WidgetConfig.Value.string))
    }

    /// 旧版的通用「自定义」比例迁成一个饮料，只做一次。
    static func migrateLegacyFactor(_ instance: WidgetInstance) {
        guard instance.config[CustomDrinks.legacyFactorKey] != nil else { return }
        WidgetWriter.write(instance) { config in
            CustomDrinks.migratingLegacyFactor(in: &config, name: tr("自定义"))
        }
    }

    /// Removed drinks the log no longer names go.
    private static func pruneDrinks(_ config: inout WidgetConfig) {
        let drinks = CustomDrinks.all(config)
        let kept = CustomDrinks.pruned(drinks, days: WaterIntake.days(config))
        if kept != drinks { CustomDrinks.store(kept, in: &config) }
    }

    /// Adds, changes or removes one of the user's own drinks.
    static func editDrinks(_ instance: WidgetInstance, _ edit: ([CustomDrink], [WaterDay]) -> [CustomDrink]) {
        WidgetWriter.write(instance) { config in
            CustomDrinks.store(edit(CustomDrinks.all(config), WaterIntake.days(config)), in: &config)
        }
    }

    static func set(_ key: String, _ value: WidgetConfig.Value?, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(key, value) }
    }

    /// 复位: the personal details, the hand-picked goal and the reminder
    /// schedule back to the defaults, so the goal follows the recommendation
    /// again. The drink log, the character and the unit stay.
    static func resetSettings(in instance: WidgetInstance) {
        let defaults = WidgetCatalog.entry(.water)?.defaults ?? WidgetConfig()
        profile(instance) { config, _ in
            for key in ["remindEvery", "start", "end", "cupSize"] {
                config.set(key, defaults[key])
            }
            for key in WaterGoal.Key.profile { config.set(key, nil) }
            WaterGoal.followingRecommendation(in: &config)
            config.set(WaterReminder.overrideKey, nil)
        }
    }
}

/// What the library and the screenshots show: a believable morning and a
/// fortnight behind it, anchored to the day being drawn.
enum WaterSamples {
    static func days(today: Date) -> [WaterDay] {
        let calendar = WaterIntake.calendar
        let key = HabitTracker.dayKey(today, calendar: calendar)
        var days = [WaterDay(key: key, goal: 2000, entries: [
            WaterEntry(minute: 8 * 60 + 40, type: .water, amount: 300),
            WaterEntry(minute: 10 * 60 + 15, type: .coffee, amount: 250),
            WaterEntry(minute: 12 * 60 + 5, type: .water, amount: 500),
            WaterEntry(minute: 14 * 60 + 30, type: .tea, amount: 222),
        ])]
        let totals = [2100, 2350, 1600, 2000, 2250, 1900, 2400, 2050, 1200, 2200, 2000, 2300, 1750]
        for (back, total) in totals.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: -(back + 1), to: today) else { continue }
            days.append(WaterDay(key: HabitTracker.dayKey(date, calendar: calendar), goal: 2000, summary: total))
        }
        return days.sorted { $0.key < $1.key }
    }
}
