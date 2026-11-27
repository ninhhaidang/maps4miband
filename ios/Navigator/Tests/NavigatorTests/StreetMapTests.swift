import Foundation
import Navigator
import XCTest

final class StreetMapTests: XCTestCase {
    let o = Point(lat: 21, lon: 105.8)
    func at(east: Double, north: Double) -> Point {
        Point(lat: o.lat + north / 111_320, lon: o.lon + east / (111_320 * cos(o.lat * .pi / 180)))
    }

    /// The bundled format: raw deflate of little-endian Int32s, per street its point count then lat, lon × 1e5.
    func deflated(_ streets: [[Point]]) throws -> Data {
        var ints: [Int32] = []
        for s in streets { ints += [Int32(s.count)] + s.flatMap { [Int32(($0.lat * 1e5).rounded()), Int32(($0.lon * 1e5).rounded())] } }
        return try (ints.withUnsafeBytes { Data($0) } as NSData).compressed(using: .zlib) as Data
    }

    func testFindsTheStreetsWithin500MOfTheRouteOnly() throws {
        // 1 km due east.
        let route = [o, at(east: 1000, north: 0)]
        let crossing = [at(east: 500, north: -100), at(east: 500, north: 100)]
        let alongside = [at(east: 0, north: 480), at(east: 300, north: 480)]
        // A long straight road with no point anywhere near the route, crossing it all the same.
        let longCrossing = [at(east: 800, north: -1500), at(east: 800, north: 1500)]
        let farAway = [at(east: 500, north: 900), at(east: 600, north: 900)]
        let map = try StreetMap(deflated: deflated([crossing, farAway, alongside, longCrossing]))
        XCTAssertEqual(map.along(route).count, 3)
        XCTAssertFalse(map.along(route).contains { $0.first!.lat > o.lat + 800 / 111_320 }, "the one 900 m off")
        // Coordinates come back to 1e-5°, about a metre.
        XCTAssertEqual(map.along(route)[0][0].lat, crossing[0].lat, accuracy: 1e-5)
    }

    func testTheBundledHaNoiMapHasTheStreetsAroundTheFixtureRoute() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .appending(path: "../../../../Maps4MiBand/hanoi-streets.bin").standardized)
        let map = try StreetMap(deflated: data)
        let around = map.along(try Vietmap.parse(fixture, status: 200).points)
        // Overpass found 202 within 150 m (lanes included); 500 m and more take in 1176.
        XCTAssertGreaterThan(around.count, 1000)
        XCTAssertLessThan(around.count, 1500)
    }

    func testBrokenDataSaysSo() {
        XCTAssertThrowsError(try StreetMap(deflated: Data("not deflate".utf8)))
    }
}
