import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RideWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { context in
            HStack(spacing: 12) {
                arrow(context.state.angle)
                    .font(.title2.weight(.semibold))
                details(context.state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                stop(context.attributes.rideID)
            }
            .padding(16)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    arrow(context.state.angle)
                        .font(.title2.weight(.semibold))
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    stop(context.attributes.rideID, iconOnly: true)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    details(context.state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                arrow(context.state.angle)
            } compactTrailing: {
                Text(context.state.distance ?? "GPS")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            } minimal: {
                arrow(context.state.angle)
            }
        }
    }

    private func arrow(_ angle: Int?) -> some View {
        Image(systemName: angle == nil ? "location.fill" : "arrow.up")
            .rotationEffect(.degrees(Double(angle ?? 0)))
            .accessibilityHidden(true)
    }

    private func details(_ state: RideAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let distance = state.distance, !distance.isEmpty {
                Text(distance)
                    .font(.headline)
                    .monospacedDigit()
            }
            Text(state.instruction)
                .font(.subheadline)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func stop(_ rideID: String, iconOnly: Bool = false) -> some View {
        Button(intent: StopRideIntent(rideID: rideID)) {
            Group {
                if iconOnly {
                    Image(systemName: "stop.fill")
                } else {
                    Text("Dừng")
                }
            }
            .frame(minWidth: 36, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel("Dừng dẫn đường")
    }
}
