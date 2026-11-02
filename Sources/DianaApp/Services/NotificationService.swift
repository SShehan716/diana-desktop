import DianaCore
import Foundation
import UserNotifications

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?
    private var reconciliation: Task<Void, Never>?
    init(model: AppModel) { self.model = model }
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: "DIANA_REMINDER",
            actions: [
                UNNotificationAction(identifier: "DONE", title: "Done"),
                UNNotificationAction(identifier: "SNOOZE", title: "Snooze 10 min"),
                UNNotificationAction(identifier: "DISMISS", title: "Dismiss"),
            ], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }
    func reconcile(data: AppData) {
        guard let model, model.storageFailure == nil else { return }
        let previous = reconciliation
        reconciliation?.cancel()
        reconciliation = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(
                withIdentifiers: pending.filter { $0.identifier.hasPrefix("reminder.") }.map(\.identifier))
            let settings = await center.notificationSettings()
            guard !Task.isCancelled, data.preferences.notificationsEnabled,
                settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            else { return }
            var problem: String?
            for (occurrence, fireAt) in ScheduleEngine.upcoming(in: data, after: .now) {
                guard !Task.isCancelled else { return }
                guard let reminder = data.reminders.first(where: { $0.id == occurrence.reminderID }) else {
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.notes.isEmpty ? "A gentle nudge from Diana." : reminder.notes
                content.categoryIdentifier = "DIANA_REMINDER"
                content.threadIdentifier = reminder.id.uuidString
                content.userInfo = [
                    "reminderID": reminder.id.uuidString, "dueAt": occurrence.dueAt.timeIntervalSince1970,
                ]
                if data.preferences.sounds { content.sound = .default }
                let interval = max(1, fireAt.timeIntervalSinceNow)
                let request = UNNotificationRequest(
                    identifier: "reminder.\(occurrence.id)", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
                do { try await center.add(request) } catch { problem = error.localizedDescription }
            }
            if !Task.isCancelled { self?.model?.notificationProblem = problem }
        }
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler([.banner]) }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let rawID = info["reminderID"] as? String
        let rawDate = info["dueAt"] as? Double
        Task { @MainActor [weak self] in
            guard let rawID, let id = UUID(uuidString: rawID), let rawDate, let model = self?.model else {
                return
            }
            let occurrence = Occurrence(reminderID: id, dueAt: Date(timeIntervalSince1970: rawDate))
            switch action {
            case "DONE":
                if model.data.records[occurrence.id]?.completedAt == nil { model.complete(occurrence) }
            case "SNOOZE": model.snooze(occurrence)
            case "DISMISS": model.dismiss(occurrence)
            default:
                model.onRevealWindow?()
                model.presentReminder(occurrence)
            }
        }
        completionHandler()
    }
}
