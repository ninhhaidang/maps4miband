import Foundation

/// Xiaomi SPP V2 frame, also used over BLE V2 (service fe95, 005e notify / 005f write):
/// `a5 a5 | type | seq | payload length (LE) | CRC-16/ARC of payload (LE) | payload`.
/// Port of Gadgetbridge XiaomiSppPacketV2 (AGPL-3.0).
enum FrameType: UInt8 {
    case nack = 0, ack = 1, session = 2, data = 3
}

struct Frame: Equatable {
    var type: FrameType
    var seq: UInt8
    var payload: Data

    static let headerSize = 8

    var bytes: Data {
        let n = UInt16(payload.count), crc = crc16arc(payload)
        return Data([0xA5, 0xA5, type.rawValue, seq, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(crc & 0xFF), UInt8(crc >> 8)]) + payload
    }
}

func crc16arc(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0
    for b in data {
        crc ^= UInt16(b)
        for _ in 0..<8 { crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
    }
    return crc
}

/// Joins BLE notifications into frames. Bytes that cannot start a frame are skipped up to the next preamble.
struct FrameReader {
    private var buffer = Data()

    mutating func feed(_ chunk: Data) -> [Frame] {
        buffer += chunk
        var frames: [Frame] = []
        while buffer.count >= Frame.headerSize {
            let b = [UInt8](buffer.prefix(Frame.headerSize))
            guard b[0] == 0xA5, b[1] == 0xA5 else { skipToNextPreamble(); continue }
            let size = Frame.headerSize + (Int(b[4]) | Int(b[5]) << 8)
            guard buffer.count >= size else { break }
            let payload = Data(buffer.dropFirst(Frame.headerSize).prefix(size - Frame.headerSize))
            buffer = Data(buffer.dropFirst(size))
            if let type = FrameType(rawValue: b[2] & 0x0F), crc16arc(payload) == UInt16(b[6]) | UInt16(b[7]) << 8 {
                frames.append(Frame(type: type, seq: b[3], payload: payload))
            }
        }
        return frames
    }

    private mutating func skipToNextPreamble() {
        let rest = buffer.dropFirst()
        buffer = rest.firstIndex(of: 0xA5).map { Data(rest[$0...]) } ?? Data()
    }
}
