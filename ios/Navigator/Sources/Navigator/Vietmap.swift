import Foundation

/// Vietmap Route v4, motorcycle profile. Sign table and the `interval` quirk: docs/vietmap/README.md.
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
    }

    public static func route(from: Point, to: Point, apiKey: String) async throws -> Route {
        var url = URLComponents(string: "https://maps.vietmap.vn/api/route/v4")!
        url.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "point", value: "\(from.lat),\(from.lon)"),
            URLQueryItem(name: "point", value: "\(to.lat),\(to.lon)"),
            URLQueryItem(name: "vehicle", value: "motorcycle"),
        ]
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: url.url!)
        } catch let error as URLError where error.code != .cancelled {
            throw Failure.offline
        }
        return try parse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public static func parse(_ data: Data, status: Int) throws -> Route {
        switch status {
        case 200: break
        case 401, 403: throw Failure.badKey
        case 429: throw Failure.quota
        default: throw Failure.http(status)
        }
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
            Maneuver(at: step.interval[0] + k * shift, text: instruction(step, first: k == 0), angle: k == 0 ? nil : signs[step.sign]?.angle)
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
