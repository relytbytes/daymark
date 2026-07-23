//
//  BriefEngine.swift
//  Daymark
//
//  Composes the editorial layer from live data: the lead story, the
//  At-a-Glance ribbon per section, the day timeline, and the evening review.
//

import Foundation

struct LeadStory {
    let kicker: String
    let headline: String
    let deck: String
}

struct EveningReview {
    let essentialsDone: Int
    let essentialsTotal: Int
    let capturesCleared: Int
    let scoreLines: [(label: String, done: Int, target: Int)]
    let tomorrowFirst: CalendarEventLite?
    let tomorrowCount: Int
}

@MainActor
extension AppState {
    // MARK: Day progress (5:00 → 23:00, like the web app)

    var dayProgress: Double {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? now
        let end = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now
        guard end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    // MARK: Lead story

    func leadStory(for phase: DayPhase) -> LeadStory {
        let moves = essentialsRemaining
        let movesWord = ["zero", "One", "Two", "Three"][min(3, max(0, moves))]
        let meetings = eventsToday.filter { $0.isMeeting && $0.end > Date() }.count

        switch phase {
        case .morning, .afternoon:
            let headline: String
            if moves == 0 {
                headline = "All three priorities are done"
            } else if meetings == 0 {
                headline = "\(movesWord) \(moves == 1 ? "priority" : "priorities") open, no meetings on the calendar"
            } else {
                headline = "\(movesWord) \(moves == 1 ? "priority" : "priorities") open, \(meetings) meeting\(meetings == 1 ? "" : "s") ahead"
            }
            let deck: String
            if let next = nextMeeting {
                deck = "First up: \(next.title) at \(next.start.timeText())."
            } else if let next = eventsToday.first(where: { !$0.isAllDay && $0.start > Date() }) {
                deck = "Next on the calendar: \(next.title) at \(next.start.timeText())."
            } else {
                deck = "No meetings scheduled today."
            }
            return LeadStory(kicker: "Lead · Your day", headline: headline, deck: deck)

        case .evening:
            return LeadStory(
                kicker: "Lead · The close",
                headline: moves == 0
                    ? "Everything on today's list is done"
                    : "\(movesWord) item\(moves == 1 ? "" : "s") still open",
                deck: "The results, the open items, and tomorrow's first event."
            )

        case .night:
            return LeadStory(
                kicker: "Lead · After hours",
                headline: "The late edition",
                deck: "Tomorrow's schedule is set. Nothing here needs attention tonight."
            )
        }
    }

    // MARK: Next meeting & timeline

    var nextMeeting: CalendarEventLite? {
        let cutoff = Date().addingTimeInterval(-10 * 60)
        return eventsToday.first { $0.isMeeting && !$0.isAllDay && $0.start > cutoff }
    }

    /// Today's chronology: events plus suggested open blocks (45+ min gaps, 8:00–18:00).
    func timelineEntries() -> [TimelineEntry] {
        let now = Date()
        let calendar = Calendar.current
        let workStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        let workEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now

        let timed = eventsToday.filter { !$0.isAllDay }
        var entries: [TimelineEntry] = timed.map { .event($0) }

        // Find open blocks between events inside working hours.
        var cursor = max(workStart, now)
        var freeBlocks: [TimelineEntry] = []
        for event in timed where event.end > cursor {
            let gap = event.start.timeIntervalSince(cursor)
            if gap >= 45 * 60, cursor < workEnd, freeBlocks.count < 3 {
                freeBlocks.append(.freeBlock(start: cursor, minutes: Int(gap / 60)))
            }
            cursor = max(cursor, event.end)
        }
        if cursor < workEnd {
            let gap = workEnd.timeIntervalSince(cursor)
            if gap >= 45 * 60, freeBlocks.count < 3 {
                freeBlocks.append(.freeBlock(start: cursor, minutes: Int(gap / 60)))
            }
        }
        entries.append(contentsOf: freeBlocks)
        return entries.sorted { $0.start < $1.start }
    }

    // MARK: Evening review + week ahead

    func eveningReview() -> EveningReview {
        let morning = EssentialTask.morning
        let done = morning.filter { essentialDone($0.id) }.count
        let cleared = persisted.captures.filter { $0.done }.count
        let lines = ScoreCategory.defaults.map { category in
            (label: category.label, done: score(category.key), target: category.target)
        }
        return EveningReview(
            essentialsDone: done,
            essentialsTotal: morning.count,
            capturesCleared: cleared,
            scoreLines: lines,
            tomorrowFirst: eventsTomorrow.first { !$0.isAllDay },
            tomorrowCount: eventsTomorrow.count
        )
    }

    /// The next seven days, grouped, for the week-ahead ledger.
    func weekAhead() -> [(day: Date, events: [CalendarEventLite])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: eventsWeek) { $0.start.startOfDay }
        return grouped.keys.sorted().map { day in
            (day: day, events: (grouped[day] ?? []).sorted { $0.start < $1.start })
        }
        .filter { !calendar.isDateInToday($0.day) }
    }

    // MARK: At a Glance — per section

    func glanceToday() -> [GlanceCellModel] {
        [
            weatherCell(),
            // Indoor takes the second cell when Nest is reporting; the
            // clock lives in the status bar and the masthead already.
            nestReading.map { nest in
                GlanceCellModel(
                    id: "indoor", label: "Indoor",
                    value: "\(nest.indoorF)°",
                    sub: nest.hvacActive ? "running" : (nest.setpointF.map { "set \($0)°" } ?? "idle")
                )
            } ?? nowCell(),
            leaveBy.map { leave in
                GlanceCellModel(
                    id: "leaveby", label: "Leave by",
                    value: leave.time.clockText(),
                    sub: "\(leave.minutes) min drive", accent: true
                )
            } ?? GlanceCellModel(
                id: "daylight", label: "Daylight",
                value: weather?.daylightText ?? "—",
                sub: weather?.sunWindowText ?? "Durham"
            ),
            GlanceCellModel(
                id: "open", label: "Open",
                value: String(openLoops), sub: "loops", accent: true
            ),
        ]
    }

    func glanceWork() -> [GlanceCellModel] {
        [
            GlanceCellModel(id: "active", label: "Active", value: String(applicationsActive), sub: "apps"),
            GlanceCellModel(id: "interviews", label: "Interviews", value: String(applicationsInterviews),
                            sub: "scheduled", accent: true),
            GlanceCellModel(id: "waiting", label: "Waiting", value: String(waitingOpen.count), sub: "replies due"),
            GlanceCellModel(id: "sprint", label: "Sprint", value: "\(sprintPercent)%", sub: "complete"),
        ]
    }

    func glanceLife() -> [GlanceCellModel] {
        [
            weatherCell(),
            nowCell(),
            GlanceCellModel(
                id: "sunset", label: "Sunset",
                value: weather.map { $0.sunset.clockText() } ?? "—", sub: "Durham"
            ),
            GlanceCellModel(
                id: "rain", label: "Rain",
                value: weather.map { "\($0.rainPct)%" } ?? "—", sub: "chance today"
            ),
        ]
    }

    func glanceMore() -> [GlanceCellModel] {
        let spx = markets.first
        let playingValue: String
        let playingSub: String
        if let playback {
            playingValue = playback.isPlaying ? "On" : "Paused"
            playingSub = playback.track
        } else {
            playingValue = "—"
            playingSub = "Spotify"
        }
        return [
            GlanceCellModel(
                id: "market", label: spx?.label ?? "S&P 500",
                value: spx.map { String(format: "%+.1f%%", $0.changePct) } ?? "—",
                sub: "delayed", accent: (spx?.changePct ?? 0) < 0
            ),
            GlanceCellModel(id: "news", label: "Headlines", value: String(news.count), sub: "this brief"),
            GlanceCellModel(id: "saved", label: "Saved", value: String(readingOpenCount), sub: "to read"),
            GlanceCellModel(id: "playing", label: "Playing", value: playingValue, sub: playingSub),
        ]
    }

    private func weatherCell() -> GlanceCellModel {
        GlanceCellModel(
            id: "weather", label: "Weather",
            value: weather.map { "\($0.tempF)°" } ?? "—",
            sub: weather?.description ?? "Durham",
            symbol: weather?.symbol ?? "sun.max.fill"
        )
    }

    private func nowCell() -> GlanceCellModel {
        let now = Date()
        return GlanceCellModel(id: "now", label: "Now", value: now.clockText(), sub: now.shortDate())
    }
}
