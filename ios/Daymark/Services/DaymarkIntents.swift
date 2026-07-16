//
//  DaymarkIntents.swift
//  Daymark
//
//  App Intents: capture from anywhere (Action button, Siri, Shortcuts,
//  Spotlight), start a focus block, and hear the day's numbers. Capture
//  writes straight to the store so it works without opening the app.
//

import AppIntents
import Foundation

// MARK: - Capture

struct CaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture"
    static let description = IntentDescription("Add a task, job lead, reminder, or read-later link to Daymark.")
    static let openAppWhenRun = false

    @Parameter(title: "What to capture", requestValueDialog: "What should Daymark hold onto?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing to capture.")
        }

        // Light classification; the inbox is triaged in-app anyway.
        let lower = trimmed.lowercased()
        let kind: CaptureKind
        if lower.contains("read") || lower.contains("article") || lower.contains("http") {
            kind = .reading
        } else if lower.contains("remind") {
            kind = .reminder
        } else if lower.contains("job") || lower.contains("apply") || lower.contains("role") || lower.contains("interview") {
            kind = .job
        } else {
            kind = .task
        }

        var state = await MainActor.run { JSONStore.load() ?? PersistedState() }
        state.captures.append(CaptureItem(kind: kind, title: trimmed))
        let snapshot = state
        await MainActor.run { JSONStore.save(snapshot) }

        return .result(dialog: "Captured as a \(kind.label.lowercased()).")
    }
}

// MARK: - Start focus

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Block"
    static let description = IntentDescription("Open Daymark and start the focus timer.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        // The app starts the block (and its Live Activity) on activation.
        UserDefaults.standard.set(true, forKey: "daymark-pending-focus")
        return .result()
    }
}

// MARK: - The day's numbers

struct DayBriefIntent: AppIntent {
    static let title: LocalizedStringResource = "Daymark Brief"
    static let description = IntentDescription("Hear the day's open items at a glance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { JSONStore.load() ?? PersistedState() }
        let captures = state.captures.filter { !$0.done }.count
        let waiting = state.waiting.filter { !$0.done }.count
        let tasksDone = state.tasks.values.filter { $0 }.count

        var parts: [String] = []
        parts.append("\(tasksDone) of 3 priorities done")
        if captures > 0 { parts.append("\(captures) capture\(captures == 1 ? "" : "s") open") }
        if waiting > 0 { parts.append("\(waiting) repl\(waiting == 1 ? "y" : "ies") awaited") }
        if let snapshot = WidgetSnapshot.read(), let title = snapshot.nextEventTitle, let time = snapshot.nextEventTime, time > Date() {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            parts.append("next: \(title) at \(formatter.string(from: time))")
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: ", ") + "."))
    }
}

// MARK: - Shortcuts / Siri phrases

struct DaymarkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["Capture in \(.applicationName)", "Add to \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "tray.and.arrow.down.fill"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Start focus in \(.applicationName)", "\(.applicationName) focus"],
            shortTitle: "Focus",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: DayBriefIntent(),
            phrases: ["What's my day in \(.applicationName)", "\(.applicationName) brief"],
            shortTitle: "Brief",
            systemImageName: "newspaper"
        )
    }
}
