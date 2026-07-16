//
//  NotificationService.swift
//  Daymark
//
//  Local notifications: morning brief, evening review, focus completion,
//  and follow-up reminders. Nothing leaves the device.
//

import Foundation
import UserNotifications

enum NotificationService {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    // MARK: Daily editions

    static func scheduleDailyEditions(morning: Bool, evening: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daymark.morning", "daymark.evening"])

        if morning {
            let content = UNMutableNotificationContent()
            content.title = "Morning Brief"
            content.body = "Today's priorities, the timeline, and what came in overnight."
            content.sound = .default
            var components = DateComponents()
            components.hour = 7
            components.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: "daymark.morning", content: content, trigger: trigger))
        }

        if evening {
            let content = UNMutableNotificationContent()
            content.title = "Evening Review"
            content.body = "The day's results and tomorrow's setup are ready."
            content.sound = .default
            var components = DateComponents()
            components.hour = 20
            components.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: "daymark.evening", content: content, trigger: trigger))
        }
    }

    // MARK: Leave-by

    /// One-shot nudge 10 minutes before the computed leave-by time.
    static func scheduleLeaveBy(at leaveBy: Date, eventTitle: String, driveMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daymark.leaveby"])
        let fireAt = leaveBy.addingTimeInterval(-10 * 60)
        guard fireAt > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Leave by \(leaveBy.timeText())"
        content.body = "\(eventTitle) — about \(driveMinutes) min drive from home."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireAt.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: "daymark.leaveby", content: content, trigger: trigger))
    }

    // MARK: Game alerts

    /// First-pitch notifications for today's D-backs and Bulls games.
    static func scheduleGameAlerts(games: [(id: String, title: String, start: Date)]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: games.map { "daymark.game.\($0.id)" })
        for game in games where game.start > Date() {
            let content = UNMutableNotificationContent()
            content.title = "First pitch"
            content.body = game.title
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: game.start.timeIntervalSinceNow, repeats: false)
            center.add(UNNotificationRequest(identifier: "daymark.game.\(game.id)", content: content, trigger: trigger))
        }
    }

    /// Fired the moment the app observes a final score while refreshing.
    static func notifyFinal(id: String, headline: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Final"
        content.body = headline
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "daymark.final.\(id)", content: content, trigger: nil))
    }

    // MARK: Focus timer

    static func scheduleFocusEnd(after seconds: TimeInterval, taskTitle: String) {
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Focus block complete"
        content.body = taskTitle
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "daymark.focus", content: content, trigger: trigger)
        )
    }

    static func cancelFocus() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["daymark.focus"])
    }

    // MARK: Follow-ups

    static func scheduleFollowUp(_ item: WaitingItem) {
        guard let due = item.due else { return }
        let content = UNMutableNotificationContent()
        content.title = "Follow up: \(item.who)"
        content.body = item.what
        content.sound = .default
        var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "daymark.wait.\(item.id.uuidString)", content: content, trigger: trigger)
        )
    }

    static func cancelFollowUp(_ item: WaitingItem) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["daymark.wait.\(item.id.uuidString)"])
    }
}
