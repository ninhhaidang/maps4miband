import CoreLocation
import Navigator
import Observation
import UIKit

/// plan → first GPS fix → Vietmap route from there, shown as `preview`; Bắt đầu → Navigator on that same route
/// → band, until arrival or Dừng. Off the route it asks Vietmap again. Each route also looks up the streets around
/// it in the Hà Nội map bundled with the app, in the background, drawn grey on the band once they are in; without
/// them it navigates all the same.
@MainActor
@Observable
final class Navigation: NSObject {
    private(set) var running = false
    /// Waiting for GPS or Vietmap to show the route before Bắt đầu.
    private(set) var planning = false
    /// The route Bắt đầu will follow.
    private(set) var preview: Route?
    /// Progress of the plan, or why it or navigation ended; while navigating the card shows `shown` instead.
    private(set) var status = ""
    /// The band's current screen while navigating, for the card on the phone.
    private(set) var shown: BandMessage?
    private static let noLocation = "App chưa được cấp quyền vị trí. Bật trong ứng dụng Cài đặt của iPhone → Dẫn đường."

    @ObservationIgnored private let band: BandConnection
    @ObservationIgnored private let rideActivity = RideActivity()
    @ObservationIgnored private let rideNotification = RideNotification()
    @ObservationIgnored private var rideStartedAt: TimeInterval = 0
    @ObservationIgnored private var startBattery: Float = -1
    @ObservationIgnored private var wasMonitoringBattery = false
    @ObservationIgnored private let gps = CLLocationManager()
    @ObservationIgnored private var destination = Point(lat: 0, lon: 0)
    @ObservationIgnored private var vietmapKey = ""
    @ObservationIgnored private var navigator: Navigator?
    @ObservationIgnored private var routing: Task<Void, Never>?
    /// Streets around `preview`, the old route's until the new one's are in.
    @ObservationIgnored private var streets: [[Point]] = []
    @ObservationIgnored private var fetchingStreets: Task<Void, Never>?
    /// A buzz sent while the quick app was still opening, so the screen after it would replace it unbuzzed.
    /// Dropped once the app opens: it showed that screen, buzz and all.
    @ObservationIgnored private var owedBuzz = false
    @ObservationIgnored private let fetchRoute: (Point, Point, String) async throws -> Route
    @ObservationIgnored private let fetchStreets: ([Point]) async throws -> [[Point]]

    init(band: BandConnection, fetchRoute: @escaping (Point, Point, String) async throws -> Route = Vietmap.route,
         fetchStreets: @escaping ([Point]) async throws -> [[Point]] = { route in
             try await Task.detached { try StreetMap.hanoi.get().along(route) }.value
         }) {
        self.band = band
        self.fetchRoute = fetchRoute
        self.fetchStreets = fetchStreets
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
        band.log.add(.nav, "Lên kế hoạch tới \(destination.text)")
        status = "Đang chờ GPS…"
        gps.requestWhenInUseAuthorization()
        gps.startUpdatingLocation()
    }

    /// Drops the preview and any plan in flight, e.g. once the user looks for another destination.
    func cancelPlan() {
        guard !running else { return }
        routing?.cancel()
        routing = nil
        fetchingStreets?.cancel()
        fetchingStreets = nil
        if planning { gps.stopUpdatingLocation() }
        (preview, planning, status, streets) = (nil, false, "", [])
    }

    /// Follows `preview` as it is; the first fix shows where it goes, or asks for a new one if far from its start.
    func start(authKey: String) {
        guard !running, !planning, !band.busy, let preview else { return }
        let first = BandMessage(i: "Đang chờ GPS…")
        band.stream(authKey: authKey, first: first.json)
        guard band.busy else {
            band.log.add(.nav, "Lỗi: không kết nối được vòng")
            status = "Không kết nối được vòng, xem nhật ký."
            return
        }
        band.log.add(.nav, "Bắt đầu dẫn đường, tuyến \(formatDistance(preview.length))")
        logSent(first.json)
        (running, shown, owedBuzz) = (true, first, false)
        navigator = Navigator(route: preview)
        navigator?.streets = streets
        status = "Đang chờ GPS…"
        gps.allowsBackgroundLocationUpdates = true
        gps.pausesLocationUpdatesAutomatically = false
        gps.showsBackgroundLocationIndicator = true
        gps.startUpdatingLocation()
        if gps.authorizationStatus == .authorizedWhenInUse {
            gps.requestAlwaysAuthorization()
        }
        let phone = UIDevice.current
        wasMonitoringBattery = phone.isBatteryMonitoringEnabled
        phone.isBatteryMonitoringEnabled = true
        startBattery = phone.batteryLevel
        rideStartedAt = ProcessInfo.processInfo.systemUptime
        let onStop: () -> Void = { [weak self] in self?.stop() }
        do {
            if try rideActivity.start(first, onStop: onStop) { return }
        } catch {
            band.log.add(.nav, "Không hiện được Live Activity: \(error.localizedDescription)")
        }
        rideNotification.show(onStop: onStop, onError: { [weak self] message in
            self?.band.log.add(.nav, "Lỗi: " + message)
        })
    }

    func stop() {
        finish(BandMessage(i: "Đã dừng dẫn đường"), "Đã dừng dẫn đường.")
    }

    private func fail(_ why: String) {
        guard !planning else {
            planning = false
            gps.stopUpdatingLocation()
            status = "Lỗi: " + why
            band.log.add(.nav, status)
            return
        }
        finish(BandMessage(i: "Lỗi: " + why), "Lỗi: " + why)
    }

    /// Puts `last` on the band, lets go of it and of GPS.
    private func finish(_ last: BandMessage, _ why: String) {
        guard running else { return }
        running = false
        let json = last.json
        band.finish(json)
        logSent(json)
        gps.stopUpdatingLocation()
        gps.allowsBackgroundLocationUpdates = false
        gps.pausesLocationUpdatesAutomatically = true
        gps.showsBackgroundLocationIndicator = false
        rideActivity.end()
        rideNotification.hide()
        let phone = UIDevice.current
        let endBattery = phone.batteryLevel
        phone.isBatteryMonitoringEnabled = wasMonitoringBattery
        let elapsed = ProcessInfo.processInfo.systemUptime - rideStartedAt
        let measurement = startBattery >= 0 && endBattery >= 0 && elapsed > 0
            ? String(format: "pin %.0f%% → %.0f%% (%.1f%%/giờ)",
                     startBattery * 100, endBattery * 100, Double(startBattery - endBattery) * 360_000 / elapsed)
            : "không đọc được pin iPhone"
        band.log.add(.nav, String(format: "Chuyến đi %.1f phút, nhịp gửi %.0f s, %@.",
                                  elapsed / 60, Tuning.sendEvery, measurement))
        routing?.cancel()
        routing = nil
        navigator = nil
        shown = nil
        status = why
        band.log.add(.nav, why)
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
                band.log.add(.nav, "Tuyến mới: \(formatDistance(route.length)), \(route.maneuvers.count) chỉ dẫn")
                // While navigating, preview is the route on the map.
                navigator?.rerouted(route)
                (preview, planning, status) = (route, false, "")
                loadStreets(along: route)
            case .failure(let error):
                let why = Vietmap.Failure.message(for: error)
                // Off the route the Navigator asks again shortly; for the preview there is nothing to fall back on.
                guard let navigator else { return fail(why) }
                navigator.rerouteFailed()
                show(BandMessage(i: "Lỗi: " + why))
                status = "Lỗi: \(why). Sẽ thử lại."
                band.log.add(.nav, status)
            }
        }
    }

    private func loadStreets(along route: Route) {
        fetchingStreets?.cancel()
        fetchingStreets = Task { @MainActor [weak self, fetchStreets] in
            let result: Result<[[Point]], Error>
            do {
                result = .success(try await fetchStreets(route.points))
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            fetchingStreets = nil
            switch result {
            case .success(let streets):
                band.log.add(.nav, "Đường xung quanh: \(streets.count) đường từ OpenStreetMap")
                self.streets = streets
                navigator?.streets = streets
            case .failure(let error):
                // Not "Lỗi": the ride goes on as before, only without grey streets, so no badge on Nhật ký.
                band.log.add(.nav, "Không đọc được đường xung quanh, đi tiếp không có đường xám: "
                                   + error.localizedDescription)
            }
        }
    }

    private func show(_ m: BandMessage) {
        var m = m
        if owedBuzz && band.opening { m.v = 1 }
        let json = m.json
        band.send(json)
        owedBuzz = band.opening && m.v == 1
        // A later screen may replace this one before the app opens: the grey layer goes again with the next.
        if band.opening { navigator?.forgetLayer() }
        shown = m
        rideActivity.update(m)
        logSent(json)
    }

    /// The JSON the band got, but the grey-street picture as its size: ~11 KB of base64 a line buried the log.
    private func logSent(_ json: Data) {
        band.log.add(.nav, String(decoding: json, as: UTF8.self).replacing(/"s":"([^"]*)"/) { #""s":"<ảnh \#($0.1.count) ký tự base64>""# })
    }
}

extension Navigation: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.denied, .restricted].contains(manager.authorizationStatus) {
            fail(Self.noLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        let age = -fix.timestamp.timeIntervalSinceNow
        guard fix.horizontalAccuracy >= 0 else { return band.log.add(.gps, "Bỏ bản tin GPS không hợp lệ") }
        // A cached fix from minutes ago would start the route somewhere else.
        guard age < 10 else { return band.log.add(.gps, String(format: "Bỏ bản tin GPS cũ %.0f s", age)) }
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
        // The phone's clock, not the fix's: fixes held back while the app was away arrive together, seconds apart by
        // their own clocks, and would each send a screen.
        for effect in navigator.update(here, at: Date()) {
            switch effect {
            case .send(let m):
                band.log.add(.gps, String(format: "%@ ±%.0f m, cách đây %.1f s", here.text, fix.horizontalAccuracy, age))
                show(m)
            case .arrived(let m):
                finish(m, "Đã đến nơi.")
            case .reroute(let from):
                band.log.add(.nav, "Lệch tuyến tại \(from.text), tìm đường lại")
                route(from: from)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient; CoreLocation keeps trying.
        if (error as? CLError)?.code == .denied { fail(Self.noLocation) }
    }
}

extension StreetMap {
    /// Hà Nội (tools/streets.py), read once on first use.
    static let hanoi = Result {
        try StreetMap(deflated: Data(contentsOf: Bundle.main.bundleURL.appending(path: "hanoi-streets.bin")))
    }
}

extension Point {
    /// "21.000000,105.800000" for the log.
    var text: String { String(format: "%.6f,%.6f", lat, lon) }
}
