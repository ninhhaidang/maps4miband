import Foundation

public struct Point: Equatable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    /// "21.0060,105.8150" as typed by the user; nil unless both numbers are valid coordinates.
    public init?(parsing text: String) {
        let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        self.init(lat: parts[0], lon: parts[1])
    }
}

/// A turn at route point `at`; `angle` is the turn in degrees (+ = right), nil = no arrow.
public struct Maneuver: Equatable {
    public var at: Int
    public var text: String
    public var angle: Int?

    public init(at: Int, text: String, angle: Int?) {
        self.at = at
        self.text = text
        self.angle = angle
    }
}

/// One polyline for the whole trip, with maneuvers pointing at its points.
public struct Route {
    public let points: [Point]
    public let maneuvers: [Maneuver]
    /// Metres from the start to each point.
    let cum: [Double]

    public init(points: [Point], maneuvers: [Maneuver]) {
        self.points = points
        self.maneuvers = maneuvers
        var cum = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { cum.append(cum.last! + dist(a, b)) }
        self.cum = cum
    }

    public var length: Double { cum.last! }
}

private let earthR = 6_371_000.0

private func rad(_ d: Double) -> Double { d * .pi / 180 }

/// Equirectangular metres (east, north) of `p` relative to `o`; exact enough over a few km.
func local(_ o: Point, _ p: Point) -> (e: Double, n: Double) {
    (rad(p.lon - o.lon) * cos(rad(o.lat)) * earthR, rad(p.lat - o.lat) * earthR)
}

func dist(_ a: Point, _ b: Point) -> Double {
    let (e, n) = local(a, b)
    return hypot(e, n)
}
