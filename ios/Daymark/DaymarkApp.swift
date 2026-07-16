//
//  DaymarkApp.swift
//  Daymark
//
//  A personal executive brief with a newspaper's manners.
//

import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.light) // the paper is the brand
                .tint(Palette.ink)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.rolloverIfNeeded()
                MorningBriefTask.scheduleNext()
                if UserDefaults.standard.bool(forKey: "daymark-pending-focus") {
                    UserDefaults.standard.set(false, forKey: "daymark-pending-focus")
                    // Reload in case an intent captured while we were closed.
                    if let fresh = JSONStore.load() { app.persisted = fresh }
                    if !app.focusRunning { app.startFocus() }
                }
                Task { await app.refreshAll(force: false) }
            }
        }
    }
}
