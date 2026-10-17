import Foundation

/// 喝水的个性化推荐目标：按体重、性别、年龄、身高、活动量、当天运动、气候、
/// 特殊状态和身体不适估算每天该喝多少，并给出逐项明细。
///
/// Every input is optional and lives in the 喝水 widget's own config beside
/// the existing `weight`, so a config written before any of this existed
/// reads as "only a weight" (or nothing) and still gets a sensible goal.
///
/// The rules, in order:
///
/// 1. 基数. With a weight (20 to 250 kg) it is weight x ml/kg:
///    - 30 ml/kg for anyone over 65, or a small frame (height under 155 cm or
///      weight under 50 kg). This wins over everything below.
///    - 35 ml/kg for a man 175 cm or taller.
///    - 32 ml/kg for a woman (33 minus 1).
///    - 33 ml/kg otherwise, which is also the default when sex, age and
///      height are not set.
///    Without a weight it is the 中国居民膳食指南（2022）figure for light
///    activity in a mild climate: 1700 ml for a man, 1500 ml for a woman,
///    1600 ml when sex is not set.
/// 2. 日常活动量 multiplies the base: 久坐 1.0, 中等 1.1, 重体力 1.2.
/// 3. 今日运动 adds 300 ml per 30 minutes, pro rata (10 ml a minute), up to
///    `maxExerciseMinutes`.
/// 4. 气候: 炎热潮湿 or 高海拔 +500 ml, 干燥或暖气房 +250 ml.
/// 5. 特殊状态: 怀孕 +300 ml, 哺乳 +700 ml, ignored when sex is 男.
/// 6. 发烧或腹泻 +500 ml.
/// 7. The sum is rounded to the nearest 50 ml (half away from zero) and kept
///    inside 1200...4500 ml.
///
/// A goal set by hand replaces the recommendation; the breakdown still shows
/// how the recommendation was reached and says the goal was set by hand.
public enum WaterSex: String, CaseIterable, Sendable, Identifiable {
    case unset
    case male
    case female

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unset: tr("未设置")
        case .male: tr("男")
        case .female: tr("女")
        }
    }
}

public enum WaterActivity: String, CaseIterable, Sendable, Identifiable {
    case sedentary
    case moderate
    case heavy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sedentary: tr("久坐")
        case .moderate: tr("中等")
        case .heavy: tr("重体力")
        }
    }

    public var factor: Double {
        switch self {
        case .sedentary: 1.0
        case .moderate: 1.1
        case .heavy: 1.2
        }
    }
}

public enum WaterClimate: String, CaseIterable, Sendable, Identifiable {
    case mild
    case hotHumid = "hot"
    case dry
    case altitude

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mild: tr("温和")
        case .hotHumid: tr("炎热潮湿")
        case .dry: tr("干燥或暖气房")
        case .altitude: tr("高海拔")
        }
    }

    public var extra: Int {
        switch self {
        case .mild: 0
        case .hotHumid, .altitude: 500
        case .dry: 250
        }
    }
}

public enum WaterCondition: String, CaseIterable, Sendable, Identifiable {
    case none
    case pregnant
    case nursing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: tr("无")
        case .pregnant: tr("怀孕")
        case .nursing: tr("哺乳")
        }
    }

    public var extra: Int {
        switch self {
        case .none: 0
        case .pregnant: 300
        case .nursing: 700
        }
    }
}

/// What the recommendation is computed from. Nil or the first case for
/// anything not set.
public struct WaterProfile: Equatable, Sendable {
    public var weight: Double?
    public var sex: WaterSex
    public var age: Int?
    public var height: Double?
    public var activity: WaterActivity
    /// Today's exercise; already zero when it was set on another day.
    public var exerciseMinutes: Int
    public var climate: WaterClimate
    public var condition: WaterCondition
    /// Today's fever or diarrhoea; already false when set on another day.
    public var unwell: Bool

    public init(weight: Double? = nil, sex: WaterSex = .unset, age: Int? = nil, height: Double? = nil,
                activity: WaterActivity = .sedentary, exerciseMinutes: Int = 0, climate: WaterClimate = .mild,
                condition: WaterCondition = .none, unwell: Bool = false) {
        self.weight = weight.flatMap(WaterGoal.validWeight)
        self.sex = sex
        self.age = age.flatMap(WaterGoal.validAge)
        self.height = height.flatMap(WaterGoal.validHeight)
        self.activity = activity
        self.exerciseMinutes = WaterGoal.clampExercise(exerciseMinutes)
        self.climate = climate
        self.condition = condition
        self.unwell = unwell
    }

    /// Reads the widget's config. Today's exercise and 发烧或腹泻 count only
    /// on the day they were set (`exerciseDay`, `unwellDay`), so they clear
    /// themselves at midnight without anything having to run.
    public init(config: WidgetConfig, now: Date = .now, calendar: Calendar = WaterIntake.calendar) {
        let today = HabitTracker.dayKey(now, calendar: calendar)
        let weight = config.double(WaterGoal.Key.weight)
        let age = config.int(WaterGoal.Key.age)
        let height = config.double(WaterGoal.Key.height)
        let exerciseToday = config.string(WaterGoal.Key.exerciseDay) == today
        let unwellToday = config.string(WaterGoal.Key.unwellDay) == today
        self.init(weight: weight > 0 ? weight : nil,
                  sex: WaterSex(rawValue: config.string(WaterGoal.Key.sex)) ?? .unset,
                  age: age > 0 ? age : nil,
                  height: height > 0 ? height : nil,
                  activity: WaterActivity(rawValue: config.string(WaterGoal.Key.activity)) ?? .sedentary,
                  exerciseMinutes: exerciseToday ? config.int(WaterGoal.Key.exercise) : 0,
                  climate: WaterClimate(rawValue: config.string(WaterGoal.Key.climate)) ?? .mild,
                  condition: WaterCondition(rawValue: config.string(WaterGoal.Key.condition)) ?? .none,
                  unwell: unwellToday && config.bool(WaterGoal.Key.unwell))
    }
}

/// One line of the breakdown.
public struct WaterGoalLine: Equatable, Sendable, Identifiable {
    public var id: String
    /// "基数", "日常活动量：中等".
    public var title: String
    /// How the figure was reached: "体重 60 公斤 x 33 毫升".
    public var detail: String
    /// Millilitres: the base itself on the first line, a change after it.
    public var millilitres: Int

    public init(id: String, title: String, detail: String, millilitres: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.millilitres = millilitres
    }
}

public struct WaterGoalResult: Equatable, Sendable {
    /// The goal in use: the hand-set one when there is one.
    public var goal: Int
    /// What the rules recommend, hand-set goal or not.
    public var recommended: Int
    /// The hand-set goal, nil when following the recommendation.
    public var manual: Int?
    /// The base and every change, summing exactly to `recommended`.
    public var lines: [WaterGoalLine]
    /// ml/kg used for the base, nil without a weight.
    public var perKilogram: Int?

    public var isManual: Bool { manual != nil }
}

public enum WaterGoal {
    public enum Key {
        public static let weight = "weight"
        public static let sex = "sex"
        public static let age = "age"
        public static let height = "height"
        public static let activity = "activity"
        public static let exercise = "exercise"
        public static let exerciseDay = "exerciseDay"
        public static let climate = "climate"
        public static let condition = "condition"
        public static let unwell = "unwell"
        public static let unwellDay = "unwellDay"
        /// "manual" or "auto"; missing on configs written before the
        /// recommendation existed, see `manualGoal`.
        public static let mode = "goalMode"
        public static let goal = "goal"

        /// Everything 复位 clears besides the reminder settings.
        public static let profile = [weight, sex, age, height, activity, exercise, exerciseDay,
                                     climate, condition, unwell, unwellDay, mode, goal]
    }

    public static let range = 1200...4500
    public static let step = 50
    public static let weightRange = 20.0...250.0
    public static let ageRange = 1...120
    public static let heightRange = 100.0...250.0
    public static let maxExerciseMinutes = 600
    public static let millilitresPerExerciseMinute = 10
    public static let unwellExtra = 500
    public static let defaultPerKilogram = 33
    public static let smallPerKilogram = 30
    public static let largePerKilogram = 35
    public static let femalePerKilogram = 32

    static func validWeight(_ value: Double) -> Double? {
        value.isFinite && weightRange.contains(value) ? value : nil
    }

    static func validAge(_ value: Int) -> Int? { ageRange.contains(value) ? value : nil }

    static func validHeight(_ value: Double) -> Double? {
        value.isFinite && heightRange.contains(value) ? value : nil
    }

    public static func clampExercise(_ minutes: Int) -> Int { min(maxExerciseMinutes, max(0, minutes)) }

    /// ml/kg for the base; see the rules at the top of the file.
    public static func perKilogram(_ profile: WaterProfile) -> Int {
        let elderly = (profile.age ?? 0) > 65
        let small = (profile.height.map { $0 < 155 } ?? false) || (profile.weight.map { $0 < 50 } ?? false)
        if elderly || small { return smallPerKilogram }
        if profile.sex == .male, let height = profile.height, height >= 175 { return largePerKilogram }
        if profile.sex == .female { return femalePerKilogram }
        return defaultPerKilogram
    }

    /// 中国居民膳食指南（2022）, light activity, mild climate.
    public static func guidelineBase(_ sex: WaterSex) -> Int {
        switch sex {
        case .male: 1700
        case .female: 1500
        case .unset: 1600
        }
    }

    /// To the nearest 50, halves away from zero.
    public static func rounded(_ value: Double) -> Int {
        Int((value / Double(step)).rounded()) * step
    }

    public static func clamp(_ value: Int) -> Int { min(range.upperBound, max(range.lowerBound, value)) }

    /// The recommendation and its breakdown, or the hand-set goal on top.
    public static func compute(_ profile: WaterProfile, manual: Int? = nil) -> WaterGoalResult {
        var lines: [WaterGoalLine] = []
        var perKg: Int?
        let base: Double
        if let weight = profile.weight {
            let rate = perKilogram(profile)
            perKg = rate
            base = weight * Double(rate)
            lines.append(WaterGoalLine(id: "base", title: tr("基数"),
                                       detail: tr("体重 \(number(weight)) 公斤 x \(rate) 毫升"),
                                       millilitres: Int(base.rounded())))
        } else {
            base = Double(guidelineBase(profile.sex))
            let who = profile.sex == .unset ? tr("成人") : tr("成年\(profile.sex.title)性")
            lines.append(WaterGoalLine(id: "base", title: tr("基数"),
                                       detail: tr("未填体重，按膳食指南（2022）\(who)基准"),
                                       millilitres: Int(base)))
        }

        var running = base
        if profile.activity != .sedentary {
            let after = base * profile.activity.factor
            lines.append(WaterGoalLine(id: "activity", title: tr("日常活动量：\(profile.activity.title)"),
                                       detail: "x \(number(profile.activity.factor))",
                                       millilitres: Int((after - base).rounded())))
            running = after
        }
        if profile.exerciseMinutes > 0 {
            let extra = profile.exerciseMinutes * millilitresPerExerciseMinute
            lines.append(WaterGoalLine(id: "exercise", title: tr("今日运动 \(profile.exerciseMinutes) 分钟"),
                                       detail: tr("每 30 分钟 +300 毫升"), millilitres: extra))
            running += Double(extra)
        }
        if profile.climate.extra > 0 {
            lines.append(WaterGoalLine(id: "climate", title: tr("气候：\(profile.climate.title)"),
                                       detail: "", millilitres: profile.climate.extra))
            running += Double(profile.climate.extra)
        }
        if profile.condition != .none, profile.sex != .male {
            lines.append(WaterGoalLine(id: "condition", title: tr("特殊状态：\(profile.condition.title)"),
                                       detail: "", millilitres: profile.condition.extra))
            running += Double(profile.condition.extra)
        }
        if profile.unwell {
            lines.append(WaterGoalLine(id: "unwell", title: tr("发烧或腹泻"), detail: tr("今天"),
                                       millilitres: unwellExtra))
            running += Double(unwellExtra)
        }

        let roundedValue = rounded(running)
        let recommended = clamp(roundedValue)
        let shown = lines.reduce(0) { $0 + $1.millilitres }
        if roundedValue != recommended {
            // Rounding folded into the limit line: one adjustment, one reason.
            lines.append(WaterGoalLine(id: "limit", title: tr("限制在 1200 到 4500 毫升"),
                                       detail: "", millilitres: recommended - shown))
        } else if recommended != shown {
            lines.append(WaterGoalLine(id: "round", title: tr("取整到 50 毫升"),
                                       detail: "", millilitres: recommended - shown))
        }

        let manual = manual.map(WaterIntake.clampGoal)
        return WaterGoalResult(goal: manual ?? recommended, recommended: recommended, manual: manual,
                               lines: lines, perKilogram: perKg)
    }

    // MARK: Config

    /// The goal set by hand, nil when following the recommendation.
    ///
    /// `goalMode` says which. A config written before it existed has only
    /// `goal`, which used to be the goal itself: 2000 (the old default, and
    /// what every widget was created with) and the old 体重 x 35 suggestion
    /// both mean the user never picked a number of their own, so those follow
    /// the recommendation; any other number was chosen by hand and is kept.
    public static func manualGoal(_ config: WidgetConfig) -> Int? {
        switch config.string(Key.mode) {
        case "manual":
            return WaterIntake.clampGoal(config.int(Key.goal, default: WaterIntake.defaultGoal))
        case "auto":
            return nil
        default:
            guard case .number = config[Key.goal] else { return nil }
            let stored = config.int(Key.goal)
            if stored == WaterIntake.defaultGoal { return nil }
            let weight = config.double(Key.weight)
            if let old = WaterIntake.suggestedGoal(weightKilograms: weight), old == stored { return nil }
            return WaterIntake.clampGoal(stored)
        }
    }

    public static func result(_ config: WidgetConfig, now: Date = .now,
                              calendar: Calendar = WaterIntake.calendar) -> WaterGoalResult {
        compute(WaterProfile(config: config, now: now, calendar: calendar), manual: manualGoal(config))
    }

    /// Writes today's exercise, stamped with today so it clears tomorrow.
    public static func settingExercise(_ minutes: Int, in config: inout WidgetConfig, now: Date = .now,
                                       calendar: Calendar = WaterIntake.calendar) {
        let value = clampExercise(minutes)
        config.set(Key.exercise, value > 0 ? .number(Double(value)) : nil)
        config.set(Key.exerciseDay, value > 0 ? .string(HabitTracker.dayKey(now, calendar: calendar)) : nil)
    }

    /// Writes today's 发烧或腹泻, stamped with today so it clears tomorrow.
    public static func settingUnwell(_ on: Bool, in config: inout WidgetConfig, now: Date = .now,
                                     calendar: Calendar = WaterIntake.calendar) {
        config.set(Key.unwell, on ? .bool(true) : nil)
        config.set(Key.unwellDay, on ? .string(HabitTracker.dayKey(now, calendar: calendar)) : nil)
    }

    /// A goal picked by hand.
    public static func settingManual(_ goal: Int, in config: inout WidgetConfig) {
        config.set(Key.mode, .string("manual"))
        config.set(Key.goal, .number(Double(WaterIntake.clampGoal(goal))))
    }

    /// Back to the recommendation.
    public static func followingRecommendation(in config: inout WidgetConfig) {
        config.set(Key.mode, .string("auto"))
        config.set(Key.goal, nil)
    }

    // MARK: Words

    /// "60", "62.5", "1.1".
    static func number(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded() ? "\(Int(tenths))" : String(format: "%.1f", tenths)
    }

    /// "+300 毫升", "-20 毫升", or the base as "1980 毫升".
    public static func signed(_ line: WaterGoalLine) -> String {
        if line.id == "base" { return tr("\(line.millilitres) 毫升") }
        return line.millilitres >= 0 ? tr("+\(line.millilitres) 毫升") : tr("\(line.millilitres) 毫升")
    }
}
