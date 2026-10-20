import AppKit
import Foundation

/// 壁纸按早中晚自动换（Pro）：从启动起每 30 秒看一次每个布局里的壁纸卡片。
///
/// 不靠扩展栏上的卡片重画，卡片在文件夹里、别的布局里或扩展栏隐藏时照样换。
/// 每张卡片换到哪一段（`WallpaperSchedule.Occurrence.key`，日期加段名）记在
/// UserDefaults，同一段只换一次，重启后不重换；刚打开开关、或 Mac 睡过了点，
/// 下一次看的时候补换当前这一段。没解锁 Pro 时什么也不做（设置照旧存着）。
/// 固定这张的那段没设图片、或图片找不到了，就不换，也不记，设好后下一次补上。
@MainActor
final class WallpaperAutoDriver {
    static let shared = WallpaperAutoDriver()

    /// 每个布局里的每个小组件。DocketApp 接上。
    var widgets: @MainActor () -> [WidgetInstance] = { [] }

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private static let appliedKey = "wallpaper.autoApplied"

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { WallpaperAutoDriver.shared.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // 合盖睡过了点，醒来马上补一次。
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WallpaperAutoDriver.shared.tick() }
        }
        tick()
    }

    /// 那天的日出日落，按这台 Mac 的时钟换成分钟数；极昼极夜是 nil。
    static func sunMinutes(on date: Date, latitude: Double, longitude: Double) -> (rise: Int, set: Int)? {
        guard case .normal(let rise, let set)? = SunTimes.on(date, latitude: latitude, longitude: longitude,
                                                              zone: .current) else { return nil }
        return (WallpaperSchedule.minuteOfDay(rise), WallpaperSchedule.minuteOfDay(set))
    }

    func tick(now: Date = .now) {
        guard ProAccess.isUnlocked else { return }
        let walls = widgets().filter { $0.kind == .wallpaper }
        guard !walls.isEmpty else { return }
        var applied = UserDefaults.standard.dictionary(forKey: Self.appliedKey) as? [String: String] ?? [:]
        var changed = false
        let sun = WeatherService.shared.place.flatMap {
            Self.sunMinutes(on: now, latitude: $0.lat, longitude: $0.lon)
        }
        for wall in walls where ProLicenseGate.wallpaperAutoChangeActive(wall.config, unlocked: true) {
            let minutes = WallpaperSchedule.effectiveMinutes(wall.config, sunrise: sun?.rise, sunset: sun?.set)
            guard let occurrence = WallpaperSchedule.slot(at: now, minutes: minutes) else { continue }
            let id = wall.id.uuidString
            // 固定这张时把那张的路径也算进去：当前这段换了图片，马上换上新的。
            let key = WallpaperSchedule.source(wall.config) == .fixed
                ? "\(occurrence.key)|\(wall.config.string(occurrence.slot.pictureKey))"
                : occurrence.key
            guard applied[id] != key else { continue }
            let service = WallpaperService.shared
            service.read()
            let candidates = Set(
                WallpaperSchedule.favorites(wall.config) + [wall.config.string(occurrence.slot.pictureKey)]
            ).filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
            guard let path = WallpaperSchedule.pick(occurrence.slot, config: wall.config,
                                                    current: service.current?.path,
                                                    available: candidates,
                                                    roll: Double.random(in: 0..<1)) else { continue }
            service.set(URL(fileURLWithPath: path), allScreens: wall.config.bool("allScreens", default: true))
            applied[id] = key
            changed = true
        }
        if changed {
            // 删掉已经不在任何布局里的卡片。
            let live = Set(walls.map(\.id.uuidString))
            applied = applied.filter { live.contains($0.key) }
            UserDefaults.standard.set(applied, forKey: Self.appliedKey)
        }
    }
}
