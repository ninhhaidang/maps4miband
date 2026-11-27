import ActivityKit

struct RideAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let instruction: String
        let distance: String?
        let angle: Int?
    }

    let rideID: String
}
