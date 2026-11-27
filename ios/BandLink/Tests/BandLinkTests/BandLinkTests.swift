import BandLink
import Foundation
import XCTest

func hex(_ s: String) -> Data {
    Data(stride(from: 0, to: s.count, by: 2).map { i in
        UInt8(s.dropFirst(i).prefix(2), radix: 16)!
    })
}

/// Expected bytes come from make_vectors.py (independent Python implementation), and from
/// Gadgetbridge's captures between Mi Fitness and a Smart Band 10.
final class BandLinkTests: XCTestCase {
    func link() -> BandLink {
        BandLink(authKey: V.authKey, appPackage: V.app, nonce: { V.phoneNonce })!
    }

    func testAuthKeyMustBe32HexCharacters() {
        XCTAssertNotNil(BandLink(authKey: " 0x" + V.authKey.uppercased() + " ", appPackage: V.app, nonce: { V.phoneNonce }))
        for bad in ["", "0011", V.authKey + "00", String(V.authKey.dropLast()) + "g"] {
            XCTAssertNil(BandLink(authKey: bad, appPackage: V.app, nonce: { V.phoneNonce }), bad)
        }
    }

    func testStartOpensASession() {
        XCTAssertEqual(link().start(), [.write(V.sessionStart)])
    }

    func testSessionReplySendsThePhoneNonce() {
        let l = link()
        _ = l.start()
        XCTAssertEqual(l.receive(V.bandSessionReply), [.write(V.authStep1)])
    }

    func testBandVerifyIsAckedAndConfirmedWithDerivedKeys() {
        let l = link()
        _ = l.start() + l.receive(V.bandSessionReply)
        XCTAssertEqual(l.receive(V.bandVerify), [.write(V.ack0), .write(V.authStep2)])
    }

    func testWrongAuthKeyIsReported() {
        let l = link()
        _ = l.start() + l.receive(V.bandSessionReply)
        XCTAssertEqual(l.receive(V.bandVerifyWrongKey), [.write(V.ack0), .event(.authKeyRejected)])
    }

    func testConfirmAuthenticatesAndAsksForInstalledApps() {
        let l = link()
        _ = l.start() + l.receive(V.bandSessionReply) + l.receive(V.bandVerify)
        XCTAssertEqual(l.receive(V.bandConfirm), [.write(V.ack1), .event(.authenticated), .write(V.listRequest)])
    }

    func authenticated() -> BandLink {
        let l = link()
        _ = l.start() + l.receive(V.bandSessionReply) + l.receive(V.bandVerify) + l.receive(V.bandConfirm)
        return l
    }

    func testInstalledQuickAppIsLaunched() {
        XCTAssertEqual(authenticated().receive(V.bandList), [.write(V.ack2), .write(V.launch)])
    }

    func testMissingQuickAppIsReported() {
        XCTAssertEqual(authenticated().receive(V.bandListWithoutApp), [.write(V.ack2), .event(.appNotInstalled(installed: ["com.other.app"]))])
    }

    func testMessageWaitsUntilTheQuickAppIsOpenThenGoesStraightOut() {
        let l = authenticated()
        XCTAssertEqual(l.send(V.message), [])
        _ = l.receive(V.bandList)
        XCTAssertEqual(l.receive(V.bandAsksStatus),
                       [.write(V.ack3), .write(V.messageFrame), .write(V.sessionEnd), .event(.messageQueued(payloadBytes: V.message.count, frameBytes: V.messageFrame.count, packets: 1))])
        XCTAssertEqual(l.send(V.message), [.write(V.secondMessageFrame), .event(.messageQueued(payloadBytes: V.message.count, frameBytes: V.secondMessageFrame.count, packets: 1))])
    }

    /// Seen on the band: a quick app left open by the last trip does not ask again, so the phone stops waiting.
    func testMessageGoesToAQuickAppThatWasAlreadyOpen() {
        let l = authenticated()
        XCTAssertEqual(l.send(V.message), [])
        _ = l.receive(V.bandList)
        XCTAssertEqual(l.assumeAppOpen(), [.write(V.messageFrame), .event(.messageQueued(payloadBytes: V.message.count, frameBytes: V.messageFrame.count, packets: 1))])
        // If the band does ask after all, it still gets its answer, without the message twice.
        XCTAssertEqual(l.receive(V.bandAsksStatus), [.write(V.ack3), .write(V.sessionEnd)])
        XCTAssertEqual(l.assumeAppOpen(), [])
    }

    func testNothingIsAssumedBeforeTheQuickAppIsLaunched() {
        let l = authenticated()
        _ = l.send(V.message)
        XCTAssertEqual(l.assumeAppOpen(), [])
    }

    /// On iOS every app shares one BLE link: once we are in, a session reply or auth reply we did not
    /// ask for means another app (Mi Fitness) has just started its own session (AstroBox report_shared_link).
    func testAnotherAppsHandshakeIsReportedAsTakeover() {
        let l = authenticated()
        XCTAssertEqual(l.receive(V.bandSessionReply), [.event(.sessionTakenOver)])
        XCTAssertEqual(authenticated().receive(V.bandVerify), [.write(V.ack0), .event(.sessionTakenOver)])
    }

    func testWritesAreSplitToTheBleWriteSize() {
        let l = link()
        l.maxWriteLength = 20
        XCTAssertEqual(l.start(), [.write(V.sessionStart.prefix(20)), .write(V.sessionStart.dropFirst(20))])
    }

    func testNotificationsAreJoinedIntoFramesSkippingNoise() {
        let l = link()
        _ = l.start() + l.receive(V.bandSessionReply)
        let bytes = hex("00ff") + V.bandVerify
        XCTAssertEqual(l.receive(bytes.prefix(5)), [])
        XCTAssertEqual(l.receive(bytes.dropFirst(5).prefix(30)), [])
        XCTAssertEqual(l.receive(bytes.dropFirst(35)), [.write(V.ack0), .write(V.authStep2)])
    }

    func testCorruptFrameIsDropped() {
        let l = link()
        _ = l.start() + l.receive(V.bandSessionReply)
        var corrupt = V.bandVerify
        corrupt[corrupt.count - 1] ^= 0xFF
        XCTAssertEqual(l.receive(corrupt), [])
    }
}
