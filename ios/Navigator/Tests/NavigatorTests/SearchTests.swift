import Foundation
import Navigator
import XCTest

/// Real Autocomplete v4 / Place v4 answers for "benh vien bach mai" near Thanh Xuân (docs/vietmap).
private func doc(_ name: String) -> Data {
    try! Data(contentsOf: URL(fileURLWithPath: #filePath).appending(path: "../../../../../docs/vietmap/\(name)").standardized)
}

final class SearchTests: XCTestCase {
    func testListsPlacesWithTheirAddress() throws {
        let places = try Vietmap.parsePlaces(doc("autocomplete-benh-vien-bach-mai.json"), status: 200)
        XCTAssertEqual(places.count, 9)
        XCTAssertEqual(places[0].name, "Bệnh Viện Bạch Mai Đường Giải Phóng")
        XCTAssertEqual(places[0].address, "Phường Kim Liên, Thành phố Hà Nội")
        // Same name in another province: the address is what tells them apart.
        XCTAssertEqual(places[2].address, "Phường Liêm Tuyền, Tỉnh Ninh Bình")
        XCTAssertTrue(places[0].id.hasPrefix("vm:ADDRESS:"))
        XCTAssertEqual(try Vietmap.parsePlaces(Data("[]".utf8), status: 200), [])
        XCTAssertThrowsError(try Vietmap.parsePlaces(Data(), status: 401)) { XCTAssertEqual($0 as? Vietmap.Failure, .badKey) }
    }

    func testResolvesAPlaceToItsCoordinates() throws {
        XCTAssertEqual(try Vietmap.parsePoint(doc("place-benh-vien-bach-mai.json"), status: 200),
                       Point(lat: 21.0029318, lon: 105.8407952))
        // A ref_id Vietmap no longer knows gets an empty 404.
        XCTAssertThrowsError(try Vietmap.parsePoint(Data(), status: 404)) { XCTAssertEqual($0 as? Vietmap.Failure, .http(404)) }
    }
}
