import Foundation

/// The streets of an area, bundled with the app (tools/streets.py, from OpenStreetMap), for the grey streets on the
/// band without asking a server mid-ride.
public struct StreetMap {
    let streets: [[Point]]

    /// `data`: raw deflate of little-endian Int32s, per street its point count, then lat and lon × 1e5 per point.
    public init(deflated data: Data) throws {
        let raw = try (data as NSData).decompressed(using: .zlib) as Data
        let ints = raw.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }.map { Int(Int32(littleEndian: $0)) }
        var streets: [[Point]] = []
        var i = 0
        while i < ints.count {
            let n = ints[i]
            guard n >= 0, i + 1 + 2 * n <= ints.count else { throw CocoaError(.fileReadCorruptFile) }
            streets.append((0..<n).map { k in Point(lat: Double(ints[i + 1 + 2 * k]) / 1e5, lon: Double(ints[i + 2 + 2 * k]) / 1e5) })
            i += 1 + 2 * n
        }
        self.streets = streets
    }

    /// Every street within 500 m of `route`, enough for the grey layer around any point of it (and some up to ~650 m:
    /// whole grid cells of 0.001°, about 110 m).
    public func along(_ route: [Point]) -> [[Point]] {
        let cell = 0.001
        func key(_ lat: Int, _ lon: Int) -> Int { lat * 1_000_000 + lon }
        var near = Set<Int>()
        sample(route) { p in
            let lat = Int((p.lat / cell).rounded(.down)), lon = Int((p.lon / cell).rounded(.down))
            for a in lat - 5...lat + 5 { for b in lon - 5...lon + 5 { near.insert(key(a, b)) } }
        }
        return streets.filter { street in
            var hit = false
            sample(street) { p in
                hit = hit || near.contains(key(Int((p.lat / cell).rounded(.down)), Int((p.lon / cell).rounded(.down))))
            }
            return hit
        }
    }
}

/// Every point of `line`, and points at most 50 m apart between them, so a long segment can't skip a cell.
private func sample(_ line: [Point], _ visit: (Point) -> Void) {
    guard let first = line.first else { return }
    visit(first)
    for (a, b) in zip(line, line.dropFirst()) {
        let steps = Int(dist(a, b) / 50) + 1
        for s in 1...steps {
            let t = Double(s) / Double(steps)
            visit(Point(lat: a.lat + t * (b.lat - a.lat), lon: a.lon + t * (b.lon - a.lon)))
        }
    }
}
