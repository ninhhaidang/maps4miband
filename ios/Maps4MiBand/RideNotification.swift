import UserNotifications

/// A delivered notification keeps Dừng accessible on the Lock Screen during a ride.
final class RideNotification: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "navigation"
    private static let stop = "navigation.stop"
    @MainActor private var rideID: String?
    @MainActor private var stopRide: (() -> Void)?

    @MainActor
    func show(onStop: @escaping () -> Void, onError: @escaping (String) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let stop = UNNotificationAction(identifier: Self.stop, title: "Dừng dẫn đường", options: .destructive)
        center.setNotificationCategories([UNNotificationCategory(
            identifier: Self.category, actions: [stop], intentIdentifiers: [])])
        let id = UUID().uuidString
        rideID = id
        stopRide = onStop
        let settingsHint = "Bật thông báo trên màn hình khoá trong Cài đặt → Dẫn đường để dùng nút Dừng."
        Task {
            do {
                let allowed = try await center.requestAuthorization(options: [.alert])
                guard rideID == id else { return }
                guard allowed else {
                    return onError(settingsHint)
                }
                let settings = await center.notificationSettings()
                guard rideID == id else { return }
                if settings.lockScreenSetting == .disabled {
                    onError(settingsHint)
                }
                let content = UNMutableNotificationContent()
                content.title = "Đang dẫn đường"
                content.body = "Nhấn giữ thông báo để dừng dẫn đường."
                content.categoryIdentifier = Self.category
                content.interruptionLevel = .passive
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                if rideID != id { center.removeDeliveredNotifications(withIdentifiers: [id]) }
            } catch {
                if rideID == id { onError("Không hiện được nút Dừng trên màn hình khoá: \(error.localizedDescription)") }
            }
        }
    }

    @MainActor
    func hide() {
        guard let id = rideID else { return }
        rideID = nil
        stopRide = nil
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        guard response.actionIdentifier == Self.stop else { return }
        await MainActor.run {
            if rideID == id { stopRide?() }
        }
    }
}
