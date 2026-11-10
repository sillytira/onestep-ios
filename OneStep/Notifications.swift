import Foundation
import UserNotifications

struct NotificationReference: Sendable {
    var kind: String
    var id: String
    var day: String?
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    @MainActor var onOpen: ((NotificationReference) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let kind = info["kind"] as? String, let id = info["id"] as? String else { return }
        let reference = NotificationReference(kind: kind, id: id, day: info["day"] as? String)
        await MainActor.run { onOpen?(reference) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@MainActor
final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func apply(_ plan: ReminderPlan) async throws {
        let pending = await center.pendingNotificationRequests()
        let wanted = Set(plan.reminders.map(\.id))
        let obsolete = pending.filter { $0.identifier.hasPrefix("task.") || $0.identifier.hasPrefix("routine.") }
            .filter { !wanted.contains($0.identifier) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let delivered = await center.deliveredNotifications()
        // Remove old banners when their action has been completed, skipped, or snoozed.
        // A delivered due notification is also cleared during the next reconciliation.
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier })
        for reminder in plan.reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = reminder.item.id
            var info: [String: String] = ["kind": reminder.item.kind.rawValue, "id": reminder.item.sourceID.uuidString]
            if let day = reminder.item.day { info["day"] = day }
            content.userInfo = info
            // Calendar components include an explicit timezone; foreground reconciliation
            // rebuilds daily routines if the phone's local timezone changes.
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: reminder.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try await center.add(request)
        }
    }
}
