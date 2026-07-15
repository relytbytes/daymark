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
            content.body = "Your day is laid out — three moves, the timeline, and what's worth knowing."
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
            content.body = "Close the loops, set tomorrow's first move, and step away."
            content.sound = .default
            var components = DateComponents()
            components.hour = 20
            components.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            center.add(UNNotificationRequest(identifier: "daymark.evening", content: content, trigger: trigger))
        }
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
