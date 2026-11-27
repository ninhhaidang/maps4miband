import Foundation

/// One message to the quick app (band/src/pages/index/index.ux): p = polyline in band px (rider at 106,460,
/// heading up), t = turn marks on it (flat x,y), g = grey streets around it (flat x1,y1,x2,y2), n = street of the
/// first mark, a = turn angle (+ right, nil = no arrow), d = distance to the turn, i = instruction, r = remaining,
/// v = 1 to buzz.
/// A message with only `i` is a status message.
public struct BandMessage: Encodable, Equatable {
    public var p: [Int]?
    public var t: [Int]?
    public var g: [Int]?
    public var n: String?
    public var a: Int?
    public var d: String?
    public var i: String
    public var r: String?
    public var v: Int?

    public init(p: [Int]? = nil, t: [Int]? = nil, g: [Int]? = nil, n: String? = nil, a: Int? = nil, d: String? = nil,
                i: String, r: String? = nil, v: Int? = nil) {
        (self.p, self.t, self.g, self.n, self.a, self.d, self.i, self.r, self.v) = (p, t, g, n, a, d, i, r, v)
    }

    /// Keys sorted so the same screen is always the same bytes, in the log too.
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try! encoder.encode(self)
    }
}

/// Follows timed GPS fixes along a route and decides what the band shows and when.
public final class Navigator {
    public enum Effect: Equatable {
        case send(BandMessage)
        /// Last message; navigation is over.
        case arrived(BandMessage)
        /// Off the route: fetch a new one from here, then call `rerouted` or `rerouteFailed`.
        case reroute(from: Point)
    }

    private var route: Route
    /// Streets around the route (StreetMap), drawn grey once they are in; none until then.
    public var streets: [[Point]] = []
    private var seg = 0
    private var lastSend: Date?
    private var done = false
    /// Turn we last buzzed for, and how many of `Tuning.buzzAtM` it has had.
    private var buzzTurn: Int?
    private var buzzes = 0
    /// Fixes in a row further than `Tuning.offRouteM` from the route.
    private var offFixes = 0
    private var rerouting = false
    private var lastReroute: Date?

    public init(route: Route) {
        self.route = route
    }

    /// Follows `route` from its start, with fresh buzzes, and sends its first frame on the next fix.
    public func rerouted(_ route: Route) {
        self.route = route
        (seg, lastSend, buzzTurn, buzzes, offFixes, rerouting) = (0, nil, nil, 0, 0, false)
    }

    /// The new route could not be fetched; asks again no sooner than `Tuning.rerouteEvery` after the last ask.
    public func rerouteFailed() {
        rerouting = false
    }

    public func update(_ here: Point, at time: Date) -> [Effect] {
        guard !done else { return [] }
        let f = frame(route, here: here, hint: seg, streets: streets)
        let onRoute = f.offRoute <= Tuning.offRouteM
        // Off the route the snap is a guess; keep the last good one so rejoining where we left counts as back.
        if onRoute { seg = f.seg }
        if onRoute && f.remaining < Tuning.arrivedM {
            done = true
            return [.arrived(BandMessage(p: f.poly, d: "", i: "Đã đến nơi", v: 1))]
        }
        offFixes = onRoute ? 0 : offFixes + 1
        if offFixes >= Tuning.offRouteFixes {
            // Off the route the old frame is wrong: leave "Đang tìm đường lại…" or the error on the band.
            if rerouting { return [] }
            if let lastReroute, time.timeIntervalSince(lastReroute) < Tuning.rerouteEvery { return [] }
            (rerouting, lastReroute) = (true, time)
            return [.send(BandMessage(i: "Đang tìm đường lại…")), .reroute(from: here)]
        }
        if buzzTurn != f.turn.at { (buzzTurn, buzzes) = (f.turn.at, 0) }
        let due = Tuning.buzzAtM.filter { f.toTurn < $0 }.count
        let buzz = due > buzzes
        buzzes = max(buzzes, due)
        if !buzz, let lastSend, time.timeIntervalSince(lastSend) < Tuning.sendEvery { return [] }
        lastSend = time
        return [.send(BandMessage(p: f.poly, t: f.marks, g: f.streets.isEmpty ? nil : f.streets,
                                  n: f.marks.isEmpty ? nil : f.turn.street, a: f.turn.angle,
                                  d: formatDistance(f.toTurn), i: f.turn.text, r:"Còn \(formatDistance(f.remaining))", v: buzz ? 1 : 0))]
    }
}
