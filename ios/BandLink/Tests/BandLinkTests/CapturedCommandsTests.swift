@testable import BandLink
import XCTest

/// Decrypted commands captured between Mi Fitness and a Xiaomi Smart Band 10 (Gadgetbridge XiaomiRpkServiceTest).
final class CapturedCommandsTests: XCTestCase {
    let appId = "com.thatguysservice.huami_xdrip"
    let wearPackage = "com.application.watch.watchdrip"
    let sha = hex("515e6fbbaae846a3945ffb938f3694ee0b8d2639")

    func testLaunchMatchesCapture() {
        XCTAssertEqual(Command.launch(id: appId, sha: sha, wearPackage: wearPackage).bytes,
                       hex("08141004b2015c325a0a370a1f636f6d2e7468617467757973736572766963652e6875616d695f78647269701214515e6fbbaae846a3945ffb938f3694ee0b8d2639121f636f6d2e6170706c69636174696f6e2e77617463682e776174636864726970"))
    }

    func testSessionEndMatchesCapture() {
        XCTAssertEqual(Command.sessionEnd(id: appId, sha: sha).bytes,
                       hex("08141007b2013d423b0a370a1f636f6d2e7468617467757973736572766963652e6875616d695f78647269701214515e6fbbaae846a3945ffb938f3694ee0b8d26391001"))
    }

    /// The band's question after launch, which BandLink answers by sending the waiting message.
    func testBandStatusRequestNamesTheApp() {
        let cmd = ProtoFields(hex("08141006b201392a370a1f636f6d2e7468617467757973736572766963652e6875616d695f78647269701214515e6fbbaae846a3945ffb938f3694ee0b8d2639"))!
        XCTAssertEqual(cmd[varint: 1], 20)
        XCTAssertEqual(cmd[varint: 2], 6)
        XCTAssertEqual(cmd[message: 22]?[message: 5]?[bytes: 1], Data(appId.utf8))
        XCTAssertEqual(cmd[message: 22]?[message: 5]?[bytes: 2], sha)
    }

    func testCtrRoundTrips() {
        let key = hex("000102030405060708090a0b0c0d0e0f"), text = Data(repeating: 7, count: 40)
        XCTAssertEqual(aesCTR(key: key, iv: key, aesCTR(key: key, iv: key, text)), text)
    }
}
