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
/// the last focus session it was fed for), `sleepNightly` (1 while it is in
/// its own night's sleep), `wokeAt` (when it was last woken by hand, so a pet
/// woken at midnight stays up) and `lastActionFull` (1 when the last thing done
/// was not needed: fed full, played with happy, washed clean). `character` is
/// the one option.
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
    /// Hearts floating up until this moment, after a game.
    case hearts(until: Date)
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
    /// Asleep because it is night rather than because it was put to bed: it
    /// sleeps until morning instead of until energy is full.
    public var sleepNightly: Bool
    /// Last woken by hand (or by being fed, played with or washed).
    public var wokeAt: Date?
    /// The last action was not needed, so it is turned down rather than acted out.
    public var lastActionFull: Bool

    public init(food: Double = 80, mood: Double = 80, energy: Double = 80, clean: Double = 80,
                at: Date, sleepSince: Date? = nil, lastAction: PetAction? = nil, lastActionAt: Date? = nil,
                cared: Set<String> = [], focusCredited: Date? = nil, sleepNightly: Bool = false,
                wokeAt: Date? = nil, lastActionFull: Bool = false) {
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
        self.sleepNightly = sleepNightly
        self.wokeAt = wokeAt
        self.lastActionFull = lastActionFull
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
    /// It goes to bed by itself at `nightStart` and gets up at `nightEnd`.
    public static let nightStart = 23
    public static let nightEnd = 7
    /// After this long with nobody looking after it (the Mac off over a
    /// weekend, a holiday), time alone takes a need no lower than `awayFloor`:
    /// hungry on the way back, not sick for days.
    public static let awayAfterHours: Double = 12
    public static let awayFloor: Double = 20
    /// At or above this, feeding, playing or washing is turned down.
    public static let fullLine: Double = 95
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
                        focusCredited: date("focusCredited"),
                        sleepNightly: config.double("sleepNightly") > 0 && date("sleepSince") != nil,
                        wokeAt: date("wokeAt"),
                        lastActionFull: config.double("lastActionFull") > 0)
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
        config.set("sleepNightly", .number(state.sleepNightly && state.isSleeping ? 1 : 0))
        config.set("wokeAt", .number(state.wokeAt?.timeIntervalSince1970 ?? 0))
        config.set("lastActionFull", .number(state.lastActionFull ? 1 : 0))
        let cutoff = calendar.date(byAdding: .day, value: -keptDays, to: now)
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        config.set("cared", .list(state.cared.filter { $0 > cutoff }.sorted().map { .string($0) }))
    }

    // MARK: Time passing

    /// Whether `date` falls in the pet's night, 23:00 to 7:00.
    public static func isNight(_ date: Date, calendar: Calendar = HabitTracker.calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= nightStart || hour < nightEnd
    }

    /// When the night `date` is in began (only meaningful at night).
    static func nightBegan(_ date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let today = calendar.date(byAdding: .hour, value: nightStart, to: day) ?? day
        if calendar.component(.hour, from: date) >= nightStart { return today }
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    /// The next 23:00 or 7:00 after `date`.
    static func nextNightEdge(after date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        if hour < nightEnd { return calendar.date(byAdding: .hour, value: nightEnd, to: day) ?? date }
        if hour < nightStart { return calendar.date(byAdding: .hour, value: nightStart, to: day) ?? date }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? date
        return calendar.date(byAdding: .hour, value: nightEnd, to: tomorrow) ?? date
    }

    /// The state as it is at `now`. Asleep, energy fills at `sleepGain` an
    /// hour and the rest fall at half speed. Put to bed by hand, it wakes once
    /// energy is full; at night it goes to bed by itself (unless it was woken
    /// by hand that night) and sleeps until morning. Past `awayAfterHours`
    /// of the gap, time alone takes nothing below `awayFloor`.
    ///
    /// Walked in pieces cut at 23:00, 7:00 and the away mark, so each piece is
    /// all night or all day; a month away is about sixty pieces.
    public static func advanced(_ state: PetState, to now: Date,
                                calendar: Calendar = HabitTracker.calendar) -> PetState {
        var s = state
        let start = state.at
        let end = start.addingTimeInterval(min(maxCatchUpHours, max(0, now.timeIntervalSince(start) / 3600)) * 3600)
        s.at = max(now, state.at)
        let awayMark = start.addingTimeInterval(awayAfterHours * 3600)
        var t = start
        while t < end {
            var next = min(end, nextNightEdge(after: t, calendar: calendar))
            if t < awayMark { next = min(next, awayMark) }
            if next <= t { next = end }
            let hours = next.timeIntervalSince(t) / 3600
            let night = isNight(t, calendar: calendar)
            let away = t >= awayMark
            let before = PetNeed.allCases.map { s[$0] }

            if s.isSleeping, s.sleepNightly, !night {
                s.sleepSince = nil
                s.sleepNightly = false
            }
            // Put to bed by hand and still asleep when night falls: stays down till morning.
            if s.isSleeping, night { s.sleepNightly = true }
            if !s.isSleeping, night, s.wokeAt.map({ $0 < nightBegan(t, calendar: calendar) }) ?? true {
                s.sleepSince = t
                s.sleepNightly = true
            }

            var awake = hours
            if s.isSleeping {
                let asleep = s.sleepNightly ? hours : min(hours, max(0, (100 - s.energy) / sleepGain))
                s.energy += sleepGain * asleep
                for need in [PetNeed.food, .mood, .clean] { s[need] -= need.perHour * 0.5 * asleep }
                awake = hours - asleep
                if !s.sleepNightly, awake > 0 || s.energy >= 100 { s.sleepSince = nil }
            }
            if !s.isSleeping, awake > 0 {
                for need in PetNeed.allCases { s[need] -= need.perHour * awake }
            }
            // Clamped piece by piece: a night's sleep past full is not banked.
            for need in PetNeed.allCases { s[need] = s[need] }
            if away {
                for (i, need) in PetNeed.allCases.enumerated() where s[need] < before[i] {
                    s[need] = max(s[need], min(before[i], awayFloor))
                }
            }
            t = next
        }
        // Read at night without any time passing (a pet stored at 23:30).
        if !s.isSleeping, isNight(s.at, calendar: calendar),
           s.wokeAt.map({ $0 < nightBegan(s.at, calendar: calendar) }) ?? true, end > start {
            s.sleepSince = s.at
            s.sleepNightly = true
        }
        if s.isSleeping, s.sleepNightly, !isNight(s.at, calendar: calendar) {
            s.sleepSince = nil
            s.sleepNightly = false
        }
        for need in PetNeed.allCases { s[need] = s[need] }
        return s
    }

    /// Whether `action` would do nothing worth doing: food for a full pet, a
    /// game for a happy one, a bath for a clean one.
    public static func isFull(_ action: PetAction, _ state: PetState) -> Bool {
        switch action {
        case .feed: state.food >= fullLine
        case .play: state.mood >= fullLine
        case .wash: state.clean >= fullLine
        case .sleep, .treat: false
        }
    }

    /// Does `action` at `now`. Feeding a full pet (or playing with a happy
    /// one, washing a clean one) changes nothing but the line it says, and
    /// leaves it asleep if it was.
    public static func performing(_ action: PetAction, on state: PetState, now: Date,
                                  calendar: Calendar = HabitTracker.calendar) -> PetState {
        var s = advanced(state, to: now, calendar: calendar)
        if isFull(action, s) {
            s.lastAction = action
            s.lastActionAt = now
            s.lastActionFull = true
            return s
        }
        let wasAsleep = s.isSleeping
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
        if wasAsleep, !s.isSleeping {
            s.wokeAt = now
            s.sleepNightly = false
        }
        if action == .sleep, s.isSleeping { s.sleepNightly = false }
        // The fields are written directly above; the subscript is what clamps.
        for need in PetNeed.allCases { s[need] = s[need] }
        // Waking it up or putting it down is not something it acts out.
        if action != .sleep {
            s.lastAction = action
            s.lastActionAt = now
            s.lastActionFull = false
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
        if let action = state.lastAction, let when = state.lastActionAt, !state.lastActionFull,
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
        if let action = state.lastAction, let when = state.lastActionAt, !state.lastActionFull,
           now >= when, now.timeIntervalSince(when) < actSeconds {
            let until = when.addingTimeInterval(actSeconds)
            if action == .wash { return .bubbles(until: until) }
            if action == .play { return .hearts(until: until) }
        }
        if state.clean < lowLine { return .dirty }
        return .none
    }

    /// The tile's one line: what it is doing, or the lowest need.
    public static func statusLine(_ state: PetState, now: Date) -> String {
        if let action = state.lastAction, let when = state.lastActionAt, state.lastActionFull,
           now >= when, now.timeIntervalSince(when) < actSeconds {
            switch action {
            case .feed: return "吃不下了"
            case .play: return "已经很开心了"
            case .wash: return "已经很干净了"
            case .sleep, .treat: break
            }
        }
        switch effect(state, now: now) {
        case .bubbles: return "洗得香喷喷"
        case .hearts: return "玩得真开心"
        default: break
        }
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
