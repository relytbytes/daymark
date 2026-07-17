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
    var imageFile: String?      // filename in the captures image store
    var createdAt = Date()
    var done = false
}

/// One discovery that crossed the wire — the listening history Spotify's
/// dev-mode gate won't let us keep in a playlist.
struct WireArchiveEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var day: String            // dayKey, e.g. "2026-07-16"
    var title: String
    var artist: String
    var reason: String = ""
    var verdict: String?       // "like" / "pass" / nil (unjudged)

    var spotifySearchURL: URL? {
        let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "spotify:search:\(q)")
    }
}

/// Photos attached to captures, stored as JPEGs in Application Support.
enum CaptureImages {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func save(_ image: UIImage) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        do {
            try data.write(to: directory.appendingPathComponent(name))
            return name
        } catch { return nil }
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
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
    let contact: String
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
    var soundcloudUser: String = ""
    var soundcloudArtists: [String] = []
    var focusPlaylist: String = ""       // Spotify playlist link/URI for focus blocks
    var feedsRevision: Int = AppSettings.currentFeedsRevision
    var appearance: String = "auto"      // auto (sun-driven) / light / dark

    init() {}

    /// Tolerant decoding: a missing key never fails the whole document, so adding
    /// fields in an update can never reset on-device state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vipSenders = (try? c.decodeIfPresent([String].self, forKey: .vipSenders)) ?? nil ?? []
        feeds = (try? c.decodeIfPresent([FeedSource].self, forKey: .feeds)) ?? nil ?? AppSettings.defaultFeeds
        watchlist = (try? c.decodeIfPresent([WatchSymbol].self, forKey: .watchlist)) ?? nil ?? AppSettings.defaultWatchlist
        morningBrief = (try? c.decodeIfPresent(Bool.self, forKey: .morningBrief)) ?? nil ?? true
        eveningReview = (try? c.decodeIfPresent(Bool.self, forKey: .eveningReview)) ?? nil ?? true
        travelETA = (try? c.decodeIfPresent(Bool.self, forKey: .travelETA)) ?? nil ?? false
        gameAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .gameAlerts)) ?? nil ?? true
        soundcloudUser = (try? c.decodeIfPresent(String.self, forKey: .soundcloudUser)) ?? nil ?? ""
        soundcloudArtists = (try? c.decodeIfPresent([String].self, forKey: .soundcloudArtists)) ?? nil ?? []
        focusPlaylist = (try? c.decodeIfPresent(String.self, forKey: .focusPlaylist)) ?? nil ?? ""
        feedsRevision = (try? c.decodeIfPresent(Int.self, forKey: .feedsRevision)) ?? nil ?? 1
        appearance = (try? c.decodeIfPresent(String.self, forKey: .appearance)) ?? nil ?? "auto"
    }

    static let defaultFeeds: [FeedSource] = [
        FeedSource(name: "NYT", url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"),
        FeedSource(name: "NPR", url: "https://feeds.npr.org/1001/rss.xml"),
        FeedSource(name: "Jacobin", url: "https://jacobin.com/feed/"),
        FeedSource(name: "CounterPunch", url: "https://www.counterpunch.org/feed/"),
        FeedSource(name: "The Intercept", url: "https://theintercept.com/feed/?rss"),
        FeedSource(name: "The Nation", url: "https://www.thenation.com/feed/?post_type=article"),
        FeedSource(name: "Guardian US", url: "https://www.theguardian.com/us-news/rss"),
        FeedSource(name: "Consortium News", url: "https://consortiumnews.com/feed/"),
        FeedSource(name: "Common Dreams", url: "https://www.commondreams.org/rss.xml"),
        FeedSource(name: "Democracy Now!", url: "https://www.democracynow.org/democracynow.rss"),
        FeedSource(name: "Truthout", url: "https://truthout.org/feed/"),
        FeedSource(name: "ProPublica", url: "https://www.propublica.org/feeds/propublica/main"),
        FeedSource(name: "Mother Jones", url: "https://www.motherjones.com/feed/"),
        FeedSource(name: "Drop Site", url: "https://www.dropsitenews.com/feed"),
        FeedSource(name: "The Grayzone", url: "https://thegrayzone.com/feed/"),
        FeedSource(name: "MintPress", url: "https://www.mintpressnews.com/feed/"),
        FeedSource(name: "Black Agenda Report", url: "https://blackagendareport.com/rss.xml"),
        FeedSource(name: "Grist", url: "https://grist.org/feed/"),
        // Longform — the reading side of the brief.
        FeedSource(name: "Longreads", url: "https://longreads.com/feed/"),
        FeedSource(name: "Harper's", url: "https://harpers.org/feed/"),
        FeedSource(name: "Monthly Review", url: "https://monthlyreview.org/feed/"),
    ]

    /// Bumped when defaultFeeds gains sources; existing installs merge
    /// the newcomers once and never resurrect feeds the user deleted.
    static let currentFeedsRevision = 3

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
    var musicLikes: [String] = []              // discovery feedback: artist names, lowercased
    var musicPasses: [String] = []
    var scoreHistory: [String: [String: Int]] = [:]   // weekKey -> category -> done
    var taskNotes: [String: String] = [:]      // EssentialTask.id -> today's note
    var wireArchive: [WireArchiveEntry] = []   // discovery listening history
    var sprintNotes: [String: String] = [:]    // SprintMilestone.id -> working note
    var sprintLedger: String = ""              // the desk's running sprint summary
    var sprintLedgerAt: Date?

    init() {}

    /// Tolerant decoding — see AppSettings. Adding fields never resets state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil ?? AppConfig.ownerName
        dayKey = (try? c.decodeIfPresent(String.self, forKey: .dayKey)) ?? nil ?? Date().dayKey
        weekKey = (try? c.decodeIfPresent(String.self, forKey: .weekKey)) ?? nil ?? Date().weekKey
        tasks = (try? c.decodeIfPresent([String: Bool].self, forKey: .tasks)) ?? nil ?? [:]
        sprint = (try? c.decodeIfPresent([String: Bool].self, forKey: .sprint)) ?? nil ?? [:]
        captures = (try? c.decodeIfPresent([CaptureItem].self, forKey: .captures)) ?? nil ?? []
        applications = (try? c.decodeIfPresent([JobApplication].self, forKey: .applications)) ?? nil ?? []
        decisions = (try? c.decodeIfPresent([String: String].self, forKey: .decisions)) ?? nil ?? [:]
        readingQueue = (try? c.decodeIfPresent([ReadingItem].self, forKey: .readingQueue)) ?? nil ?? []
        waiting = (try? c.decodeIfPresent([WaitingItem].self, forKey: .waiting)) ?? nil ?? []
        weeklyScores = (try? c.decodeIfPresent([String: Int].self, forKey: .weeklyScores)) ?? nil ?? [:]
        focusTaskID = try? c.decodeIfPresent(String.self, forKey: .focusTaskID) ?? nil
        focusEndsAt = try? c.decodeIfPresent(Date.self, forKey: .focusEndsAt) ?? nil
        focusMinutes = (try? c.decodeIfPresent(Int.self, forKey: .focusMinutes)) ?? nil ?? 25
        clearedMailIDs = (try? c.decodeIfPresent([String].self, forKey: .clearedMailIDs)) ?? nil ?? []
        tomorrowFirstMove = (try? c.decodeIfPresent(String.self, forKey: .tomorrowFirstMove)) ?? nil ?? ""
        settings = (try? c.decodeIfPresent(AppSettings.self, forKey: .settings)) ?? nil ?? AppSettings()
        musicLikes = (try? c.decodeIfPresent([String].self, forKey: .musicLikes)) ?? nil ?? []
        musicPasses = (try? c.decodeIfPresent([String].self, forKey: .musicPasses)) ?? nil ?? []
        scoreHistory = (try? c.decodeIfPresent([String: [String: Int]].self, forKey: .scoreHistory)) ?? nil ?? [:]
        taskNotes = (try? c.decodeIfPresent([String: String].self, forKey: .taskNotes)) ?? nil ?? [:]
        wireArchive = (try? c.decodeIfPresent([WireArchiveEntry].self, forKey: .wireArchive)) ?? nil ?? []
        sprintNotes = (try? c.decodeIfPresent([String: String].self, forKey: .sprintNotes)) ?? nil ?? [:]
        sprintLedger = (try? c.decodeIfPresent(String.self, forKey: .sprintLedger)) ?? nil ?? ""
        sprintLedgerAt = try? c.decodeIfPresent(Date.self, forKey: .sprintLedgerAt) ?? nil
    }
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
    var symbol: String { weatherSymbol(code, night: isNight()) }

    /// Between sunset and sunrise, the sky wears the moon.
    func isNight(at date: Date = Date()) -> Bool {
        date >= sunset || date < sunrise
    }

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

func weatherSymbol(_ code: Int, night: Bool = false) -> String {
    switch code {
    case 0: return night ? "moon.stars.fill" : "sun.max.fill"
    case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
    case 3: return "cloud.fill"
    case 45, 48: return "cloud.fog.fill"
    case 51...67: return night ? "cloud.moon.rain.fill" : "cloud.rain.fill"
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

    /// A "meeting" is other people expecting you — invitees, a call
    /// link, or an appointment-shaped title. Self-created events (an
    /// interview typed into the calendar) carry no attendees, so the
    /// title check matters. A location alone does NOT qualify — a
    /// ballgame has a stadium, but it isn't a meeting.
    var isMeeting: Bool {
        if !attendees.isEmpty || joinURL != nil { return true }
        let haystack = title.lowercased()
        return ["interview", "meeting", "call", "appointment", "appt",
                "screen", "1:1", "sync", "dr.", "dentist", "doctor"]
            .contains { haystack.contains($0) }
    }
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
    var otherSources: [String] = []      // same story carried elsewhere
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
