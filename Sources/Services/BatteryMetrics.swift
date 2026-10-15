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

    static func absent(_ kind: BatteryDeviceKind) -> BatteryDevice {
        BatteryDevice(id: kind.rawValue, kind: kind, level: 0, charging: false, present: false)
    }
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

    private static let order: [BatteryDeviceKind] = [.mac, .pods, .podsCase, .keyboard]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var profiler: [BluetoothBattery] = []
    @ObservationIgnored private var profiledAt = Date.distantPast
    @ObservationIgnored private var profiling = false

    /// System Information is slow (a second or two) and its readings move
    /// slowly, so it is asked every five minutes, off the main thread.
    static let profilerInterval: TimeInterval = 5 * 60
    /// A device only System Information knows is dropped once its snapshot
    /// is this old, so a headset switched off does not linger for ever.
    static let profilerStale: TimeInterval = 11 * 60

    private init() {}

    func device(_ kind: BatteryDeviceKind) -> BatteryDevice? {
        devices.first { $0.kind == kind }
    }

    /// The accessory a fixed slot reads, if any.
    func source(of kind: BatteryDeviceKind) -> BluetoothBattery? {
        guard let id = slotSources[kind] else { return nil }
        return accessories.first { $0.id == id }
    }

    func start() {
        guard timer == nil else { return }
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
        let registry = Self.registryAccessories()
        refreshProfilerIfDue()
        let profiled = Date.now.timeIntervalSince(profiledAt) < Self.profilerStale ? profiler : []
        let merged = BluetoothBatteries.panelOrder(
            BluetoothBatteries.merge(registry: registry, profiler: profiled))

        var found: [BatteryDeviceKind: BatteryDevice] = [:]
        var sources: [BatteryDeviceKind: String] = [:]
        if let mac = Self.macDevice() { found[.mac] = mac }
        // The old fixed slots, read from the same list: the first AirPods
        // (or any buds pair) and the first keyboard.
        let pods = merged.first { $0.kind.isAirPods && $0.hasBuds }
            ?? merged.first { $0.kind.isAirPods }
            ?? merged.first { $0.hasBuds }
        if let pods {
            if let level = pods.level {
                found[.pods] = BatteryDevice(id: "pods", kind: .pods, level: Double(level) / 100,
                                             charging: pods.charging, present: true)
            }
            if let caseLevel = pods.caseLevel {
                found[.podsCase] = BatteryDevice(id: "podsCase", kind: .podsCase, level: Double(caseLevel) / 100,
                                                 charging: false, present: true)
            }
            sources[.pods] = pods.id
            sources[.podsCase] = pods.id
        }
        if let keyboard = merged.first(where: { $0.kind == .keyboard }), let level = keyboard.level {
            found[.keyboard] = BatteryDevice(id: "keyboard", kind: .keyboard, level: Double(level) / 100,
                                             charging: keyboard.charging, present: true)
            sources[.keyboard] = keyboard.id
        }
        let next = Self.order.map { found[$0] ?? .absent($0) }
        if !Self.same(next, devices) { devices = next }
        if merged != accessories { accessories = merged }
        slotSources = sources
        BatteryAlerts.shared.check(devices: devices, accessories: merged)
    }

    /// Writing an equal value still wakes every observer, once a second.
    private static func same(_ a: [BatteryDevice], _ b: [BatteryDevice]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.kind == $1.kind && $0.level == $1.level && $0.charging == $1.charging
                && $0.present == $1.present && $0.onPower == $1.onPower
        }
    }

    // MARK: - System Information

    /// Only while a 电池 widget is in some layout: with none, nobody reads
    /// the accessories and the subprocess would be waste.
    private func refreshProfilerIfDue() {
        guard !profiling, Date.now.timeIntervalSince(profiledAt) >= Self.profilerInterval,
              BatteryAlerts.shared.hasBatteryWidget else { return }
        profiling = true
        Task.detached(priority: .utility) {
            let data = Self.runProfiler()
            let parsed = data.map(SystemProfilerBluetooth.parse) ?? []
            await MainActor.run {
                let metrics = BatteryMetrics.shared
                metrics.profiling = false
                metrics.profiledAt = .now
                if data != nil { metrics.profiler = parsed }
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

    private static func macDevice() -> BatteryDevice? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType else { continue }
            guard let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey as String] as? Int, capacity > 0
            else { continue }
            return BatteryDevice(
                id: BatteryDeviceKind.mac.rawValue,
                kind: .mac,
                level: min(Double(current) / Double(capacity), 1),
                charging: description[kIOPSIsChargingKey as String] as? Bool ?? false,
                present: true,
                onPower: description[kIOPSPowerSourceStateKey as String] as? String == kIOPSACPowerValue
            )
        }
        return nil  // desktop Mac, or the API gave us nothing
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
            let name = (properties["Product"] as? String) ?? ""
            let main = BluetoothBattery.percent(properties["BatteryPercent"])
            let left = BluetoothBattery.percent(properties["BatteryPercentLeft"])
            let right = BluetoothBattery.percent(properties["BatteryPercentRight"])
            let caseLevel = BluetoothBattery.percent(properties["BatteryPercentCase"])
            guard main != nil || left != nil || right != nil || caseLevel != nil else { continue }
            let address = (properties["DeviceAddress"] as? String)
                ?? (properties["SerialNumber"] as? String)
            let kind = AccessoryClassifier.kind(AccessoryHints(
                name: name,
                productID: BluetoothBattery.hexOrInt(properties["ProductID"]),
                vendorID: BluetoothBattery.hexOrInt(properties["VendorID"]),
                usagePage: BluetoothBattery.hexOrInt(properties["PrimaryUsagePage"]),
                usage: BluetoothBattery.hexOrInt(properties["PrimaryUsage"]),
                hasBuds: left != nil || right != nil))
            // Magic accessories report 3 in BatteryStatusFlags while on the
            // cable. Not documented; nothing else reports charging here.
            let flags = BluetoothBattery.hexOrInt(properties["BatteryStatusFlags"])
            let device = BluetoothBattery(
                id: BluetoothBattery.makeID(address: address, name: name),
                name: name, kind: kind, main: main, left: left, right: right, caseLevel: caseLevel,
                charging: flags == 3, address: BluetoothBattery.normalizedAddress(address))
            // One device can publish several services; the first one wins.
            if !found.contains(where: { $0.id == device.id }) { found.append(device) }
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
