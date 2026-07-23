//
//  CaptureControlIntent.swift
//  Shared: the Control Center button's intent. Opens the app and
//  leaves a flag in the App Group so the capture sheet comes up.
//

import AppIntents
import Foundation

struct OpenCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture to Daymark"
    static var description = IntentDescription("Opens Daymark straight into quick capture.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: WidgetSnapshot.groupID)?
            .set(true, forKey: "daymark-pending-capture")
        return .result()
    }
}
