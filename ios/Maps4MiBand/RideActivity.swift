import ActivityKit
import Foundation
import Navigator

@MainActor
final class RideActivity {
    private var activity: Activity<RideAttributes>?
    private var state: RideAttributes.ContentState?
    private var updating: Task<Void, Never>?

    func start(_ message: BandMessage, onStop: @escaping () -> Void) throws -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let id = UUID().uuidString
        let state = Self.content(message)
        let older = Activity<RideAttributes>.activities
        activity = try Activity.request(attributes: RideAttributes(rideID: id),
                                        content: ActivityContent(state: state, staleDate: nil),
                                        pushType: nil)
        self.state = state
        StopRideIntent.stopRide = { requested in
            guard requested == id else { return false }
            onStop()
            return true
        }
        Task {
            for activity in older {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        return true
    }

    func update(_ message: BandMessage) {
        guard let activity else { return }
        let next = Self.content(message)
        guard state != next else { return }
        state = next
        guard updating == nil else { return }
        updating = Task {
            var sent: RideAttributes.ContentState?
            while !Task.isCancelled, let state, sent != state {
                await activity.update(ActivityContent(state: state, staleDate: nil))
                sent = state
            }
            if !Task.isCancelled { updating = nil }
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        state = nil
        StopRideIntent.stopRide = nil
        let pending = updating
        pending?.cancel()
        updating = nil
        Task {
            await pending?.value
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func content(_ message: BandMessage) -> RideAttributes.ContentState {
        RideAttributes.ContentState(instruction: message.i, distance: message.d, angle: message.a)
    }
}
