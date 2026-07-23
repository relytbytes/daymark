//
//  AppState.swift
//  Daymark
//
//  The observable root store: persisted user data, live feeds, and actions.
//

import SwiftUI
import Observation
import AVFoundation
import WidgetKit
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
    let nest = NestService()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    // MARK: Live feeds

    var weather: WeatherSnapshot?
    var weatherStatus: FeedStatus = .idle
    var airQuality: AirQuality?
    var astro: AstroSnapshot?
    var nestReading: NestReading?
    var cadence: CadenceSnapshot?

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
    var dbacksNext: GameInfo?
    var nlWest: [StandingRow] = []
    var wildcard: [StandingRow] = []
    var baseballStatus: FeedStatus = .idle
    var bullsGame: GameInfo?
    var bullsNext: GameInfo?
    var bullsStandings: [StandingRow] = []
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
    var landedError: String?            // why the Landed wire is down, if it is
    private var lastNestPoll = Date.distantPast
    var readiness: HealthService.Readiness?
    var weatherAlerts: [WeatherAlert] = []
    var issPasses: [ISSPass] = []
    private var lastISSFetch = Date.distantPast

    // MARK: Init

    init() {
        persisted = JSONStore.load() ?? PersistedState()
        googleConnected = google.isConnected
        spotifyConnected = spotify.isConnected
        mergeNewDefaultFeeds()
        rolloverIfNeeded()
    }

    /// One-time merge when an update ships new default feeds: add the
    /// newcomers (keyed by URL) without resurrecting deleted ones.
    private func mergeNewDefaultFeeds() {
        guard persisted.settings.feedsRevision < AppSettings.currentFeedsRevision else { return }
        let existing = Set(persisted.settings.feeds.map(\.url))
        for feed in AppSettings.defaultFeeds where !existing.contains(feed.url) {
            persisted.settings.feeds.append(feed)
        }
        persisted.settings.feedsRevision = AppSettings.currentFeedsRevision
        scheduleSave()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = persisted
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            JSONStore.save(snapshot)
            self.publishWidgetSnapshot()
        }
    }

    /// Keep the wrist edition current alongside the widgets.
    private func pushWatchContext() {
        let essentials = essentialsForNow.map {
            ["id": $0.id, "kicker": $0.kicker, "title": $0.title,
             "done": essentialDone($0.id)] as [String: Any]
        }
        var context: [String: Any] = [
            "updated": Date(),
            "loops": openLoops,
            "essentials": essentials,
        ]
        if let weather {
            context["weather"] = "\(weather.tempF)° \(weather.description) · H \(weather.high) L \(weather.low)"
        }
        if let next = nextMeeting {
            context["event"] = "\(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)"
        }
        if let game = dbacksGame ?? dbacksNext {
            let score: String
            if let awayRuns = game.away.score, let homeRuns = game.home.score {
                score = "\(game.away.abbr) \(awayRuns)\u{2013}\(homeRuns) \(game.home.abbr)"
            } else {
                score = "\(game.away.abbr) at \(game.home.abbr)"
            }
            context["game"] = "\(score) · \(game.detail)"
        }
        WatchBridge.shared.push(context)
    }

    /// Keep the widget's personal numbers current.
    func publishWidgetSnapshot() {
        let next = nextMeeting
        let today = eventsToday
            .filter { $0.end > Date() }
            .map { WidgetSnapshot.Event(title: $0.title, start: $0.start, end: $0.end, isTomorrow: false) }
        let tomorrow = eventsTomorrow
            .prefix(4)
            .map { WidgetSnapshot.Event(title: $0.title, start: $0.start, end: $0.end, isTomorrow: true) }
        WidgetSnapshot.write(WidgetSnapshot(
            updatedAt: Date(),
            openLoops: openLoops,
            clearedPercent: Int((dayProgress * 100).rounded()),
            nextEventTitle: next?.title,
            nextEventTime: next?.start,
            focusTitle: focusRunning ? focusTaskTitle : nil,
            events: Array((today + tomorrow).prefix(8)),
            essentials: essentialsForNow.map {
                WidgetSnapshot.Essential(id: $0.id, kicker: $0.kicker,
                                         title: $0.title, done: essentialDone($0.id))
            }
        ))
        // Nudge the widgets whenever the app has fresher data than they
        // do — app-initiated reloads don't count against their budget.
        WidgetCenter.shared.reloadAllTimelines()
        pushWatchContext()
    }

    func rolloverIfNeeded() {
        let now = Date()
        if persisted.dayKey != now.dayKey {
            persisted.dayKey = now.dayKey
            persisted.tasks = [:]
            persisted.taskNotes = [:]
            for capture in persisted.captures where capture.done {
                CaptureImages.delete(capture.imageFile)
            }
            persisted.captures.removeAll { $0.done }
            // Reading queue hygiene: read items go, and anything saved
            // more than 30 days ago has answered its own question.
            persisted.readingQueue.removeAll {
                $0.done || $0.savedAt < now.addingTimeInterval(-30 * 86400)
            }
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
            persisted.sprintNotes = [:]
            persisted.sprintLedger = ""
            persisted.sprintLedgerAt = nil
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
        scheduleInterviewAutopilot()
        pickTodaysRead()
        if weekReviewWindowOpen { composeWeekReview() }
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
        // NWS alerts: banner on Today, notification when a new one lands.
        if let alerts = try? await AlertsService.active() {
            let known = Set(UserDefaults.standard.stringArray(forKey: "daymark-alert-ids") ?? [])
            for alert in alerts where !known.contains(alert.id) {
                NotificationService.notifyNow(
                    id: "daymark.wx.\(alert.id.hashValue)",
                    title: alert.event,
                    body: alert.headline)
            }
            UserDefaults.standard.set(alerts.map(\.id), forKey: "daymark-alert-ids")
            weatherAlerts = alerts
        }
        // The rain nowcast: one heads-up per shower, not per refresh.
        if let starts = weather?.rainStartsAt {
            let slotKey = "daymark-nowcast-\(Int(starts.timeIntervalSince1970 / 1800))"
            if !UserDefaults.standard.bool(forKey: slotKey) {
                UserDefaults.standard.set(true, forKey: slotKey)
                NotificationService.notifyNow(
                    id: slotKey,
                    title: "Rain incoming",
                    body: "Starting around \(starts.timeText()) — about \(max(1, Int(starts.timeIntervalSinceNow / 60))) minutes out.")
            }
        }
        // Sky math is local and instant.
        astro = Astronomy.snapshot(latitude: AppConfig.homeLatitude, longitude: AppConfig.homeLongitude)
        // ISS passes change slowly; ask twice a day.
        if Date().timeIntervalSince(lastISSFetch) > 12 * 3600 || issPasses.isEmpty {
            if let passes = try? await SatelliteService.issPasses() {
                issPasses = passes.filter { $0.start > Date() }
                lastISSFetch = Date()
            }
        }
        await refreshFitnessScore()
        cadence = CadenceBridge.read()
        if NestService.isConfigured, nest.isConnected {
            // Keep the last good reading — SDM rate-limits hard, and a
            // failed poll shouldn't blank the Indoor cell. Poll gently.
            if Date().timeIntervalSince(lastNestPoll) > 120 || nestReading == nil {
                lastNestPoll = Date()
                if let fresh = try? await nest.thermostat() { nestReading = fresh }
            }
        }
    }

    func refreshFitnessScore() async {
        guard HealthService.isAvailable else { return }
        if !health.authorized {
            guard await health.requestAuthorization() else { return }
        }
        autoFitnessDays = await health.fitnessDaysThisWeek()
        readiness = await health.readiness()
    }

    // MARK: Game Live Activity

    #if canImport(ActivityKit)
    private var gameActivity: Activity<GameActivityAttributes>?

    /// The live game rides the Lock Screen: start when it goes live,
    /// update each refresh, end at the final.
    private func syncGameActivity(_ game: GameInfo?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let game else { return }
        let state = GameActivityAttributes.ContentState(
            awayScore: game.away.score ?? 0,
            homeScore: game.home.score ?? 0,
            detail: game.detail)

        if game.isLive {
            if let activity = gameActivity {
                Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            } else {
                let attributes = GameActivityAttributes(
                    awayAbbr: game.away.abbr.nilIfEmpty ?? String(game.away.name.prefix(3)).uppercased(),
                    homeAbbr: game.home.abbr.nilIfEmpty ?? String(game.home.name.prefix(3)).uppercased())
                gameActivity = try? Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil))
            }
        } else if let activity = gameActivity {
            Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(1800))) }
            gameActivity = nil
        }
    }
    #else
    private func syncGameActivity(_ game: GameInfo?) {}
    #endif

    // MARK: The Garden Bench

    func waterPlant(_ id: UUID) {
        guard let index = persisted.plants.firstIndex(where: { $0.id == id }) else { return }
        persisted.plants[index].lastWatered = Date()
        toast("\(persisted.plants[index].name) watered.")
    }

    func addPlant(name: String, note: String, everyDays: Int) {
        persisted.plants.append(Plant(name: name, note: note, waterEveryDays: max(1, everyDays)))
        toast("\(name) joins the garden.")
    }

    func removePlant(_ id: UUID) {
        if let plant = persisted.plants.first(where: { $0.id == id }) {
            for photo in plant.photos { CaptureImages.delete(photo.file) }
        }
        persisted.plants.removeAll { $0.id == id }
    }

    func addPlantPhoto(_ id: UUID, image: UIImage) {
        guard let index = persisted.plants.firstIndex(where: { $0.id == id }),
              let file = CaptureImages.save(image) else { return }
        persisted.plants[index].photos.append(PlantPhoto(file: file))
        toast("Photo filed to \(persisted.plants[index].name)'s record.")
    }

    var plantPlanBusy: UUID?

    /// The desk writes the watering plan and sets the cadence from it.
    func composePlantPlan(_ id: UUID) {
        guard AIService.isConfigured,
              let index = persisted.plants.firstIndex(where: { $0.id == id }),
              plantPlanBusy == nil else { return }
        let plant = persisted.plants[index]
        plantPlanBusy = id

        var lines = ["Name: \(plant.name)"]
        if !plant.species.isEmpty { lines.append("Species: \(plant.species)") }
        if !plant.potSize.isEmpty { lines.append("Pot/size: \(plant.potSize)") }
        if !plant.soil.isEmpty { lines.append("Soil: \(plant.soil)") }
        if !plant.light.isEmpty { lines.append("Light: \(plant.light)") }
        if !plant.note.isEmpty { lines.append("Notes: \(plant.note)") }
        if let weather { lines.append("Current weather: \(weather.tempF)°F, \(weather.description)") }

        Task {
            defer { plantPlanBusy = nil }
            guard let reply = try? await AIDesk.wateringPlan(profile: lines.joined(separator: "\n")),
                  let idx = persisted.plants.firstIndex(where: { $0.id == id }) else { return }
            var days: Int?
            var planText = reply
            if let firstLine = reply.split(separator: "\n").first,
               firstLine.uppercased().contains("DAYS:") {
                days = Int(firstLine.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
                planText = reply.split(separator: "\n").dropFirst()
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            persisted.plants[idx].plan = planText
            if let days, days >= 1, days <= 60 {
                persisted.plants[idx].waterEveryDays = days
                toast("\(persisted.plants[idx].name): watering every \(days) days.")
            }
        }
    }

    var plantsDue: Int { persisted.plants.filter { $0.daysUntilDue <= 0 }.count }

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
            let (fresh, next) = try await game
            announceGameTransitions(old: dbacksGame, new: fresh, team: "D-backs")
            dbacksGame = fresh
            dbacksNext = next
            syncGameActivity(fresh)
            (nlWest, wildcard) = try await tables
            baseballStatus = .live(Date())
        } catch {
            baseballStatus = degrade(baseballStatus)
        }
    }

    func refreshBulls() async {
        if bullsGame == nil { bullsStatus = .checking }
        do {
            async let standings = BaseballService.bullsStandings()
            let (fresh, next) = try await BaseballService.bullsGame()
            announceGameTransitions(old: bullsGame, new: fresh, team: "Bulls")
            bullsGame = fresh
            bullsNext = next
            bullsStandings = (try? await standings) ?? bullsStandings
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
            // The tail is the ballpark, not the tracked team — "Knights at
            // Bulls — Bulls" read like the home side twice.
            let place = new.venue ?? team
            NotificationService.scheduleGameAlerts(games: [
                (id: String(new.id), title: "\(new.away.name) at \(new.home.name) — \(place), \(start.timeText())", start: start)
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

    // While the app is on screen, poll now-playing so the player card
    // advances when Spotify moves to the next track. Playback only —
    // recents and everything else stay on the normal refresh cadence.
    private var playbackTicker: Task<Void, Never>?

    func startPlaybackTicker() {
        playbackTicker?.cancel()
        playbackTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.spotifyConnected else { continue }
                if let live = try? await self.spotify.playback() {
                    self.playback = live
                    self.spotifyStatus = .live(Date())
                }
            }
        }
    }

    func stopPlaybackTicker() {
        playbackTicker?.cancel()
        playbackTicker = nil
    }

    // MARK: Meeting prep brief

    var meetingPrepOutput: String?
    var meetingPrepFor: String?          // event id the output belongs to
    var meetingPrepBusy = false
    var meetingPrepError: String?

    /// The desk composes a prep brief for the next meeting, cached per
    /// event so reopening the page never re-bills.
    func runMeetingPrep(force: Bool = false) {
        guard let meeting = nextMeeting else { return }
        // v2: sharper prompt (company knowledge + background); retire v1 briefs.
        let cacheKey = "daymark-meeting-prep-v2-\(meeting.id)"
        if !force, let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
            meetingPrepOutput = cached
            meetingPrepFor = meeting.id
            return
        }
        guard AIService.isConfigured, !meetingPrepBusy else { return }
        meetingPrepBusy = true
        meetingPrepError = nil

        // Everything real we know about the moment.
        var lines: [String] = []
        lines.append("Title: \(meeting.title)")
        lines.append("When: \(meeting.timeRangeText)")
        if let location = meeting.location?.nilIfEmpty { lines.append("Where: \(location)") }
        if !meeting.attendees.isEmpty { lines.append("With: \(meeting.attendees.joined(separator: ", "))") }
        if let notes = meeting.notes?.nilIfEmpty { lines.append("Notes on the invite: \(notes.prefix(500))") }
        if let travel, travel.eventID == meeting.id { lines.append("Drive time: \(travel.minutes) minutes") }
        if let weather { lines.append("Weather: \(weather.tempF)°, \(weather.description)") }

        // If the title names a pipeline company, bring the whole file.
        let match = landedRoles.first { meeting.title.localizedCaseInsensitiveContains($0.company) }
        if let match {
            lines.append("Landed pipeline match: \(match.company) — \(match.role) · stage \(match.status)"
                + (match.track.nilIfEmpty.map { " · track \($0)" } ?? "")
                + (match.notes.nilIfEmpty.map { " · notes: \($0)" } ?? ""))
        }
        let looksLikeInterview = match != nil
            || meeting.title.lowercased().contains("interview")
            || meeting.title.lowercased().contains("screen")

        Task {
            defer { meetingPrepBusy = false }
            do {
                let brief = try await AIDesk.meetingPrep(
                    details: lines.joined(separator: "\n"), isInterview: looksLikeInterview)
                meetingPrepOutput = brief
                meetingPrepFor = meeting.id
                UserDefaults.standard.set(brief, forKey: cacheKey)
            } catch let error as AIError {
                meetingPrepError = error.readable
            } catch {
                meetingPrepError = error.localizedDescription
            }
        }
    }

    // MARK: Interview autopilot

    /// When tomorrow's calendar holds an interview that matches a Landed
    /// role, compose the desk brief tonight and deliver it with breakfast.
    func scheduleInterviewAutopilot() {
        guard AIService.isConfigured else { return }
        let tomorrowMeetings = eventsTomorrow.filter { event in
            event.isMeeting && !event.isAllDay
        }
        for meeting in tomorrowMeetings {
            let match = landedRoles.first { meeting.title.localizedCaseInsensitiveContains($0.company) }
            let looksLikeInterview = match != nil || meeting.title.lowercased().contains("interview")
                || meeting.title.lowercased().contains("screen")
            guard looksLikeInterview else { continue }
            let doneKey = "daymark-autopilot-\(meeting.id)"
            guard !UserDefaults.standard.bool(forKey: doneKey) else { continue }
            UserDefaults.standard.set(true, forKey: doneKey)

            var lines = ["Title: \(meeting.title)", "When: tomorrow, \(meeting.timeRangeText)"]
            if let location = meeting.location?.nilIfEmpty { lines.append("Where: \(location)") }
            if let match {
                lines.append("Landed pipeline: \(match.company) — \(match.role) · stage \(match.status)"
                    + (match.notes.nilIfEmpty.map { " · notes: \($0)" } ?? ""))
            }
            Task {
                guard let brief = try? await AIDesk.meetingPrep(
                    details: lines.joined(separator: "\n"), isInterview: true) else { return }
                // Same cache the meeting card reads, so it's there on open.
                UserDefaults.standard.set(brief, forKey: "daymark-meeting-prep-v2-\(meeting.id)")
                NotificationService.scheduleInterviewBrief(
                    eventID: meeting.id,
                    title: "The desk brief: \(meeting.title)",
                    body: String(brief.prefix(500)))
            }
        }
    }

    // MARK: The Week in Review

    var weekReviewBusy = false

    /// Sundays from 17:00, and Monday mornings, carry the column.
    var weekReviewWindowOpen: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let hour = Calendar.current.component(.hour, from: Date())
        return (weekday == 1 && hour >= 17) || (weekday == 2 && hour < 12)
    }

    func composeWeekReview(force: Bool = false) {
        guard AIService.isConfigured, !weekReviewBusy else { return }
        // The column belongs to the week being reviewed (Sunday's weekKey).
        let key = Date().weekKey
        if !force, persisted.weekReviewKey == key, !persisted.weekReview.isEmpty { return }
        weekReviewBusy = true

        var lines: [String] = []
        for category in ScoreCategory.defaults {
            lines.append("\(category.label): \(score(category.key)) of \(category.target)")
        }
        lines.append("Job pipeline rows touched this week: \(autoJobTouches)")
        lines.append("Veraya sprint: \(sprintPercent)% complete"
            + (persisted.sprintLedger.nilIfEmpty.map { " — ledger: \($0.prefix(200))" } ?? ""))
        let likes = persisted.wireArchive.filter { $0.verdict == "like" }.suffix(5)
            .map { "\($0.title) — \($0.artist)" }.joined(separator: "; ")
        lines.append("Music discoveries kept: \(likes.nilIfEmpty ?? "(none)")")

        Task {
            defer { weekReviewBusy = false }
            if let column = try? await AIDesk.weekInReview(ledger: lines.joined(separator: "\n")) {
                persisted.weekReview = column
                persisted.weekReviewKey = key
            }
        }
    }

    // MARK: Today's read

    var todaysReadID: UUID?

    /// The desk picks one saved piece per day.
    func pickTodaysRead() {
        guard AIService.isConfigured else { return }
        let queue = persisted.readingQueue.filter { !$0.done }
        guard queue.count >= 2 else {
            todaysReadID = queue.first?.id
            return
        }
        let dayKey = Date().dayKey
        let cacheKey = "daymark-todays-read-\(dayKey)"
        if let cached = UserDefaults.standard.string(forKey: cacheKey),
           let id = UUID(uuidString: cached),
           queue.contains(where: { $0.id == id }) {
            todaysReadID = id
            return
        }
        let listing = queue.enumerated()
            .map { "\($0.offset + 1). \($0.element.title)" }
            .joined(separator: "\n")
        Task {
            guard let reply = try? await AIDesk.todaysRead(queue: listing),
                  let number = Int(reply.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)),
                  number >= 1, number <= queue.count else { return }
            let pick = queue[number - 1]
            todaysReadID = pick.id
            UserDefaults.standard.set(pick.id.uuidString, forKey: cacheKey)
        }
    }

    // MARK: Nest control

    var nestAdjusting = false

    func nestSetTemperature(_ targetF: Int) {
        guard let reading = nestReading, !nestAdjusting else { return }
        nestAdjusting = true
        Task {
            defer { nestAdjusting = false }
            do {
                try await nest.setTemperature(targetF, reading: reading)
                toast("Nest set to \(targetF)°.")
                if let fresh = try? await nest.thermostat() { nestReading = fresh }
            } catch {
                toast("Nest didn't take it: \(error.localizedDescription)")
            }
        }
    }

    func nestSetMode(_ mode: String) {
        guard !nestAdjusting else { return }
        nestAdjusting = true
        Task {
            defer { nestAdjusting = false }
            do {
                try await nest.setMode(mode)
                toast("Nest mode: \(mode.capitalized).")
                if let fresh = try? await nest.thermostat() { nestReading = fresh }
            } catch {
                toast("Nest didn't take it: \(error.localizedDescription)")
            }
        }
    }

    func nestFan(on: Bool, minutes: Int = 60) {
        guard !nestAdjusting else { return }
        nestAdjusting = true
        Task {
            defer { nestAdjusting = false }
            do {
                try await nest.setFan(on: on, minutes: minutes)
                toast(on ? "Fan running for \(minutes) minutes." : "Fan off.")
                if let fresh = try? await nest.thermostat() { nestReading = fresh }
            } catch {
                toast("Nest didn't take it: \(error.localizedDescription)")
            }
        }
    }

    // MARK: The Spoken Edition

    let spokenEdition = SpokenEdition()

    /// The brief as a radio script — what you'd want read aloud in the car.
    func spokenScript() -> String {
        var parts: [String] = []
        let phase = DayPhase.current()
        parts.append("Good \(phase == .morning ? "morning" : phase == .afternoon ? "afternoon" : "evening"), Ty. Here's the brief.")
        if let weather {
            parts.append("Durham weather: \(weather.tempF) degrees and \(weather.description.lowercased()). High of \(weather.high), low of \(weather.low). Rain chance \(weather.rainPct) percent.")
        }
        let lead = leadStory(for: phase)
        parts.append(lead.headline + ". " + lead.deck)
        if let plan = aiPlan?.nilIfEmpty {
            parts.append("The plan. " + plan.replacingOccurrences(of: "\n", with: ". "))
        } else {
            let open = EssentialTask.forPhase(phase).filter { !essentialDone($0.id) }.map(\.title)
            if !open.isEmpty {
                parts.append("Still open: " + open.joined(separator: ". ") + ".")
            }
        }
        if let next = nextMeeting {
            parts.append("Next on the calendar: \(next.title) at \(next.start.timeText()).")
        }
        if let game = dbacksGame {
            parts.append("Diamondbacks: \(game.detail).")
        }
        parts.append("That's the edition.")
        return parts.joined(separator: " ")
    }

    // MARK: Appearance

    /// The edition's color scheme: sun-driven by default (dark from
    /// sunset to sunrise), or pinned by the Appearance setting.
    func preferredScheme(at date: Date = Date()) -> ColorScheme {
        switch persisted.settings.appearance {
        case "light": return .light
        case "dark": return .dark
        default:
            if let weather { return weather.isNight(at: date) ? .dark : .light }
            let hour = Calendar.current.component(.hour, from: date)
            return (hour >= 21 || hour < 6) ? .dark : .light
        }
    }

    // MARK: Capture requests (empty states open the capture sheet)

    var captureRequested = false

    func requestCapture() {
        captureRequested = true
    }

    /// The Indoor glance cell asks Today to present the thermostat.
    var thermostatRequested = false

    /// Glance cells can steer navigation: a tab to switch to and an
    /// optional section anchor for the page to scroll to.
    var requestedTab: String?
    var pendingAnchor: String?

    func navigate(tab: String, anchor: String? = nil) {
        requestedTab = tab
        pendingAnchor = anchor
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

    // MARK: Reading desk intelligence

    var gistBusy: UUID?
    var presentedGist: ReadingGist?
    var musicReviewBusy = false

    /// Fetch a saved story and hand back the desk's summary.
    func composeGist(for item: ReadingItem) {
        guard gistBusy == nil else { return }
        gistBusy = item.id
        Task {
            defer { gistBusy = nil }
            guard let raw = item.url, let url = URL(string: raw),
                  let text = await ArticleService.extract(url) else {
                toast("Couldn't pull the article text.")
                return
            }
            do {
                let gist = try await AIDesk.storyGist(title: item.title, text: text)
                presentedGist = ReadingGist(title: item.title, text: gist)
            } catch {
                toast("The desk couldn't summarize it.")
            }
        }
    }

    /// Read a saved story aloud — same voice as the spoken edition.
    func speakReading(_ item: ReadingItem) {
        if spokenEdition.isSpeaking {
            spokenEdition.stop()
            return
        }
        toast("Fetching the story…")
        Task {
            guard let raw = item.url, let url = URL(string: raw),
                  let text = await ArticleService.extract(url) else {
                toast("Couldn't pull the article text.")
                return
            }
            spokenEdition.toggle(script: "\(item.title). \(text)")
        }
    }

    /// The month in music, composed from the wire archive.
    func composeMonthInMusic() {
        guard !musicReviewBusy else { return }
        let monthKey = String(Date().dayKey.prefix(7))
        let entries = persisted.wireArchive.filter { $0.day.hasPrefix(monthKey) }
        guard !entries.isEmpty else {
            toast("No discoveries on the wire this month yet.")
            return
        }
        musicReviewBusy = true
        Task {
            defer { musicReviewBusy = false }
            let lines = entries.map { entry -> String in
                let verdict = entry.verdict == "like" ? "liked"
                    : entry.verdict == "pass" ? "passed" : "unjudged"
                return "\(entry.title) — \(entry.artist) (\(verdict))"
            }
            do {
                let column = try await AIDesk.monthInMusic(
                    month: monthKey, entries: lines.joined(separator: "\n"))
                persisted.musicReviews[monthKey] = column
                toast("The month in music is in.")
            } catch {
                toast("The desk couldn't write the column.")
            }
        }
    }

    /// File anything queued from the share sheet into the right desk.
    func absorbSharedCaptures() {
        for item in SharedCaptures.drain() {
            addCapture(kind: CaptureKind(rawValue: item.kind) ?? .task,
                       title: item.title, url: item.url, note: item.note)
        }
    }

    /// Apply check-offs made from the home-screen widget while the
    /// app was closed, then republish so both sides agree.
    func absorbWidgetActions() {
        let queued = WidgetActions.drain()
        guard !queued.isEmpty else { return }
        for (id, done) in queued {
            persisted.tasks[id] = done
            if persisted.focusTaskID == id, done {
                persisted.focusTaskID = nil
            }
        }
    }

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

    func addCapture(kind: CaptureKind, title: String, url: String?, note: String?, imageFile: String? = nil) {
        switch kind {
        case .job:
            persisted.applications.insert(
                JobApplication(organization: title, role: note?.nilIfEmpty ?? "Role TBD",
                               url: url, status: .interested, nextStep: "Qualify this lead"),
                at: 0
            )
            CaptureImages.delete(imageFile)      // pipeline entries don't carry photos
            toast("Added to the job pipeline.")
        case .reading:
            persisted.readingQueue.insert(ReadingItem(title: title, url: url), at: 0)
            CaptureImages.delete(imageFile)
            toast("Saved to your reading queue.")
        default:
            persisted.captures.insert(
                CaptureItem(kind: kind, title: title, url: url, note: note, imageFile: imageFile),
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
        if let item = persisted.captures.first(where: { $0.id == id }) {
            CaptureImages.delete(item.imageFile)
        }
        persisted.captures.removeAll { $0.id == id }
    }

    // MARK: Applications

    /// The Landed sheet is the pipeline's source of truth when it's live;
    /// the manual tracker only counts for itself when Landed is dark.
    private var landedOpenRoles: [LandedRole] {
        landedRoles.filter { role in
            !["closed", "rejected", "declined", "withdrawn"].contains {
                role.status.lowercased().contains($0)
            }
        }
    }

    var applicationsActive: Int {
        landedRoles.isEmpty
            ? persisted.applications.filter { $0.status != .closed }.count
            : landedOpenRoles.count
    }

    var applicationsInterviews: Int {
        landedRoles.isEmpty
            ? persisted.applications.filter { $0.status == .interview }.count
            : landedOpenRoles.filter { $0.stageRank <= 2 }.count
    }

    var applicationsFollowUps: Int {
        landedRoles.isEmpty
            ? persisted.applications.filter { $0.status == .followUp }.count
            : landedOpenRoles.filter { !$0.nextAction.isEmpty }.count
    }

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

    func toggleSprint(_ id: String) {
        persisted.sprint[id] = !(persisted.sprint[id] ?? false)
        updateSprintLedger()
    }

    func sprintNote(_ id: String) -> String { persisted.sprintNotes[id] ?? "" }

    func setSprintNote(_ id: String, _ note: String) {
        persisted.sprintNotes[id] = note.nilIfEmpty
        if persisted.sprintNotes[id] == nil { persisted.sprintNotes.removeValue(forKey: id) }
    }

    var sprintPercent: Int {
        let total = SprintMilestone.defaults.count
        guard total > 0 else { return 0 }
        let done = SprintMilestone.defaults.filter { sprintDone($0.id) }.count
        return Int((Double(done) / Double(total) * 100).rounded())
    }

    var sprintLedgerBusy = false

    /// The desk rewrites the sprint ledger from the current checks and
    /// notes — called after every toggle and note commit, so there's
    /// always a record of what the checkmarks meant.
    func updateSprintLedger() {
        guard AIService.isConfigured else { return }
        sprintLedgerBusy = true
        let lines = SprintMilestone.defaults.map { milestone in
            let mark = sprintDone(milestone.id) ? "[done]" : "[open]"
            let note = sprintNote(milestone.id)
            return "\(mark) \(milestone.title)\(note.isEmpty ? "" : " — notes: \(note)")"
        }.joined(separator: "\n")
        Task {
            defer { sprintLedgerBusy = false }
            if let text = try? await AIDesk.sprintLedger(
                state: lines, percent: sprintPercent, previous: persisted.sprintLedger) {
                persisted.sprintLedger = text
                persisted.sprintLedgerAt = Date()
            }
        }
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

    /// Sprint milestones checked this week double as the Veraya score.
    private var autoVerayaProofs: Int {
        SprintMilestone.defaults.filter { sprintDone($0.id) }.count
    }

    func score(_ key: String) -> Int {
        let manual = persisted.weeklyScores[key] ?? 0
        switch key {
        case "fitness": return max(manual, autoFitnessDays)
        case "jobs": return max(manual, autoJobTouches)
        case "veraya": return max(manual, autoVerayaProofs)
        default: return manual
        }
    }

    /// Whether this category currently shows an automatic reading.
    func scoreIsAuto(_ key: String) -> Bool {
        switch key {
        case "fitness": return autoFitnessDays > (persisted.weeklyScores[key] ?? 0)
        case "jobs": return autoJobTouches > (persisted.weeklyScores[key] ?? 0)
        case "veraya": return autoVerayaProofs > (persisted.weeklyScores[key] ?? 0)
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
            // A fresh grant may be the first with playlist scopes — retry
            // today's wire sync right away instead of waiting for tomorrow.
            UserDefaults.standard.removeObject(forKey: "daymark-wire-synced-day")
            UserDefaults.standard.removeObject(forKey: Self.wireGateKey)
            await refreshDiscovery()
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
            landedError = nil
            updateJobTouches()
        } catch let error as LandedFetchError {
            landedStatus = degrade(landedStatus)
            landedError = error.readable
        } catch let error as URLError where error.code == .cancelled {
            // A dismissed pull-to-refresh cancels in-flight requests;
            // that's not a failure worth wearing. Try again quietly.
            if landedRoles.isEmpty { landedStatus = .checking }
        } catch is CancellationError {
            if landedRoles.isEmpty { landedStatus = .checking }
        } catch {
            landedStatus = degrade(landedStatus)
            landedError = error.localizedDescription
        }
    }

    // MARK: Landed write-back

    static let landedStages = ["Interested", "Applied", "Screen", "Interview", "Offer", "Closed"]

    var landedWriting = false

    private func landedDataRow(_ role: LandedRole) -> Int? {
        Int(role.id.dropFirst())
    }

    func updateLandedStatus(_ role: LandedRole, to status: String) {
        guard let row = landedDataRow(role), !landedWriting else { return }
        landedWriting = true
        Task {
            defer { landedWriting = false }
            do {
                try await google.updateLandedCell(
                    sheetID: AppConfig.landedSheetID, dataRow: row, column: "H", value: status)
                toast("\(role.company): \(status).")
                await refreshLanded()
            } catch let error as LandedFetchError where error.status == 403 {
                toast("Google needs edit access — disconnect and reconnect Google in Settings.")
            } catch {
                toast("The sheet didn't take it: \(error.localizedDescription)")
            }
        }
    }

    func updateLandedNextAction(_ role: LandedRole, to next: String) {
        guard let row = landedDataRow(role), !landedWriting else { return }
        landedWriting = true
        Task {
            defer { landedWriting = false }
            do {
                try await google.updateLandedCell(
                    sheetID: AppConfig.landedSheetID, dataRow: row, column: "K", value: next)
                toast("Next action noted for \(role.company).")
                await refreshLanded()
            } catch let error as LandedFetchError where error.status == 403 {
                toast("Google needs edit access — disconnect and reconnect Google in Settings.")
            } catch {
                toast("The sheet didn't take it: \(error.localizedDescription)")
            }
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

        // Ghost tracker: stamp a last-touched date per role whenever its
        // fingerprint changes; first sighting counts as a touch.
        var stamps = (defaults.dictionary(forKey: "daymark-jobtouch-stamps") as? [String: Double]) ?? [:]
        var lastPrints = (defaults.dictionary(forKey: "daymark-jobtouch-lastprints") as? [String: String]) ?? [:]
        let now = Date().timeIntervalSince1970
        for (key, print) in fingerprints where lastPrints[key] != print {
            stamps[key] = now
            lastPrints[key] = print
        }
        defaults.set(stamps, forKey: "daymark-jobtouch-stamps")
        defaults.set(lastPrints, forKey: "daymark-jobtouch-lastprints")
        roleTouchStamps = stamps
    }

    var roleTouchStamps: [String: Double] = [:]

    /// Days since this Landed role last changed in the sheet.
    func daysSinceTouch(_ role: LandedRole) -> Int? {
        guard let stamp = roleTouchStamps[role.company + "|" + role.role] else { return nil }
        return Int(Date().timeIntervalSince1970 - stamp) / 86400
    }

    /// A role has gone cold: active stage, untouched for 10+ days.
    func isGhosting(_ role: LandedRole) -> Bool {
        guard role.stageRank <= 4, let days = daysSinceTouch(role) else { return false }
        return days >= 10
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

        // A target bump (10 → 20) invalidates the day's cache so the
        // fuller wire arrives immediately, not tomorrow.
        let wireTarget = 20
        if !force,
           defaults.string(forKey: Self.discoveryDayKey) == Date().dayKey,
           defaults.integer(forKey: "daymark-discovery-target") == wireTarget,
           let data = defaults.data(forKey: Self.discoveryCacheKey),
           let cached = try? JSONDecoder().decode([DiscoveryTrack].self, from: data),
           !cached.isEmpty {
            discoveryWire = cached
            if case .idle = discoveryStatus { discoveryStatus = .live(Date()) }
            syncWirePlaylistIfNeeded(cached)
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
            exclude: exclude,
            count: wireTarget
        )
        guard !wire.isEmpty else {
            discoveryStatus = degrade(discoveryStatus)
            return
        }
        discoveryWire = wire
        discoveryStatus = .live(Date())
        defaults.set(Date().dayKey, forKey: Self.discoveryDayKey)
        defaults.set(wireTarget, forKey: "daymark-discovery-target")
        defaults.set(try? JSONEncoder().encode(wire), forKey: Self.discoveryCacheKey)
        defaults.set(surfaced + wire.map { $0.artist.lowercased() }, forKey: Self.discoverySurfacedKey)

        archiveWire(wire)
        syncWirePlaylistIfNeeded(wire)
    }

    /// The Wire Archive — every discovery that ever crossed the wire,
    /// with the verdicts, kept in Daymark since Spotify won't host it.
    private func archiveWire(_ wire: [DiscoveryTrack]) {
        let day = Date().dayKey
        let seen = Set(persisted.wireArchive
            .filter { $0.day == day }
            .map { $0.artist.lowercased() + "|" + $0.title.lowercased() })
        for track in wire {
            let key = track.artist.lowercased() + "|" + track.title.lowercased()
            guard !seen.contains(key) else { continue }
            persisted.wireArchive.append(WireArchiveEntry(
                day: day, title: track.title, artist: track.artist, reason: track.reason))
        }
        // Keep roughly two months of history.
        if persisted.wireArchive.count > 1200 {
            persisted.wireArchive.removeFirst(persisted.wireArchive.count - 1200)
        }
    }

    private func setWireVerdict(_ track: DiscoveryTrack, verdict: String) {
        if let index = persisted.wireArchive.lastIndex(where: {
            $0.artist.caseInsensitiveCompare(track.artist) == .orderedSame &&
            $0.title.caseInsensitiveCompare(track.title) == .orderedSame
        }) {
            persisted.wireArchive[index].verdict = verdict
        }
    }

    /// Mirror today's wire into its Spotify playlist, once per day —
    /// also retried from the cached path, so connecting Spotify (or
    /// granting the playlist scopes) later in the day still fills it.
    /// Fire and forget; a miss never degrades the wire itself.
    static let wireGateKey = "daymark-wire-playlist-gated"

    private func syncWirePlaylistIfNeeded(_ wire: [DiscoveryTrack]) {
        let syncKey = "daymark-wire-synced-day"
        // Spotify's dev-mode gate forbids all playlist writes for this
        // app; once detected, stand down instead of failing daily. A
        // reconnect clears the flag and probes again.
        guard !UserDefaults.standard.bool(forKey: Self.wireGateKey) else { return }
        guard UserDefaults.standard.string(forKey: syncKey) != Date().dayKey else { return }
        Task {
            do {
                let count = try await spotify.syncDiscoveryWirePlaylist(
                    tracks: wire.map { (title: $0.title, artist: $0.artist) })
                if count > 0 {
                    UserDefaults.standard.set(Date().dayKey, forKey: syncKey)
                    toast("Discovery Wire playlist updated — \(count) tracks.")
                } else {
                    toast("Wire playlist: none of today's tracks matched on Spotify.")
                }
            } catch let error as SpotifyAPIError {
                if error.status == 403 {
                    UserDefaults.standard.set(true, forKey: Self.wireGateKey)
                    toast("Spotify blocks playlist writes for this app — use ▶ Play the wire instead.")
                } else {
                    toast(error.readable)
                }
            } catch HTTPError.status(let code) {
                toast("Wire playlist sync failed — Spotify error \(code).")
            } catch {
                toast("Wire playlist sync failed: \(error.localizedDescription)")
            }
        }
    }

    var wireQueueBusy = false

    /// Send the whole wire to the Spotify queue so it plays straight
    /// through — the route around the playlist API's dev-mode gate.
    func playWire() {
        guard spotifyConnected, !discoveryWire.isEmpty, !wireQueueBusy else { return }
        wireQueueBusy = true
        Task {
            defer { wireQueueBusy = false }
            do {
                let queued = try await spotify.queueWire(
                    tracks: discoveryWire.map { (title: $0.title, artist: $0.artist) })
                toast(queued > 0
                      ? "Queued \(queued) wire tracks in Spotify."
                      : "None of today's wire matched on Spotify.")
            } catch let error as SpotifyAPIError where error.status == 404 {
                toast("No active Spotify device — play anything in Spotify first, then tap again.")
            } catch let error as SpotifyAPIError {
                toast(error.readable)
            } catch {
                toast("Couldn't queue the wire: \(error.localizedDescription)")
            }
        }
    }

    func discoveryLike(_ track: DiscoveryTrack) {
        let key = track.artist.lowercased()
        if !persisted.musicLikes.contains(key) { persisted.musicLikes.append(key) }
        persisted.musicPasses.removeAll { $0 == key }
        setWireVerdict(track, verdict: "like")
        Task {
            if let added = try? await spotify.addToDiscoveries(title: track.title, artist: track.artist), added {
                toast("Filed to Daymark Discoveries.")
            } else {
                toast("Noted — more like \(track.artist).")
            }
        }
    }

    func discoveryPass(_ track: DiscoveryTrack) {
        let key = track.artist.lowercased()
        if !persisted.musicPasses.contains(key) { persisted.musicPasses.append(key) }
        persisted.musicLikes.removeAll { $0 == key }
        setWireVerdict(track, verdict: "pass")
        discoveryWire.removeAll { $0.id == track.id }
        // Rewrite the day's cache, or the next refresh resurrects the track.
        UserDefaults.standard.set(try? JSONEncoder().encode(discoveryWire),
                                  forKey: Self.discoveryCacheKey)
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
            } catch let error as AIError {
                toast(error.readable)
            } catch {
                toast("The AI desk didn't answer: \(error.localizedDescription)")
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

    var aiPrep: [String: String] = [:]        // role key -> primer
    var aiFollowUp: [String: String] = [:]    // role key -> draft

    /// Keyed variant of runAI for per-role outputs.
    private func runAIKeyed(slot: String, work: @escaping () async throws -> String, apply: @escaping (String) -> Void) {
        guard AIService.isConfigured, !aiBusy.contains(slot) else { return }
        aiBusy.insert(slot)
        Task {
            defer { aiBusy.remove(slot) }
            do {
                apply(try await work())
            } catch let error as AIError {
                toast(error.readable)
            } catch {
                toast("The AI desk didn't answer: \(error.localizedDescription)")
            }
        }
    }

    func runInterviewPrep(_ role: LandedRole) {
        let key = role.company + "|" + role.role
        let recentNews = news.prefix(6).map(\.title).joined(separator: "\n")
        runAIKeyed(slot: "prep-\(key)") {
            try await AIDesk.interviewPrep(
                company: role.company, role: role.role, stage: role.status,
                track: role.track, notes: role.notes, headlines: recentNews)
        } apply: { [weak self] text in
            self?.aiPrep[key] = text
        }
    }

    func runFollowUp(_ role: LandedRole) {
        let key = role.company + "|" + role.role
        let days = daysSinceTouch(role) ?? 0
        runAIKeyed(slot: "follow-\(key)") {
            try await AIDesk.followUpDraft(
                company: role.company, role: role.role, stage: role.status,
                contact: role.contact, daysSinceTouch: days)
        } apply: { [weak self] text in
            self?.aiFollowUp[key] = text
        }
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
