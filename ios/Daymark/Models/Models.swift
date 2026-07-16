//
//  Models.swift
//  Daymark
//
//  Domain models: persisted user data and live feed snapshots.
//

import SwiftUI

// MARK: - Feed freshness

enum FeedStatus: Equatable {
    case idle
    case checking
    case live(Date)
    case cached(Date)
    case unavailable

    var label: String {
        switch self {
        case .idle: return "Waiting"
        case .checking: return "Checking"
        case .live(let at): return "Updated \(relativeAge(at))"
        case .cached(let at): return "Cached · \(relativeAge(at))"
        case .unavailable: return "Unavailable"
        }
    }

    var isStale: Bool {
        switch self {
        case .cached, .unavailable: return true
        default: return false
        }
    }
}

// MARK: - Persisted user data

enum CaptureKind: String, Codable, CaseIterable, Identifiable {
    case task, job, reading, reminder
    var id: String { rawValue }
    var label: String {
        switch self {
        case .task: return "Task"
        case .job: return "Job lead"
        case .reading: return "Read later"
        case .reminder: return "Reminder"
        }
    }
}

struct CaptureItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: CaptureKind
    var title: String
    var url: String?
    var note: String?
    var createdAt = Date()
    var done = false
}

enum ApplicationStatus: String, Codable, CaseIterable, Identifiable {
    case interested = "Interested"
    case applied = "Applied"
    case followUp = "Follow-up"
    case interview = "Interview"
    case offer = "Offer"
    case closed = "Closed"

    var id: String { rawValue }

    var chipColors: (fg: Color, bg: Color) {
        switch self {
        case .interview, .offer: return (Color(hex: 0x0E7A54), Palette.greenSoft)
        case .followUp: return (Palette.coral, Palette.coralSoft)
        case .applied: return (Palette.blue, Palette.blueSoft)
        default: return (Palette.muted, Palette.paperDeep)
        }
    }
}

/// A pipeline row read live from the Landed sheet (job-search-command-center).
struct LandedRole: Identifiable, Hashable {
    let id: String
    let company: String
    let role: String
    let location: String
    let salary: String
    let track: String
    let status: String
    let priority: String
    let nextAction: String
    let notes: String

    /// Rough stage ordering for the focus queue: closer to offer sorts first.
    var stageRank: Int {
        switch status.lowercased() {
        case let s where s.contains("offer"): return 0
        case let s where s.contains("interview"): return 1
        case let s where s.contains("screen"): return 2
        case let s where s.contains("progress"): return 3
        case let s where s.contains("applied"): return 4
        default: return 5
        }
    }

    var isHot: Bool { stageRank <= 2 || priority.lowercased() == "high" }
}

struct JobApplication: Identifiable, Codable, Hashable {
    var id = UUID()
    var organization: String
    var role: String
    var url: String?
    var status: ApplicationStatus = .applied
    var nextStep: String = "Choose next step"
    var updatedAt = Date()
}

struct ReadingItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String?
    var savedAt = Date()
    var done = false
}

struct WaitingItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var who: String
    var what: String
    var since = Date()
    var due: Date?
    var done = false
    var source: String = "manual" // manual | mail | application
}

struct FeedSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
}

struct WatchSymbol: Identifiable, Codable, Hashable {
    var symbol: String   // stooq symbol, e.g. "^spx" or "aapl.us"
    var label: String
    var id: String { symbol }
}

struct ScoreCategory: Identifiable, Codable, Hashable {
    var key: String
    var label: String
    var target: Int
    var colorKey: String
    var id: String { key }

    var color: Color {
        switch colorKey {
        case "blue": return Palette.blue
        case "violet": return Palette.violet
        case "green": return Palette.green
        case "gold": return Palette.gold
        default: return Palette.coral
        }
    }

    static let defaults: [ScoreCategory] = [
        ScoreCategory(key: "jobs", label: "Job search", target: 5, colorKey: "coral"),
        ScoreCategory(key: "veraya", label: "Veraya", target: 4, colorKey: "blue"),
        ScoreCategory(key: "writing", label: "Writing", target: 3, colorKey: "violet"),
        ScoreCategory(key: "fitness", label: "Fitness", target: 4, colorKey: "green"),
        ScoreCategory(key: "household", label: "Household", target: 5, colorKey: "gold"),
    ]
}

/// A fixed daily anchor task (the Essential Three), defined per phase.
struct EssentialTask: Identifiable, Hashable {
    let id: String
    let kicker: String
    let title: String
    let detail: String

    static let morning: [EssentialTask] = [
        EssentialTask(id: "m-jobs", kicker: "Job search", title: "Move one application forward",
                      detail: "Follow up, apply, or add the next concrete opportunity."),
        EssentialTask(id: "m-veraya", kicker: "Veraya", title: "Advance the current milestone",
                      detail: "Choose the smallest piece of evidence that changes the work."),
        EssentialTask(id: "m-practical", kicker: "Practical", title: "Clear one captured loose end",
                      detail: "Pick the inbox item that keeps resurfacing."),
    ]

    static let evening: [EssentialTask] = [
        EssentialTask(id: "e-pipeline", kicker: "Job search", title: "Update the job pipeline",
                      detail: "Record what moved and the next follow-up date."),
        EssentialTask(id: "e-veraya", kicker: "Veraya", title: "Capture today's decision",
                      detail: "Write what changed, why, and the next test."),
        EssentialTask(id: "e-tomorrow", kicker: "Tomorrow", title: "Choose the first move",
                      detail: "Put one specific task on the 9:00 AM line."),
    ]

    static func forPhase(_ phase: DayPhase) -> [EssentialTask] {
        phase.isEndOfDay ? evening : morning
    }
}

struct SprintMilestone: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    static let defaults: [SprintMilestone] = [
        SprintMilestone(id: "s1", title: "Define this week's outcome", detail: "Write one observable result"),
        SprintMilestone(id: "s2", title: "Review the strongest evidence", detail: "Customer, market, or product signal"),
        SprintMilestone(id: "s3", title: "Choose the next test", detail: "Small, specific, and falsifiable"),
        SprintMilestone(id: "s4", title: "Publish or schedule the next move", detail: "Give the sprint a finish line"),
    ]
}

struct DecisionDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let options: [String]

    static let defaults: [DecisionDefinition] = [
        DecisionDefinition(id: "offer", title: "Which Veraya offer leads?",
                           detail: "The focused research sprint or ongoing advisory.",
                           options: ["Sprint", "Advisory", "Defer"]),
        DecisionDefinition(id: "duke", title: "Set up the Duke alert?",
                           detail: "Use the official careers site to create the search alert.",
                           options: ["Open", "Later", "Defer"]),
        DecisionDefinition(id: "housing", title: "Open the Durham home search?",
                           detail: "Browse homes for sale around the $450,000 ceiling.",
                           options: ["Open", "Later", "Defer"]),
    ]
}

struct AppSettings: Codable, Hashable {
    var vipSenders: [String] = []
    var feeds: [FeedSource] = AppSettings.defaultFeeds
    var watchlist: [WatchSymbol] = AppSettings.defaultWatchlist
    var morningBrief = true
    var eveningReview = true
    var travelETA = false
    var gameAlerts = true

    static let defaultFeeds: [FeedSource] = [
        FeedSource(name: "NYT", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"),
        FeedSource(name: "NPR", url: "https://feeds.npr.org/1001/rss.xml"),
        FeedSource(name: "Jacobin", url: "https://jacobin.com/feed/"),
        FeedSource(name: "Longreads", url: "https://longreads.com/feed/"),
    ]

    static let defaultWatchlist: [WatchSymbol] = [
        WatchSymbol(symbol: "^spx", label: "S&P 500"),
        WatchSymbol(symbol: "^dji", label: "Dow"),
        WatchSymbol(symbol: "^ndq", label: "Nasdaq"),
    ]
}

/// Everything Daymark persists locally, in one Codable document.
struct PersistedState: Codable {
    var name: String = AppConfig.ownerName
    var dayKey: String = Date().dayKey
    var weekKey: String = Date().weekKey
    var tasks: [String: Bool] = [:]           // EssentialTask.id -> done
    var sprint: [String: Bool] = [:]           // SprintMilestone.id -> done
    var captures: [CaptureItem] = []
    var applications: [JobApplication] = []
    var decisions: [String: String] = [:]      // DecisionDefinition.id -> choice
    var readingQueue: [ReadingItem] = []
    var waiting: [WaitingItem] = []
    var weeklyScores: [String: Int] = [:]
    var focusTaskID: String?
    var focusEndsAt: Date?
    var focusMinutes: Int = 25
    var clearedMailIDs: [String] = []
    var tomorrowFirstMove: String = ""
    var settings = AppSettings()
}

// MARK: - Live feed snapshots

struct HourForecast: Identifiable, Hashable {
    let time: Date
    let temp: Int
    let precip: Int
    let code: Int
    var precipAmount: Double = 0
    var id: Date { time }
}

struct DayForecast: Identifiable, Hashable {
    let date: Date
    let high: Int
    let low: Int
    let rainPct: Int
    let code: Int
    var id: Date { date }
    var symbol: String { weatherSymbol(code) }
}

struct AirQuality: Hashable {
    let usAQI: Int?
    let pm25: Double?
    let ozone: Double?
    let topPollenName: String?
    let topPollenLevel: Double

    var aqiLabel: String {
        guard let aqi = usAQI else { return "—" }
        switch aqi {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for some"
        case ..<201: return "Unhealthy"
        default: return "Very unhealthy"
        }
    }

    var pollenLabel: String {
        guard let name = topPollenName else { return "Low" }
        let level = topPollenLevel > 50 ? "High" : topPollenLevel > 10 ? "Moderate" : "Low"
        return "\(level) · \(name)"
    }
}

struct WeatherSnapshot {
    let tempF: Int
    let feels: Int
    let code: Int
    let high: Int
    let low: Int
    let rainPct: Int
    let sunrise: Date
    let sunset: Date
    let hourly: [HourForecast]
    var humidity: Int? = nil
    var windMph: Int = 0
    var uvIndexMax: Double? = nil
    var week: [DayForecast] = []
    var rainWindow: String = ""

    var description: String { weatherDescription(code) }
    var symbol: String { weatherSymbol(code) }

    var daylightText: String {
        let minutes = max(0, Int(sunset.timeIntervalSince(sunrise) / 60))
        return "\(minutes / 60)h"
    }

    var sunWindowText: String { "\(sunrise.clockText())–\(sunset.clockText())" }
}

func weatherDescription(_ code: Int) -> String {
    switch code {
    case 0: return "Clear"
    case 1: return "Mostly clear"
    case 2: return "Partly cloudy"
    case 3: return "Overcast"
    case 45, 48: return "Fog"
    case 51...57: return "Drizzle"
    case 61...67: return "Rain"
    case 71...77: return "Snow"
    case 80...82: return "Showers"
    case 85, 86: return "Snow showers"
    case 95...99: return "Thunderstorms"
    default: return "Weather"
    }
}

func weatherSymbol(_ code: Int) -> String {
    switch code {
    case 0: return "sun.max.fill"
    case 1, 2: return "cloud.sun.fill"
    case 3: return "cloud.fill"
    case 45, 48: return "cloud.fog.fill"
    case 51...67: return "cloud.rain.fill"
    case 71...77, 85, 86: return "cloud.snow.fill"
    case 80...82: return "cloud.heavyrain.fill"
    case 95...99: return "cloud.bolt.rain.fill"
    default: return "cloud.fill"
    }
}

struct CalendarEventLite: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let attendees: [String]
    let joinURL: URL?
    let links: [URL]

    var isMeeting: Bool { !attendees.isEmpty || joinURL != nil }
    var timeRangeText: String {
        isAllDay ? "All day" : "\(start.timeText()) – \(end.timeText())"
    }
}

struct TravelEstimate: Equatable {
    let eventID: String
    let minutes: Int
}

struct EmailMessage: Identifiable, Hashable {
    let id: String
    let threadID: String
    let fromName: String
    let fromEmail: String
    let subject: String
    let snippet: String
    let date: Date?
    var isVIP = false
    var needsReply = false
}

struct TeamScore: Hashable {
    let name: String
    let abbr: String
    let score: Int?
    var teamID: Int?

    /// Official team mark from MLB's static CDN (works for MLB and MiLB ids).
    var logoURL: URL? {
        teamID.flatMap { URL(string: "https://midfield.mlbstatic.com/v1/team/\($0)/spots/64") }
    }
}

struct GameInfo: Hashable {
    let id: Int
    let date: Date?
    let state: String        // "Preview" | "Live" | "Final"
    let detail: String       // human line: "Tonight 7:10 PM" / "Top 5 · 2 out" / "Final"
    let home: TeamScore
    let away: TeamScore
    let venue: String?

    var isLive: Bool { state == "Live" }
}

struct StandingRow: Identifiable, Hashable {
    let id: String
    let name: String
    let wins: Int
    let losses: Int
    let pct: String
    let gamesBack: String
    let isDbacks: Bool

    /// Official team mark from MLB's static CDN.
    var logoURL: URL? {
        Int(id).flatMap { $0 > 0 ? URL(string: "https://midfield.mlbstatic.com/v1/team/\($0)/spots/64") : nil }
    }
}

struct NewsArticle: Identifiable, Hashable {
    let title: String
    let link: URL
    let source: String
    let published: Date?
    var id: String { link.absoluteString }
}

struct MarketQuote: Identifiable, Hashable {
    let symbol: String
    let label: String
    let price: Double
    let change: Double
    let changePct: Double
    var id: String { symbol }
    var isUp: Bool { change >= 0 }
}

struct PlaybackInfo: Hashable {
    let isPlaying: Bool
    let track: String
    let artist: String
    let artURL: URL?
    let deviceName: String?
    let progressMs: Int?
    let durationMs: Int?
}

struct RecentTrack: Identifiable, Hashable {
    let id: String
    let track: String
    let artist: String
    let playedAt: Date?
    let artURL: URL?
}

/// One entry in the Today timeline: a calendar event or a suggested open block.
enum TimelineEntry: Identifiable {
    case event(CalendarEventLite)
    case freeBlock(start: Date, minutes: Int)

    var id: String {
        switch self {
        case .event(let e): return "ev-\(e.id)"
        case .freeBlock(let start, _): return "free-\(start.timeIntervalSince1970)"
        }
    }

    var start: Date {
        switch self {
        case .event(let e): return e.start
        case .freeBlock(let start, _): return start
        }
    }
}
