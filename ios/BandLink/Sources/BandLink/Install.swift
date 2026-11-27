import CryptoKit
import Foundation

/// Installing a quick app: port of AstroBox-NG-Module-Core components/install, components/mass and packet/mass
/// (AGPL-3.0) for the third-party app type only.
extension Command {
    static func prepareInstall(_ package: String, size: Int) -> Proto {
        // shortcut: fixed version code 114514 as AstroBox sends (the band replaced the app in place with it); send the
        // manifest's versionCode if the band ever answers DOWNGRADE or DUPLICATED.
        rpk(1, Proto { $0.add(2, Proto { $0.add(1, package); $0.add(2, 114514); $0.add(3, UInt64(size)) }) })
    }

    /// Mass (type 22) prepare: data type 64 = third-party app, data id = md5 of the file.
    static func massPrepare(md5: Data, length: Int) -> Proto {
        Proto {
            $0.add(1, 22)
            $0.add(2, 0)
            $0.add(24, Proto { $0.add(1, Proto { $0.add(1, 64); $0.add(2, md5); $0.add(3, UInt64(length)) }) })
        }
    }
}

enum Mass {
    /// Slice length when neither prepare reply names one (the official app's default, per AstroBox).
    static let defaultSlice = 4096
    /// Wire bytes of a part before its data: channel | opcode | total LE16 | part LE16.
    static let partHeader = 6

    static func md5(_ data: Data) -> Data { Data(Insecure.MD5.hash(data: data)) }

    /// Mass payload `00 | 0x40 | md5 | length LE32 | file | CRC-32 LE32`, from byte `sent` on when the band kept part
    /// of an earlier transfer, cut into parts of `slice` bytes on the wire: channel | opcode | total LE16 | part LE16 | data.
    static func parts(_ file: Data, from sent: Int, slice: Int) -> [Data] {
        let rest = file.dropFirst(min(sent, file.count))
        var body = Data([0x00, 0x40]) + md5(file) + le(UInt32(rest.count), 4) + rest
        body += le(crc32(body), 4)
        let n = slice - partHeader
        let chunks = stride(from: 0, to: body.count, by: n).map { body.dropFirst($0).prefix(n) }
        return chunks.enumerated().map { le(UInt32(chunks.count), 2) + le(UInt32($0.offset + 1), 2) + $0.element }
    }

    private static func le(_ v: UInt32, _ bytes: Int) -> Data { Data((0..<bytes).map { UInt8(v >> (8 * $0) & 0xFF) }) }

    /// CRC-32/ISO-HDLC (zlib's crc32).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
