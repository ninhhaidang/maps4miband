import CoreLocation
import Navigator
import Observation

/// Bắt đầu → first GPS fix → Vietmap route from there → Navigator → band, until arrival or Dừng.
// shortcut: GPS only while the app is open, background navigation is #10.
// shortcut: no new route when the rider leaves this one, rerouting is #7.
@Observable
final class Navigation: NSObject {
    private(set) var running = false
    /// What the band shows, or why navigation ended.
    private(set) var status = ""
    private static let noLocation = "App chưa được cấp quyền vị trí. Bật trong Cài đặt → Dẫn đường."

    @ObservationIgnored private let band: BandConnection
    @ObservationIgnored private let gps = CLLocationManager()
    @ObservationIgnored private var destination = Point(lat: 0, lon: 0)
    @ObservationIgnored private var vietmapKey = ""
    @ObservationIgnored private var navigator: Navigator?
    @ObservationIgnored private var routing: Task<Void, Never>?

    init(band: BandConnection) {
        self.band = band
        super.init()
        gps.delegate = self
        gps.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gps.activityType = .otherNavigation
    }

    func start(to destination: Point, authKey: String, vietmapKey: String) {
        guard !running, !band.busy else { return }
        self.destination = destination
        self.vietmapKey = vietmapKey
        band.stream(authKey: authKey, first: BandMessage(i: "Đang tìm đường…").json)
        guard band.busy else {
            status = "Không kết nối được vòng, xem nhật ký."
            return
        }
        running = true
        status = "Đang chờ GPS…"
        gps.requestWhenInUseAuthorization()
        gps.startUpdatingLocation()
    }

    func stop() {
        finish(BandMessage(i: "Đã dừng dẫn đường"), "Đã dừng dẫn đường.")
    }

    private func fail(_ why: String) {
        finish(BandMessage(i: "Lỗi: " + why), "Lỗi: " + why)
    }

    /// Puts `last` on the band, lets go of it and of GPS.
    private func finish(_ last: BandMessage, _ why: String) {
        guard running else { return }
        running = false
        band.finish(last.json)
        gps.stopUpdatingLocation()
        routing?.cancel()
        routing = nil
        navigator = nil
        status = why
    }

    private func route(from here: Point) {
        guard routing == nil else { return }
        status = "Đang tìm đường…"
        routing = Task { @MainActor [weak self, destination, vietmapKey] in
            do {
                let route = try await Vietmap.route(from: here, to: destination, apiKey: vietmapKey)
                guard let self, running else { return }
                navigator = Navigator(route: route)
            } catch {
                self?.fail((error as? Vietmap.Failure)?.message ?? error.localizedDescription)
            }
        }
    }
}

extension Navigation: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.denied, .restricted].contains(manager.authorizationStatus) {
            fail(Self.noLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A cached fix from minutes ago would start the route somewhere else.
        guard running, let fix = locations.last, fix.horizontalAccuracy >= 0, fix.timestamp.timeIntervalSinceNow > -10 else { return }
        guard band.busy else {
            // The band connection failed on its own (reason in the log); nothing left to show the route on.
            return finish(BandMessage(i: ""), "Mất kết nối với vòng, xem nhật ký.")
        }
        let here = Point(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        guard let navigator else { return route(from: here) }
        for effect in navigator.update(here, at: fix.timestamp) {
            switch effect {
            case .send(let m):
                band.send(m.json)
                status = [m.d, m.i, m.r].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            case .arrived(let m):
                finish(m, "Đã đến nơi.")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient; CoreLocation keeps trying.
        if (error as? CLError)?.code == .denied { fail(Self.noLocation) }
    }
}
