import Foundation

/// Vietmap Autocomplete v4, Place v4 and Route v4 (motorcycle). Sign table and the `interval` quirk: docs/vietmap/README.md.
public enum Vietmap {
    public enum Failure: Error, Equatable {
        case offline
        case badKey
        case quota
        case http(Int)
        case noRoute(String)
        case badResponse

        /// Short enough for the band's two-line instruction.
        public var message: String {
            switch self {
            case .offline: "Mất mạng, không gọi được Vietmap"
            case .badKey: "API key Vietmap sai"
            case .quota: "Hết hạn mức Vietmap hôm nay"
            case .http(let code): "Vietmap lỗi HTTP \(code)"
            case .noRoute(let why): "Vietmap không tìm được đường: \(why)"
            case .badResponse: "Vietmap trả dữ liệu lạ"
            }
        }

        public static func message(for error: Error) -> String {
            (error as? Failure)?.message ?? error.localizedDescription
        }
    }

    /// Autocomplete v4 result; `id` is Vietmap's ref_id, only good for `point(of:)` right away.
    public struct Place: Equatable, Identifiable, Decodable {
        public let id: String
        public let name: String
        public let address: String

        enum CodingKeys: String, CodingKey {
            case id = "ref_id", name, address
        }
    }

    /// Places matching `text`, nearest to `near` first.
    public static func search(_ text: String, near: Point?, apiKey: String) async throws -> [Place] {
        var query = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "display_type", value: "1")]
        if let near { query.append(URLQueryItem(name: "focus", value: "\(near.lat),\(near.lon)")) }
        let (data, status) = try await get("autocomplete/v4", query, apiKey: apiKey)
        return try parsePlaces(data, status: status)
    }

    public static func parsePlaces(_ data: Data, status: Int) throws -> [Place] {
        try check(status)
        guard let places = try? JSONDecoder().decode([Place].self, from: data) else { throw Failure.badResponse }
        return places
    }

    /// Place v4: where a search result is. Costs one Place request (500/day on Trial).
    public static func point(of place: Place, apiKey: String) async throws -> Point {
        let (data, status) = try await get("place/v4", [URLQueryItem(name: "refid", value: place.id)], apiKey: apiKey)
        return try parsePoint(data, status: status)
    }

    public static func parsePoint(_ data: Data, status: Int) throws -> Point {
        struct Body: Decodable { let lat: Double; let lng: Double }
        try check(status)
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw Failure.badResponse }
        return Point(lat: body.lat, lon: body.lng)
    }

    public static func route(from: Point, to: Point, apiKey: String) async throws -> Route {
        let (data, status) = try await get("route/v4", [
            URLQueryItem(name: "point", value: "\(from.lat),\(from.lon)"),
            URLQueryItem(name: "point", value: "\(to.lat),\(to.lon)"),
            URLQueryItem(name: "vehicle", value: "motorcycle"),
        ], apiKey: apiKey)
        return try parse(data, status: status)
    }

    private static func get(_ path: String, _ query: [URLQueryItem], apiKey: String) async throws -> (Data, Int) {
        var url = URLComponents(string: "https://maps.vietmap.vn/api/" + path)!
        url.queryItems = [URLQueryItem(name: "apikey", value: apiKey)] + query
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url.url!)
        } catch let error as URLError where error.code != .cancelled {
            throw Failure.offline
        }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private static func check(_ status: Int) throws {
        switch status {
        case 200: break
        case 401, 403: throw Failure.badKey
        case 429: throw Failure.quota
        default: throw Failure.http(status)
        }
    }

    public static func parse(_ data: Data, status: Int) throws -> Route {
        try check(status)
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw Failure.badResponse }
        guard body.code == "OK", let path = body.paths?.first else {
            throw Failure.noRoute(body.messages ?? body.code)
        }
        let points = decodePolyline(path.points)
        let steps = path.instructions
        guard points.count >= 2, let last = steps.last else { throw Failure.badResponse }
        // The polyline has one extra point per step boundary, so step k sits at interval[0] + k.
        // If Vietmap fixes that, the last step lands on the last point without the shift.
        let shift: Int
        switch points.count - 1 - last.interval[0] {
        case steps.count - 1: shift = 1
        case 0: shift = 0
        default: throw Failure.badResponse
        }
        let maneuvers = steps.enumerated().map { k, step in
            Maneuver(at: step.interval[0] + k * shift, text: instruction(step, first: k == 0), angle: k == 0 ? nil : signs[step.sign]?.angle,
                     street: step.street_name ?? "")
        }
        return Route(points: points, maneuvers: maneuvers)
    }

    private struct Body: Decodable {
        let code: String
        let messages: String?
        let paths: [Path]?
    }

    private struct Path: Decodable {
        let points: String
        let instructions: [Step]
    }

    private struct Step: Decodable {
        let sign: Int
        let interval: [Int]
        let text: String
        let street_name: String?
    }

    // Arrow from the sign, not from bearings: OSRM's bearings once said +4° for a left turn.
    private static let signs: [Int: (text: String, angle: Int?)] = [
        -98: ("Quay đầu", -180),
        -8: ("Quay đầu", -180),
        -7: ("Đi về bên trái", -30),
        -6: ("Ra khỏi vòng xuyến", nil),
        -3: ("Rẽ gắt trái", -135),
        -2: ("Rẽ trái", -90),
        -1: ("Chếch trái", -45),
        0: ("Đi thẳng", 0),
        1: ("Chếch phải", 45),
        2: ("Rẽ phải", 90),
        3: ("Rẽ gắt phải", 135),
        4: ("Đến nơi", nil),
        5: ("Đã qua điểm dừng", nil),
        6: ("Đi vào vòng xuyến", nil),
        7: ("Đi về bên phải", 30),
        8: ("Quay đầu", 180),
    ]

    // Our own wording: Vietmap's `text` is lower-case and mistranslated (sign 3 → "rẽ phải ngay lập tức").
    private static func instruction(_ step: Step, first: Bool) -> String {
        if step.sign == 4 && !first { return "Đến nơi" }
        var base = first ? "Xuất phát" : signs[step.sign]?.text ?? "Đi tiếp"
        // The exit number is only in the text ("… rẽ lối rẽ 2 vào …").
        if step.sign == 6, !first, let exit = step.text.firstMatch(of: #/lối rẽ (\d+)/#)?.1 {
            base = "Vòng xuyến, lối ra thứ \(exit)"
        }
        let street = step.street_name ?? ""
        return street.isEmpty ? base : "\(base) vào \(street)"
    }

    /// Google encoded polyline, precision 5.
    static func decodePolyline(_ s: String) -> [Point] {
        var bytes = Array(s.utf8)[...]
        var lat = 0, lon = 0
        var out: [Point] = []
        func next() -> Int? {
            var result = 0, shift = 0
            while let b = bytes.popFirst().map({ Int($0) - 63 }) {
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return result & 1 != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while let dLat = next(), let dLon = next() {
            lat += dLat
            lon += dLon
            out.append(Point(lat: Double(lat) / 1e5, lon: Double(lon) / 1e5))
        }
        return out
    }
}
