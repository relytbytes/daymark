//
//  DaymarkApp.swift
//  Daymark
//
//  A personal executive brief with a newspaper's manners.
//

import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onRoute: ((String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        onRoute?(response.notification.request.identifier)
        completionHandler()
    }
}

@main
struct DaymarkApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        MorningBriefTask.register()
        EveningReviewTask.register()
    }

    var body: some Scene {
        WindowGroup {
            // The scheme follows the sun: day paper until sunset, the
            // night edition until sunrise (or pinned in Settings).
            TimelineView(.everyMinute) { context in
                RootView()
                    .environment(app)
                    .preferredColorScheme(app.preferredScheme(at: context.date))
                    .tint(Palette.ink)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Route notification taps once per launch.
            if notificationDelegate.onRoute == nil {
                notificationDelegate.onRoute = { [weak app] identifier in
                    guard let app else { return }
                    Task { @MainActor in
                        switch true {
                        case identifier.hasPrefix("daymark.autopilot"):
                            app.navigate(tab: "today", anchor: "today-prep")
                        case identifier.hasPrefix("daymark.evening"):
                            app.navigate(tab: "today", anchor: "today-close")
                        case identifier.hasPrefix("daymark.game"), identifier.hasPrefix("daymark.final"):
                            app.navigate(tab: "life", anchor: "life-scoreboard")
                        case identifier == "daymark.leaveby":
                            app.navigate(tab: "today", anchor: "today-day")
                        default:
                            app.navigate(tab: "today")
                        }
                    }
                }
            }
            if phase == .active {
                app.rolloverIfNeeded()
                app.absorbWidgetActions()
                app.absorbSharedCaptures()
                MorningBriefTask.scheduleNext()
                EveningReviewTask.scheduleNext()
                if UserDefaults.standard.bool(forKey: "daymark-pending-focus") {
                    UserDefaults.standard.set(false, forKey: "daymark-pending-focus")
                    // Reload in case an intent captured while we were closed.
                    if let fresh = JSONStore.load() { app.persisted = fresh }
                    if !app.focusRunning { app.startFocus() }
                }
                Task { await app.refreshAll(force: false) }
                app.startPlaybackTicker()
            } else {
                app.stopPlaybackTicker()
            }
        }
    }
}
