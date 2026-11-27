import Foundation

/// Every number to tune after a test ride, in one place.
public enum Tuning {
    /// Rider marker in band px, in the middle of the map under the instruction panel: north is up, so the route may
    /// leave it any way. Must match `.me` in band/src/pages/index/index.ux.
    static let meX = 106.0
    static let meY = 345.0
    /// The map on the band: 212×520 px, the instruction panel covering y < 170 (MAP_TOP in band/src/common/render.js).
    static let screenW = 212.0
    static let screenH = 520.0
    static let mapTop = 170.0
    /// Grey streets go to the band as one layer it moves rather than redraws: the map plus this much each side, so a
    /// new one is due once the rider is this far from where the last one was made.
    static let layerMarginPx = 50.0
    /// Moving a layer of 300 streets takes up to 1.3 s a frame, 500 take 2.4 s and 4 s to build, 800 freeze the band
    /// (docs/band-screen.md); the ones furthest from the rider go first.
    static let maxLayerSegments = 300
    /// Grey streets are simplified to within this of where they are, 2 m: fewer segments, the same streets.
    static let streetTolerancePx = 1.0
    static let metresPerPx = 2.0
    static let aheadM = 700.0
    static let behindM = 100.0
    /// How far ahead of the last segment to look when snapping; keeps a U-turn from snapping to the way back.
    static let searchM = 500.0
    /// Polyline points closer than this to the previous one are dropped.
    static let minStepPx = 3.0
    /// The band redraws 100 segments a second smoothly, 200 take 3 s (docs/band-screen.md): the route's far end goes
    /// first.
    static let maxSegments = 100
    /// At most one frame per this many seconds, unless it buzzes.
    static let sendEvery: TimeInterval = 1
    /// Buzz once at each of these distances before a turn.
    static let buzzAtM = [200.0, 40.0]
    static let arrivedM = 20.0
    /// This far from the route for this many fixes in a row → ask for a new route.
    static let offRouteM = 40.0
    static let offRouteFixes = 3
    /// At most one new-route request per this many seconds, failed ones included.
    static let rerouteEvery: TimeInterval = 10
}

/// Where the rider is on the route, and the north-up screen polyline. `seg` is the segment snapped to;
/// feed it back as the next `hint`.
/// `marks` are the turns in the drawn stretch (street-name changes and the arrival left out), flat x,y like
/// `poly`; the first of them, if any, is `turn`. `snap` is the rider on the route, drawn at (meX, meY). `heading` is
/// the way they go, in degrees clockwise from north.
struct Frame {
    let poly: [Int]
    let marks: [Int]
    let snap: Point
    let heading: Int
    let turn: Maneuver
    let toTurn: Double
    let remaining: Double
    let offRoute: Double
    let seg: Int
}

/// Snaps `here` to the route and builds the north-up polyline in band px.
/// Only searches forward from `hint` so an out-and-back route can't snap to the return leg.
func frame(_ route: Route, here: Point, hint: Int) -> Frame {
    let pts = route.points, cum = route.cum
    var best = hint, bestT = 0.0, bestD = Double.greatestFiniteMagnitude
    var i = hint
    while i < pts.count - 1 && cum[i] - cum[hint] <= Tuning.searchM {
        let (ax, ay) = local(here, pts[i])
        let (bx, by) = local(here, pts[i + 1])
        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : min(max((-ax * dx - ay * dy) / len2, 0), 1)
        let d = hypot(ax + t * dx, ay + t * dy)
        if d < bestD { (best, bestT, bestD) = (i, t, d) }
        i += 1
    }
    let along = cum[best] + bestT * (cum[best + 1] - cum[best])
    let a = pts[best], b = pts[best + 1]
    let snap = Point(lat: a.lat + bestT * (b.lat - a.lat), lon: a.lon + bestT * (b.lon - a.lon))

    // From the route rather than GPS: GPS bearing is noise at walking speed.
    let (he, hn) = local(a, b)
    let heading = (Int((atan2(he, hn) * 180 / .pi).rounded()) + 360) % 360
    func screen(_ p: Point) -> (x: Double, y: Double) {
        let (e, n) = local(snap, p)
        return (Tuning.meX + e / Tuning.metresPerPx, Tuning.meY - n / Tuning.metresPerPx)
    }
    var poly: [Int] = []
    var last = (x: Double.nan, y: Double.nan)
    func add(_ p: Point, force: Bool = false) {
        let (x, y) = screen(p)
        if poly.count > 2 * Tuning.maxSegments || !force && hypot(x - last.x, y - last.y) < Tuning.minStepPx { return }
        poly += [Int(x.rounded()), Int(y.rounded())]
        last = (x, y)
    }
    var j = best
    while j > 0 && along - cum[j] < Tuning.behindM { j -= 1 }
    for k in j...best { add(pts[k]) }
    add(snap)
    for k in best + 1 ..< pts.count {
        let far = cum[k] - along >= Tuning.aheadM
        add(pts[k], force: far)
        if far { break }
    }

    // Skip street-name changes ("Đi thẳng", nearly every junction) so the real turn behind one shows and buzzes on time.
    func ahead(_ m: Maneuver) -> Bool { m.at > best && m.angle != 0 }
    let turn = route.maneuvers.first(where: ahead) ?? route.maneuvers.last!
    let marks = route.maneuvers
        .filter { ahead($0) && $0 != route.maneuvers.last && cum[$0.at] - along < Tuning.aheadM }
        .flatMap { m in let (x, y) = screen(pts[m.at]); return [Int(x.rounded()), Int(y.rounded())] }

    return Frame(poly: poly, marks: marks, snap: snap, heading: heading, turn: turn, toTurn: max(cum[turn.at] - along, 0),
                 remaining: cum.last! - along, offRoute: bestD, seg: best)
}

/// The grey layer's size in band px: the map under the panel plus `Tuning.layerMarginPx` each side.
let layerW = Tuning.screenW + 2 * Tuning.layerMarginPx
let layerH = Tuning.screenH - Tuning.mapTop + 2 * Tuning.layerMarginPx

/// `streets` around `anchor`, north up, as segments flat x1,y1,x2,y2 from the layer's top-left, `anchor` in its
/// middle: cut to the layer, nearest `anchor` first, at most `Tuning.maxLayerSegments`.
func layer(_ streets: [[Point]], around anchor: Point) -> [Int] {
    func px(_ p: Point) -> (x: Double, y: Double) {
        let (e, n) = local(anchor, p)
        return (layerW / 2 + e / Tuning.metresPerPx, layerH / 2 - n / Tuning.metresPerPx)
    }
    var segs: [(d: Double, s: [Int])] = []
    for street in streets {
        let line = simplify(street.map(px), tolerance: Tuning.streetTolerancePx)
        for (a, b) in zip(line, line.dropFirst()) {
            if let c = clip(a, b) { segs.append((distance((layerW / 2, layerH / 2), c), c.map { Int($0.rounded()) })) }
        }
    }
    return segs.sorted { $0.d < $1.d }.prefix(Tuning.maxLayerSegments).flatMap(\.s)
}

/// The points of `line` that keep it within `tolerance` px of where it was (Douglas–Peucker): fewer segments for
/// the same street.
private func simplify(_ line: [(x: Double, y: Double)], tolerance: Double) -> [(x: Double, y: Double)] {
    guard line.count > 2 else { return line }
    var keep = [Bool](repeating: false, count: line.count)
    (keep[0], keep[line.count - 1]) = (true, true)
    var spans = [(0, line.count - 1)]
    while let (i, j) = spans.popLast() {
        let chord = [line[i].x, line[i].y, line[j].x, line[j].y]
        var far = i, farD = tolerance
        for k in i + 1 ..< j {
            let d = distance(line[k], chord)
            if d > farD { (far, farD) = (k, d) }
        }
        if far != i {
            keep[far] = true
            spans += [(i, far), (far, j)]
        }
    }
    return line.indices.filter { keep[$0] }.map { line[$0] }
}

/// The part of a→b on the layer as x1,y1,x2,y2, nil if none (Liang–Barsky).
private func clip(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> [Double]? {
    let dx = b.x - a.x, dy = b.y - a.y
    var t0 = 0.0, t1 = 1.0
    for (p, q) in [(-dx, a.x), (dx, layerW - a.x), (-dy, a.y), (dy, layerH - a.y)] {
        if p == 0 {
            if q < 0 { return nil }
        } else if p < 0 {
            t0 = max(t0, q / p)
        } else {
            t1 = min(t1, q / p)
        }
    }
    return t0 < t1 ? [a.x + t0 * dx, a.y + t0 * dy, a.x + t1 * dx, a.y + t1 * dy] : nil
}

/// From `p` to the nearest point of segment `s` (x1,y1,x2,y2).
private func distance(_ p: (x: Double, y: Double), _ s: [Double]) -> Double {
    let dx = s[2] - s[0], dy = s[3] - s[1]
    let len2 = dx * dx + dy * dy
    let t = len2 == 0 ? 0 : min(max(((p.x - s[0]) * dx + (p.y - s[1]) * dy) / len2, 0), 1)
    return hypot(s[0] + t * dx - p.x, s[1] + t * dy - p.y)
}

/// "80 m" under 1 km (to 10 m), else "1.6 km".
public func formatDistance(_ m: Double) -> String {
    m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000)
}
