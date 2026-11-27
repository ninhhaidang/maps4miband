import Foundation
@testable import Navigator
import XCTest

final class NavigatorTests: XCTestCase {
    let route = try! Vietmap.parse(fixture, status: 200)
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testSendsTheFirstFrameRightAwayThenAtMostOnePerSecond() throws {
        let nav = Navigator(route: route)
        let first = nav.update(route.points[0], at: t0)
        guard case .send(let m) = first.first, first.count == 1 else { return XCTFail("\(first)") }
        XCTAssertEqual(m.a, 45)
        XCTAssertEqual(m.d, "80 m")
        XCTAssertEqual(m.i, "Chếch phải vào Ngõ 73 Nguyễn Trãi")
        XCTAssertEqual(m.r, "Còn 1.4 km")
        XCTAssertEqual(Array(m.p!.prefix(2)), [106, 460])

        let p = route.points[0] // stays 80 m from the turn: no new buzz
        XCTAssertEqual(nav.update(p, at: t0 + 0.5), [])
        XCTAssertEqual(nav.update(p, at: t0 + 0.9), [])
        XCTAssertEqual(nav.update(p, at: t0 + 1.0).count, 1)
        XCTAssertEqual(nav.update(p, at: t0 + 1.5), [])
    }

    /// 498 m east, right turn, 150 m south past a street-name change, 148 m more to the destination
    /// (lengths off the 5 m ride grid so no distance lands on a rounding boundary).
    let street: Route = {
        let o = Point(lat: 21, lon: 105.8)
        func at(east: Double, south: Double) -> Point {
            Point(lat: o.lat - south / 111_320, lon: o.lon + east / (111_320 * cos(o.lat * .pi / 180)))
        }
        return Route(points: [o, at(east: 498, south: 0), at(east: 498, south: 150), at(east: 498, south: 298)], maneuvers: [
            Maneuver(at: 0, text: "Xuất phát", angle: nil),
            Maneuver(at: 1, text: "Rẽ phải", angle: 90),
            Maneuver(at: 2, text: "Đi thẳng", angle: 0),
            Maneuver(at: 3, text: "Đến nơi", angle: nil),
        ])
    }()

    func testMarksTheTurnsAheadOnTheMapAndNamesTheStreetOfTheNextOne() throws {
        // 100 m east, right onto Láng Hạ for 100 m, left onto Thái Hà for 100 m, arrive.
        let o = Point(lat: 21, lon: 105.8)
        func at(east: Double, south: Double) -> Point {
            Point(lat: o.lat - south / 111_320, lon: o.lon + east / (111_320 * cos(o.lat * .pi / 180)))
        }
        let r = Route(points: [o, at(east: 100, south: 0), at(east: 100, south: 100), at(east: 200, south: 100)], maneuvers: [
            Maneuver(at: 0, text: "Xuất phát", angle: nil),
            Maneuver(at: 1, text: "Rẽ phải vào Láng Hạ", angle: 90, street: "Láng Hạ"),
            Maneuver(at: 2, text: "Rẽ trái vào Thái Hà", angle: -90, street: "Thái Hà"),
            Maneuver(at: 3, text: "Đến nơi", angle: nil),
        ])
        let first = Navigator(route: r).update(o, at: t0)
        guard case .send(let m) = first.first else { return XCTFail("\(first)") }
        XCTAssertEqual(Array(m.p!.prefix(2)), [106, 460]) // rider near the bottom, heading up, 2 m/px
        XCTAssertEqual(m.t, [106, 410, 156, 410]) // both turns; the arrival is not a turn
        XCTAssertEqual(m.n, "Láng Hạ")
    }

    func testSendsTheStreetsAroundTheRouteInGreyOnceTheyAreIn() throws {
        let nav = Navigator(route: street)
        guard case .send(let before) = nav.update(street.points[0], at: t0).first else { return XCTFail() }
        XCTAssertNil(before.g)
        // A side street 100 m ahead, 50 m each side of the route.
        let o = street.points[0], m = 1 / (111_320 * cos(o.lat * .pi / 180))
        nav.streets = [[Point(lat: o.lat + 50 / 111_320.0, lon: o.lon + 100 * m), Point(lat: o.lat - 50 / 111_320.0, lon: o.lon + 100 * m)]]
        guard case .send(let after) = nav.update(street.points[0], at: t0 + 1).first else { return XCTFail() }
        XCTAssertEqual(after.g, [81, 410, 131, 410])
    }

    func testDrawsAtMost100SegmentsTheMostTheBandRedrawsEverySecond() throws {
        // 800 m due north, a point every 6.5 m (3.25 px, just over the 3 px step): ~108 points in the 700 m ahead.
        let o = Point(lat: 21, lon: 105.8)
        let pts = (0...123).map { Point(lat: o.lat + Double($0) * 6.5 / 111_320, lon: o.lon) }
        let r = Route(points: pts, maneuvers: [Maneuver(at: 0, text: "Xuất phát", angle: nil),
                                               Maneuver(at: 123, text: "Đến nơi", angle: nil)])
        let first = Navigator(route: r).update(o, at: t0)
        guard case .send(let m) = first.first else { return XCTFail("\(first)") }
        XCTAssertEqual(m.p!.count / 2 - 1, 100)
        XCTAssertEqual(Array(m.p!.prefix(2)), [106, 460]) // the near end is kept, the far end goes
    }

    /// Rides `route` in 5 m steps, 0.1 s apart (faster than frames go out), and returns everything sent.
    func ride(_ nav: Navigator, _ route: Route, from start: Date? = nil) -> [Navigator.Effect] {
        var out: [Navigator.Effect] = []
        var t = start ?? t0
        for (a, b) in zip(route.points, route.points.dropFirst()) {
            let steps = Int((dist(a, b) / 5).rounded())
            for s in 0..<steps {
                let k = Double(s) / Double(steps)
                out += nav.update(Point(lat: a.lat + k * (b.lat - a.lat), lon: a.lon + k * (b.lon - a.lon)), at: t)
                t += 0.1
            }
        }
        out += nav.update(route.points.last!, at: t)
        return out
    }

    /// A street-name change ("Đi thẳng") comes at nearly every junction: it must not hide the real turn after it.
    func testBuzzesOnceAt200mAndOnceAt40mBeforeEachTurnSkippingStraightOn() {
        let buzzes = ride(Navigator(route: street), street).compactMap { e -> String? in
            guard case .send(let m) = e, m.v == 1 else { return nil }
            return "\(m.d!) \(m.i)"
        }
        XCTAssertEqual(buzzes, ["200 m Rẽ phải", "40 m Rẽ phải", "200 m Đến nơi", "40 m Đến nơi"])
    }

    func testArrivesWithABuzzThenStops() {
        let nav = Navigator(route: street)
        let effects = ride(nav, street)
        guard case .arrived(let m) = effects.last else { return XCTFail("\(effects.last!)") }
        XCTAssertEqual(m.i, "Đã đến nơi")
        XCTAssertEqual(m.v, 1)
        XCTAssertEqual(effects.filter { if case .arrived = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(nav.update(street.points.last!, at: t0 + 1000), [])
    }

    /// `metres` north of `street`'s first leg, `east` metres along it.
    func off(_ metres: Double, east: Double = 100) -> Point {
        let o = street.points[0]
        return Point(lat: o.lat + metres / 111_320, lon: o.lon + east / (111_320 * cos(o.lat * .pi / 180)))
    }

    func reroutes(_ effects: [Navigator.Effect]) -> [Point] {
        effects.compactMap { if case .reroute(let p) = $0 { p } else { nil } }
    }

    func testAsksForANewRouteAfterThreeFixesInARowOffTheRoute() {
        let nav = Navigator(route: street)
        _ = nav.update(off(0), at: t0)
        XCTAssertEqual(reroutes(nav.update(off(60), at: t0 + 1) + nav.update(off(60), at: t0 + 2)), [])
        _ = nav.update(off(5), at: t0 + 3) // back near the route: start counting again
        XCTAssertEqual(reroutes(nav.update(off(60), at: t0 + 4) + nav.update(off(60), at: t0 + 5)), [])

        let third = nav.update(off(60, east: 120), at: t0 + 6)
        XCTAssertEqual(third, [.send(BandMessage(i: "Đang tìm đường lại…")), .reroute(from: off(60, east: 120))])
    }

    /// Rides 60 m off `street` from `start`, one fix a second, and returns when it asked for a new route.
    func offRideReroutes(_ nav: Navigator, from start: Double, to end: Double) -> [Double] {
        stride(from: start, through: end, by: 1).filter { !reroutes(nav.update(off(60), at: t0 + $0)).isEmpty }
    }

    func testWaitsForTheRouteItAskedForInsteadOfAskingAgain() {
        let nav = Navigator(route: street)
        XCTAssertEqual(offRideReroutes(nav, from: 0, to: 60), [2])
    }

    func testAfterAFailedRerouteTriesAgainEveryTenSeconds() {
        let nav = Navigator(route: street)
        XCTAssertEqual(offRideReroutes(nav, from: 0, to: 4), [2])
        nav.rerouteFailed()
        XCTAssertEqual(offRideReroutes(nav, from: 5, to: 12), [12])
        nav.rerouteFailed()
        XCTAssertEqual(offRideReroutes(nav, from: 13, to: 25), [22])
    }

    func testFollowsTheNewRouteFromItsStartAndBuzzesForItsTurns() {
        let nav = Navigator(route: street)
        // Both buzzes for the turn, then off the route: the new route's first turn is the same point index.
        for (k, east) in stride(from: 0.0, through: 470, by: 10).enumerated() {
            _ = nav.update(off(0, east: east), at: t0 + Double(k) / 10)
        }
        XCTAssertEqual(offRideReroutes(nav, from: 10, to: 12), [12])

        nav.rerouted(street)
        let effects = ride(nav, street, from: t0 + 13)
        guard case .send(let first) = effects.first else { return XCTFail("\(effects)") }
        XCTAssertEqual(first.i, "Rẽ phải")
        XCTAssertEqual(first.d, "500 m")
        let buzzes = effects.compactMap { e -> String? in
            guard case .send(let m) = e, m.v == 1 else { return nil }
            return "\(m.d!) \(m.i)"
        }
        XCTAssertEqual(buzzes, ["200 m Rẽ phải", "40 m Rẽ phải", "200 m Đến nơi", "40 m Đến nơi"])
    }

    func testDoesNotArriveFromBesideTheDestination() {
        let nav = Navigator(route: street)
        let end = street.points.last!
        let beside = Point(lat: end.lat, lon: end.lon + 60 / (111_320 * cos(end.lat * .pi / 180)))
        let effects = (0..<3).flatMap { nav.update(beside, at: t0 + Double($0)) }
        XCTAssertEqual(reroutes(effects), [beside])
    }

    func testMessagesGoOutAsTheQuickAppsJson() throws {
        func object(_ m: BandMessage) throws -> NSDictionary {
            try JSONSerialization.jsonObject(with: m.json) as! NSDictionary
        }
        XCTAssertEqual(try object(BandMessage(i: "Đã dừng dẫn đường")), ["i": "Đã dừng dẫn đường"])
        XCTAssertEqual(try object(BandMessage(p: [1, 2], d: "", i: "Đã đến nơi", v: 1)),
                       ["p": [1, 2], "d": "", "i": "Đã đến nơi", "v": 1]) // no "a": no arrow
    }

    func testReadsADestinationTypedAsLatCommaLon() {
        XCTAssertEqual(Point(parsing: " 21.0060, 105.8150 "), Point(lat: 21.006, lon: 105.815))
        XCTAssertEqual(Point(parsing: "21.0060,105.8150"), Point(lat: 21.006, lon: 105.815))
        XCTAssertNil(Point(parsing: "21.0060"))
        XCTAssertNil(Point(parsing: "Hồ Gươm"))
        XCTAssertNil(Point(parsing: "91,105"))
        XCTAssertNil(Point(parsing: "21,181"))
    }
}
