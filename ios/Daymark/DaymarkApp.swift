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
                Task { await app.refreshAll(force: false) }
            }
        }
    }
}
