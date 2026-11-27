import Foundation

/// The streets around a route from OpenStreetMap, through the public Overpass API (no key; about 10,000 requests and
/// under 1 GB a day, then 429). A 1.45 km route takes 35–42 s: fetch in the background. Sample answer: docs/osm.
public enum Overpass {
    public enum Failure: Error, Equatable {
        case http(Int)
        /// Why it stopped, when it gave up (timeout, out of memory) but still answered 200.
        case remark(String)
        case badResponse
    }

    /// Every street within 150 m of `route` a motorbike can take, as polylines.
    // shortcut: one query with every route point; if long trips time out (a `remark`), ask in pieces of the route.
    public static func streets(along route: [Point]) async throws -> [[Point]] {
        let around = route.map { String(format: "%.5f,%.5f", $0.lat, $0.lon) }.joined(separator: ",")
        let query = "[out:json][timeout:180];way[\"highway\"](around:150,\(around));out tags geom;"
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "data", value: query)]
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!, timeoutInterval: 200)
        request.httpMethod = "POST"
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        // Overpass answers 406 to clients that don't name themselves.
        request.setValue("Maps4MiBand/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Lanes are mostly `service` in Hà Nội, so they stay; ways a motorbike can't take go, expressways too.
    private static let notForMotorbikes: Set = ["footway", "steps", "cycleway", "path", "pedestrian", "bridleway",
                                                "corridor", "platform", "proposed", "construction", "motorway",
                                                "motorway_link"]

    public static func parse(_ data: Data, status: Int) throws -> [[Point]] {
        struct Body: Decodable { let elements: [Way]; let remark: String? }
        struct Way: Decodable { let tags: [String: String]; let geometry: [Node] }
        struct Node: Decodable { let lat: Double; let lon: Double }
        guard status == 200 else { throw Failure.http(status) }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw Failure.badResponse }
        if let remark = body.remark { throw Failure.remark(remark) }
        return body.elements
            .filter { !notForMotorbikes.contains($0.tags["highway"] ?? "") && $0.geometry.count >= 2 }
            .map { $0.geometry.map { Point(lat: $0.lat, lon: $0.lon) } }
    }
}
