import Foundation
import Navigator
import XCTest

/// Real Overpass answer (docs/osm): every way["highway"] within 150 m of the Vietmap fixture route.
let streetsFixture = try! Data(contentsOf: URL(fileURLWithPath: #filePath)
    .appending(path: "../../../../../docs/osm/overpass-nguyen-trai.json").standardized)

final class OverpassTests: XCTestCase {
    func testKeepsEveryStreetAMotorbikeCanTakeLanesIncluded() throws {
        let streets = try Overpass.parse(streetsFixture, status: 200)
        // 300 ways: 118 service, 53 primary, 13 residential, 11 secondary, 7 links kept; 50 footway, 28 steps,
        // 10 pedestrian, 8 cycleway, 2 proposed dropped.
        XCTAssertEqual(streets.count, 202)
        XCTAssertEqual(streets.map(\.count).reduce(0, +), 1041)
        func starts(at lat: Double, _ lon: Double) -> Bool { streets.contains { $0.first == Point(lat: lat, lon: lon) } }
        XCTAssertTrue(starts(at: 21.0020211, 105.8205503), "service way 597111782, a lane")
        XCTAssertFalse(starts(at: 21.0034471, 105.8204427), "footway 330602536, the Ngã Tư Sở underpass")
        XCTAssertFalse(starts(at: 21.0027728, 105.8194112), "steps 330602538")
        XCTAssertFalse(starts(at: 21.0029502, 105.8212484), "cycleway 1234813096")
        XCTAssertFalse(starts(at: 21.0026263, 105.8157907), "pedestrian 1189350852")
        XCTAssertFalse(starts(at: 21.0032742, 105.819291), "proposed 1176087578, Vành đai 2 not built yet")
        let motorway = Data(#"{"elements":[{"tags":{"highway":"motorway"},"geometry":[{"lat":21,"lon":105},{"lat":21.1,"lon":105}]}]}"#.utf8)
        XCTAssertEqual(try Overpass.parse(motorway, status: 200), [], "no motorbikes on expressways")
    }

    func testSaysWhyThereAreNoStreets() {
        XCTAssertThrowsError(try Overpass.parse(Data(), status: 429)) { XCTAssertEqual($0 as? Overpass.Failure, .http(429)) }
        // Overloaded, Overpass still answers 200, with what it got so far and why it stopped.
        let timedOut = Data(#"{"elements":[],"remark":"runtime error: Query timed out in \"query\" at line 1 after 181 seconds."}"#.utf8)
        XCTAssertThrowsError(try Overpass.parse(timedOut, status: 200)) {
            XCTAssertEqual($0 as? Overpass.Failure, .remark("runtime error: Query timed out in \"query\" at line 1 after 181 seconds."))
        }
        XCTAssertThrowsError(try Overpass.parse(Data("# 502 Gateway Timeout".utf8), status: 200)) {
            XCTAssertEqual($0 as? Overpass.Failure, .badResponse)
        }
    }
}
