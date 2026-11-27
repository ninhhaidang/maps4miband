import BandLink
import XCTest

/// Installing the quick app's .rpk over the authenticated link. Expected bytes from make_vectors.py, which follows
/// AstroBox-NG-Module-Core (components/install, components/mass, packet/mass).
final class InstallTests: XCTestCase {
    func link() -> BandLink {
        let l = BandLink(authKey: V.authKey, appPackage: V.app, nonce: { V.phoneNonce })!
        _ = l.start() + l.install(V.rpk) + l.receive(V.bandSessionReply) + l.receive(V.bandVerify)
        return l
    }

    func testInstallAsksTheBandToPrepareInsteadOfOpeningTheApp() {
        XCTAssertEqual(link().receive(V.bandConfirm), [.write(V.ack1), .event(.authenticated), .write(V.installPrepare)])
    }

    func testBandRefusingToPrepareIsReported() {
        let l = link()
        _ = l.receive(V.bandConfirm)
        XCTAssertEqual(l.receive(V.bandInstallLowStorage), [.write(V.ack2), .event(.installRefused(status: 3))])
    }

    func ready() -> BandLink {
        let l = link()
        _ = l.receive(V.bandConfirm)
        XCTAssertEqual(l.receive(V.bandInstallReady), [.write(V.ack2), .write(V.massPrepare)])
        return l
    }

    /// One part in flight at a time: the band's window is small (3 frames in AstroBox's log), and waiting for
    /// each ack keeps CoreBluetooth's write queue short.
    func testPartsGoOutOneAckAtATimeThenTheBandReportsTheResult() {
        let l = ready()
        XCTAssertEqual(l.receive(V.bandMassReady), [.write(V.ack3), .write(V.massPart1)])
        XCTAssertEqual(l.receive(V.ack4), [.event(.installProgress(sent: 1, of: 3)), .write(V.massPart2)])
        XCTAssertEqual(l.receive(V.ack5), [.event(.installProgress(sent: 2, of: 3)), .write(V.massPart3)])
        XCTAssertEqual(l.receive(V.ack6), [.event(.installProgress(sent: 3, of: 3))])
        XCTAssertEqual(l.receive(V.bandInstalled), [.write(V.ack4), .event(.installed)])
    }

    func testBandRejectingThePackageIsReported() {
        let l = ready()
        _ = l.receive(V.bandMassReady) + l.receive(V.ack4) + l.receive(V.ack5) + l.receive(V.ack6)
        XCTAssertEqual(l.receive(V.bandInstallVerifyFailed), [.write(V.ack4), .event(.installFailed(code: 2))])
    }

    func testPartTheBandNacksIsSentAgain() {
        let l = ready()
        _ = l.receive(V.bandMassReady)
        XCTAssertEqual(l.receive(V.nack4), [.write(V.massPart1)])
        XCTAssertEqual(l.receive(V.ack4), [.event(.installProgress(sent: 1, of: 3)), .write(V.massPart2)])
    }

    func testSliceTooSmallForAPartHeaderIsRefused() {
        XCTAssertEqual(ready().receive(V.bandMassTinySlice), [.write(V.ack3), .event(.installRefused(status: 255))])
    }

    func testTransferResumesWhereTheBandSaysItStopped() {
        let l = ready()
        XCTAssertEqual(l.receive(V.bandMassResume), [.write(V.ack3), .write(V.massResumePart1)])
        XCTAssertEqual(l.receive(V.ack4), [.event(.installProgress(sent: 1, of: 2)), .write(V.massResumePart2)])
    }
}
