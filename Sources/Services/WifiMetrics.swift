import CoreWLAN
import Foundation
import Observation

/// The Wi-Fi link the Mac is on, read every two seconds from CoreWLAN.
///
/// Signal, noise and the negotiated rate need no permission. The network's
/// name does: since macOS 14 `ssid()` returns nil without Location access,
/// so the panel shows it only when the system hands it over.
@MainActor @Observable
final class WifiMetrics {
    static let shared = WifiMetrics()

    /// nil when Wi-Fi is off or not joined to a network.
    private(set) var rssi: Int?
    private(set) var noise: Int?
    private(set) var rate: Double?
    private(set) var ssid: String?
    private(set) var isPoweredOn = false

    @ObservationIgnored private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 只读一次，不开定时器（网络活动面板打开时读网络名用）。
    func sampleNow() { sample() }

    private func sample() {
        guard let interface = CWWiFiClient.shared().interface() else {
            isPoweredOn = false
            rssi = nil; noise = nil; rate = nil; ssid = nil
            return
        }
        isPoweredOn = interface.powerOn()
        let value = interface.rssiValue()
        // 0 is CoreWLAN's "not associated".
        guard isPoweredOn, value < 0 else {
            rssi = nil; noise = nil; rate = nil; ssid = nil
            return
        }
        rssi = value
        let noiseValue = interface.noiseMeasurement()
        noise = noiseValue < 0 ? noiseValue : nil
        let tx = interface.transmitRate()
        rate = tx > 0 ? tx : nil
        ssid = interface.ssid()
    }
}
