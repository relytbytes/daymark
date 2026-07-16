//
//  AppState.swift
//  Daymark
//
//  The observable root store: persisted user data, live feeds, and actions.
//

import SwiftUI
import Observation
import AVFoundation
#if canImport(ActivityKit)
import ActivityKit
#endif

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
    let health = HealthService()
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
    var discoveryWire: [DiscoveryTrack] = []
    var discoveryStatus: FeedStatus = .idle
    var previewingTrackID: String?
    @ObservationIgnored var focusSoundtrackStarted = false
    @ObservationIgnored var previewPlayer: AVPlayer?

    var isRefreshing = false
    var toastMessage: String?

    // MARK: AI desk output

    var aiPlan: String?
    var aiJobCoach: String?
    var aiMailTriage: String?
    var aiEveningNote: String?
    var aiHoroscope: String?
    var aiBusy: Set<String> = []

    // MARK: Auto-scored categories

    var autoFitnessDays: Int = 0        // HealthKit: fitness days since Monday
    var autoJobTouches: Int = 0         // Landed: rows changed since Monday

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
            await self.publishWidgetSnapshot()
        }
    }

    /// Keep the widget's personal numbers current.
    func publishWidgetSnapshot() {
        let next = nextMeeting
        WidgetSnapshot.write(WidgetSnapshot(
            updatedAt: Date(),
            openLoops: openLoops,
            clearedPercent: Int((dayProgress * 100).rounded()),
            nextEventTitle: next?.title,
            nextEventTime: next?.start,
            focusTitle: focusRunning ? focusTaskTitle : nil
        ))
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
            if !persisted.weeklyScores.isEmpty {
                persisted.scoreHistory[persisted.weekKey] = persisted.weeklyScores
                // Keep roughly a year of history.
                if persisted.scoreHistory.count > 60 {
                    let sortedKeys = persisted.scoreHistory.keys.sorted()
                    for key in sortedKeys.prefix(persisted.scoreHistory.count - 60) {
                        persisted.scoreHistory.removeValue(forKey: key)
                    }
                }
            }
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
            group.addTask { await self.refreshDiscovery() }
            for await _ in group {}
        }
        publishWidgetSnapshot()
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
        await refreshFitnessScore()
    }

    func refreshFitnessScore() async {
        guard HealthService.isAvailable else { return }
        if !health.authorized {
            guard await health.requestAuthorization() else { return }
        }
        autoFitnessDays = await health.fitnessDaysThisWeek()
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
        guard googleConnected || ICloudMailService.isConfigured else { return }
        if mail.isEmpty { mailStatus = .checking }

        async let gmailTask: [EmailMessage] = googleConnected
            ? google.fetchPriorityMail(vips: persisted.settings.vipSenders, cleared: persisted.clearedMailIDs)
            : []
        async let icloudTask: [EmailMessage] = ICloudMailService.isConfigured
            ? ICloudMailService.fetchUnseen(vips: persisted.settings.vipSenders, cleared: persisted.clearedMailIDs)
            : []

        var merged: [EmailMessage] = []
        var anySucceeded = false
        if let gmail = try? await gmailTask { merged += gmail; anySucceeded = true }
        if let icloud = try? await icloudTask { merged += icloud; anySucceeded = true }

        if anySucceeded {
            mail = merged.sorted {
                if $0.isVIP != $1.isVIP { return $0.isVIP }
                return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            mailStatus = .live(Date())
        } else {
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
        // Completing the pinned focus task releases the pin so the next
        // open item takes its place.
        if persisted.focusTaskID == id, essentialDone(id) {
            persisted.focusTaskID = nil
        }
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
        // A pinned focus task only holds the slot while it's still open —
        // checking it off advances the bulletin to the next open item.
        if let id = persisted.focusTaskID,
           !essentialDone(id),
           let task = (EssentialTask.morning + EssentialTask.evening).first(where: { $0.id == id }) {
            return task.title
        }
        return essentialsForNow.first { !essentialDone($0.id) }?.title
            ?? "All three are done."
    }

    func startFocus(cappedToMinutes cap: Int? = nil) {
        let title = focusTaskTitle
        let minutes = cap.map { max(5, min($0, persisted.focusMinutes)) } ?? persisted.focusMinutes
        persisted.focusTaskID = essentialsForNow.first { !essentialDone($0.id) }?.id
        persisted.focusEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        NotificationService.scheduleFocusEnd(after: TimeInterval(minutes * 60), taskTitle: title)
        Task { _ = await NotificationService.requestAuthorization() }
        startFocusActivity(endsAt: persisted.focusEndsAt ?? Date(), title: title)
        // The focus soundtrack: start the chosen playlist on the active device.
        if spotifyConnected, !persisted.settings.focusPlaylist.isEmpty {
            Task {
                do {
                    try await spotify.playContext(persisted.settings.focusPlaylist)
                    focusSoundtrackStarted = true
                } catch {
                    // No active device or restricted playback — the timer still runs.
                }
            }
        }
    }

    func stopFocus() {
        persisted.focusEndsAt = nil
        NotificationService.cancelFocus()
        endFocusActivity()
        if focusSoundtrackStarted {
            focusSoundtrackStarted = false
            Task { try? await spotify.send(.pause) }
        }
    }

    // MARK: Focus Live Activity

    private func startFocusActivity(endsAt: Date, title: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endFocusActivity()
        let attributes = FocusActivityAttributes(startedAt: Date())
        let state = FocusActivityAttributes.ContentState(endsAt: endsAt, taskTitle: title)
        _ = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: endsAt)
        )
        #endif
    }

    private func endFocusActivity() {
        #if canImport(ActivityKit)
        Task {
            for activity in Activity<FocusActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
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
            toast("Captured.")
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

    func score(_ key: String) -> Int {
        let manual = persisted.weeklyScores[key] ?? 0
        switch key {
        case "fitness": return max(manual, autoFitnessDays)
        case "jobs": return max(manual, autoJobTouches)
        default: return manual
        }
    }

    /// Whether this category currently shows an automatic reading.
    func scoreIsAuto(_ key: String) -> Bool {
        switch key {
        case "fitness": return autoFitnessDays > (persisted.weeklyScores[key] ?? 0)
        case "jobs": return autoJobTouches > (persisted.weeklyScores[key] ?? 0)
        default: return false
        }
    }

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
                if message.id.hasPrefix("icloud-") {
                    try await ICloudMailService.markSeen(id: message.id)
                } else {
                    try await google.markRead(id: message.id)
                }
            } catch {
                toast("Couldn't mark it read — it will stay unread in the inbox.")
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
            updateJobTouches()
        } catch {
            landedStatus = degrade(landedStatus)
        }
    }

    /// Job-search auto-score: count pipeline rows whose stage or next action
    /// changed since Monday, tracked by comparing per-row fingerprints against
    /// a weekly snapshot (the read-only sheet has no timestamps).
    private func updateJobTouches() {
        let defaults = UserDefaults.standard
        let weekKey = Date().weekKey
        let fingerprints = Dictionary(uniqueKeysWithValues: landedRoles.map {
            ($0.company + "|" + $0.role, $0.status + "|" + $0.nextAction)
        })
        let storedWeek = defaults.string(forKey: "daymark-jobtouch-week")
        var baseline = (defaults.dictionary(forKey: "daymark-jobtouch-baseline") as? [String: String]) ?? [:]
        var touched = Set(defaults.stringArray(forKey: "daymark-jobtouch-touched") ?? [])

        if storedWeek != weekKey {
            // New week: current state becomes the baseline, touches reset.
            baseline = fingerprints
            touched = []
            defaults.set(weekKey, forKey: "daymark-jobtouch-week")
        } else {
            for (key, print) in fingerprints where baseline[key] != nil && baseline[key] != print {
                touched.insert(key)
            }
            for key in fingerprints.keys where baseline[key] == nil {
                touched.insert(key)          // newly added role counts as a touch
                baseline[key] = fingerprints[key]
            }
        }
        defaults.set(baseline, forKey: "daymark-jobtouch-baseline")
        defaults.set(Array(touched), forKey: "daymark-jobtouch-touched")
        autoJobTouches = touched.count
    }

    /// Roles most worth attention: hot stages and high priority first.
    var landedFocusQueue: [LandedRole] {
        landedRoles.filter(\.isHot).prefix(5).map { $0 }
    }

    // MARK: The Discovery Wire

    private static let discoveryCacheKey = "daymark-discovery-wire"
    private static let discoveryDayKey = "daymark-discovery-day"
    private static let discoverySurfacedKey = "daymark-discovery-surfaced"

    /// Ten new tracks a day, cached by day so the wire only rebuilds each morning.
    func refreshDiscovery(force: Bool = false) async {
        guard spotifyConnected else { return }
        let defaults = UserDefaults.standard

        if !force,
           defaults.string(forKey: Self.discoveryDayKey) == Date().dayKey,
           let data = defaults.data(forKey: Self.discoveryCacheKey),
           let cached = try? JSONDecoder().decode([DiscoveryTrack].self, from: data),
           !cached.isEmpty {
            discoveryWire = cached
            if case .idle = discoveryStatus { discoveryStatus = .live(Date()) }
            return
        }

        if discoveryWire.isEmpty { discoveryStatus = .checking }
        let seeds = (try? await spotify.topArtists()) ?? []
        let recentArtists = recentTracks.map(\.artist)
        guard !seeds.isEmpty || !recentArtists.isEmpty else {
            discoveryStatus = degrade(discoveryStatus)
            return
        }

        var exclude = Set((seeds + recentArtists).map { $0.lowercased() })
        exclude.formUnion(persisted.musicPasses)
        let surfaced = defaults.stringArray(forKey: Self.discoverySurfacedKey) ?? []
        exclude.formUnion(surfaced.suffix(120))     // don't repeat the last ~2 weeks

        let wire = await DiscoveryService.dailyWire(
            seeds: seeds.isEmpty ? recentArtists : seeds,
            liked: persisted.musicLikes,
            exclude: exclude
        )
        guard !wire.isEmpty else {
            discoveryStatus = degrade(discoveryStatus)
            return
        }
        discoveryWire = wire
        discoveryStatus = .live(Date())
        defaults.set(Date().dayKey, forKey: Self.discoveryDayKey)
        defaults.set(try? JSONEncoder().encode(wire), forKey: Self.discoveryCacheKey)
        defaults.set(surfaced + wire.map { $0.artist.lowercased() }, forKey: Self.discoverySurfacedKey)
    }

    func discoveryLike(_ track: DiscoveryTrack) {
        let key = track.artist.lowercased()
        if !persisted.musicLikes.contains(key) { persisted.musicLikes.append(key) }
        persisted.musicPasses.removeAll { $0 == key }
        toast("Noted — more like \(track.artist).")
    }

    func discoveryPass(_ track: DiscoveryTrack) {
        let key = track.artist.lowercased()
        if !persisted.musicPasses.contains(key) { persisted.musicPasses.append(key) }
        persisted.musicLikes.removeAll { $0 == key }
        discoveryWire.removeAll { $0.id == track.id }
    }

    /// Toggle the 30-second preview for a track; one preview at a time.
    func togglePreview(_ track: DiscoveryTrack) {
        if previewingTrackID == track.id {
            previewPlayer?.pause()
            previewingTrackID = nil
            return
        }
        guard let url = track.previewURL else { return }
        previewPlayer?.pause()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        player.play()
        previewPlayer = player
        previewingTrackID = track.id
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.previewingTrackID == track.id { self?.previewingTrackID = nil }
            }
        }
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
