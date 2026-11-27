import CoreLocation
import Navigator
import XCTest
@testable import Maps4MiBand

/// About 450 m due north, with a right turn half way.
private let straight = Route(
    points: [Point(lat: 21.000, lon: 105.8), Point(lat: 21.002, lon: 105.8), Point(lat: 21.004, lon: 105.8)],
    maneuvers: [Maneuver(at: 0, text: "Xuất phát", angle: nil), Maneuver(at: 1, text: "Rẽ phải vào Phố Thử", angle: 90),
                Maneuver(at: 2, text: "Đến nơi", angle: nil)])
private let destination = Point(lat: 21.004, lon: 105.8)

@MainActor
final class NavigationTests: XCTestCase {
    private func fix(_ nav: Navigation, _ p: Point) {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon), altitude: 0,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        nav.locationManager(CLLocationManager(), didUpdateLocations: [location])
    }

    /// Lets the route request started by a fix finish.
    private func settle(_ nav: Navigation) async throws {
        for _ in 0..<100 where nav.planning { try await Task.sleep(for: .milliseconds(10)) }
    }

    func testStartFollowsThePreviewedRouteWithoutAskingVietmapAgain() async throws {
        var asked: [(Point, Point, String)] = []
        let nav = Navigation(band: BandConnection()) { from, to, key in
            asked.append((from, to, key))
            return straight
        }
        nav.plan(to: destination, vietmapKey: "vm-key")
        fix(nav, straight.points[0])
        try await settle(nav)
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.0, straight.points[0])
        XCTAssertEqual(asked.first?.1, destination)
        XCTAssertEqual(asked.first?.2, "vm-key")
        XCTAssertEqual(nav.preview?.points, straight.points)

        nav.start(authKey: String(repeating: "0", count: 32))
        XCTAssertTrue(nav.running)
        fix(nav, straight.points[0])
        // Long enough for a route request, had one been started, to reach the fake.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(asked.count, 1)
        // The card on the phone shows the very message the band got.
        XCTAssertEqual(nav.shown?.i, "Rẽ phải vào Phố Thử")
        XCTAssertEqual(nav.shown?.a, 90)
        nav.stop()
        XCTAssertNil(nav.shown)
    }

    func testAFailedPreviewSaysWhyAndCannotStart() async throws {
        let nav = Navigation(band: BandConnection()) { _, _, _ in throw Vietmap.Failure.offline }
        nav.plan(to: destination, vietmapKey: "vm-key")
        fix(nav, straight.points[0])
        try await settle(nav)
        XCTAssertNil(nav.preview)
        XCTAssertEqual(nav.status, "Lỗi: Mất mạng, không gọi được Vietmap")
        nav.start(authKey: String(repeating: "0", count: 32))
        XCTAssertFalse(nav.running)
    }
}
