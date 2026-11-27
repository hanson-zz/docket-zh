import AppKit
import CoreLocation
import MapKit
import Observation

/// Where the user actually is, for the weather widget.
///
/// The widget previously took a city typed into its config, defaulting to the
/// reference shelf's "Oslo". Guessing from the system time zone is no better -
/// `Asia/Kolkata` covers the whole country, so it names a city most of its
/// users do not live in.
///
/// Asked for once, lazily, and only because a weather widget is on the shelf.
/// A refusal is remembered rather than re-prompted, and leaves the widget on
/// whatever city was configured.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    /// The nearest named place, once known.
    private(set) var city: String?
    private(set) var coordinate: CLLocationCoordinate2D?
    /// True once the user has said no, so nothing asks again.
    private(set) var denied = false
    /// True when no answer arrived at all - see `start()`.
    private(set) var unavailable = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var asked = false

    private override init() {
        super.init()
        manager.delegate = self
        // A city name needs kilometres, not metres, and the coarse setting
        // avoids waking the GPS.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Idempotent: the first weather widget to appear starts this, the rest
    /// find it already running.
    func start() {
        guard !asked, !denied else { return }
        asked = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Measured on this machine: the request returns with the status
            // still `notDetermined` and no prompt on screen, and promoting the
            // app to `.regular` first - which is what makes the automation
            // consent appear - does not change that. So the widget must not
            // wait on an answer that may never come: after a few seconds it
            // says so, and offers the city field instead.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if self.manager.authorizationStatus == .notDetermined { self.unavailable = true }
            }
        case .denied, .restricted:
            denied = true
        default:
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // `self.manager` rather than the parameter: the delegate argument
            // is not Sendable, so it cannot cross into this isolated body.
            switch self.manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                denied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            coordinate = location.coordinate
            Task { await self.name(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: any Error) {
        // Nothing to do: the widget keeps whatever city it already had.
    }

    /// Reverse-geocodes to something a person would call the place.
    ///
    /// MapKit rather than `CLGeocoder`, which is deprecated on macOS 26. Its
    /// `cityWithContext` reads "Mumbai, Maharashtra"; the widget wants the
    /// city alone, and a map item's `name` is the nearest *street*.
    private func name(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first,
              let context = item.addressRepresentations?.cityWithContext,
              let place = PhotoMemory.placeName(cityWithContext: context)
        else { return }
        city = place
    }
}
