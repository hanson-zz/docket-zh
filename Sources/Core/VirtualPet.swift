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
/// was not needed: fed full, played with happy, washed clean), `touchedAt`
/// (when someone last did something for it by hand, for 积灰). `character` is
/// the one option.
public enum PetNeed: String, CaseIterable, Sendable, Identifiable {
    case food, mood, energy, clean

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .food: tr("饱食")
        case .mood: tr("心情")
        case .energy: tr("精力")
        case .clean: tr("清洁")
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
    /// Only offered while it is sick: brings every need back to `healTo`.
    case heal
    /// Something done elsewhere in 码头 that feeds it: a glass of water, a
    /// habit checked off, a focus session finished.
    case treat

    public var id: String { rawValue }

    public static let buttons: [PetAction] = [.feed, .play, .sleep, .wash]

    public var title: String {
        switch self {
        case .feed: tr("喂食")
        case .play: tr("玩耍")
        case .sleep: tr("睡觉")
        case .wash: tr("清洁")
        case .heal: tr("看病")
        case .treat: tr("奖励")
        }
    }

    public var symbol: String {
        switch self {
        case .feed: "fork.knife"
        case .play: "tennisball.fill"
        case .sleep: "moon.zzz.fill"
        case .wash: "shower.fill"
        case .heal: "cross.case.fill"
        case .treat: "gift.fill"
        }
    }
}

/// Where a treat came from, for the line under the panel's buttons.
public enum PetTreat: String, CaseIterable, Sendable {
    case water, habit, focus

    public var title: String {
        switch self {
        case .water: tr("喝了一杯水")
        case .habit: tr("完成一项习惯打卡")
        case .focus: tr("完成一轮专注")
        }
    }
}

/// What the character is drawn doing.
public enum PetLook: String, CaseIterable, Sendable {
    case idle, cheer, rest, eat, hungry, sick
    /// 喝水连续 3 天没达标：渴成骷髅，喝够一天就复活。
    case dried
    /// 很久没人陪它（`VirtualPet.dustyAfterHours`）：身上积灰长蘑菇，摸一下就好。
    case dusty
    /// Mac 过热、CPU 一直很忙或外面太热（见 `PetHeat`）：化成一滩，凉下来就好。
    case melted

    public var title: String {
        switch self {
        case .idle: tr("还不错")
        case .cheer: tr("很开心")
        case .rest: tr("睡着了")
        case .eat: tr("吃得正香")
        case .hungry: tr("饿了")
        case .sick: tr("生病了")
        case .dried: tr("渴成骷髅了")
        case .dusty: tr("积灰了")
        case .melted: tr("热化了")
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
    /// Little crosses floating up until this moment, after seeing the doctor.
    case healing(until: Date)
    /// Smudges while 清洁 is low.
    case dirty
}

/// A reminder to look after it, from `VirtualPet.nextAlert`.
public struct PetAlert: Equatable, Sendable {
    public var date: Date
    public var sick: Bool
    /// The tile's line at that moment: 饿了, 有点脏了, 生病了...
    public var line: String

    public init(date: Date, sick: Bool, line: String) {
        self.date = date
        self.sick = sick
        self.line = line
    }

    public func message(name: String) -> (title: String, body: String) {
        sick ? (tr("\(name)生病了"), tr("快去看看它，带它看病吧。"))
             : (tr("\(name)需要照顾"), tr("它\(line)，去照顾一下它吧。"))
    }
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
    /// When someone last did something for it by hand (a treat from 喝水 or
    /// 习惯打卡 does not count): how long it has sat gathering dust.
    public var touchedAt: Date?

    public init(food: Double = 80, mood: Double = 80, energy: Double = 80, clean: Double = 80,
                at: Date, sleepSince: Date? = nil, lastAction: PetAction? = nil, lastActionAt: Date? = nil,
                cared: Set<String> = [], focusCredited: Date? = nil, sleepNightly: Bool = false,
                wokeAt: Date? = nil, lastActionFull: Bool = false, touchedAt: Date? = nil) {
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
        self.touchedAt = touchedAt
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
    /// Seeing the doctor brings every need at least this far: out of sick and
    /// out of hungry, but still wanting looking after.
    public static let healTo: Double = 40
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
                        lastActionFull: config.double("lastActionFull") > 0,
                        touchedAt: date("touchedAt"))
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
        config.set("touchedAt", .number(state.touchedAt?.timeIntervalSince1970 ?? 0))
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
        // Nothing to treat in a pet that is not sick.
        case .heal: !isSick(state)
        case .sleep, .treat: false
        }
    }

    /// Does `action` at `now`. Feeding a full pet (or playing with a happy
    /// one, washing a clean one) changes nothing but the line it says, and
    /// leaves it asleep if it was.
    public static func performing(_ action: PetAction, on state: PetState, now: Date,
                                  calendar: Calendar = HabitTracker.calendar) -> PetState {
        var s = advanced(state, to: now, calendar: calendar)
        // Anything done by hand, even turned down, brushes the dust off.
        if action != .treat { s.touchedAt = now }
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
        case .heal:
            for need in PetNeed.allCases { s[need] = max(s[need], healTo) }
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
    /// 渴成骷髅, 热化了, sleep, sick, 积灰, hungry and happy.
    public static func look(_ state: PetState, now: Date, dried: Bool = false,
                            melted: Bool = false) -> PetLook {
        if let action = state.lastAction, let when = state.lastActionAt, !state.lastActionFull,
           now >= when, now.timeIntervalSince(when) < actSeconds {
            switch action {
            case .feed, .treat: return .eat
            case .play, .wash, .heal: return .cheer
            case .sleep: break
            }
        }
        if dried { return .dried }
        if melted { return .melted }
        if state.isSleeping { return .rest }
        if isSick(state) { return .sick }
        if isDusty(state, now: now) { return .dusty }
        if state.food < lowLine { return .hungry }
        if PetNeed.allCases.allSatisfy({ state[$0] >= happyLine }) { return .cheer }
        return .idle
    }

    /// 积灰：这么久没人亲手照顾它。比离开超过 `awayAfterHours` 更久，所以
    /// 一晚上不碰不会积灰，出门一整天回来才会。
    public static let dustyAfterHours: Double = 24

    /// When it was last looked after by hand. A pet saved before `touchedAt`
    /// existed falls back to its last action unless that was a treat; one
    /// with neither has never been touched and is not dusty yet.
    public static func lastTouched(_ state: PetState) -> Date? {
        if let touched = state.touchedAt { return touched }
        if let action = state.lastAction, action != .treat { return state.lastActionAt }
        return nil
    }

    public static func isDusty(_ state: PetState, now: Date) -> Bool {
        guard let touched = lastTouched(state) else { return false }
        return now.timeIntervalSince(touched) >= dustyAfterHours * 3600
    }

    /// Any need below `sickLine`.
    public static func isSick(_ state: PetState) -> Bool {
        PetNeed.allCases.contains { state[$0] < sickLine }
    }

    /// The next reminder for 需要照顾时通知: when it next starts wanting
    /// looking after, or, if it already does, when it falls sick. Looked for
    /// in ten-minute steps over two days; one due at night waits for 7:00,
    /// when it is up anyway. Nil when it is already sick (the reminder for
    /// that has gone) or nothing comes due.
    public static func nextAlert(_ state: PetState, after now: Date,
                                 calendar: Calendar = HabitTracker.calendar) -> PetAlert? {
        let current = advanced(state, to: now, calendar: calendar)
        if isSick(current) { return nil }
        let wantsSick = current.needsCare
        var t = now
        let limit = now.addingTimeInterval(48 * 3600)
        while t < limit {
            t = t.addingTimeInterval(600)
            let later = advanced(current, to: t, calendar: calendar)
            let due = wantsSick ? isSick(later) : (later.needsCare || isSick(later))
            guard due else { continue }
            var when = t
            if isNight(when, calendar: calendar) {
                when = nextNightEdge(after: when, calendar: calendar)
            }
            let then = advanced(current, to: when, calendar: calendar)
            if isSick(then) { return PetAlert(date: when, sick: true, line: tr("生病了")) }
            return PetAlert(date: when, sick: false, line: statusLine(then, now: when))
        }
        return nil
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
            if action == .heal { return .healing(until: until) }
        }
        if state.clean < lowLine { return .dirty }
        return .none
    }

    /// The tile's one line: what it is doing, or the lowest need.
    public static func statusLine(_ state: PetState, now: Date, dried: Bool = false,
                                  melted: Bool = false) -> String {
        if let action = state.lastAction, let when = state.lastActionAt, state.lastActionFull,
           now >= when, now.timeIntervalSince(when) < actSeconds {
            switch action {
            case .feed: return tr("吃不下了")
            case .play: return tr("已经很开心了")
            case .wash: return tr("已经很干净了")
            case .heal: return tr("没有生病")
            case .sleep, .treat: break
            }
        }
        switch effect(state, now: now) {
        case .bubbles: return tr("洗得香喷喷")
        case .hearts: return tr("玩得真开心")
        case .healing: return tr("好多了")
        default: break
        }
        let look = look(state, now: now, dried: dried, melted: melted)
        switch look {
        case .dried:
            return tr("渴成骷髅了，快喝水")
        case .dusty:
            return tr("积灰了，摸摸它")
        case .melted:
            return tr("热化了，歇一歇")
        case .idle:
            if state.clean < lowLine { return tr("有点脏了") }
            if state.mood < lowLine { return tr("有点无聊") }
            if state.energy < lowLine { return tr("困了") }
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
        if look == .dried { return "pet-\(character.rawValue)-skeleton" }
        // Every character, the red panda too, has its own 积灰 and 化成一滩.
        if look == .dusty { return "pet-\(character.rawValue)-dusty" }
        if look == .melted { return "pet-\(character.rawValue)-melt" }
        if character == .redPanda { return "pet-panda-\(look.rawValue)" }
        switch look {
        case .idle, .cheer, .rest: return "water-\(character.rawValue)-\(look.rawValue)"
        case .eat, .hungry, .sick, .dried, .dusty, .melted: return "pet-\(character.rawValue)-\(look.rawValue)"
        }
    }

    /// 渴成骷髅: switched on in the panel, and 喝水 has gone `dryDays`
    /// days in a row without reaching its goal (today met counts as 0).
    public static let dryKey = "dryUp"
    public static let dryDays = 3
    /// Where 喝水 leaves its run of missed days for the pet to read.
    public static let missedDaysDefault = "docket.water.missedDays"

    public static func isDried(_ config: WidgetConfig, missedDays: Int) -> Bool {
        config.bool(dryKey) && missedDays >= dryDays
    }

    /// A believable pet for the library and the screenshots.
    public static func sample(now: Date, calendar: Calendar = HabitTracker.calendar) -> PetState {
        let cared = Set((0..<6).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            .map { HabitTracker.dayKey($0, calendar: calendar) })
        return PetState(food: 72, mood: 86, energy: 64, clean: 90, at: now, cared: cared)
    }
}
