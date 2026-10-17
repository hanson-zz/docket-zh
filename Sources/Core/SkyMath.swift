import Foundation

/// Sunrise and sunset, worked out from a place and a day.
///
/// The forecast MET serves carries no sun times, and a second request for
/// them would be a second service to throttle and attribute. They are
/// astronomy rather than weather, so they are computed here instead, with the
/// standard sunrise equation (the NOAA simplification). Good to a minute or
/// two away from the poles, which is all a card needs.
public enum SunTimes {
    public enum Day: Equatable, Sendable {
        case normal(rise: Date, set: Date)
        /// The sun never sets that day.
        case polarDay
        /// The sun never rises that day.
        case polarNight
    }

    /// For the calendar day containing `date` in `zone`.
    public static func on(_ date: Date, latitude: Double, longitude: Double,
                          zone: TimeZone = .current) -> Day? {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) else { return nil }

        let rad = Double.pi / 180
        let julian = noon.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = (julian - 2_451_545.0 + 0.0008).rounded()
        let meanNoon = n - longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let m = anomaly * rad
        let centre = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)
        let ecliptic = ((anomaly + centre + 180 + 102.9372).truncatingRemainder(dividingBy: 360)) * rad
        let transit = 2_451_545.0 + meanNoon + 0.0053 * sin(m) - 0.0069 * sin(2 * ecliptic)
        let declination = asin(sin(ecliptic) * sin(23.4397 * rad))
        let phi = latitude * rad
        let cosHour = (sin(-0.833 * rad) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        if cosHour < -1 { return .polarDay }
        if cosHour > 1 { return .polarNight }
        let hour = acos(cosHour) / rad / 360
        func moment(_ jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400) }
        return .normal(rise: moment(transit - hour), set: moment(transit + hour))
    }
}

/// Wind, said the way a Chinese forecast says it.
public enum Wind {
    private static let points = [tr("北"), tr("东北"), tr("东"), tr("东南"), tr("南"), tr("西南"), tr("西"), tr("西北")]

    /// MET's `wind_from_direction` is where the wind comes from, in degrees
    /// clockwise from north, which is also how a Chinese forecast names it:
    /// a wind from the north-east is 东北风.
    public static func direction(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "-" }
        let normal = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int((normal / 45).rounded()) % 8] + tr("风")
    }

    /// The Beaufort force for a speed in metres a second, which is the
    /// "3 级" every Chinese weather report quotes.
    public static func beaufort(_ metresPerSecond: Double) -> Int {
        let limits: [Double] = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]
        guard metresPerSecond.isFinite else { return 0 }
        return limits.firstIndex { metresPerSecond < $0 } ?? 12
    }

    /// "东北风 3 级 · 4.2 m/s".
    public static func summary(speed: Double, from degrees: Double) -> String {
        let force = beaufort(speed)
        let calm = force == 0
        return calm ? tr("无风") : tr("\(direction(degrees)) \(force) 级 · \(String(format: "%.1f", speed)) m/s")
    }
}

/// The digit shapes the pixel clock draws, five dots by seven.
public enum PixelFont {
    public static let width = 5
    public static let height = 7

    /// Rows top to bottom, a 1 for each lit dot. Nil for a character the
    /// clock never shows.
    public static func glyph(_ character: Character) -> [[Bool]]? {
        guard let rows = table[character] else { return nil }
        return rows.map { row in row.map { $0 == "#" } }
    }

    /// A whole string laid out with one dark column between characters,
    /// as a grid of lit dots. Unknown characters become a blank cell.
    public static func render(_ text: String) -> [[Bool]] {
        var grid = Array(repeating: [Bool](), count: height)
        for (index, character) in text.enumerated() {
            let cell = glyph(character) ?? Array(repeating: Array(repeating: false, count: narrow(character)), count: height)
            for row in 0..<height {
                if index > 0 { grid[row].append(false) }
                grid[row].append(contentsOf: cell[row])
            }
        }
        return grid
    }

    private static func narrow(_ character: Character) -> Int { character == " " ? 2 : width }

    private static let table: [Character: [String]] = [
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        ":": [".", "#", "#", ".", "#", "#", "."],
    ]
}
