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
        XCTAssertEqual(Array(f.poly.prefix(2)), [106, 345]) // rider is drawn at the marker
    }

    func testNorthIsUpWhicheverWayTheRouteGoes() {
        // 100 m east, then 100 m south: east is right, south is down.
        let o = Point(lat: 21, lon: 105.8)
        let east = Point(lat: 21, lon: 105.8 + 100 / (111_320 * cos(21 * Double.pi / 180)))
        let south = Point(lat: east.lat - 100 / 111_320, lon: east.lon)
        let r = Route(points: [o, east, south], maneuvers: [
            Maneuver(at: 0, text: "", angle: nil), Maneuver(at: 1, text: "", angle: 90), Maneuver(at: 2, text: "", angle: nil),
        ])
        let f = frame(r, here: o, hint: 0)
        XCTAssertEqual(f.poly, [106, 345, 156, 345, 156, 395])
        XCTAssertEqual(f.toTurn, 100, accuracy: 1)
        // The rider's arrow points along the route: east, then south after the turn.
        XCTAssertEqual(f.heading, 90)
        XCTAssertEqual(frame(r, here: south, hint: 1).heading, 180)
    }

    /// 100 m east, right turn, 100 m south; north up, the rider in the middle of the map.
    let o = Point(lat: 21, lon: 105.8)
    func at(east: Double, north: Double) -> Point {
        Point(lat: o.lat + north / 111_320, lon: o.lon + east / (111_320 * cos(o.lat * .pi / 180)))
    }
    lazy var r = Route(points: [o, at(east: 100, north: 0), at(east: 100, north: -100)], maneuvers: [
        Maneuver(at: 0, text: "", angle: nil), Maneuver(at: 1, text: "", angle: 90), Maneuver(at: 2, text: "", angle: nil),
    ])

    func testALayerOfStreetsAroundTheAnchorCutToItsBoxNearestFirst() {
        // The box is the map plus 100 m each side: 312×450 px, the anchor in its middle at (156, 225).
        let streets = [
            [at(east: 0, north: 20), at(east: 1000, north: 20)], // 20 m north, runs off the right edge
            [at(east: 100, north: 0), at(east: 100, north: 100)], // 100 m east, going north
            [at(east: 2000, north: 0), at(east: 2000, north: 100)], // far off
        ]
        XCTAssertEqual(layer(streets, around: o), [156, 215, 312, 215, 206, 225, 206, 175])
    }

    func testStreetsAreSimplifiedToWithin2MOfWhereTheyAre() {
        // 100 m east with a point every 10 m, each up to 0.5 m off the line: one segment.
        let wobbly = (0...10).map { k in at(east: 10 * Double(k), north: k % 2 == 0 ? 0.5 : -0.5) }
        XCTAssertEqual(layer([wobbly], around: o), [156, 225, 206, 225])
        // A real corner stays.
        let corner = [at(east: 0, north: -40), at(east: 50, north: -40), at(east: 50, north: -80)]
        XCTAssertEqual(layer([corner], around: o), [156, 245, 181, 245, 181, 245, 181, 265])
    }

    func testALayerHoldsAt300SegmentsTheBandCanMove() {
        // 400 short streets 10 m apart, 100 m each way around the anchor.
        let streets = (0..<400).map { k in
            let e = -100 + 10 * Double(k % 20), n = -100 + 10 * Double(k / 20)
            return [at(east: e, north: n), at(east: e + 6, north: n)]
        }
        let l = layer(streets, around: o)
        XCTAssertEqual(l.count / 4, 300)
        let starts = stride(from: 0, to: l.count, by: 4).map { [l[$0], l[$0 + 1]] }
        XCTAssertTrue(starts.contains([156, 225]), "the one at the anchor stays")
        XCTAssertFalse(starts.contains([106, 275]), "the far corner goes")
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
