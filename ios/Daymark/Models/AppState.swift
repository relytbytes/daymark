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
    var airQuality: AirQuality?
    var astro: AstroSnapshot?

    var calendarAccess: Bool?
    var eventsToday: [CalendarEventLite] = []
    var eventsTomorrow: [CalendarEventLite] = []
    var eventsWeek: [CalendarEventLite] = []
    var travel: TravelEstimate?

    var mail: [EmailMessage] = []
    var mailStatus: FeedStatus = .idle
    var googleConnected = false
    var landedRoles: [LandedRole] = []
    var landedStatus: FeedStatus = .idle

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

    // MARK: AI desk output

    var aiPlan: String?
    var aiJobCoach: String?
    var aiMailTriage: String?
    var aiEveningNote: String?
    var aiHoroscope: String?
    var aiBusy: Set<String> = []

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
            group.addTask { await self.refreshLanded() }
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
        // Air quality rides along; a miss never degrades the weather card.
        airQuality = try? await WeatherService.fetchAirQuality()
        // Sky math is local and instant.
        astro = Astronomy.snapshot(latitude: AppConfig.homeLatitude, longitude: AppConfig.homeLongitude)
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
                if let leaveBy {
                    NotificationService.scheduleLeaveBy(
                        at: leaveBy.time, eventTitle: next.title, driveMinutes: minutes)
                }
            }
        }
    }

    /// When to walk out the door for the next meeting: start − drive − 5 min buffer.
    var leaveBy: (time: Date, minutes: Int)? {
        guard let travel, let next = nextMeeting, travel.eventID == next.id else { return nil }
        let time = next.start.addingTimeInterval(TimeInterval(-(travel.minutes + 5) * 60))
        guard time > Date() else { return nil }
        return (time, travel.minutes)
    }

    func refreshBaseball() async {
        if dbacksGame == nil { baseballStatus = .checking }
        do {
            async let game = BaseballService.dbacksGame()
            async let tables = BaseballService.standings()
            let fresh = try await game
            announceGameTransitions(old: dbacksGame, new: fresh, team: "D-backs")
            dbacksGame = fresh
            (nlWest, wildcard) = try await tables
            baseballStatus = .live(Date())
        } catch {
            baseballStatus = degrade(baseballStatus)
        }
    }

    func refreshBulls() async {
        if bullsGame == nil { bullsStatus = .checking }
        do {
            let fresh = try await BaseballService.bullsGame()
            announceGameTransitions(old: bullsGame, new: fresh, team: "Bulls")
            bullsGame = fresh
            bullsStatus = .live(Date())
        } catch {
            bullsStatus = degrade(bullsStatus)
        }
    }

    /// Schedule first-pitch alerts for upcoming games; announce finals when a
    /// refresh observes the transition.
    private func announceGameTransitions(old: GameInfo?, new: GameInfo?, team: String) {
        guard persisted.settings.gameAlerts, let new else { return }
        if new.state == "Preview", let start = new.date, start > Date() {
            NotificationService.scheduleGameAlerts(games: [
                (id: String(new.id), title: "\(new.away.name) at \(new.home.name) — \(team), \(start.timeText())", start: start)
            ])
        }
        if new.state == "Final", let old, old.id == new.id, old.state != "Final" {
            let headline = "\(new.away.name) \(new.away.score ?? 0), \(new.home.name) \(new.home.score ?? 0)"
            NotificationService.notifyFinal(id: String(new.id), headline: headline)
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

    func startFocus(cappedToMinutes cap: Int? = nil) {
        let title = focusTaskTitle
        let minutes = cap.map { max(5, min($0, persisted.focusMinutes)) } ?? persisted.focusMinutes
        persisted.focusTaskID = essentialsForNow.first { !essentialDone($0.id) }?.id
        persisted.focusEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        NotificationService.scheduleFocusEnd(after: TimeInterval(minutes * 60), taskTitle: title)
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

    // MARK: Landed pipeline

    func refreshLanded() async {
        guard AppConfig.landedConfigured, googleConnected else { return }
        if landedRoles.isEmpty { landedStatus = .checking }
        do {
            landedRoles = try await google.fetchLandedRoles(sheetID: AppConfig.landedSheetID)
                .sorted { ($0.stageRank, $0.company) < ($1.stageRank, $1.company) }
            landedStatus = .live(Date())
        } catch {
            landedStatus = degrade(landedStatus)
        }
    }

    /// Roles most worth attention: hot stages and high priority first.
    var landedFocusQueue: [LandedRole] {
        landedRoles.filter(\.isHot).prefix(5).map { $0 }
    }

    // MARK: - AI desk

    private func runAI(_ slot: String, into keyPath: ReferenceWritableKeyPath<AppState, String?>, _ work: @escaping () async throws -> String) {
        guard AIService.isConfigured, !aiBusy.contains(slot) else { return }
        aiBusy.insert(slot)
        Task {
            defer { aiBusy.remove(slot) }
            do {
                self[keyPath: keyPath] = try await work()
            } catch AIError.notConfigured {
                toast("Add an AI key in Settings first.")
            } catch {
                toast("The AI desk didn't answer — try again.")
            }
        }
    }

    func runDailyPlan() {
        let events = eventsToday.map { "\($0.start.timeText()) \($0.title)" }.joined(separator: "\n")
        let captures = persisted.captures.filter { !$0.done }.map(\.title).joined(separator: "\n")
        let apps = persisted.applications.filter { $0.status != .closed }
            .map { "\($0.status.rawValue): \($0.organization) — \($0.role) (next: \($0.nextStep))" }
            .joined(separator: "\n")
        let briefing = """
        Weather: \(weather.map { "\($0.tempF)°, \($0.description), rain \($0.rainPct)%" } ?? "unknown")
        Calendar today:
        \(events.nilIfEmpty ?? "(no events)")
        Open captures:
        \(captures.nilIfEmpty ?? "(none)")
        Job pipeline:
        \(apps.nilIfEmpty ?? "(none)")
        """
        runAI("plan", into: \.aiPlan) { try await AIDesk.dailyPlan(briefing: briefing) }
    }

    func runJobCoach() {
        // Prefer the live Landed sheet; fall back to the local pipeline.
        let pipeline: String
        if !landedRoles.isEmpty {
            pipeline = landedRoles.map {
                "\($0.status) · \($0.company) · \($0.role) · priority \($0.priority.nilIfEmpty ?? "—") · next: \($0.nextAction.nilIfEmpty ?? "—")"
            }.joined(separator: "\n")
        } else {
            let now = Date()
            let apps = persisted.applications.filter { $0.status != .closed }
            guard !apps.isEmpty else { toast("No open applications to coach on."); return }
            pipeline = apps.map {
                let days = Int(now.timeIntervalSince($0.updatedAt) / 86400)
                return "\($0.status.rawValue) · \($0.organization) · \($0.role) · \(days)d since touch · next: \($0.nextStep)"
            }.joined(separator: "\n")
        }
        runAI("coach", into: \.aiJobCoach) { try await AIDesk.jobCoach(pipeline: pipeline) }
    }

    func runMailTriage() {
        guard !mail.isEmpty else { toast("No priority mail to triage."); return }
        let messages = mail.prefix(8)
            .map { "\($0.fromName) <\($0.fromEmail)> · \($0.subject) · \($0.snippet.prefix(140))" }
            .joined(separator: "\n")
        runAI("triage", into: \.aiMailTriage) { try await AIDesk.mailTriage(messages: messages) }
    }

    func runEveningNarrative() {
        let review = eveningReview()
        let scores = review.scoreLines.map { "\($0.label): \($0.done)/\($0.target)" }.joined(separator: ", ")
        let dayData = """
        Essentials landed: \(review.essentialsDone)/\(review.essentialsTotal)
        Loops cleared: \(review.capturesCleared)
        Scorecard: \(scores)
        Tomorrow's first event: \(review.tomorrowFirst.map { "\($0.start.timeText()) \($0.title)" } ?? "none")
        Stated first move: \(persisted.tomorrowFirstMove.nilIfEmpty ?? "not set")
        """
        runAI("evening", into: \.aiEveningNote) { try await AIDesk.eveningNarrative(dayData: dayData) }
    }

    func runHoroscope() {
        guard let astro else { return }
        let transits = """
        Sun in \(astro.sunSign). Moon in \(astro.moon.zodiacSign), \(astro.moon.phaseName) \
        (\(Int((astro.moon.illumination * 100).rounded()))% lit, day \(Int(astro.moon.ageDays.rounded()))).
        Mercury retrograde: \(astro.mercuryRetrograde ? "yes" : "no").
        Planets visible tonight: \(astro.planets.filter(\.visibleTonight).map(\.name).joined(separator: ", ").nilIfEmpty ?? "none").
        """
        runAI("horoscope", into: \.aiHoroscope) { try await AIDesk.horoscope(transits: transits) }
    }
}
