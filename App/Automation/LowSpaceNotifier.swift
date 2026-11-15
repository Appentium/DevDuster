import Foundation
import SweepCore
import UserNotifications

@MainActor
final class LowSpaceNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ volume: Volume) async {
        let content = UNMutableNotificationContent()
        content.title = "Low disk space on \(volume.name)"
        content.body = "\(ByteFormatter.string(volume.availableBytes)) free of \(ByteFormatter.string(volume.totalBytes)). Open Sweep to clean up."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "lowSpace.\(volume.url.path(percentEncoded: false))", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
