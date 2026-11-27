import Foundation
import Observation
import UIKit

/// The diagnostic log behind the Nhật ký tab: band, navigation, GPS and Vietmap in one timeline, kept in memory only.
// shortcut: lost when iOS kills the app, write it to a file if rides keep getting cut off.
@Observable
final class Log {
    enum Source: String, CaseIterable, Identifiable {
        case band = "Vòng", nav = "Dẫn đường", gps = "GPS", vietmap = "Vietmap"
        var id: Self { self }
    }

    struct Line: Identifiable {
        let id: Int
        let time: Date
        let source: Source
        let text: String
        /// Every error message in the app starts with "Lỗi".
        var error: Bool { text.hasPrefix("Lỗi") }
        var formatted: String { "\(Log.clock.string(from: time)) [\(source.rawValue)] \(text)" }
    }

    static let limit = 5000
    private static let clock = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private(set) var lines: [Line] = []
    /// Errors since the Nhật ký tab was last looked at.
    private(set) var unseenErrors = 0
    @ObservationIgnored private var next = 0

    func add(_ source: Source, _ text: String) {
        let line = Line(id: next, time: Date(), source: source, text: text)
        next += 1
        lines.append(line)
        if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
        if line.error { unseenErrors += 1 }
    }

    func seen() {
        unseenErrors = 0
    }

    func clear() {
        (lines, unseenErrors) = ([], 0)
    }

    /// Everything, whatever the filter, under a header saying which app and phone it came from.
    func report() -> String {
        let info = Bundle.main.infoDictionary
        var machine = utsname()
        uname(&machine)
        let model = withUnsafeBytes(of: machine.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let header = [
            "Dẫn đường \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "iOS \(UIDevice.current.systemVersion), \(model)",
            "Sao chép lúc \(Date().formatted(date: .numeric, time: .standard))",
        ]
        return (header + [""] + lines.map(\.formatted)).joined(separator: "\n")
    }
}
