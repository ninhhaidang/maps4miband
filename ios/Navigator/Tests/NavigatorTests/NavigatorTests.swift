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
        XCTAssertEqual(Array(m.p!.prefix(2)), [106, 280])

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

    /// Rides `route` in 5 m steps, 0.1 s apart (faster than frames go out), and returns everything sent.
    func ride(_ nav: Navigator, _ route: Route) -> [Navigator.Effect] {
        var out: [Navigator.Effect] = []
        var t = t0
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
