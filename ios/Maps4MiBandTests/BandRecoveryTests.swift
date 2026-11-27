import XCTest
@testable import Maps4MiBand

// The app and the BandLink package replay the same generated fixtures.
func hex(_ s: String) -> Data {
    Data(stride(from: 0, to: s.count, by: 2).map { UInt8(s.dropFirst($0).prefix(2), radix: 16)! })
}

final class BandRecoveryTests: XCTestCase {
    func testForeignVerificationDuringRecoveryAsksToCloseMiFitness() {
        var writes: [Data] = []
        let band = BandConnection(write: { writes.append($0) }, nonce: { V.phoneNonce })
        band.stream(authKey: V.authKey, first: V.message, resumeFrame: { V.message })
        for reply in [V.bandSessionReply, V.bandVerify, V.bandConfirm] { band.receive(reply) }

        band.receive(V.bandSessionReply) // Mi Fitness takes over; the app starts its one retry.
        band.receive(V.bandSessionReply)
        band.receive(V.bandVerifyWrongKey) // The verify belongs to Mi Fitness's nonce.

        XCTAssertTrue(band.retryMessage?.contains("đóng hẳn Mi Fitness") == true)
        XCTAssertEqual(writes.filter { $0 == V.sessionStart }.count, 2)
        band.cancel()
    }

    @MainActor
    func testOneAutomaticRetryPerRideAndManualRetryResumesSending() {
        var writes: [Data] = []
        let band = BandConnection(write: { writes.append($0) }, nonce: { V.phoneNonce })
        band.stream(authKey: V.authKey, first: V.message, resumeFrame: { V.message })

        func openQuickApp() {
            for reply in [V.bandSessionReply, V.bandVerify, V.bandConfirm, V.bandList, V.bandAsksStatus] {
                band.receive(reply)
            }
        }
        func starts() -> Int { writes.filter { $0 == V.sessionStart }.count }
        func frames() -> Int { writes.filter { $0 == V.messageFrame }.count }

        openQuickApp()
        XCTAssertEqual(starts(), 1)
        XCTAssertEqual(frames(), 1)

        band.receive(V.bandSessionReply)
        XCTAssertEqual(starts(), 2)
        XCTAssertNil(band.retryMessage)
        openQuickApp()
        XCTAssertEqual(frames(), 2)

        let count = writes.count
        band.receive(V.bandVerify)
        XCTAssertNotNil(band.retryMessage)
        XCTAssertTrue(band.busy, "the ride still owns the connection")
        band.send(V.message)
        band.receive(V.bandVerify)
        XCTAssertEqual(writes.count, count, "no writes while Mi Fitness owns the session")

        band.retry()
        band.retry()
        XCTAssertEqual(starts(), 3)
        XCTAssertNil(band.retryMessage)
        openQuickApp()
        XCTAssertEqual(frames(), 3)
        band.send(V.message)
        XCTAssertEqual(writes.last, V.secondMessageFrame)

        band.receive(V.bandSessionReply)
        XCTAssertNotNil(band.retryMessage)
        XCTAssertEqual(starts(), 3, "manual retry does not renew the automatic retry")
        band.finish(V.message)
        XCTAssertEqual(starts(), 3)
        XCTAssertFalse(band.busy)
        XCTAssertNil(band.retryMessage)
    }
}
