import Foundation

/// 电子宠物：住在扩展栏里的小熊猫（或另选的角色），要喂、要陪、要睡、要洗。
///
/// Four needs, each 0...100, that run down by the hour and go up with care.
/// Nothing ticks in the background: the config keeps the values as they were
/// at `at`, and every reading works out what they are now from the time that
/// has passed, the way the water log keeps minutes rather than a running
/// clock. So a Mac that slept all weekend wakes up to a hungry pet without
/// anything having run in between.
///
/// Config keys, all written by the tile and the panel, never Settings rows:
/// `food`, `mood`, `energy`, `clean` (numbers), `at` (seconds since 1970),
/// `sleepSince` (0 while awake), `lastAction` + `lastActionAt` (what was done
/// last, for the few seconds the character acts it out), `cared` (the day keys
/// something was done for it, for the streak) and `focusCredited` (the end of
/// the last focus session it was fed for). `character` is the one option.
public enum PetNeed: String, CaseIterable, Sendable, Identifiable {
    case food, mood, energy, clean

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .food: "饱食"
        case .mood: "心情"
        case .energy: "精力"
        case .clean: "清洁"
        }
    }

    public var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .mood: "heart.fill"
        case .energy: "bolt.fill"
        case .clean: "bubbles.and.sparkles.fill"
        }
    }

    /// Points lost per hour awake. Full to empty in about 20 hours of food,
    /// a day of mood, a day and a half of energy and two of cleanliness, so a
    /// pet looked after once in the morning and once in the evening is fine.
    public var perHour: Double {
        switch self {
        case .food: 5
        case .mood: 4
        case .energy: 3
        case .clean: 2
        }
    }
}

/// What can be done for it, from the panel's four buttons (feeding is also
/// the tile's one control).
public enum PetAction: String, CaseIterable, Sendable, Identifiable {
    case feed, play, sleep, wash
    /// Something done elsewhere in 码头 that feeds it: a glass of water, a
    /// habit checked off, a focus session finished.
    case treat

    public var id: String { rawValue }

    public static let buttons: [PetAction] = [.feed, .play, .sleep, .wash]

    public var title: String {
        switch self {
        case .feed: "喂食"
        case .play: "玩耍"
        case .sleep: "睡觉"
        case .wash: "清洁"
        case .treat: "奖励"
        }
    }

    public var symbol: String {
        switch self {
        case .feed: "fork.knife"
        case .play: "tennisball.fill"
        case .sleep: "moon.zzz.fill"
        case .wash: "shower.fill"
        case .treat: "gift.fill"
        }
    }
}

/// Where a treat came from, for the line under the panel's buttons.
public enum PetTreat: String, CaseIterable, Sendable {
    case water, habit, focus

    public var title: String {
        switch self {
        case .water: "喝了一杯水"
        case .habit: "完成一项习惯打卡"
        case .focus: "完成一轮专注"
        }
    }
}

/// What the character is drawn doing.
public enum PetLook: String, CaseIterable, Sendable {
    case idle, cheer, rest, eat, hungry, sick

    public var title: String {
        switch self {
        case .idle: "还不错"
        case .cheer: "很开心"
        case .rest: "睡着了"
        case .eat: "吃得正香"
        case .hungry: "饿了"
        case .sick: "生病了"
        }
    }
}

/// Drawn over the pet's picture rather than a picture of its own.
public enum PetEffect: Equatable, Sendable {
    case none
    /// Bubbles rising until this moment, after a wash.
    case bubbles(until: Date)
    /// Smudges while 清洁 is low.
    case dirty
}

public struct PetState: Equatable, Sendable {
    public var food: Double
    public var mood: Double
    public var energy: Double
    public var clean: Double
    /// When the four values above were true.
    public var at: Date
    public var sleepSince: Date?
    public var lastAction: PetAction?
    public var lastActionAt: Date?
    /// Day keys, `yyyyMMdd`.
    public var cared: Set<String>
    public var focusCredited: Date?

    public init(food: Double = 80, mood: Double = 80, energy: Double = 80, clean: Double = 80,
                at: Date, sleepSince: Date? = nil, lastAction: PetAction? = nil, lastActionAt: Date? = nil,
                cared: Set<String> = [], focusCredited: Date? = nil) {
        self.food = VirtualPet.clamp(food)
        self.mood = VirtualPet.clamp(mood)
        self.energy = VirtualPet.clamp(energy)
        self.clean = VirtualPet.clamp(clean)
        self.at = at
        self.sleepSince = sleepSince
        self.lastAction = lastAction
        self.lastActionAt = lastActionAt
        self.cared = cared
        self.focusCredited = focusCredited
    }

    public subscript(need: PetNeed) -> Double {
        get {
            switch need {
            case .food: food
            case .mood: mood
            case .energy: energy
            case .clean: clean
            }
        }
        set {
            let value = VirtualPet.clamp(newValue)
            switch need {
            case .food: food = value
            case .mood: mood = value
            case .energy: energy = value
            case .clean: clean = value
            }
        }
    }

    public var isSleeping: Bool { sleepSince != nil }

    /// The four needs averaged: the tile's bar.
    public var health: Double { (food + mood + energy + clean) / 4 }

    /// Whether something is low enough that it wants looking after.
    public var needsCare: Bool { PetNeed.allCases.contains { self[$0] < VirtualPet.lowLine } }
}

public enum VirtualPet {
    /// Below this a need shows as low, and the character shows hungry for food.
    public static let lowLine: Double = 35
    /// Below this on any need it is sick.
    public static let sickLine: Double = 15
    /// All four at or above this and it cheers.
    public static let happyLine: Double = 75
    /// How long a feed, a game or a wash is acted out.
    public static let actSeconds: TimeInterval = 4
    /// Energy gained per hour asleep; asleep, the other needs fall at half speed.
    public static let sleepGain: Double = 20
    /// Longer than this away is counted as this, so a month off is a sad pet,
    /// not a negative one (the values are clamped anyway) or an overflow.
    public static let maxCatchUpHours: Double = 24 * 30
    /// How much a treat from elsewhere in 码头 gives.
    public static let treatFood: Double = 10
    public static let treatMood: Double = 6
    public static let keptDays = 120

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    // MARK: Reading and writing

    public static func state(_ config: WidgetConfig, now: Date = .now) -> PetState {
        let at = config.double("at")
        // A brand new pet starts fed and happy, as of now.
        guard at > 0 else { return PetState(at: now, cared: Set(config.strings("cared"))) }
        func date(_ key: String) -> Date? {
            let value = config.double(key)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        return PetState(food: config.double("food", default: 80), mood: config.double("mood", default: 80),
                        energy: config.double("energy", default: 80), clean: config.double("clean", default: 80),
                        at: Date(timeIntervalSince1970: at), sleepSince: date("sleepSince"),
                        lastAction: PetAction(rawValue: config.string("lastAction")),
                        lastActionAt: date("lastActionAt"),
                        cared: Set(config.strings("cared").filter(HabitTracker.isDayKey)),
                        focusCredited: date("focusCredited"))
    }

    public static func store(_ state: PetState, in config: inout WidgetConfig, now: Date = .now,
                             calendar: Calendar = HabitTracker.calendar) {
        func round(_ value: Double) -> WidgetConfig.Value { .number((value * 10).rounded() / 10) }
        config.set("food", round(state.food))
        config.set("mood", round(state.mood))
        config.set("energy", round(state.energy))
        config.set("clean", round(state.clean))
        config.set("at", .number(state.at.timeIntervalSince1970))
        config.set("sleepSince", .number(state.sleepSince?.timeIntervalSince1970 ?? 0))
        config.set("lastAction", .string(state.lastAction?.rawValue ?? ""))
        config.set("lastActionAt", .number(state.lastActionAt?.timeIntervalSince1970 ?? 0))
        config.set("focusCredited", .number(state.focusCredited?.timeIntervalSince1970 ?? 0))
        let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: now)
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        config.set("cared", .list(state.cared.filter { $0 > cutoff }.sorted().map { .string($0) }))
    }

    // MARK: Time passing

    /// The state as it is at `now`. Asleep, energy fills at `sleepGain` an
    /// hour and the rest fall at half speed; once energy is full it wakes up
    /// by itself and the rest of the time is spent awake.
    public static func advanced(_ state: PetState, to now: Date) -> PetState {
        var s = state
        var hours = min(maxCatchUpHours, max(0, now.timeIntervalSince(state.at) / 3600))
        s.at = max(now, state.at)
        if s.isSleeping, hours > 0 {
            let toFull = max(0, (100 - s.energy) / sleepGain)
            let asleep = min(hours, toFull)
            s.energy += sleepGain * asleep
            for need in [PetNeed.food, .mood, .clean] { s[need] -= need.perHour * 0.5 * asleep }
            hours -= asleep
            if hours > 0 || s.energy >= 100 { s.sleepSince = nil }
        }
        if !s.isSleeping, hours > 0 {
            for need in PetNeed.allCases { s[need] -= need.perHour * hours }
        }
        for need in PetNeed.allCases { s[need] = s[need] }
        return s
    }

    /// Does `action` at `now`.
    public static func performing(_ action: PetAction, on state: PetState, now: Date,
                                  calendar: Calendar = HabitTracker.calendar) -> PetState {
        var s = advanced(state, to: now)
        switch action {
        case .feed:
            s.food += 30
            s.mood += 4
            s.sleepSince = nil
        case .play:
            s.mood += 25
            s.energy -= 10
            s.food -= 5
            s.clean -= 5
            s.sleepSince = nil
        case .sleep:
            // The same button wakes it.
            s.sleepSince = s.isSleeping ? nil : now
        case .wash:
            s.clean += 40
            s.mood += 4
            s.sleepSince = nil
        case .treat:
            s.food += treatFood
            s.mood += treatMood
        }
        // The fields are written directly above; the subscript is what clamps.
        for need in PetNeed.allCases { s[need] = s[need] }
        // Waking it up or putting it down is not something it acts out.
        if action != .sleep {
            s.lastAction = action
            s.lastActionAt = now
        }
        s.cared.insert(HabitTracker.dayKey(now, calendar: calendar))
        return s
    }

    /// Several treats at once (a backlog drained when the tile next draws).
    public static func treating(_ count: Int, on state: PetState, now: Date,
                                calendar: Calendar = HabitTracker.calendar) -> PetState {
        guard count > 0 else { return state }
        var s = state
        for _ in 0..<min(count, 20) { s = performing(.treat, on: s, now: now, calendar: calendar) }
        return s
    }

    // MARK: Readings

    /// Acting out what was just done beats everything for a few seconds, then
    /// sleep, then sick, hungry and happy.
    public static func look(_ state: PetState, now: Date) -> PetLook {
        if let action = state.lastAction, let when = state.lastActionAt,
           now >= when, now.timeIntervalSince(when) < actSeconds {
            switch action {
            case .feed, .treat: return .eat
            case .play, .wash: return .cheer
            case .sleep: break
            }
        }
        if state.isSleeping { return .rest }
        if PetNeed.allCases.contains(where: { state[$0] < sickLine }) { return .sick }
        if state.food < lowLine { return .hungry }
        if PetNeed.allCases.allSatisfy({ state[$0] >= happyLine }) { return .cheer }
        return .idle
    }

    /// What is drawn over the picture: bubbles for a few seconds after a
    /// wash, smudges while it is dirty. The pictures have no bath of their
    /// own, and washing a pet that was already happy would otherwise change
    /// nothing on screen.
    public static func effect(_ state: PetState, now: Date) -> PetEffect {
        if state.lastAction == .wash, let when = state.lastActionAt,
           now >= when, now.timeIntervalSince(when) < actSeconds {
            return .bubbles(until: when.addingTimeInterval(actSeconds))
        }
        if state.clean < lowLine { return .dirty }
        return .none
    }

    /// The tile's one line: what it is doing, or the lowest need.
    public static func statusLine(_ state: PetState, now: Date) -> String {
        if case .bubbles = effect(state, now: now) { return "洗得香喷喷" }
        let look = look(state, now: now)
        switch look {
        case .idle:
            if state.clean < lowLine { return "有点脏了" }
            if state.mood < lowLine { return "有点无聊" }
            if state.energy < lowLine { return "困了" }
            return look.title
        default:
            return look.title
        }
    }

    /// Consecutive days something was done for it, ending today; nothing yet
    /// today keeps the run that ended yesterday.
    public static func streak(_ state: PetState, today: Date, calendar: Calendar = HabitTracker.calendar) -> Int {
        var day = calendar.startOfDay(for: today)
        if !state.cared.contains(HabitTracker.dayKey(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while state.cared.contains(HabitTracker.dayKey(day, calendar: calendar)), count <= keptDays {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Whether the display condition 需要照顾时显示 holds.
    public static func needsCare(_ config: WidgetConfig, now: Date = .now) -> Bool {
        advanced(state(config, now: now), to: now).needsCare
    }

    /// A focus session that ended and has not been rewarded yet: the timer is
    /// on a focus phase, not paused, its deadline has passed, and that
    /// deadline is not the one already credited. Returns the deadline to
    /// remember, or nil.
    public static func finishedFocus(_ timer: TimerState, credited: Date?, now: Date) -> Date? {
        guard timer.phase == .focus, timer.paused == nil, let deadline = timer.deadline,
              deadline <= now else { return nil }
        // An hour late is a session finished while the Mac was off or the
        // shelf hidden; still worth a treat, but a deadline from last week is
        // the stale leftover of a timer nobody restarted.
        guard now.timeIntervalSince(deadline) < 12 * 3600 else { return nil }
        if let credited, abs(credited.timeIntervalSince(deadline)) < 1 { return nil }
        return deadline
    }

    // MARK: Pictures

    /// The bundled picture for a character and a look, without the extension.
    /// The five 喝水 characters reuse their sitting, cheering and resting
    /// pictures; eating, hungry and sick are the pet's own. The red panda has
    /// all six of its own, full body, since 喝水's is the app icon's head.
    public static func imageName(_ character: WaterCharacter, _ look: PetLook) -> String {
        if character == .redPanda { return "pet-panda-\(look.rawValue)" }
        switch look {
        case .idle, .cheer, .rest: return "water-\(character.rawValue)-\(look.rawValue)"
        case .eat, .hungry, .sick: return "pet-\(character.rawValue)-\(look.rawValue)"
        }
    }

    /// A believable pet for the library and the screenshots.
    public static func sample(now: Date, calendar: Calendar = HabitTracker.calendar) -> PetState {
        let cared = Set((0..<6).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            .map { HabitTracker.dayKey($0, calendar: calendar) })
        return PetState(food: 72, mood: 86, energy: 64, clean: 90, at: now, cared: cared)
    }
}
