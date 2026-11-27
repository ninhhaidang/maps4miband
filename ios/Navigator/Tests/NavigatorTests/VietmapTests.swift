import Foundation
import Navigator
import XCTest

/// Real Route v4 answer (docs/vietmap): 1452 m motorcycle route in Thanh Xuân with a U-turn on Nguyễn Trãi.
let fixture = try! Data(contentsOf: URL(fileURLWithPath: #filePath)
    .appending(path: "../../../../../docs/vietmap/route-motorcycle-nguyen-trai.json").standardized)

final class VietmapTests: XCTestCase {
    func testParsesTheRealRouteIntoOnePolylineWithManeuvers() throws {
        let route = try Vietmap.parse(fixture, status: 200)
        XCTAssertEqual(route.points.count, 40)
        XCTAssertEqual(route.maneuvers.count, 10)
        // interval[0] is off by one per step boundary; the real point of step k is interval[0] + k.
        XCTAssertEqual(route.maneuvers.map(\.at), [0, 2, 7, 10, 19, 30, 31, 36, 38, 39])
        XCTAssertEqual(route.maneuvers[0], Maneuver(at: 0, text: "Xuất phát vào Ngõ 73 Nguyễn Trãi", angle: nil, street: "Ngõ 73 Nguyễn Trãi"))
        XCTAssertEqual(route.maneuvers[1], Maneuver(at: 2, text: "Chếch phải vào Ngõ 73 Nguyễn Trãi", angle: 45, street: "Ngõ 73 Nguyễn Trãi"))
        XCTAssertEqual(route.maneuvers[2], Maneuver(at: 7, text: "Rẽ phải vào Nguyễn Trãi", angle: 90, street: "Nguyễn Trãi"))
        XCTAssertEqual(route.maneuvers[3], Maneuver(at: 10, text: "Quay đầu vào Nguyễn Trãi", angle: -180, street: "Nguyễn Trãi"))
        XCTAssertEqual(route.maneuvers[5], Maneuver(at: 30, text: "Rẽ trái vào Ngõ 213 Giáp Nhất", angle: -90, street: "Ngõ 213 Giáp Nhất"))
        XCTAssertEqual(route.maneuvers[9], Maneuver(at: 39, text: "Đến nơi", angle: nil))
        // Haversine over the decoded polyline; Vietmap's own "distance" (1452) is measured on its road graph.
        XCTAssertEqual(route.length, 1421, accuracy: 2)
    }

    func testTellsWhyThereIsNoRoute() {
        // Bodies as Vietmap sent them when probed (a wrong key gets an empty 401).
        let noRoute = Data(#"{"license":"vietmap","code":"ERROR_UNKNOWN","paths":[],"messages":"Cannot find point 1: 17, 112"}"#.utf8)
        XCTAssertThrowsError(try Vietmap.parse(noRoute, status: 200)) {
            XCTAssertEqual($0 as? Vietmap.Failure, .noRoute("Cannot find point 1: 17, 112"))
        }
        XCTAssertThrowsError(try Vietmap.parse(Data(), status: 401)) { XCTAssertEqual($0 as? Vietmap.Failure, .badKey) }
        XCTAssertThrowsError(try Vietmap.parse(Data(), status: 429)) { XCTAssertEqual($0 as? Vietmap.Failure, .quota) }
        XCTAssertThrowsError(try Vietmap.parse(Data("<html>".utf8), status: 200)) { XCTAssertEqual($0 as? Vietmap.Failure, .badResponse) }
    }
}
