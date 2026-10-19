import AppKit
import SwiftUI
@preconcurrency import UserNotifications

/// 电子宠物：它过得怎么样。角色是主角，放大到约 54pt 占满卡片高度，旁边一行
/// 名字和状态，下面四个需求小格（饱食、心情、精力、清洁）两两一排，每格一条
/// 小进度条；最要紧的那一格标红。点一格直接喂、玩、睡（睡着时叫醒）、洗，
/// 卡片别的地方照旧打开面板，看病、提醒和换角色在面板里。喝水那边杯子才是
/// 主角，两张卡片不再长得一样（见 `WaterPetCards`）。
///
/// The tile is also where treats from elsewhere in 码头 arrive: a glass of
/// water, a habit checked off or a focus session that ran out (noticed by
/// `PetFocusWatcher` whether or not a pet is showing) leaves one in
/// `PetTreats`, and every pet picks up each one once. Picking them up here
/// rather than at the source keeps 喝水 and 习惯打卡 knowing nothing about the
/// pet beyond dropping a note in a box.
struct PetTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var character: WaterCharacter {
        WaterCharacter.petShown(instance.config, unlocked: ProAccess.isUnlocked || context.isPreview)
    }

    @AppStorage(VirtualPet.missedDaysDefault) private var missedDays = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dried: Bool {
        !context.isPreview && VirtualPet.isDried(instance.config, missedDays: missedDays)
    }

    /// 热化了：Mac 过热、CPU 一直很忙或外面太热，见 `PetHeat`。
    private var melted: Bool {
        !context.isPreview && PetMelt.now
    }

    private var state: PetState {
        if context.isPreview { return VirtualPet.sample(now: context.now) }
        return VirtualPet.advanced(VirtualPet.state(instance.config, now: context.now), to: context.now)
    }

    var body: some View {
        let s = state
        let look = VirtualPet.look(s, now: context.now, dried: dried, melted: melted)
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(s, look: look)
                } else {
                    wide(s, look: look)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("电子宠物\(character.title)，\(VirtualPet.statusLine(s, now: context.now, dried: dried, melted: melted))"))
        .onAppear { collectTreats() }
        .onChange(of: context.now) { _, _ in collectTreats() }
        // Rescheduled when the stored state changes (something was done for
        // it) or the reminder is switched; not every second.
        .task(id: alertKey) { scheduleAlert() }
    }

    private var alertKey: String {
        "\(instance.config.double("at"))|\(instance.config.bool("notify"))|\(character.rawValue)"
    }

    private func scheduleAlert() {
        guard !context.isPreview else { return }
        guard instance.config.bool("notify") else {
            PetNotifier.shared.update(instance, alert: nil, name: character.title)
            return
        }
        let now = Date.now
        let alert = VirtualPet.nextAlert(VirtualPet.state(instance.config, now: now), after: now)
        PetNotifier.shared.update(instance, alert: alert, name: character.title)
    }

    private func wide(_ s: PetState, look: PetLook) -> some View {
        let urgent = WaterPetCards.mostNeeded(s)
        return HStack(spacing: 6) {
            PetFigure(character: character, look: look, height: 54,
                      effect: VirtualPet.effect(s, now: context.now))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(character.title) · \(VirtualPet.statusLine(s, now: context.now, dried: dried, melted: melted))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PetStyle.headline(look: look, health: s.health))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    GridRow {
                        needCell(.food, s, urgent: urgent)
                        needCell(.mood, s, urgent: urgent)
                    }
                    GridRow {
                        needCell(.energy, s, urgent: urgent)
                        needCell(.clean, s, urgent: urgent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 竖排 56pt 宽：角色、一行状态、四个小格两两一排（只画图标）。
    private func column(_ s: PetState, look: PetLook) -> some View {
        let urgent = WaterPetCards.mostNeeded(s)
        return VStack(spacing: 4) {
            PetFigure(character: character, look: look, height: 40,
                      effect: VirtualPet.effect(s, now: context.now))
            Text(VirtualPet.statusLine(s, now: context.now, dried: dried, melted: melted))
                .font(WidgetStyle.caption(9))
                .foregroundStyle(PetStyle.tint(look: look, health: s.health))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    needCell(.food, s, urgent: urgent, compact: true)
                    needCell(.mood, s, urgent: urgent, compact: true)
                }
                GridRow {
                    needCell(.energy, s, urgent: urgent, compact: true)
                    needCell(.clean, s, urgent: urgent, compact: true)
                }
            }
        }
    }

    /// 一个需求小格：名字（竖排时是图标）和一条小进度条，点一下做对应的事。
    /// 添加面板的预览里只画不点。
    private func needCell(_ need: PetNeed, _ s: PetState, urgent: PetNeed?, compact: Bool = false) -> some View {
        let action = WaterPetCards.action(for: need)
        let hot = need == urgent
        let red = Color(hex: PaletteColor.red.hex)
        let label = Group {
            if compact {
                // 竖排太窄放不下进度条：只画图标，颜色就是这一项的高低。
                Image(systemName: need.symbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(hot ? red : PetStyle.level(s[need]))
            } else {
                HStack(spacing: 4) {
                    Text(need.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(hot ? red : WidgetStyle.primary.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                    PetBar(value: s[need], height: 3.5, tint: hot ? red : nil)
                }
                .padding(.horizontal, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 14 : 17)
        .background(RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous)
            .fill(hot ? red.opacity(0.16) : WidgetStyle.primary.opacity(0.07)))
        .contentShape(.rect)
        return Group {
            if context.isPreview {
                label
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { PetLog.act(action, in: instance) }
                } label: { label }
                .buttonStyle(.plain)
            }
        }
        .help(WaterPetCards.cellHelp(need, state: s))
        .accessibilityLabel(WaterPetCards.cellHelp(need, state: s))
    }

    private func collectTreats() {
        guard !context.isPreview else { return }
        PetLog.collect(in: instance, now: context.now)
    }
}

/// The character in one of its six looks, cross-faded when the look changes.
struct PetFigure: View {
    var character: WaterCharacter
    var look: PetLook
    var height: CGFloat
    var effect: PetEffect = .none

    var body: some View {
        Group {
            if let image = PetArt.image(character, look) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .id(look)
                    .transition(.opacity)
            } else {
                // No pictures in the bundle (the screenshot tool has none).
                Image(systemName: "pawprint.fill")
                    .font(.system(size: height * 0.55))
                    .foregroundStyle(PetStyle.accent)
            }
        }
        .frame(width: height * 0.95, height: height)
        .overlay {
            // Smudges go on the character, not the card: masked by its own
            // outline, so an octopus's gaps and a penguin's narrow body show
            // none in the air beside them.
            if effect == .dirty, let image = PetArt.image(character, look) {
                PetEffectLayer(effect: effect, height: height)
                    .mask {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
            } else {
                PetEffectLayer(effect: effect, height: height)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: look)
        .animation(.easeInOut(duration: 0.4), value: effect)
        .accessibilityHidden(true)
    }
}

/// Bubbles rising over the pet after a wash, or a few smudges on it while it
/// is dirty. The bubbles keep their own clock and stop by themselves, since
/// the tile is not redrawn every second.
struct PetEffectLayer: View {
    var effect: PetEffect
    var height: CGFloat

    /// 打开“减少动态效果”时泡泡和小心心停在原地，只按原来的时长淡出。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var interval: Double { reduceMotion ? 0.25 : 1.0 / 30 }
    private func clock(_ date: Date) -> Double { reduceMotion ? 0 : date.timeIntervalSinceReferenceDate }
    private func elapsed(_ left: Double) -> Double {
        reduceMotion ? VirtualPet.actSeconds * 0.5 : VirtualPet.actSeconds - left
    }

    var body: some View {
        Group {
            switch effect {
            case .none:
                EmptyView()
            case .bubbles(let until):
                TimelineView(.animation(minimumInterval: interval)) { timeline in
                    let left = until.timeIntervalSince(timeline.date)
                    if left > 0 {
                        Canvas { context, size in
                            Self.drawBubbles(in: &context, size: size,
                                             time: clock(timeline.date),
                                             fade: min(1, left / 0.6), height: height)
                        }
                    }
                }
                .transition(.opacity)
            case .hearts(let until):
                TimelineView(.animation(minimumInterval: interval)) { timeline in
                    let left = until.timeIntervalSince(timeline.date)
                    if left > 0 {
                        Canvas { context, size in
                            Self.drawFloaters(in: &context, size: size, symbol: "heart.fill",
                                              color: Color(red: 1, green: 0.38, blue: 0.52),
                                              elapsed: elapsed(left),
                                              fade: min(1, left / 0.6), height: height)
                        }
                    }
                }
                .transition(.opacity)
            case .healing(let until):
                TimelineView(.animation(minimumInterval: interval)) { timeline in
                    let left = until.timeIntervalSince(timeline.date)
                    if left > 0 {
                        Canvas { context, size in
                            Self.drawFloaters(in: &context, size: size, symbol: "cross.fill",
                                              color: Color(red: 0.30, green: 0.80, blue: 0.55),
                                              elapsed: elapsed(left),
                                              fade: min(1, left / 0.6), height: height)
                        }
                    }
                }
                .transition(.opacity)
            case .dirty:
                Canvas { context, size in Self.drawSmudges(in: &context, size: size) }
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated private static func fraction(_ x: Double) -> Double { x - x.rounded(.down) }

    nonisolated static func drawBubbles(in context: inout GraphicsContext, size: CGSize, time: Double,
                            fade: Double, height: CGFloat) {
        for i in 0..<12 {
            let n = Double(i)
            let phase = fraction(time * 0.55 + n * 0.137)
            let x = size.width * (0.12 + 0.76 * fraction(n * 0.618))
                + sin(time * 2.4 + n) * size.width * 0.04
            let y = size.height * (1.05 - phase * 1.1)
            let r = height * (0.035 + 0.035 * fraction(n * 0.37))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let alpha = fade * (phase < 0.15 ? phase / 0.15 : 1 - (phase - 0.15) / 0.85)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(.white.opacity(0.22 * alpha)))
            context.stroke(circle, with: .color(.white.opacity(0.9 * alpha)), lineWidth: max(0.6, r * 0.18))
            // The highlight that makes a circle read as a bubble.
            let shine = CGRect(x: x - r * 0.5, y: y - r * 0.55, width: r * 0.35, height: r * 0.35)
            context.fill(Path(ellipseIn: shine), with: .color(.white.opacity(0.85 * alpha)))
        }
    }

    /// Five symbols (hearts, crosses) that pop out one after another and float up.
    nonisolated static func drawFloaters(in context: inout GraphicsContext, size: CGSize, symbol name: String,
                                         color: Color, elapsed: Double, fade: Double, height: CGFloat) {
        var symbol = context.resolve(Image(systemName: name))
        symbol.shading = .color(color)
        for i in 0..<5 {
            let n = Double(i)
            let t = elapsed - n * 0.45
            guard t > 0 else { continue }
            let life = min(1, t / 1.8)
            let x = size.width * (0.2 + 0.6 * fraction(n * 0.618 + 0.1)) + sin(t * 3 + n) * size.width * 0.05
            let y = size.height * (0.45 - life * 0.5)
            let side = height * (0.12 + 0.06 * fraction(n * 0.37)) * min(1, t / 0.25)
            var layer = context
            layer.opacity = fade * (1 - life * 0.7)
            layer.draw(symbol, in: CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side))
        }
    }

    nonisolated static func drawSmudges(in context: inout GraphicsContext, size: CGSize) {
        // Fixed spots on the lower half, where a pet that has been rolling
        // around picks up dirt.
        // Spread over the lower body, clear of the face; the mask keeps only
        // the ones that land on the character.
        let spots: [(Double, Double, Double)] = [
            (0.30, 0.66, 0.09), (0.62, 0.72, 0.08), (0.46, 0.84, 0.07), (0.72, 0.62, 0.06),
            (0.24, 0.82, 0.05), (0.40, 0.74, 0.05), (0.56, 0.64, 0.05), (0.68, 0.86, 0.06),
        ]
        let mud = Color(red: 0.42, green: 0.30, blue: 0.20)
        for (x, y, r) in spots {
            let w = size.width * r * 1.4
            let h = size.width * r
            let rect = CGRect(x: size.width * x - w / 2, y: size.height * y - h / 2, width: w, height: h)
            context.fill(Path(ellipseIn: rect), with: .color(mud.opacity(0.55)))
        }
    }
}

/// A rounded bar, green when healthy, then yellow, then red.
struct PetBar: View {
    var value: Double
    var height: CGFloat
    var tint: Color?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetStyle.secondary.opacity(0.25))
                Capsule()
                    .fill(tint ?? PetStyle.level(value))
                    .frame(width: max(height, proxy.size.width * CGFloat(VirtualPet.clamp(value) / 100)))
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.5), value: value)
    }
}

/// Treats left by other widgets for every pet. Kept in the defaults rather
/// than a widget's config because the widget that earns one is not the pet:
/// a glass of water knows nothing about which pets are on which shelf, and
/// there may be none.
///
/// A log rather than a queue: each treat has a number, and each pet keeps the
/// last number it picked up (`treatSeen` in its config), so two pets both get
/// it and a pet on another layout gets it when it next shows. Two days of
/// treats are kept.
@MainActor
enum PetTreats {
    private static let logKey = "docket.pet.treatLog"
    private static let seqKey = "docket.pet.treatSeq"
    private static let givenKey = "docket.pet.treatsGiven"
    /// A backlog is a bowl, not a buffet: a long day away is worth a good
    /// meal, not a hundred.
    static let maxPending = 20
    static let keptSeconds: TimeInterval = 2 * 86_400

    struct Entry {
        var seq: Int
        var treat: PetTreat
        var at: Date
    }

    static var latest: Int { UserDefaults.standard.integer(forKey: seqKey) }

    private static func entries() -> [Entry] {
        (UserDefaults.standard.stringArray(forKey: logKey) ?? []).compactMap { line in
            let parts = line.split(separator: "|")
            guard parts.count == 3, let seq = Int(parts[0]), let treat = PetTreat(rawValue: String(parts[1])),
                  let at = Double(parts[2]) else { return nil }
            return Entry(seq: seq, treat: treat, at: Date(timeIntervalSince1970: at))
        }
    }

    static func give(_ treat: PetTreat, now: Date = .now) {
        let defaults = UserDefaults.standard
        let seq = latest + 1
        var lines = entries().filter { now.timeIntervalSince($0.at) < keptSeconds }
            .map { "\($0.seq)|\($0.treat.rawValue)|\($0.at.timeIntervalSince1970)" }
        lines.append("\(seq)|\(treat.rawValue)|\(now.timeIntervalSince1970)")
        defaults.set(Array(lines.suffix(60)), forKey: logKey)
        defaults.set(seq, forKey: seqKey)
    }

    /// Gives `treat` unless one was already given under `key` today (a habit
    /// and its day). Only today's keys are kept.
    static func giveOnce(_ treat: PetTreat, for key: String) {
        let defaults = UserDefaults.standard
        let today = HabitTracker.dayKey(.now)
        var given = (defaults.stringArray(forKey: givenKey) ?? []).filter { $0.hasSuffix(today) }
        guard !given.contains(key) else { return }
        given.append(key)
        defaults.set(given, forKey: givenKey)
        give(treat)
    }

    /// The treats after `seen` from the last two days, at most `maxPending`.
    static func since(_ seen: Int, now: Date = .now) -> [PetTreat] {
        Array(entries().filter { $0.seq > seen && now.timeIntervalSince($0.at) < keptSeconds }
            .map(\.treat).suffix(maxPending))
    }
}

/// Notices a focus session ending, for the pet, whether or not a pet is
/// showing: checked every few seconds from launch, so a session that ends and
/// is followed straight away by the next one is still counted.
@MainActor
final class PetFocusWatcher {
    static let shared = PetFocusWatcher()
    private static let creditedKey = "docket.pet.focusCredited"
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { PetFocusWatcher.shared.check() }
        }
    }

    func check(now: Date = .now) {
        let defaults = UserDefaults.standard
        let credited = defaults.double(forKey: Self.creditedKey)
        guard let deadline = VirtualPet.finishedFocus(TimerStateProvider.shared.state,
                                                      credited: credited > 0
                                                          ? Date(timeIntervalSince1970: credited) : nil,
                                                      now: now) else { return }
        defaults.set(deadline.timeIntervalSince1970, forKey: Self.creditedKey)
        PetTreats.give(.focus, now: now)
    }
}

/// The writes the tile and the panel both make, from the instance's current
/// config so the two can never disagree.
@MainActor
enum PetLog {
    static func act(_ action: PetAction, in instance: WidgetInstance) {
        let now = Date.now
        WidgetWriter.write(instance) { config in
            let state = VirtualPet.performing(action, on: VirtualPet.state(config, now: now), now: now)
            VirtualPet.store(state, in: &config, now: now)
        }
    }

    /// The treats this pet has not picked up yet, written only when there
    /// are some: the tile calls this every tick.
    static func collect(in instance: WidgetInstance, now: Date) {
        let latest = PetTreats.latest
        let seen = Int(instance.config.double("treatSeen"))
        guard latest != seen else { return }
        // A log that went backwards (defaults reset) starts this pet over.
        let treats = latest > seen ? PetTreats.since(seen, now: now) : []
        WidgetWriter.write(instance) { config in
            let state = VirtualPet.treating(treats.count, on: VirtualPet.state(config, now: now), now: now)
            if !treats.isEmpty { VirtualPet.store(state, in: &config, now: now) }
            config.set("treatSeen", .number(Double(latest)))
        }
    }

    static func set(_ key: String, _ value: WidgetConfig.Value, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(key, value) }
    }
}

/// 读 `PetHeat` 要的三个读数：系统的热状态、系统活动在跑时的 CPU 记录、
/// 天气取到的气温。都是别处已经有的，这里不开任何采样。
@MainActor
enum PetMelt {
    static var now: Bool {
        PetHeat.isMelting(thermal: ProcessInfo.processInfo.thermalState.rawValue,
                          cpuHistory: SystemMetrics.shared.cpuHistory,
                          outdoorCelsius: WeatherService.shared.current?.temperatureC)
    }
}

@MainActor
enum PetArt {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    /// Loose PNGs in the bundle's Resources, like 喝水's; read once.
    static func image(_ character: WaterCharacter, _ look: PetLook) -> NSImage? {
        let name = VirtualPet.imageName(character, look)
        if let image = cache[name] { return image }
        guard !missing.contains(name),
              let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }
}

enum PetStyle {
    static var accent: Color { Color(hex: WidgetCatalog.accentHex(.pet) ?? ShelfColor.redPanda.hex) }

    static func level(_ value: Double) -> Color {
        if value >= 60 { return Color(hex: PaletteColor.green.hex) }
        if value >= 30 { return Color(hex: PaletteColor.yellow.hex) }
        return Color(hex: PaletteColor.red.hex)
    }

    /// 卡片上“名字 · 状态”那一行：平常是正文色，饿了、病了这类时候和状态一样标红，
    /// 吃饭、开心时用宠物的颜色。
    static func headline(look: PetLook, health: Double) -> Color {
        switch look {
        case .sick, .hungry, .dried, .melted, .cheer, .eat: tint(look: look, health: health)
        default: health < 30 ? tint(look: look, health: health) : WidgetStyle.primary
        }
    }

    static func tint(look: PetLook, health: Double) -> Color {
        switch look {
        case .sick, .hungry, .dried, .melted: Color(hex: PaletteColor.red.hex)
        case .cheer, .eat: accent
        default: health < 30 ? Color(hex: PaletteColor.red.hex) : WidgetStyle.secondary
        }
    }
}

/// 需要照顾时通知: one pending reminder per pet, for when it next wants
/// looking after (or falls sick), replaced whenever something is done for it.
/// Off unless switched on in the panel; permission is asked the first time.
@MainActor
final class PetNotifier {
    static let shared = PetNotifier()
    private var scheduled: [UUID: Date] = [:]
    private var asked = false
    private let presenter = BannerPresenter()

    private static func identifier(_ id: UUID) -> String { "docket.pet.\(id.uuidString)" }

    func update(_ instance: WidgetInstance, alert: PetAlert?, name: String) {
        let id = Self.identifier(instance.id)
        guard let alert, alert.date > .now else {
            if scheduled.removeValue(forKey: instance.id) != nil {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            }
            return
        }
        if let existing = scheduled[instance.id], abs(existing.timeIntervalSince(alert.date)) < 1 { return }
        scheduled[instance.id] = alert.date
        let message = alert.message(name: name)
        let date = alert.date
        Task { await schedule(id: id, at: date, title: message.title, body: message.body) }
    }

    private func schedule(id: String, at date: Date, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
