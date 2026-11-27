import XCTest
@testable import Maps4MiBand

final class LogTests: XCTestCase {
    func testKeepsOnlyTheNewest5000Lines() {
        let log = Log()
        for i in 0..<5003 { log.add(.gps, "fix \(i)") }
        XCTAssertEqual(log.lines.count, 5000)
        XCTAssertEqual(log.lines.first?.text, "fix 3")
        XCTAssertEqual(log.lines.last?.text, "fix 5002")
    }

    func testCountsErrorsUntilSeen() {
        let log = Log()
        log.add(.band, "Đã kết nối.")
        log.add(.band, "Lỗi: Mất kết nối với vòng.")
        log.add(.vietmap, "Lỗi: HTTP 401")
        XCTAssertEqual(log.unseenErrors, 2)
        log.seen()
        XCTAssertEqual(log.unseenErrors, 0)
        log.add(.nav, "Lỗi: Mất mạng")
        XCTAssertEqual(log.unseenErrors, 1)
    }

    func testReportHasTheDeviceHeaderAndEveryLineTagged() {
        let log = Log()
        log.add(.band, "Đã kết nối.")
        log.add(.nav, #"{"i":"Rẽ trái"}"#)
        log.add(.gps, "21.000000,105.800000 ±5 m")
        log.add(.vietmap, "HTTP 200")
        let report = log.report()
        XCTAssertTrue(report.contains("iOS "), report)
        XCTAssertTrue(report.contains("[Vòng] Đã kết nối."), report)
        XCTAssertTrue(report.contains(#"[Dẫn đường] {"i":"Rẽ trái"}"#), report)
        XCTAssertTrue(report.contains("[GPS] 21.000000,105.800000 ±5 m"), report)
        XCTAssertTrue(report.contains("[Vietmap] HTTP 200"), report)
        // Oldest first, as it happened.
        XCTAssertLessThan(report.range(of: "[Vòng]")!.lowerBound, report.range(of: "[Vietmap]")!.lowerBound)
    }
}
