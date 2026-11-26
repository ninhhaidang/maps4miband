import Foundation

/// Just enough protobuf for Xiaomi's Command messages (proto2: only fields explicitly set go on the wire).
struct Proto {
    private(set) var bytes = Data()

    init(_ build: (inout Proto) -> Void) { build(&self) }

    mutating func add(_ field: Int, _ value: UInt64) {
        varint(UInt64(field << 3))
        varint(value)
    }

    mutating func add(_ field: Int, _ value: Data) {
        varint(UInt64(field << 3 | 2))
        varint(UInt64(value.count))
        bytes += value
    }

    mutating func add(_ field: Int, _ value: String) { add(field, Data(value.utf8)) }

    mutating func add(_ field: Int, _ value: Proto) { add(field, value.bytes) }

    private mutating func varint(_ v: UInt64) {
        var v = v
        repeat {
            bytes.append(UInt8(v & 0x7F) | (v > 0x7F ? 0x80 : 0))
            v >>= 7
        } while v != 0
    }
}

/// Decoded fields of one message: varints and length-delimited values by field number. Other wire types are skipped.
struct ProtoFields {
    private var varints: [Int: UInt64] = [:]
    private var blobs: [Int: [Data]] = [:]

    init?(_ data: Data) {
        var b = [UInt8](data)[...]
        func varint() -> UInt64? {
            var v: UInt64 = 0, shift: UInt64 = 0
            while let x = b.popFirst() {
                guard shift < 64 else { return nil }
                v |= UInt64(x & 0x7F) << shift
                if x & 0x80 == 0 { return v }
                shift += 7
            }
            return nil
        }
        while !b.isEmpty {
            guard let key = varint() else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0: guard let v = varint() else { return nil }; varints[field] = v
            case 1: guard b.count >= 8 else { return nil }; b = b.dropFirst(8)
            case 2:
                guard let n = varint(), n <= b.count else { return nil }
                blobs[field, default: []].append(Data(b.prefix(Int(n))))
                b = b.dropFirst(Int(n))
            case 5: guard b.count >= 4 else { return nil }; b = b.dropFirst(4)
            default: return nil
            }
        }
    }

    subscript(varint field: Int) -> UInt64? { varints[field] }
    subscript(bytes field: Int) -> Data? { blobs[field]?.first }
    subscript(message field: Int) -> ProtoFields? { blobs[field]?.first.flatMap(ProtoFields.init) }
    func all(_ field: Int) -> [ProtoFields] { (blobs[field] ?? []).compactMap(ProtoFields.init) }
}
