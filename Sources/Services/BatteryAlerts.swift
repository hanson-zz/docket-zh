import Foundation
import IOKit
import Observation
@preconcurrency import UserNotifications

/// Sends the 电池 widget's reminders and tells its tiles to flash.
///
/// Fed by BatteryMetrics, which samples from launch, so a reminder does not
/// depend on a tile being on screen. The settings come from the first 电池
/// widget in any layout; with none, nothing is sent. Permission is asked the
/// first time a reminder goes out.
@MainActor @Observable
final class BatteryAlerts {
    static let shared = BatteryAlerts()

    /// Bumped on every reminder; tiles animate on its change.
    private(set) var pulse = 0

    @ObservationIgnored var settings: @MainActor () -> BatteryAlertSettings? = { nil }
    @ObservationIgnored private var tracker = BatteryAlertTracker()
    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var asked = false
    @ObservationIgnored private let presenter = BannerPresenter()

    private init() {}

    /// Whether any layout has a 电池 widget, which is what the reminders
    /// and the slower accessory reads both wait for.
    var hasBatteryWidget: Bool { settings() != nil }

    func check(devices: [BatteryDevice], accessories: [BluetoothBattery]) {
        let now = Date.now
        guard now.timeIntervalSince(lastCheck) >= 15 else { return }
        lastCheck = now
        guard let settings = settings() else {
            tracker = BatteryAlertTracker()
            return
        }
        let mac = devices.first { $0.kind == .mac && $0.present }.map {
            BatteryReading(percent: Int(($0.level * 100).rounded()), onPower: $0.onPower,
                           celsius: Self.temperature())
        }
        // Every accessory once, from the one list: the fixed AirPods and
        // keyboard slots read the same devices, so they are not added again.
        let readings = BluetoothBatteries.alertReadings(accessories)
        let alerts = tracker.check(mac, accessories: readings, settings: settings, now: now)
        guard !alerts.isEmpty else { return }
        pulse += 1
        for alert in alerts {
            Task { await post(alert) }
        }
    }

    private func post(_ alert: BatteryAlert) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "docket.battery.\(alert.id)",
                                            content: content, trigger: nil)
        try? await center.add(request)
    }

    /// The battery's temperature in °C, from AppleSmartBattery (hundredths of a degree).
    private static func temperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString,
                                                          kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        let celsius = value.doubleValue / 100
        return (0...100).contains(celsius) ? celsius : nil
    }
}
