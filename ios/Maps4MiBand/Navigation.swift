import CoreLocation
import Navigator
import Observation

/// plan → first GPS fix → Vietmap route from there, shown as `preview`; Bắt đầu → Navigator on that same route
/// → band, until arrival or Dừng. Off the route it asks Vietmap again.
// shortcut: GPS only while the app is open, background navigation is #10.
@Observable
final class Navigation: NSObject {
    private(set) var running = false
    /// Waiting for GPS or Vietmap to show the route before Bắt đầu.
    private(set) var planning = false
    /// The route Bắt đầu will follow.
    private(set) var preview: Route?
    /// What the band shows, or why navigation ended.
    private(set) var status = ""
    private static let noLocation = "App chưa được cấp quyền vị trí. Bật trong Cài đặt → Dẫn đường."

    @ObservationIgnored private let band: BandConnection
    @ObservationIgnored private let gps = CLLocationManager()
    @ObservationIgnored private var destination = Point(lat: 0, lon: 0)
    @ObservationIgnored private var vietmapKey = ""
    @ObservationIgnored private var navigator: Navigator?
    @ObservationIgnored private var routing: Task<Void, Never>?
    @ObservationIgnored private let fetchRoute: (Point, Point, String) async throws -> Route

    init(band: BandConnection, fetchRoute: @escaping (Point, Point, String) async throws -> Route = Vietmap.route) {
        self.band = band
        self.fetchRoute = fetchRoute
        super.init()
        gps.delegate = self
        gps.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        gps.activityType = .otherNavigation
    }

    /// Last known position, for ranking search results; nil before the first fix.
    var here: Point? {
        gps.location.map { Point(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
    }

    /// Routes from the next GPS fix to `destination` into `preview`.
    func plan(to destination: Point, vietmapKey: String) {
        guard !running else { return }
        cancelPlan()
        self.destination = destination
        self.vietmapKey = vietmapKey
        planning = true
        status = "Đang chờ GPS…"
        gps.requestWhenInUseAuthorization()
        gps.startUpdatingLocation()
    }

    /// Drops the preview and any plan in flight, e.g. once the user looks for another destination.
    func cancelPlan() {
        guard !running else { return }
        routing?.cancel()
        routing = nil
        if planning { gps.stopUpdatingLocation() }
        (preview, planning, status) = (nil, false, "")
    }

    /// Follows `preview` as it is; the first fix shows where it goes, or asks for a new one if far from its start.
    func start(authKey: String) {
        guard !running, !planning, !band.busy, let preview else { return }
        band.stream(authKey: authKey, first: BandMessage(i: "Đang chờ GPS…").json)
        guard band.busy else {
            status = "Không kết nối được vòng, xem nhật ký."
            return
        }
        running = true
        navigator = Navigator(route: preview)
        status = "Đang chờ GPS…"
        gps.startUpdatingLocation()
    }

    func stop() {
        finish(BandMessage(i: "Đã dừng dẫn đường"), "Đã dừng dẫn đường.")
    }

    private func fail(_ why: String) {
        guard !planning else {
            planning = false
            gps.stopUpdatingLocation()
            status = "Lỗi: " + why
            return
        }
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
        status = navigator == nil ? "Đang tìm đường…" : "Đang tìm đường lại…"
        routing = Task { @MainActor [weak self, destination, vietmapKey, fetchRoute] in
            let result: Result<Route, Error>
            do {
                result = .success(try await fetchRoute(here, destination, vietmapKey))
            } catch {
                result = .failure(error)
            }
            // A request cut off by Dừng or a new destination must not touch what came after.
            guard let self, !Task.isCancelled else { return }
            routing = nil
            switch result {
            case .success(let route):
                if let navigator {
                    navigator.rerouted(route)
                } else {
                    (preview, planning, status) = (route, false, "")
                }
            case .failure(let error):
                let why = Vietmap.Failure.message(for: error)
                // Off the route the Navigator asks again shortly; for the preview there is nothing to fall back on.
                guard let navigator else { return fail(why) }
                navigator.rerouteFailed()
                band.send(BandMessage(i: "Lỗi: " + why).json)
                status = "Lỗi: \(why). Sẽ thử lại."
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
        guard let fix = locations.last, fix.horizontalAccuracy >= 0, fix.timestamp.timeIntervalSinceNow > -10 else { return }
        let here = Point(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        if planning, routing == nil {
            gps.stopUpdatingLocation()
            return route(from: here)
        }
        guard running else { return }
        guard band.busy else {
            // The band connection failed on its own (reason in the log); nothing left to show the route on.
            return finish(BandMessage(i: ""), "Mất kết nối với vòng, xem nhật ký.")
        }
        guard let navigator else { return }
        for effect in navigator.update(here, at: fix.timestamp) {
            switch effect {
            case .send(let m):
                band.send(m.json)
                status = [m.d, m.i, m.r].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            case .arrived(let m):
                finish(m, "Đã đến nơi.")
            case .reroute(let from):
                route(from: from)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient; CoreLocation keeps trying.
        if (error as? CLError)?.code == .denied { fail(Self.noLocation) }
    }
}
