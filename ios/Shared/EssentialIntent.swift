//
//  EssentialIntent.swift
//  Shared between the app and the widget extension: tapping a circle
//  on the home screen checks the task off right there — the widget
//  updates its own snapshot instantly and queues the change for the
//  app to absorb on its next open.
//

import AppIntents
import Foundation
import WidgetKit

struct ToggleEssentialIntent: AppIntent {
    static var title: LocalizedStringResource = "Check off an essential"
    static var description = IntentDescription("Marks one of the Essential Three done from the widget.")

    @Parameter(title: "Task")
    var taskID: String

    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult {
        guard var snapshot = WidgetSnapshot.read(),
              var essentials = snapshot.essentials,
              let index = essentials.firstIndex(where: { $0.id == taskID })
        else { return .result() }
        essentials[index].done.toggle()
        snapshot.essentials = essentials
        snapshot.updatedAt = Date()
        WidgetSnapshot.write(snapshot)
        WidgetActions.record(taskID, done: essentials[index].done)
        WidgetCenter.shared.reloadTimelines(ofKind: "DaymarkEssentials")
        return .result()
    }
}
