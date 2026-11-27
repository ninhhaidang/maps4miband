import Foundation
import Security

public enum Effect: Equatable {
    case write(Data)
    case event(Event)
}

public enum Event: Equatable {
    case authKeyRejected
    case authenticated
    /// `installed`: package ids the band listed, to tell a missing app from an id mismatch.
    case appNotInstalled(installed: [String])
    case messageSent
    case sessionTakenOver
    /// The band would not take the package. PrepareStatus: 1 busy, 2 duplicated, 3 low storage, 4 low battery,
    /// 5 downgrade, 6 not supported, 7 too many apps, 255 failed.
    case installRefused(status: Int)
    case installProgress(sent: Int, of: Int)
    case installed
    /// AppInstaller.Result code: 1 install failed, 2 verify failed (corrupt package).
    case installFailed(code: Int)
}

/// Xiaomi BLE V2 protocol to talk to a quick app on the band, bytes in / bytes out (no CoreBluetooth).
/// Port of Gadgetbridge (XiaomiBleProtocolV2, XiaomiAuthService, XiaomiRpkService) and
/// AstroBox-NG-Module-Core (components/auth, thirdparty_app, sar), both AGPL-3.0.
public final class BandLink {
    private enum State { case idle, session, verifying, confirming, ready }

    private let authKey: Data
    private let appPackage: String
    private let makeNonce: () -> Data
    private var state = State.idle
    private var reader = FrameReader()
    private var nextSeq: UInt8 = 0
    private var phoneNonce = Data()

    /// Largest single BLE write (CoreBluetooth maximumWriteValueLength). Longer frames go out in pieces.
    public var maxWriteLength = 244

    /// `authKey`: 32 hex characters, optionally prefixed with 0x. Nil if malformed.
    public init?(authKey: String, appPackage: String, nonce: @escaping () -> Data = BandLink.randomNonce) {
        var hex = authKey.trimmingCharacters(in: .whitespaces).lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(hex.dropFirst($0).prefix(2), radix: 16) }
        guard hex.count == 32, bytes.count == 16 else { return nil }
        self.authKey = Data(bytes)
        self.appPackage = appPackage
        self.makeNonce = nonce
    }

    public static func randomNonce() -> Data {
        var b = [UInt8](repeating: 0, count: 16)
        precondition(SecRandomCopyBytes(kSecRandomDefault, b.count, &b) == errSecSuccess)
        return Data(b)
    }

    // Session config payload from Gadgetbridge (official app dump): version 1.0.0, max frame 0xfc00,
    // tx window 32 frames, send timeout 10000 ms.
    static let sessionConfig = Data([0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x00, 0x00, 0xFC,
                                     0x03, 0x02, 0x00, 0x20, 0x00, 0x04, 0x02, 0x00, 0x10, 0x27])

    public func start() -> [Effect] {
        state = .session
        nextSeq = 0
        reader = FrameReader()
        return write(Frame(type: .session, seq: 0, payload: Data([1]) + Self.sessionConfig))
    }

    public func receive(_ chunk: Data) -> [Effect] {
        reader.feed(chunk).flatMap(handle)
    }

    private func handle(_ frame: Frame) -> [Effect] {
        switch frame.type {
        case .session where frame.payload.first == 2 && state == .session:
            phoneNonce = makeNonce()
            state = .verifying
            return send(Command.authNonce(phoneNonce))
        case .session where frame.payload.first == 2 && state == .ready:
            return takenOver()
        case .data:
            // Data payload: channel (1 = protobuf) | opcode (1 plain, 2 encrypted) | body.
            let p = [UInt8](frame.payload)
            let ack = write(Frame(type: .ack, seq: frame.seq, payload: Data()))
            guard p.count >= 2, p[0] & 0x0F == 1 else { return ack }
            var body = Data(p.dropFirst(2))
            if p[1] == 2 {
                guard let keys else { return ack }
                body = aesCTR(key: keys.decKey, iv: keys.decKey, body)
            }
            guard let cmd = ProtoFields(body) else { return ack }
            return ack + handle(cmd)
        case .ack where frame.seq == awaitingAck:
            awaitingAck = nil
            return [.event(.installProgress(sent: partsTotal - parts.count, of: partsTotal))] + sendNextPart()
        case .nack where frame.seq == awaitingAck:
            return write(partInFlight!)
        default:
            return []
        }
    }

    private var keys: SessionKeys?
    private var appSha: Data?
    private var appOpen = false
    /// Only the newest message waits for the quick app: each one is a whole screen.
    private var pending: Data?
    /// Package being installed; set, it replaces opening the app after auth.
    private var rpk: Data?
    private var sliceHint: UInt64?
    private var parts: [Data] = []
    private var partsTotal = 0
    private var awaitingAck: UInt8?
    private var partInFlight: Frame?

    private func handle(_ cmd: ProtoFields) -> [Effect] {
        switch (cmd[varint: 1], cmd[varint: 2]) {
        case (1, 26):
            guard state == .verifying else { return state == .ready ? takenOver() : [] }
            // A reply without DeviceVerify carries an account error code instead (AstroBox: device rejected).
            guard let verify = cmd[message: 3]?[message: 31],
                  let watchNonce = verify[bytes: 1], let hmac = verify[bytes: 2] else { return reject() }
            let k = SessionKeys(authKey: authKey, phoneNonce: phoneNonce, watchNonce: watchNonce)
            guard hmacSHA256(k.decKey, watchNonce + phoneNonce) == hmac else { return reject() }
            keys = k
            state = .confirming
            let companion = Proto {
                $0.add(1, 1) // device type iOS, as AstroBox sends over BLE
                $0.add(3, "maps4miband")
                $0.add(4, 0xFFFF_FFFF) // app capability, as AstroBox
            }
            return send(Command.authConfirm(
                signs: hmacSHA256(k.encKey, phoneNonce + watchNonce),
                deviceInfo: aesCCMEncrypt(key: k.encKey, nonce: k.encNonce + Data(count: 8), companion.bytes)))
        case (1, 27):
            guard state == .confirming else { return state == .ready ? takenOver() : [] }
            guard cmd[message: 3]?[message: 33]?[varint: 1] == 1 else { return reject() }
            state = .ready
            return [.event(.authenticated)]
                + send(rpk.map { Command.prepareInstall(appPackage, size: $0.count) } ?? Command.rpk(0), encrypted: true)
        case (20, _) where state == .ready && rpk != nil && cmd[message: 22]?[message: 3] != nil:
            let reply = cmd[message: 22]![message: 3]!
            let status = reply[varint: 1] ?? 255
            guard status == 0 else { return refuseInstall(status) }
            sliceHint = reply[varint: 2]
            return send(Command.massPrepare(md5: Mass.md5(rpk!), length: rpk!.count), encrypted: true)
        case (22, _) where state == .ready && rpk != nil && cmd[message: 24]?[message: 2] != nil:
            let reply = cmd[message: 24]![message: 2]!
            let status = reply[varint: 2] ?? 255
            guard status == 0 else { return refuseInstall(status) }
            // The mass reply's slice length wins over the install reply's; neither → the official default.
            let slice = [reply[varint: 5], sliceHint].compactMap { $0 }.first { $0 > 0 }.map(Int.init) ?? Mass.defaultSlice
            guard slice > Mass.partHeader else { return refuseInstall(255) }
            parts = Mass.parts(rpk!, from: Int(reply[varint: 4] ?? 0), slice: slice)
            partsTotal = parts.count
            return sendNextPart()
        case (20, _) where state == .ready && rpk != nil && cmd[message: 22]?[message: 4] != nil:
            let code = cmd[message: 22]![message: 4]![varint: 1] ?? 255
            endInstall()
            return [.event(code == 0 ? .installed : .installFailed(code: Int(code)))]
        case (20, 0) where state == .ready:
            // Installed list: rpk.rpkList.rpkInfo[] = { id 1, sha 2, name 5 }. Launch needs the sha.
            let apps = cmd[message: 22]?[message: 1]?.all(1) ?? []
            guard let sha = apps.first(where: { $0[bytes: 1] == Data(appPackage.utf8) })?[bytes: 2] else {
                return [.event(.appNotInstalled(installed: apps.compactMap { $0[bytes: 1].flatMap { String(data: $0, encoding: .utf8) } }))]
            }
            appSha = sha
            // The official app launches by the package of the app on the band (Gadgetbridge).
            return send(Command.launch(id: appPackage, sha: sha, wearPackage: appPackage), encrypted: true)
        case (20, 6) where state == .ready && cmd[message: 22]?[message: 5]?[bytes: 1] == Data(appPackage.utf8):
            // The quick app opened its interconnect and the band asks whether the phone side is there.
            guard let sha = appSha else { return [] }
            appOpen = true
            // Gadgetbridge's capture of Mi Fitness: messages, then "session end" (AstroBox reads the same
            // bytes as phone app status CONNECTED).
            guard let payload = pending else { return send(Command.sessionEnd(id: appPackage, sha: sha), encrypted: true) }
            pending = nil
            return send(Command.message(id: appPackage, sha: sha, payload: payload), encrypted: true)
                + send(Command.sessionEnd(id: appPackage, sha: sha), encrypted: true) + [.event(.messageSent)]
        default:
            return []
        }
    }

    /// Sends `payload` to the quick app (its `interconnect.onmessage`), once it is open. Before that, keeps the newest one.
    public func send(_ payload: Data) -> [Effect] {
        guard appOpen else {
            pending = payload
            return []
        }
        return send(Command.message(id: appPackage, sha: appSha!, payload: payload), encrypted: true) + [.event(.messageSent)]
    }

    /// Installs `rpk` as the quick app (same package), instead of opening it, once authenticated.
    public func install(_ rpk: Data) -> [Effect] {
        self.rpk = rpk
        return state == .ready ? send(Command.prepareInstall(appPackage, size: rpk.count), encrypted: true) : []
    }

    private func refuseInstall(_ status: UInt64) -> [Effect] {
        endInstall()
        return [.event(.installRefused(status: Int(status)))]
    }

    private func endInstall() {
        rpk = nil
        sliceHint = nil
        parts = []
        awaitingAck = nil
        partInFlight = nil
    }

    /// Mass parts go on channel 2, opcode 1 (plaintext), one at a time: the next waits for this one's ack.
    private func sendNextPart() -> [Effect] {
        guard !parts.isEmpty else { return [] }
        let frame = Frame(type: .data, seq: nextSeq, payload: Data([2, 1]) + parts.removeFirst())
        nextSeq &+= 1
        awaitingAck = frame.seq
        partInFlight = frame
        return write(frame)
    }

    /// Another app on the phone started its own session on the shared link; ours is dead. Reported once.
    private func takenOver() -> [Effect] {
        state = .idle
        appOpen = false
        return [.event(.sessionTakenOver)]
    }

    private func reject() -> [Effect] {
        state = .idle
        return [.event(.authKeyRejected)]
    }

    /// Auth commands go in plaintext (opcode 1); everything after auth is AES-CTR with key = IV (opcode 2).
    private func send(_ command: Proto, encrypted: Bool = false) -> [Effect] {
        let body = encrypted ? aesCTR(key: keys!.encKey, iv: keys!.encKey, command.bytes) : command.bytes
        return sendFrame(Data([1, encrypted ? 2 : 1]) + body)
    }

    /// Data payload: channel | opcode | body.
    private func sendFrame(_ payload: Data) -> [Effect] {
        let frame = Frame(type: .data, seq: nextSeq, payload: payload)
        nextSeq &+= 1
        return write(frame)
    }

    private func write(_ frame: Frame) -> [Effect] {
        let b = frame.bytes
        return stride(from: 0, to: b.count, by: maxWriteLength).map { .write(Data(b.dropFirst($0).prefix(maxWriteLength))) }
    }
}

/// Xiaomi `Command` protobuf: type 1, subtype 2, payloads by field (3 auth, 22 rpk).
enum Command {
    static func authNonce(_ nonce: Data) -> Proto {
        Proto {
            $0.add(1, 1)
            $0.add(2, 26)
            $0.add(3, Proto { $0.add(30, Proto { $0.add(1, nonce) }) })
        }
    }

    static func rpk(_ subtype: UInt64, _ payload: Proto? = nil) -> Proto {
        Proto {
            $0.add(1, 20)
            $0.add(2, subtype)
            if let payload { $0.add(22, payload) }
        }
    }

    /// rpk ref { id 1, sha 2 } as in the installed list.
    private static func ref(_ id: String, _ sha: Data) -> Proto { Proto { $0.add(1, id); $0.add(2, sha) } }

    static func launch(id: String, sha: Data, wearPackage: String) -> Proto {
        rpk(4, Proto { $0.add(6, Proto { $0.add(1, ref(id, sha)); $0.add(2, wearPackage) }) })
    }

    static func message(id: String, sha: Data, payload: Data) -> Proto {
        rpk(8, Proto { $0.add(9, Proto { $0.add(1, ref(id, sha)); $0.add(2, payload) }) })
    }

    static func sessionEnd(id: String, sha: Data) -> Proto {
        rpk(7, Proto { $0.add(8, Proto { $0.add(1, ref(id, sha)); $0.add(2, 1) }) })
    }

    static func authConfirm(signs: Data, deviceInfo: Data) -> Proto {
        Proto {
            $0.add(1, 1)
            $0.add(2, 27)
            $0.add(3, Proto { $0.add(32, Proto { $0.add(1, signs); $0.add(2, deviceInfo) }) })
        }
    }
}
