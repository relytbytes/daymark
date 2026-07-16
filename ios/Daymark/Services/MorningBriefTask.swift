//
//  MorningBriefTask.swift
//  Daymark
//
//  The rich morning brief: a background refresh around 7:15 composes
//  the AI daily plan and puts it in the 7:30 notification body. If iOS
//  declines to run the task (it often does), the static 7:30 edition
//  from NotificationService still fires — the brief degrades, never
//  disappears.
//

import Foundation
import BackgroundTasks
import UserNotifications

enum MorningBriefTask {
    static let identifier = "com.relytbytes.daymark.morningbrief"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Ask for the next run shortly before the 7:30 edition.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 7
        components.minute = 15
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
            let body = await composeBriefBody()
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

    /// Compose from what's on disk plus a quick weather read — no full app boot.
    private static func composeBriefBody() async -> String? {
        guard AIService.isConfigured else { return nil }
        let persisted = JSONStore.load() ?? PersistedState()

        let captures = persisted.captures.filter { !$0.done }.map(\.title).joined(separator: "\n")
        let applications = persisted.applications.filter { $0.status != .closed }
            .map { "\($0.status.rawValue): \($0.organization) — \($0.role)" }
            .joined(separator: "\n")
        let weather = (try? await WeatherService.fetch())
            .map { "\($0.tempF)°, \($0.description), rain \($0.rainPct)%" } ?? "unknown"

        let briefing = """
        Weather: \(weather)
        Open captures:
        \(captures.nilIfEmpty ?? "(none)")
        Job pipeline:
        \(applications.nilIfEmpty ?? "(none)")
        """
        guard let plan = try? await AIDesk.dailyPlan(briefing: briefing) else { return nil }
        return plan
    }

    /// Replace this morning's static edition with the composed one, then
    /// restore the repeating fallback for the days the task doesn't run.
    private static func scheduleRichEdition(body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daymark.morning"])

        let content = UNMutableNotificationContent()
        content.title = "Morning Brief"
        content.body = body
        content.sound = .default
        var components = DateComponents()
        components.hour = 7
        components.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: "daymark.morning.rich", content: content, trigger: trigger))

        // Fallback returns for subsequent mornings.
        let fallback = UNMutableNotificationContent()
        fallback.title = "Morning Brief"
        fallback.body = "Today's priorities, the timeline, and what came in overnight."
        fallback.sound = .default
        let repeating = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "daymark.morning", content: fallback, trigger: repeating))
    }
}
