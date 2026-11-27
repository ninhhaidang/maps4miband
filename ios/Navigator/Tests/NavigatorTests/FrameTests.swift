import Foundation
@testable import Navigator
import XCTest

/// Ported from the legacy Android NavTest, on the real Vietmap route instead of OSRM.
final class FrameTests: XCTestCase {
    let route = try! Vietmap.parse(fixture, status: 200)

    func testAtTheStartTheNextTurnIsTheFirstManeuverAhead() {
        let f = frame(route, here: route.points[0], hint: 0)
        XCTAssertEqual(f.turn, route.maneuvers[1])
        XCTAssertEqual(f.toTurn, 81, accuracy: 2) // haversine to point 2
        XCTAssertEqual(f.remaining, 1421, accuracy: 2)
        XCTAssertEqual(f.offRoute, 0, accuracy: 1)
        XCTAssertEqual(Array(f.poly.prefix(2)), [106, 460]) // rider is drawn at the marker
    }

    func testHeadingUpWithTheTurnDrawnToTheRight() {
        // 100 m east, then 100 m south: a right turn whatever the compass says.
        let o = Point(lat: 21, lon: 105.8)
        let east = Point(lat: 21, lon: 105.8 + 100 / (111_320 * cos(21 * Double.pi / 180)))
        let south = Point(lat: east.lat - 100 / 111_320, lon: east.lon)
        let r = Route(points: [o, east, south], maneuvers: [
            Maneuver(at: 0, text: "", angle: nil), Maneuver(at: 1, text: "", angle: 90), Maneuver(at: 2, text: "", angle: nil),
        ])
        let f = frame(r, here: o, hint: 0)
        XCTAssertEqual(f.poly, [106, 460, 106, 410, 156, 410])
        XCTAssertEqual(f.toTurn, 100, accuracy: 1)
    }

    func testAfterTheUturnItDoesNotSnapBackToTheOutboundLeg() {
        let uturn = route.maneuvers[3].at
        XCTAssertEqual(route.maneuvers[3].text, "Quay đầu vào Nguyễn Trãi")
        // Halfway down the outbound leg on Nguyễn Trãi, which the return leg retraces.
        let p = route.points[(route.maneuvers[2].at + uturn) / 2]
        let f = frame(route, here: p, hint: uturn)
        XCTAssertGreaterThanOrEqual(f.seg, uturn)
        XCTAssertEqual(f.turn, route.maneuvers[4])
    }

    func testReportsHowFarOffTheRouteWeAre() {
        let p = route.points[0]
        let f = frame(route, here: Point(lat: p.lat + 0.002, lon: p.lon), hint: 0) // ~220 m north
        XCTAssertGreaterThan(f.offRoute, 100)
    }

    func testFormatsDistances() {
        XCTAssertEqual(formatDistance(83), "80 m")
        XCTAssertEqual(formatDistance(1634), "1.6 km")
    }
}
