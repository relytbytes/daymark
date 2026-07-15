//
//  AppState.swift
//  Daymark
//
//  The observable root store: persisted user data, live feeds, and actions.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppState {
    // MARK: Persisted document

    var persisted: PersistedState {
        didSet { scheduleSave() }
    }

    // MARK: Services

    let calendarService = CalendarService()
    let travelService = TravelService()
    let google = GoogleService()
    let spotify = SpotifyService()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // MARK: Live feeds

    var weather: WeatherSnapshot?
    var weatherStatus: FeedStatus = .idle

    var calendarAccess: Bool?
    var eventsToday: [CalendarEventLite] = []
    var eventsTomorrow: [CalendarEventLite] = []
    var eventsWeek: [CalendarEventLite] = []
    var travel: TravelEstimate?

    var mail: [EmailMessage] = []
    var mailStatus: FeedStatus = .idle
    var googleConnected = false

    var news: [NewsArticle] = []
    var newsStatus: FeedStatus = .idle

    var markets: [MarketQuote] = []
    var marketsStatus: FeedStatus = .idle

    var dbacksGame: GameInfo?
    var nlWest: [StandingRow] = []
    var wildcard: [StandingRow] = []
    var baseballStatus: FeedStatus = .idle
    var bullsGame: GameInfo?
    var bullsStatus: FeedStatus = .idle

    var playback: PlaybackInfo?
    var recentTracks: [RecentTrack] = []
    var spotifyStatus: FeedStatus = .idle
    var spotifyConnected = false

    var isRefreshing = false
    var toastMessage: String?

    // MARK: Init

    init() {
        persisted = JSONStore.load() ?? PersistedState()
        googleConnected = google.isConnected
        spotifyConnected = spotify.isConnected
        rolloverIfNeeded()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = persisted
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            JSONStore.save(snapshot)
        }
    }

    func rolloverIfNeeded() {
        let now = Date()
        if persisted.dayKey != now.dayKey {
            persisted.dayKey = now.dayKey
            persisted.tasks = [:]
            persisted.captures.removeAll { $0.done }
            persisted.focusEndsAt = nil
            persisted.focusTaskID = nil
            persisted.tomorrowFirstMove = ""
        }
        if persisted.weekKey != now.weekKey {
            persisted.weekKey = now.weekKey
            persisted.weeklyScores = [:]
            persisted.sprint = [:]
        }
        if let ends = persisted.focusEndsAt, ends <= now {
            persisted.focusEndsAt = nil
        }
    }

    // MARK: Refresh orchestration

    func refreshAll(force: Bool) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        rolloverIfNeeded()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshWeather() }
            group.addTask { await self.refreshCalendar() }
            group.addTask { await self.refreshBaseball() }
            group.addTask { await self.refreshBulls() }
            group.addTask { await self.refreshNews() }
            group.addTask { await self.refreshMarkets() }
            group.addTask { await self.refreshMail() }
            group.addTask { await self.refreshSpotify() }
            for await _ in group {}
        }
    }

    private func degrade(_ status: FeedStatus) -> FeedStatus {
        switch status {
        case .live(let at), .cached(let at): return .cached(at)
        default: return .unavailable
        }
    }

    func refreshWeather() async {
        if weather == nil { weatherStatus = .checking }
        do {
            weather = try await WeatherService.fetch()
            weatherStatus = .live(Date())
        } catch {
            weatherStatus = degrade(weatherStatus)
        }
    }

    func refreshCalendar() async {
        let granted = await calendarService.ensureAccess()
        calendarAccess = granted
        guard granted else { return }
        let today = Date().startOfDay
        eventsToday = calendarService.events(from: today, to: today.addingDays(1))
        eventsTomorrow = calendarService.events(from: today.addingDays(1), to: today.addingDays(2))
        eventsWeek = calendarService.events(from: today.addingDays(1), to: today.addingDays(8))

        if persisted.settings.travelETA, let next = nextMeeting {
            if let minutes = await travelService.minutes(to: next) {
                travel = TravelEstimate(eventID: next.id, minutes: minutes)
            }
        }
    }

    func refreshBaseball() async {
        if dbacksGame == nil { baseballStatus = .checking }
        do {
            async let game = BaseballService.dbacksGame()
            async let tables = BaseballService.standings()
            dbacksGame = try await game
            (nlWest, wildcard) = try await tables
            baseballStatus = .live(Date())
        } catch {
            baseballStatus = degrade(baseballStatus)
        }
    }

    func refreshBulls() async {
        if bullsGame == nil { bullsStatus = .checking }
        do {
            bullsGame = try await BaseballService.bullsGame()
            bullsStatus = .live(Date())
        } catch {
            bullsStatus = degrade(bullsStatus)
        }
    }

    func refreshNews() async {
        if news.isEmpty { newsStatus = .checking }
        let articles = await NewsService.fetch(feeds: persisted.settings.feeds)
        if articles.isEmpty {
            newsStatus = degrade(newsStatus)
        } else {
            news = articles
            newsStatus = .live(Date())
        }
    }

    func refreshMarkets() async {
        if markets.isEmpty { marketsStatus = .checking }
        let quotes = await MarketsService.fetch(persisted.settings.watchlist)
        if quotes.isEmpty {
            marketsStatus = degrade(marketsStatus)
        } else {
            markets = quotes
            marketsStatus = .live(Date())
        }
    }

    func refreshMail() async {
        guard googleConnected else { return }
        if mail.isEmpty { mailStatus = .checking }
        do {
            mail = try await google.fetchPriorityMail(
                vips: persisted.settings.vipSenders,
                cleared: persisted.clearedMailIDs
            )
            mailStatus = .live(Date())
        } catch {
            mailStatus = degrade(mailStatus)
        }
    }

    func refreshSpotify() async {
        guard spotifyConnected else { return }
        do {
            playback = try await spotify.playback()
            recentTracks = try await spotify.recentTracks()
            spotifyStatus = .live(Date())
        } catch {
            spotifyStatus = degrade(spotifyStatus)
        }
    }

    // MARK: Toast

    func toast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    // MARK: Essential tasks

    func essentialDone(_ id: String) -> Bool { persisted.tasks[id] ?? false }

    func toggleEssential(_ id: String) {
        persisted.tasks[id] = !(persisted.tasks[id] ?? false)
    }

    var essentialsForNow: [EssentialTask] { EssentialTask.forPhase(DayPhase.current()) }

    var essentialsRemaining: Int {
        essentialsForNow.filter { !essentialDone($0.id) }.count
    }

    var openLoops: Int {
        essentialsRemaining
            + persisted.captures.filter { !$0.done }.count
            + persisted.waiting.filter { !$0.done }.count
    }

    // MARK: Focus timer

    var focusRemaining: TimeInterval? {
        guard let ends = persisted.focusEndsAt else { return nil }
        let remaining = ends.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    var focusRunning: Bool { focusRemaining != nil }

    var focusTaskTitle: String {
        if let id = persisted.focusTaskID,
           let task = (EssentialTask.morning + EssentialTask.evening).first(where: { $0.id == id }) {
            return task.title
        }
        return essentialsForNow.first { !essentialDone($0.id) }?.title ?? "Choose the next useful move"
    }

    func startFocus() {
        let title = focusTaskTitle
        persisted.focusTaskID = essentialsForNow.first { !essentialDone($0.id) }?.id
        persisted.focusEndsAt = Date().addingTimeInterval(TimeInterval(persisted.focusMinutes * 60))
        NotificationService.scheduleFocusEnd(after: TimeInterval(persisted.focusMinutes * 60), taskTitle: title)
        Task { _ = await NotificationService.requestAuthorization() }
    }

    func stopFocus() {
        persisted.focusEndsAt = nil
        NotificationService.cancelFocus()
    }

    // MARK: Captures

    func addCapture(kind: CaptureKind, title: String, url: String?, note: String?) {
        switch kind {
        case .job:
            persisted.applications.insert(
                JobApplication(organization: title, role: note?.nilIfEmpty ?? "Role TBD",
                               url: url, status: .interested, nextStep: "Qualify this lead"),
                at: 0
            )
            toast("Added to the job pipeline.")
        case .reading:
            persisted.readingQueue.insert(ReadingItem(title: title, url: url), at: 0)
            toast("Saved to your reading queue.")
        default:
            persisted.captures.insert(
                CaptureItem(kind: kind, title: title, url: url, note: note),
                at: 0
            )
            toast("Captured. It can wait its turn.")
        }
    }

    func toggleCapture(_ id: UUID) {
        guard let index = persisted.captures.firstIndex(where: { $0.id == id }) else { return }
        persisted.captures[index].done.toggle()
    }

    func removeCapture(_ id: UUID) {
        persisted.captures.removeAll { $0.id == id }
    }

    // MARK: Applications

    var applicationsActive: Int { persisted.applications.filter { $0.status != .closed }.count }
    var applicationsInterviews: Int { persisted.applications.filter { $0.status == .interview }.count }
    var applicationsFollowUps: Int { persisted.applications.filter { $0.status == .followUp }.count }

    func upsertApplication(_ application: JobApplication) {
        if let index = persisted.applications.firstIndex(where: { $0.id == application.id }) {
            persisted.applications[index] = application
        } else {
            persisted.applications.insert(application, at: 0)
        }
    }

    func removeApplication(_ id: UUID) {
        persisted.applications.removeAll { $0.id == id }
    }

    // MARK: Sprint

    func sprintDone(_ id: String) -> Bool { persisted.sprint[id] ?? false }
    func toggleSprint(_ id: String) { persisted.sprint[id] = !(persisted.sprint[id] ?? false) }

    var sprintPercent: Int {
        let total = SprintMilestone.defaults.count
        guard total > 0 else { return 0 }
        let done = SprintMilestone.defaults.filter { sprintDone($0.id) }.count
        return Int((Double(done) / Double(total) * 100).rounded())
    }

    // MARK: Decisions

    func choose(_ decisionID: String, option: String) {
        if option.isEmpty {
            persisted.decisions.removeValue(forKey: decisionID)
        } else {
            persisted.decisions[decisionID] = option
        }
    }

    // MARK: Reading

    func toggleReading(_ id: UUID) {
        guard let index = persisted.readingQueue.firstIndex(where: { $0.id == id }) else { return }
        persisted.readingQueue[index].done.toggle()
    }

    func removeReading(_ id: UUID) {
        persisted.readingQueue.removeAll { $0.id == id }
    }

    var readingOpenCount: Int { persisted.readingQueue.filter { !$0.done }.count }

    // MARK: Waiting on

    func addWaiting(who: String, what: String, due: Date?, source: String = "manual") {
        let item = WaitingItem(who: who, what: what, due: due, source: source)
        persisted.waiting.insert(item, at: 0)
        if due != nil {
            NotificationService.scheduleFollowUp(item)
            Task { _ = await NotificationService.requestAuthorization() }
        }
    }

    func completeWaiting(_ id: UUID) {
        guard let index = persisted.waiting.firstIndex(where: { $0.id == id }) else { return }
        persisted.waiting[index].done = true
        NotificationService.cancelFollowUp(persisted.waiting[index])
    }

    var waitingOpen: [WaitingItem] { persisted.waiting.filter { !$0.done } }

    // MARK: Scorecard

    func score(_ key: String) -> Int { persisted.weeklyScores[key] ?? 0 }

    func bumpScore(_ category: ScoreCategory, by delta: Int) {
        let next = max(0, min(category.target, score(category.key) + delta))
        persisted.weeklyScores[category.key] = next
    }

    // MARK: Mail actions

    func markMailRead(_ message: EmailMessage) {
        mail.removeAll { $0.id == message.id }
        persisted.clearedMailIDs.append(message.id)
        if persisted.clearedMailIDs.count > 200 {
            persisted.clearedMailIDs.removeFirst(persisted.clearedMailIDs.count - 200)
        }
        Task {
            do {
                try await google.markRead(id: message.id)
            } catch {
                toast("Couldn't mark it read — it will stay unread in Gmail.")
            }
        }
    }

    func waitingFromMail(_ message: EmailMessage) {
        addWaiting(
            who: message.fromName,
            what: "Reply on: \(message.subject)",
            due: Date().addingDays(2),
            source: "mail"
        )
        toast("Tracking a reply from \(message.fromName).")
    }

    // MARK: Connections

    func connectGoogle() async {
        do {
            try await google.connect()
            googleConnected = true
            toast("Google connected — priority mail is live.")
            await refreshMail()
        } catch {
            toast(error.localizedDescription)
        }
    }

    func disconnectGoogle() {
        google.disconnect()
        googleConnected = false
        mail = []
        mailStatus = .idle
        toast("Google session ended on this device.")
    }

    func connectSpotify() async {
        do {
            try await spotify.connect()
            spotifyConnected = true
            toast("Spotify connected.")
            await refreshSpotify()
        } catch {
            toast(error.localizedDescription)
        }
    }

    func disconnectSpotify() {
        spotify.disconnect()
        spotifyConnected = false
        playback = nil
        recentTracks = []
        spotifyStatus = .idle
        toast("Spotify session ended on this device.")
    }

    func spotifyControl(_ control: SpotifyService.Control) {
        Task {
            do {
                try await spotify.send(control)
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshSpotify()
            } catch {
                toast(error.localizedDescription)
            }
        }
    }

    // MARK: Notifications

    func syncNotifications() async {
        let settings = persisted.settings
        if settings.morningBrief || settings.eveningReview {
            let granted = await NotificationService.requestAuthorization()
            guard granted else {
                toast("Notifications are off in iOS Settings.")
                return
            }
        }
        NotificationService.scheduleDailyEditions(
            morning: settings.morningBrief,
            evening: settings.eveningReview
        )
    }
}
