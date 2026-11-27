import ActivityKit
import AppIntents

struct StopRideIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Dừng dẫn đường"

    @Parameter(title: "Chuyến đi")
    var rideID: String

    init() {}

    init(rideID: String) {
        self.rideID = rideID
    }

    @MainActor static var stopRide: ((String) -> Bool)?

    @MainActor
    func perform() async throws -> some IntentResult {
        if Self.stopRide?(rideID) != true {
            // The process may have been killed with the activity still on screen.
            for activity in Activity<RideAttributes>.activities where activity.attributes.rideID == rideID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        return .result()
    }
}
