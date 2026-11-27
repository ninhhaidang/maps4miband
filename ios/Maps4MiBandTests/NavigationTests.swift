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
    private func fix(_ nav: Navigation, _ p: Point, age: TimeInterval = 0) {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon), altitude: 0,
                                  horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSinceNow: -age))
        nav.locationManager(CLLocationManager(), didUpdateLocations: [location])
    }

    /// Lets the route request started by a fix finish.
    private func settle(_ nav: Navigation) async throws {
        for _ in 0..<100 where nav.planning { try await Task.sleep(for: .milliseconds(10)) }
    }

    func testStartFollowsThePreviewedRouteWithoutAskingVietmapAgain() async throws {
        var asked: [(Point, Point, String)] = []
        let band = BandConnection()
        let nav = Navigation(band: band) { from, to, key in
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
        // The log keeps the exact JSON the band got.
        let sent = try XCTUnwrap(nav.shown.map { String(decoding: $0.json, as: UTF8.self) })
        XCTAssertTrue(band.log.lines.contains { $0.source == .nav && $0.text == sent }, sent)
        nav.stop()
        XCTAssertNil(nav.shown)
    }

    /// Planned and started on `straight`; the band in tests never opens the quick app, so every screen waits.
    private func started() async throws -> (Navigation, BandConnection) {
        let band = BandConnection()
        let nav = Navigation(band: band) { _, _, _ in straight }
        nav.plan(to: destination, vietmapKey: "vm-key")
        fix(nav, straight.points[0])
        try await settle(nav)
        nav.start(authKey: String(repeating: "0", count: 32))
        XCTAssertTrue(nav.running)
        return (nav, band)
    }

    private func screensSent(_ band: BandConnection) -> [String] {
        band.log.lines.filter { $0.source == .nav && $0.text.hasPrefix("{\"a\"") }.map(\.text)
    }

    func testABuzzStillWaitingForTheQuickAppIsCarriedOntoTheScreenThatReplacesIt() async throws {
        let (nav, _) = try await started()
        // About 190 m before the turn: the 200 m buzz.
        let near = Point(lat: 21.0003, lon: 105.8)
        fix(nav, near)
        XCTAssertEqual(nav.shown?.v, 1)
        // Off the route three times: "Đang tìm đường lại…" replaces the waiting screen right away.
        let off = Point(lat: 21.0003, lon: 105.802)
        for _ in 0..<3 { fix(nav, off) }
        XCTAssertEqual(nav.shown?.i, "Đang tìm đường lại…")
        XCTAssertEqual(nav.shown?.v, 1, "the buzz never left the phone")
        nav.stop()
    }

    func testFixesThatArriveTogetherSendOneScreen() async throws {
        let (nav, band) = try await started()
        // iOS hands over fixes held back while the app was away, seconds apart by their own clocks.
        fix(nav, straight.points[0], age: 5.2)
        fix(nav, straight.points[0], age: 3.3)
        fix(nav, straight.points[0], age: 1.4)
        XCTAssertEqual(screensSent(band).count, 1)
        nav.stop()
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
