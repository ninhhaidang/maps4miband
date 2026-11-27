import Foundation

/// Every number to tune after a test ride, in one place.
public enum Tuning {
    /// Rider marker in band px, near the bottom under the instruction panel; must match `.me` in
    /// band/src/pages/index/index.ux.
    static let meX = 106.0
    static let meY = 460.0
    static let metresPerPx = 2.0
    static let aheadM = 700.0
    static let behindM = 100.0
    /// How far ahead of the last segment to look when snapping; keeps a U-turn from snapping to the way back.
    static let searchM = 500.0
    /// Polyline points closer than this to the previous one are dropped.
    static let minStepPx = 3.0
    /// The band redraws 100 segments a second smoothly, 200 take 3 s (docs/band-screen.md); the far end goes first.
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

/// Where the rider is on the route, and the heading-up screen polyline. `seg` is the segment snapped to;
/// feed it back as the next `hint`.
/// `marks` are the turns in the drawn stretch (street-name changes and the arrival left out), flat x,y like
/// `poly`; the first of them, if any, is `turn`.
struct Frame {
    let poly: [Int]
    let marks: [Int]
    let turn: Maneuver
    let toTurn: Double
    let remaining: Double
    let offRoute: Double
    let seg: Int
}

/// Snaps `here` to the route and builds the heading-up polyline in band px.
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

    // Heading from the route rather than GPS: GPS bearing is noise at walking speed.
    let (he, hn) = local(a, b)
    let h = atan2(he, hn)
    func screen(_ p: Point) -> (x: Double, y: Double) {
        let (e, n) = local(snap, p)
        return (Tuning.meX + (e * cos(h) - n * sin(h)) / Tuning.metresPerPx,
                Tuning.meY - (e * sin(h) + n * cos(h)) / Tuning.metresPerPx)
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
    return Frame(poly: poly, marks: marks, turn: turn, toTurn: max(cum[turn.at] - along, 0), remaining: cum.last! - along,
                 offRoute: bestD, seg: best)
}

/// "80 m" under 1 km (to 10 m), else "1.6 km".
public func formatDistance(_ m: Double) -> String {
    m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000)
}
