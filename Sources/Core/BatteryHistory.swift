import Foundation

/// The Mac battery's level over the last two days, one sample per five
/// minutes, for the panel's 24-hour curve.
///
/// Stored as runs rather than as 576 separate samples: consecutive slots
/// with the same percentage and the same charging state are one run. A level
/// that sits at 100% on the adapter all night is one entry, not a hundred.
/// A slot with no sample (the Mac was asleep or Docket was not running) is a
/// gap between runs, and the curve breaks there rather than drawing a
/// straight line across hours it knows nothing about.
public struct BatteryHistory: Codable, Equatable, Sendable {
    public static let slotLength: TimeInterval = 5 * 60
    public static let keep: TimeInterval = 2 * 24 * 60 * 60
    static var keepSlots: Int { Int(keep / slotLength) }

    /// Inclusive slot indices, counted in five-minute steps since 1970.
    public struct Run: Codable, Equatable, Sendable {
        public var start: Int
        public var end: Int
        public var percent: Int
        public var charging: Bool

        public init(start: Int, end: Int, percent: Int, charging: Bool) {
            self.start = start
            self.end = end
            self.percent = percent
            self.charging = charging
        }
    }

    public struct Sample: Equatable, Sendable {
        public var date: Date
        public var percent: Int
        public var charging: Bool
    }

    public private(set) var runs: [Run]

    public init(runs: [Run] = []) {
        self.runs = runs
    }

    public static func slot(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / slotLength).rounded(.down))
    }

    public static func date(ofSlot slot: Int) -> Date {
        Date(timeIntervalSince1970: Double(slot) * slotLength)
    }

    /// The last slot that has a sample.
    public var lastSlot: Int? { runs.last?.end }

    /// How many samples the runs stand for.
    public var sampleCount: Int { runs.reduce(0) { $0 + $1.end - $1.start + 1 } }

    /// Whether `date` falls in a slot that has no sample yet, which is when
    /// the sampler should call `record`.
    public func wants(_ date: Date) -> Bool {
        guard let last = lastSlot else { return true }
        return Self.slot(of: date) > last
    }

    /// Records one sample. Only the first sample of a slot is kept; a clock
    /// that went backwards is ignored rather than rewriting history. Returns
    /// whether anything changed. Prunes anything older than two days.
    @discardableResult
    public mutating func record(percent: Int, charging: Bool, at date: Date) -> Bool {
        let slot = Self.slot(of: date)
        let value = min(max(percent, 0), 100)
        if let last = runs.last {
            guard slot > last.end else { return false }
            if slot == last.end + 1, last.percent == value, last.charging == charging {
                runs[runs.count - 1].end = slot
            } else {
                runs.append(Run(start: slot, end: slot, percent: value, charging: charging))
            }
        } else {
            runs.append(Run(start: slot, end: slot, percent: value, charging: charging))
        }
        prune(before: slot - Self.keepSlots + 1)
        return true
    }

    /// Drops everything before `slot`, cutting a run that straddles it.
    public mutating func prune(before slot: Int) {
        runs.removeAll { $0.end < slot }
        if let first = runs.first, first.start < slot {
            runs[0].start = slot
        }
    }

    public mutating func prune(now: Date) {
        prune(before: Self.slot(of: now) - Self.keepSlots + 1)
    }

    /// Every sample with a date in `from..<to`, oldest first.
    public func samples(from: Date, to: Date) -> [Sample] {
        let lower = Int((from.timeIntervalSince1970 / Self.slotLength).rounded(.up))
        let upper = Int((to.timeIntervalSince1970 / Self.slotLength).rounded(.up)) - 1
        guard upper >= lower else { return [] }
        var result: [Sample] = []
        for run in runs where run.end >= lower && run.start <= upper {
            for slot in max(run.start, lower)...min(run.end, upper) {
                result.append(Sample(date: Self.date(ofSlot: slot), percent: run.percent, charging: run.charging))
            }
        }
        return result
    }

    /// The samples in `from..<to`, split wherever a slot is missing, so a
    /// chart draws one line per stretch the Mac was awake.
    public func segments(from: Date, to: Date) -> [[Sample]] {
        var result: [[Sample]] = []
        var previous: Int?
        for sample in samples(from: from, to: to) {
            let slot = Self.slot(of: sample.date)
            if let previous, slot == previous + 1, !result.isEmpty {
                result[result.count - 1].append(sample)
            } else {
                result.append([sample])
            }
            previous = slot
        }
        return result
    }

    /// Stretches spent charging in `from..<to`, each running from its first
    /// sample to the end of its last slot. Consecutive charging slots merge
    /// even across a change of percentage.
    public func chargingSpans(from: Date, to: Date) -> [DateInterval] {
        var spans: [DateInterval] = []
        var open: (start: Int, end: Int)?
        for sample in samples(from: from, to: to) {
            let slot = Self.slot(of: sample.date)
            guard sample.charging else {
                if let span = open { spans.append(interval(span)) }
                open = nil
                continue
            }
            if let span = open, slot == span.end + 1 {
                open = (span.start, slot)
            } else {
                if let span = open { spans.append(interval(span)) }
                open = (slot, slot)
            }
        }
        if let span = open { spans.append(interval(span)) }
        return spans.map { DateInterval(start: max($0.start, from), end: min($0.end, to)) }
    }

    private func interval(_ span: (start: Int, end: Int)) -> DateInterval {
        DateInterval(start: Self.date(ofSlot: span.start), end: Self.date(ofSlot: span.end + 1))
    }
}
