import UserNotifications

/// System banners (Notification Center) for hosts that go up or down.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert])
    }

    /// True if the user has switched notifications for the app off in System Settings.
    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    /// Shows a banner. A newer banner with the same `key` replaces the older one.
    func post(key: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // The app plays its own sounds, so the banner stays silent.
        center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }

    // Without this, banners are not shown while PingWatch is the frontmost app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
