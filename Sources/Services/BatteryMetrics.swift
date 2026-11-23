import Foundation
import IOKit
import IOKit.ps
import Observation

enum BatteryDeviceKind: String, Sendable {
    case mac, pods, podsCase, keyboard
}

struct BatteryDevice: Identifiable, Sendable {
    var id: String
    var kind: BatteryDeviceKind
    /// 0...1. Meaningless unless `present`.
    var level: Double
    var charging: Bool
    /// False = nothing reported this battery; render it as unavailable rather
    /// than as an empty one.
    var present: Bool
    /// The Mac only: running from the adapter rather than its battery. Not
    /// the same as `charging`, which is false on an adapter once the battery
    /// is full or charging is held back.
    var onPower: Bool = false
    /// 连着（Mac 有内置电池）但读不到电量：`present` 为 false，界面写「电量不可获取」，
    /// 不写「未连接」，也不画百分比。
    var unreadable: Bool = false
    /// 读数超过 `BluetoothBatteries.staleAfter` 没更新（只有系统信息那份配件会这样）。
    var stale: Bool = false

    static func absent(_ kind: BatteryDeviceKind) -> BatteryDevice {
        BatteryDevice(id: kind.rawValue, kind: kind, level: 0, charging: false, present: false)
    }

    /// 连着但读不到电量的那一格。
    static func unreadableSlot(_ kind: BatteryDeviceKind) -> BatteryDevice {
        BatteryDevice(id: kind.rawValue, kind: kind, level: 0, charging: false, present: false, unreadable: true)
    }
}

/// The Mac's adapter and time estimates, from the power-source API.
struct MacPower: Equatable, Sendable {
    /// The adapter's rating, while one is connected.
    var watts: Int?
    /// macOS's estimates in minutes; -1 while it is still working one out.
    var minutesToFull: Int?
    var minutesToEmpty: Int?
    /// macOS considers the battery full.
    var charged = false
}

/// AppleSmartBattery's longer-term figures. Each one is nil when this Mac
/// does not publish it, and the panel then leaves that item out.
struct MacBatteryHealth: Equatable, Sendable {
    var capacityPercent: Int?
    var cycles: Int?
    var celsius: Double?

    var isEmpty: Bool { capacityPercent == nil && cycles == nil && celsius == nil }
}

/// Battery levels for the Mac and whatever Bluetooth accessories are connected.
///
/// The Mac comes from the power-source API; Apple accessories publish a
/// `BatteryPercent` in the IO registry, and System Information adds the
/// ones that do not (see `SystemProfilerBluetooth`). Anything that does not answer is
/// reported absent - a desktop Mac and a missing pair of AirPods look the
/// same to this class, and both are honest.
@MainActor @Observable
final class BatteryMetrics {
    static let shared = BatteryMetrics()

    /// Always one entry per kind, in this order, so a view can lay out fixed slots.
    private(set) var devices: [BatteryDevice] = BatteryMetrics.order.map(BatteryDevice.absent)
    /// Every connected Bluetooth accessory that reports a battery, AirPods
    /// and keyboards included, in the panel's order.
    private(set) var accessories: [BluetoothBattery] = []
    /// Which accessory the fixed AirPods and keyboard slots are reading, so
    /// a card that shows those slots does not show the same device again.
    @ObservationIgnored private(set) var slotSources: [BatteryDeviceKind: String] = [:]
    /// The Mac's adapter and estimates, for the panel's status line.
    private(set) var power = MacPower()
    /// Read once a minute: these move over weeks, not seconds.
    private(set) var health = MacBatteryHealth()
    /// 低电量模式, which tints every look yellow.
    private(set) var lowPowerMode = false
    /// One sample per five minutes over the last two days, kept on disk.
    private(set) var history = BatteryHistory()
    /// When the adapter was last connected, for the plug-in sweep.
    private(set) var pluggedAt: Date?
    /// When the adapter was last pulled out, for the liquid look's small slosh.
    private(set) var unpluggedAt: Date?
    /// When the battery last reached 100% on the adapter, for the gold glow.
    private(set) var fullAt: Date?
    /// 充满（100% 或到达生效中的充电上限）时小熊猫挥爪那一下，停 2.4 秒；到期后清掉，
    /// 电池卡片和面板就不再画小熊猫（判定在 Core，见 `BatteryFullWatch`）。
    private(set) var fullPulse: PandaPulse?
    /// 蓝牙配件连上、断开、电量低的轻提示有变化（出现或到期）时加一，多设备卡片读它来刷新；
    /// 提示本身在 `accessoryFlash(id:group:)`。不随每秒的采样变化。
    private(set) var accessoryFlashVersion = 0

    @ObservationIgnored private var fullWatch = BatteryFullWatch()
    @ObservationIgnored private var fullWatchPercent: Int?
    /// 充电上限打开、接着电源时上一次重读助手状态文件的时刻。电量停在上限不动时也要隔一会儿
    /// 读一次：状态文件 2 分钟没重读就算过期，上限会被当成没生效，挥爪那条线跟着来回跳。
    @ObservationIgnored private var limitsReadAt = Date.distantPast
    @ObservationIgnored private var accessoryChanges = AccessoryChangeTracker()
    @ObservationIgnored private var lastOnPower: Bool?
    @ObservationIgnored private var lastLevel: Double?
    @ObservationIgnored private var healthReadAt = Date.distantPast
    @ObservationIgnored private var historyLoaded = false

    private static let order: [BatteryDeviceKind] = [.mac, .pods, .podsCase, .keyboard]

    @ObservationIgnored private var timer: Timer?
    /// 最近一次采样的时刻。不进观察（每秒都变，进了会每秒唤醒所有电池卡片），
    /// 多设备圆环悬停时读它写「更新于」。
    @ObservationIgnored private(set) var sampledAt: Date?
    @ObservationIgnored private var profiler: [BluetoothBattery] = []
    /// 上一份读成功的系统信息快照是什么时候开始读的；读失败不算，旧快照不会因此「变新」。
    @ObservationIgnored private var profiledAt = Date.distantPast
    /// 上一次去读系统信息（成功与否）的时刻，只管多久再读一次。
    @ObservationIgnored private var profileTriedAt = Date.distantPast
    @ObservationIgnored private var profiling = false
    /// 上一份快照之后从注册表里消失的配件，见 `AccessoryDepartures`。
    @ObservationIgnored private var departures = AccessoryDepartures()
    @ObservationIgnored private var lastRegistry: [BluetoothBattery] = []

    /// System Information is slow (a second or two) and its readings move
    /// slowly, so it is asked every few minutes (`BluetoothBatteries.profilerInterval`),
    /// off the main thread. A snapshot older than `BluetoothBatteries.profilerDropAfter`
    /// is not used at all, so a headset switched off does not linger for ever.

    private init() {}

    func device(_ kind: BatteryDeviceKind) -> BatteryDevice? {
        devices.first { $0.kind == kind }
    }

    /// The accessory a fixed slot reads, if any.
    func source(of kind: BatteryDeviceKind) -> BluetoothBattery? {
        guard let id = slotSources[kind] else { return nil }
        return accessories.first { $0.id == id }
    }

    /// 多设备卡片某一格现在的轻提示（2.5 秒内）；没有时 nil。读 `accessoryFlashVersion` 跟着刷新。
    func accessoryFlash(id: String?, group: String, now: Date = .now) -> AccessoryChange? {
        _ = accessoryFlashVersion
        return accessoryChanges.flash(id: id, group: group, now: now)
    }

    /// The panel's summary line for the Mac, or nil without a battery.
    var statusLine: String? {
        guard let mac = device(.mac), mac.present else { return nil }
        return BatteryStatusText.line(percent: BatteryColorMap.percent(mac.level), charging: mac.charging,
                                      onPower: mac.onPower, charged: power.charged, watts: power.watts,
                                      minutesToFull: power.minutesToFull, minutesToEmpty: power.minutesToEmpty)
    }

    /// 每张电池卡片、电池面板出现时都调用。卡片、面板读的都是这一个采样器的
    /// `devices`，同一刻显示同一个电量；已经在跑但上一次采样超过 2 秒（比如刚从
    /// 睡眠醒来、计时器还没赶上），先补采一次，新出现的那张不会先画旧数。
    func start() {
        if timer != nil {
            if let sampledAt, Date.now.timeIntervalSince(sampledAt) > 2 { sample() }
            return
        }
        loadHistory()
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        // 两次采样隔了半分钟以上（睡眠醒来）：蓝牙配件会成批断开再连上，轻提示重新当底数。
        if let previous = sampledAt, Date.now.timeIntervalSince(previous) > 30 {
            accessoryChanges.rebaseline(now: .now)
        }
        let now = Date.now
        sampledAt = now
        let registry = Self.registryAccessories()
        lastRegistry = registry
        let departed = departures.update(registry: registry, now: now)
        refreshProfilerIfDue()
        let profiled = now.timeIntervalSince(profiledAt) < BluetoothBatteries.profilerDropAfter ? profiler : []
        let merged = BluetoothBatteries.panelOrder(BluetoothBatteries.markStale(
            BluetoothBatteries.merge(registry: registry, profiler: profiled, departed: departed), now: now))

        var found: [BatteryDeviceKind: BatteryDevice] = [:]
        var sources: [BatteryDeviceKind: String] = [:]
        let macReading = Self.macDevice()
        if let reading = macReading, reading.0.present {
            let (mac, macPower) = reading
            found[.mac] = mac
            if macPower != power { power = macPower }
            noteTransitions(mac)
            noteFull(mac)
            recordHistory(mac)
        } else {
            // 有内置电池却读不到电量（电源 API 这一刻没给容量）：写「电量不可获取」，
            // 不留上一秒的百分比，也不记进今日曲线。
            if let reading = macReading, reading.0.unreadable { found[.mac] = reading.0 }
            if power != MacPower() { power = MacPower() }
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if lowPower != lowPowerMode { lowPowerMode = lowPower }
        refreshHealthIfDue(hasBattery: found[.mac] != nil)
        // The old fixed slots, read from the same list (`BluetoothBatteries.budsSource`,
        // `keyboardSource`): one with a usable level first; one that is connected but
        // reports nothing says 电量不可获取 rather than 未连接 or an old number.
        if let pods = BluetoothBatteries.budsSource(merged) {
            if let level = pods.level {
                found[.pods] = BatteryDevice(id: "pods", kind: .pods, level: Double(level) / 100,
                                             charging: pods.charging, present: true, stale: pods.stale)
            } else {
                found[.pods] = .unreadableSlot(.pods)
            }
            if let caseLevel = pods.caseLevel {
                found[.podsCase] = BatteryDevice(id: "podsCase", kind: .podsCase, level: Double(caseLevel) / 100,
                                                 charging: false, present: true, stale: pods.stale)
            }
            sources[.pods] = pods.id
            sources[.podsCase] = pods.id
        }
        if let keyboard = BluetoothBatteries.keyboardSource(merged) {
            if let level = keyboard.level {
                found[.keyboard] = BatteryDevice(id: "keyboard", kind: .keyboard, level: Double(level) / 100,
                                                 charging: keyboard.charging, present: true, stale: keyboard.stale)
            } else {
                found[.keyboard] = .unreadableSlot(.keyboard)
            }
            sources[.keyboard] = keyboard.id
        }
        let next = Self.order.map { found[$0] ?? .absent($0) }
        if !Self.same(next, devices) { devices = next }
        if merged != accessories { accessories = merged }
        slotSources = sources
        noteAccessoryChanges(merged)
        if let pulse = fullPulse, !pulse.isActive(at: .now) { fullPulse = nil }
        BatteryAlerts.shared.check(devices: devices, accessories: merged)
    }

    /// Writing an equal value still wakes every observer, once a second.
    private static func same(_ a: [BatteryDevice], _ b: [BatteryDevice]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.kind == $1.kind && $0.level == $1.level && $0.charging == $1.charging
                && $0.present == $1.present && $0.onPower == $1.onPower
                && $0.unreadable == $1.unreadable && $0.stale == $1.stale
        }
    }

    // MARK: - System Information

    /// Only while a 电池 widget is in some layout: with none, nobody reads
    /// the accessories and the subprocess would be waste.
    private func refreshProfilerIfDue() {
        let interval = BluetoothBatteries.profilerInterval(registry: lastRegistry, profiler: profiler)
        guard !profiling, Date.now.timeIntervalSince(profileTriedAt) >= interval,
              BatteryAlerts.shared.hasBatteryWidget else { return }
        profiling = true
        let started = Date.now
        profileTriedAt = started
        Task.detached(priority: .utility) {
            let data = Self.runProfiler()
            let parsed = data.map { SystemProfilerBluetooth.parse($0, keepUnreadable: true, readAt: started) } ?? []
            await MainActor.run {
                let metrics = BatteryMetrics.shared
                let now = Date.now
                metrics.profiling = false
                // 读失败（data 为 nil）时旧快照原样留着、读到的时刻也不改：它照常变旧、标过期，
                // 到 `profilerDropAfter` 整份不用，不会因为又试了一次就被当成新读数。
                guard data != nil else { return }
                // 第一次（启动后系统信息可能要十几秒才回来）或过期以后重新报上来的那批配件，
                // 不算「已连上」，轻提示从这里重新当底数。
                let wasStale = now.timeIntervalSince(metrics.profiledAt) >= BluetoothBatteries.profilerDropAfter
                metrics.profiledAt = started
                metrics.profiler = parsed
                metrics.departures.snapshotArrived(startedAt: started)
                if wasStale { metrics.accessoryChanges.rebaseline(now: now) }
            }
        }
    }

    nonisolated private static func runProfiler() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    // MARK: - Mac

    /// The adapter going in, and the battery reaching full on it: each
    /// stamps a moment the looks animate from once.
    private func noteTransitions(_ mac: BatteryDevice) {
        let now = Date.now
        switch BatteryLiquidFX.plugEvent(previous: lastOnPower, current: mac.onPower) {
        case .plugged: pluggedAt = now
        case .unplugged: unpluggedAt = now
        case nil: break
        }
        lastOnPower = mac.onPower
        if mac.onPower, mac.level >= 0.995, let previous = lastLevel, previous < 0.995 { fullAt = now }
        lastLevel = mac.level
    }

    /// 充满时挥爪一次。充电上限打开时，电量每变一格、或至少每 30 秒重新看一眼助手的状态文件
    /// （平时它只在面板打开时刷新），上限真在生效才把那条线降到上限。
    private func noteFull(_ mac: BatteryDevice) {
        let now = Date.now
        let percent = BatteryColorMap.percent(mac.level)
        let limits = ChargeLimitService.shared
        if mac.onPower, limits.config.isActive,
           percent != fullWatchPercent || now.timeIntervalSince(limitsReadAt) >= 30 {
            limits.refresh()
            limitsReadAt = now
        }
        fullWatchPercent = percent
        let effective = limits.effect(unlocked: ProAccess.isUnlocked, now: now).isEffective
        let target = BatteryPandaCue.fullTarget(effectiveLimit: effective ? limits.config.clamped.limit : nil)
        if fullWatch.update(percent: percent, onPower: mac.onPower, target: target) {
            fullPulse = BatteryPandaCue.fullPulse(at: now)
        }
    }

    /// 配件连上、断开、跌破 20%：只给多设备卡片画 2 到 3 秒的轻提示，不发系统通知。
    private func noteAccessoryChanges(_ merged: [BluetoothBattery]) {
        let now = Date.now
        let expired = accessoryChanges.prune(now: now)
        let changes = accessoryChanges.update(AccessoryPresence.from(merged), now: now)
        if expired || !changes.isEmpty { accessoryFlashVersion &+= 1 }
    }

    // MARK: - History

    private static var historyURL: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.docket-zh.app"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "battery-history.json")
    }

    private func loadHistory() {
        guard !historyLoaded else { return }
        historyLoaded = true
        if let data = try? Data(contentsOf: Self.historyURL),
           var decoded = try? JSONDecoder().decode(BatteryHistory.self, from: data) {
            decoded.prune(now: .now)
            history = decoded
        }
    }

    /// The first second of each five-minute slot, so the file is written
    /// at most twelve times an hour.
    private func recordHistory(_ mac: BatteryDevice) {
        let now = Date.now
        guard history.wants(now) else { return }
        var next = history
        guard next.record(percent: BatteryColorMap.percent(mac.level), charging: mac.charging, at: now) else { return }
        history = next
        let url = Self.historyURL
        if let data = try? JSONEncoder().encode(next) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Health

    private func refreshHealthIfDue(hasBattery: Bool) {
        let now = Date.now
        guard now.timeIntervalSince(healthReadAt) >= 60 else { return }
        healthReadAt = now
        let next = hasBattery ? Self.readHealth() : MacBatteryHealth()
        if next != health { health = next }
    }

    /// `AppleRawMaxCapacity`/`DesignCapacity` (or `MaxCapacity`),
    /// `CycleCount` and `Temperature` off AppleSmartBattery.
    private static func readHealth() -> MacBatteryHealth {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return MacBatteryHealth() }
        defer { IOObjectRelease(service) }
        guard let properties = properties(of: service) else { return MacBatteryHealth() }
        func int(_ key: String) -> Int? { (properties[key] as? NSNumber)?.intValue }
        return MacBatteryHealth(
            capacityPercent: BatteryHealth.maximumCapacityPercent(rawMax: int("AppleRawMaxCapacity"),
                                                                  design: int("DesignCapacity"),
                                                                  maxCapacity: int("MaxCapacity")),
            cycles: BatteryHealth.cycleCount(int("CycleCount")),
            celsius: BatteryHealth.celsius(raw: int("Temperature")))
    }

    private static func macDevice() -> (BatteryDevice, MacPower)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType else { continue }
            guard let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey as String] as? Int, capacity > 0,
                  current >= 0
            else {
                // 有内置电池，这一刻读不到容量：不是台式机，也不该显示上一秒的数。
                return (.unreadableSlot(.mac), MacPower())
            }
            let onPower = description[kIOPSPowerSourceStateKey as String] as? String == kIOPSACPowerValue
            let charged = description[kIOPSIsChargedKey as String] as? Bool ?? false
            let powerSourceSays = description[kIOPSIsChargingKey as String] as? Bool ?? false
            // Only ask the registry when the power source API says no on
            // the adapter: that is the case it gets wrong.
            let registry: (isCharging: Bool?, amperage: Int?) =
                (!powerSourceSays && onPower && !charged) ? smartBatteryCharging() : (nil, nil)
            let charging = BatteryChargingState.isCharging(powerSourceSays: powerSourceSays, onPower: onPower,
                                                           charged: charged,
                                                           registryIsCharging: registry.isCharging,
                                                           amperage: registry.amperage)
            let device = BatteryDevice(
                id: BatteryDeviceKind.mac.rawValue,
                kind: .mac,
                level: min(Double(current) / Double(capacity), 1),
                charging: charging,
                present: true,
                onPower: onPower
            )
            var power = MacPower()
            power.minutesToFull = description[kIOPSTimeToFullChargeKey as String] as? Int
            power.minutesToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int
            power.charged = charged
            if onPower, let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
                power.watts = adapter[kIOPSPowerAdapterWattsKey as String] as? Int
            }
            return (device, power)
        }
        return nil  // desktop Mac, or the API gave us nothing
    }

    /// AppleSmartBattery's own IsCharging and the current into the battery
    /// in mA (InstantAmperage, else Amperage; negative while discharging).
    private static func smartBatteryCharging() -> (isCharging: Bool?, amperage: Int?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func value(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        func milliamps(_ key: String) -> Int? {
            guard let number = value(key) as? NSNumber else { return nil }
            // The registry stores these as unsigned 64-bit; reinterpret.
            return Int(truncatingIfNeeded: number.int64Value)
        }
        let isCharging = (value("IsCharging") as? NSNumber)?.boolValue
        let amperage = milliamps("InstantAmperage") ?? milliamps("Amperage")
        return (isCharging, amperage)
    }

    // MARK: - Accessories

    /// AirPods, Beats, and the Magic Mouse, Trackpad and Keyboard hang off
    /// `AppleDeviceManagementHIDEventService` and publish battery
    /// percentages as plain registry properties. Most third-party devices do
    /// not, and come from System Information instead.
    private static func registryAccessories() -> [BluetoothBattery] {
        var found: [BluetoothBattery] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return found
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            guard let properties = properties(of: service) else { continue }
            // Mac 自己的键盘触控板（Built-In = Yes，走 SPI）不是配件，就算报了电量也不算，
            // 免得 Mac 的电量被当成一个蓝牙设备再画一遍。
            if (properties["Built-In"] as? Bool) == true { continue }
            let name = (properties["Product"] as? String) ?? ""
            let main = BluetoothBattery.percent(properties["BatteryPercent"])
            let left = BluetoothBattery.percent(properties["BatteryPercentLeft"])
            let right = BluetoothBattery.percent(properties["BatteryPercentRight"])
            let caseLevel = BluetoothBattery.percent(properties["BatteryPercentCase"])
            let address = (properties["DeviceAddress"] as? String)
                ?? (properties["SerialNumber"] as? String)
            let kind = AccessoryClassifier.kind(AccessoryHints(
                name: name,
                productID: BluetoothBattery.hexOrInt(properties["ProductID"]),
                vendorID: BluetoothBattery.hexOrInt(properties["VendorID"]),
                usagePage: BluetoothBattery.hexOrInt(properties["PrimaryUsagePage"]),
                usage: BluetoothBattery.hexOrInt(properties["PrimaryUsage"]),
                hasBuds: left != nil || right != nil))
            // 没报电量的：只有蓝牙连着的耳机、鼠标、触控板、键盘留下，写「电量不可获取」。
            let reported = main != nil || left != nil || right != nil || caseLevel != nil
            guard reported || BluetoothBatteries.keepsUnreadable(kind: kind,
                                                                 transport: properties["Transport"] as? String)
            else { continue }
            // Magic accessories report 3 in BatteryStatusFlags while on the
            // cable. Not documented; nothing else reports charging here.
            let flags = BluetoothBattery.hexOrInt(properties["BatteryStatusFlags"])
            let device = BluetoothBattery(
                id: BluetoothBattery.makeID(address: address, name: name),
                name: name, kind: kind, main: main, left: left, right: right, caseLevel: caseLevel,
                charging: flags == 3, address: BluetoothBattery.normalizedAddress(address))
            // One device can publish several services; the first one wins, unless it
            // reports no battery and a later one does.
            BluetoothBatteries.insert(device, into: &found)
        }
        return found
    }

    private static func properties(of service: io_service_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return properties
    }
}

extension BatteryMetrics {
    /// Config-string form, for callers that hold raw config values.
    func isPresent(configValue: String) -> Bool {
        let kind: BatteryDeviceKind? = switch configValue {
        case "mac": .mac
        case "pods": .pods
        case "case": .podsCase
        case "keyboard": .keyboard
        default: nil
        }
        guard let kind else { return false }
        return device(kind)?.present == true
    }
}
