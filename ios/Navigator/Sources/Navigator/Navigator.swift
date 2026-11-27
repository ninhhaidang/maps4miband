import Foundation

/// One message to the quick app (band/src/pages/index/index.ux): p = polyline in band px (rider at 106,345,
/// north up), t = turn marks on it (flat x,y), s = a new layer of grey streets (base64 PNG, layerW×layerH),
/// o = where the layer's top-left goes on the screen (x,y; nil = no layer), n = street of the first mark, h = the rider's heading (degrees clockwise from north), a = turn angle (+ right, nil = no arrow),
/// d = distance to the turn, i = instruction, r = remaining, v = 1 to buzz.
/// A message with only `i` is a status message.
public struct BandMessage: Encodable, Equatable {
    public var p: [Int]?
    public var t: [Int]?
    public var s: String?
    public var o: [Int]?
    public var n: String?
    public var h: Int?
    public var a: Int?
    public var d: String?
    public var i: String
    public var r: String?
    public var v: Int?

    public init(p: [Int]? = nil, t: [Int]? = nil, s: String? = nil, o: [Int]? = nil, n: String? = nil, h: Int? = nil,
                a: Int? = nil, d: String? = nil, i: String, r: String? = nil, v: Int? = nil) {
        (self.p, self.t, self.s, self.o, self.n, self.h, self.a, self.d, self.i, self.r, self.v) =
            (p, t, s, o, n, h, a, d, i, r, v)
    }

    /// Keys sorted so the same screen is always the same bytes, in the log too. Slashes as they are: escaped, the
    /// grey-street picture's base64 grows by one byte in 64.
    public var json: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
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
    public var streets: [[Point]] = [] { didSet { anchor = nil } }
    /// Middle of the grey layer the band has; nil = send a new one.
    private var anchor: Point?
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

    /// The band may not have the grey layer (its app was still opening): send it again with the next frame.
    public func forgetLayer() {
        anchor = nil
    }

    public func update(_ here: Point, at time: Date) -> [Effect] {
        guard !done else { return [] }
        let f = frame(route, here: here, hint: seg)
        let onRoute = f.offRoute <= Tuning.offRouteM
        // Off the route the snap is a guess; keep the last good one so rejoining where we left counts as back.
        if onRoute { seg = f.seg }
        if onRoute && f.remaining < Tuning.arrivedM {
            done = true
            return [.arrived(BandMessage(p: f.poly, h: f.heading, d: "", i: "Đã đến nơi", v: 1))]
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
        var layerPNG: String?, layerAt: [Int]?
        if !streets.isEmpty {
            // Past the layer's margin the screen would show its edge.
            let off = anchor.map { local($0, f.snap) }.map { max(abs($0.e), abs($0.n)) } ?? .infinity
            if off > Tuning.layerMarginPx * Tuning.metresPerPx {
                anchor = f.snap
                layerPNG = mapImage(streets, around: f.snap, width: Int(layerW), height: Int(layerH))?.base64EncodedString()
            }
            let (e, n) = local(f.snap, anchor!)
            layerAt = [Int((Tuning.meX + e / Tuning.metresPerPx - layerW / 2).rounded()),
                       Int((Tuning.meY - n / Tuning.metresPerPx - layerH / 2).rounded())]
        }
        return [.send(BandMessage(p: f.poly, t: f.marks, s: layerPNG, o: layerAt,
                                  n: f.marks.isEmpty ? nil : f.turn.street, h: f.heading, a: f.turn.angle,
                                  d: formatDistance(f.toTurn), i: f.turn.text, r:"Còn \(formatDistance(f.remaining))", v: buzz ? 1 : 0))]
    }
}
