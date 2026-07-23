//
//  EveningReviewTask.swift
//  Daymark
//
//  The evening bookend to the morning brief: a background refresh
//  around 20:45 composes the day's ledger into the 21:00 notification.
//  If iOS declines to run the task, the static edition still fires.
//

import Foundation
import BackgroundTasks
import UserNotifications

enum EveningReviewTask {
    static let identifier = "com.relytbytes.daymark.eveningreview"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Ask for the next run shortly before the 21:00 edition.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 20
        components.minute = 45
        var fireDate = Calendar.current.date(from: components) ?? Date()
        if fireDate <= Date() {
            fireDate = Calendar.current.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
        }
        request.earliestBeginDate = fireDate
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNext() // always re-arm for tomorrow

        let work = Task {
            let body = await composeReviewBody()
            if let body {
                scheduleRichEdition(body: body)
            }
            task.setTaskCompleted(success: body != nil)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Compose from what's on disk — no full app boot.
    private static func composeReviewBody() async -> String? {
        guard AIService.isConfigured else { return nil }
        let persisted = JSONStore.load() ?? PersistedState()

        let done = EssentialTask.evening.filter { persisted.tasks[$0.id] ?? false }.count
        let openCaptures = persisted.captures.filter { !$0.done }.map(\.title)
        let notes = persisted.taskNotes.values.joined(separator: " · ")

        let ledger = """
        Essentials completed today: \(done) of 3
        Task notes from the day: \(notes.nilIfEmpty ?? "(none)")
        Still open: \(openCaptures.isEmpty ? "(nothing)" : openCaptures.joined(separator: "; "))
        Tomorrow's first move (if set): \(persisted.tomorrowFirstMove.nilIfEmpty ?? "(not set)")
        """
        return try? await AIDesk.eveningNarrative(dayData: ledger)
    }

    private static func scheduleRichEdition(body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daymark.evening.rich"])

        let content = UNMutableNotificationContent()
        content.title = "Evening Review"
        content.body = body
        content.sound = .default
        var components = DateComponents()
        components.hour = 21
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: "daymark.evening.rich", content: content, trigger: trigger))
    }
}
