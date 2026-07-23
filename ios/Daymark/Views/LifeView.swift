//
//  LifeView.swift
//  Daymark
//
//  Section C · Durham: the weather feature, the hourly strip, around town,
//  the Bulls, and practical reminders.
//

import SwiftUI
import UIKit
import PhotosUI

struct LifeView: View {
    @Environment(AppState.self) private var app
    @Binding var showSettings: Bool
    @State private var openURLItem: SheetLink?
    @State private var mapQuery = ""
    @State private var showThermostat = false
    @State private var standingsView = "division"
    @State private var addingPlant = false
    @State private var plantName = ""
    @State private var plantNote = ""
    @State private var plantDays = 7
    @State private var openPlant: UUID?

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: "Section D · Durham", showSettings: $showSettings, index: [
            (label: "Home", anchor: "life-home"),
            (label: "Garden", anchor: "life-garden"),
            (label: "Training", anchor: "life-training"),
            (label: "Durham", anchor: "life-durham"),
            (label: "Scoreboard", anchor: "life-scoreboard"),
            (label: "Spirit", anchor: "life-spirit"),
        ]) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Masthead(
                        dateline: context.date.dateline(),
                        phaseLabel: phase.label,
                        accent: phase.accent,
                        title: Text("Life")
                    )
                    GlanceRibbon(cells: app.glanceLife())
                }
            }

            homeDesk.id("life-home")
            gardenBench.id("life-garden")
            trainingDesk.id("life-training")
            aroundTown.id("life-durham")
            remindersSection
            sportsSection.id("life-scoreboard")
            bullsSection
            SpiritSectionsView().id("life-spirit")
        }
        .scrollDismissesKeyboard(.immediately)
        // Tapping anywhere outside a field drops the keyboard;
        // simultaneous so buttons and links keep working.
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
        .sheet(item: $openURLItem) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showThermostat) {
            ThermostatSheet()
                .presentationDetents([.medium, .large])
        }
        .onChange(of: app.thermostatRequested) { _, requested in
            if requested {
                showThermostat = true
                app.thermostatRequested = false
            }
        }
        .sheet(item: Binding(
            get: { openPlant.map { PlantSheetTarget(id: $0) } },
            set: { openPlant = $0?.id }
        )) { target in
            PlantSheet(plantID: target.id)
        }
        .alert("New plant", isPresented: $addingPlant) {
            TextField("Name (Monstera, tomatoes…)", text: $plantName)
            TextField("Note (window, porch…)", text: $plantNote)
            Button("Every 3 days") { savePlant(days: 3) }
            Button("Weekly") { savePlant(days: 7) }
            Button("Every 2 weeks") { savePlant(days: 14) }
            Button("Cancel", role: .cancel) { plantName = ""; plantNote = "" }
        } message: {
            Text("Pick the watering cadence.")
        }
    }

    private func savePlant(days: Int) {
        guard let name = plantName.nilIfEmpty else { return }
        app.addPlant(name: name, note: plantNote, everyDays: days)
        plantName = ""
        plantNote = ""
    }

    // MARK: The Home Desk (Nest, in its own quarters)

    @ViewBuilder
    private var homeDesk: some View {
        if let nest = app.nestReading {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("THE HOME DESK").kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                    Spacer()
                    Text(nest.roomName.uppercased())
                        .kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                }
                .padding(.bottom, 8)

                Button {
                    showThermostat = true
                } label: {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(nest.indoorF)°")
                                .font(DS.display(40))
                                .foregroundStyle(Palette.ink)
                            Text(nest.hvacActive
                                 ? "\(nest.mode.capitalized) running"
                                 : (nest.mode == "OFF" ? "System off" : "\(nest.mode.capitalized) · idle"))
                                .font(DS.label(11, weight: .semibold))
                                .foregroundStyle(nest.hvacActive ? Palette.coral : Palette.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            if let setpoint = nest.setpointF { detailLine("Set to \(setpoint)°") }
                            if let humidity = nest.humidity { detailLine("\(humidity)% humidity") }
                            detailLine(nest.fanRunning ? "Fan on" : "Fan auto")
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .editorialPanel(padding: 14)
            }
            .padding(.top, 22)
        }
    }

    // MARK: Training desk (live from Cadence's app group)

    @ViewBuilder
    private var trainingDesk: some View {
        if let cadence = app.cadence {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionRuleHeader(title: "The Training Desk")
                    Text("CADENCE · WK \(cadence.wk)")
                        .kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                }
                .padding(.bottom, 10)

                readinessLine
                    .padding(.bottom, 10)

                VStack(spacing: 10) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", cadence.w))
                            .font(DS.display(30))
                            .foregroundStyle(Palette.ink)
                        Text(String(format: "%+.1f LB/WK", cadence.delta))
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(cadence.delta <= 0 ? Palette.green : Palette.coral)
                        Spacer()
                        StatusChip(text: "\(cadence.streak)-day streak",
                                   foreground: Color(hex: 0x0E7A54), background: Palette.greenSoft)
                    }

                    HStack(spacing: 8) {
                        workoutChip("AM", title: cadence.amT, done: cadence.amDone)
                        workoutChip("PM", title: cadence.pmT, done: cadence.pmDone)
                    }

                    HStack(spacing: 0) {
                        fuelCell("CAL", cadence.cal, cadence.calT)
                        fuelDivider
                        fuelCell("PROTEIN", cadence.pro, cadence.proT)
                        fuelDivider
                        fuelCell("WATER", cadence.water, cadence.waterT)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .top) { Hairline() }
                }
                .editorialPanel(padding: 14)
            }
            .padding(.top, 24)
        }
    }

    /// Last night, against your own baselines — the go/easy signal.
    @ViewBuilder
    private var readinessLine: some View {
        if let readiness = app.readiness {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(readiness.score >= 2 ? Palette.green
                          : readiness.score >= 0 ? Palette.gold : Palette.coral)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(readiness.verdict.uppercased())
                        .kickerStyle(readiness.score >= 2 ? Palette.green
                                     : readiness.score >= 0 ? Palette.gold : Palette.coral,
                                     size: 8.5, tracking: 1.2)
                    Text(readiness.line)
                        .font(DS.label(12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(10)
            .background(Palette.wash)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// The Garden Bench: what needs water, and when.
    @ViewBuilder
    private var gardenBench: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "The Garden Bench")
                if app.plantsDue > 0 {
                    StatusChip(text: "\(app.plantsDue) due", foreground: .white, background: Palette.coral)
                }
            }
            .padding(.bottom, 8)

            if app.persisted.plants.isEmpty {
                Button {
                    addingPlant = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.green)
                        Text("No plants on file — tap to plant the first one.")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                if let watch = app.gardenWatch {
                    Text(watch)
                        .font(DS.label(11, weight: .semibold))
                        .foregroundStyle(watch.hasPrefix("Frost") ? Palette.blue : Palette.coral)
                        .padding(.bottom, 6)
                }
                if let weather = app.weather, app.plantsDue > 0, weather.rainPct >= 60 {
                    Text("Rain likely today (\(weather.rainPct)%) — the outdoor ones may take care of themselves.")
                        .font(DS.label(11, weight: .medium))
                        .foregroundStyle(Palette.blue)
                        .padding(.bottom, 6)
                }
                ForEach(app.persisted.plants.sorted { $0.daysUntilDue < $1.daysUntilDue }) { plant in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 10) {
                            Button {
                                openPlant = plant.id
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "leaf.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(plant.daysUntilDue <= 0 ? Palette.coral : Palette.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plant.name)
                                            .font(DS.label(13.5, weight: .semibold))
                                            .foregroundStyle(Palette.ink)
                                        Text("every \(plant.waterEveryDays)d · \(plant.dueText)"
                                             + (plant.note.nilIfEmpty.map { " · \($0)" } ?? ""))
                                            .font(DS.label(10.5, weight: .regular))
                                            .foregroundStyle(plant.daysUntilDue <= 0 ? Palette.coral : Palette.subtle)
                                            .lineLimit(1)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            QuietButton(label: plant.daysUntilDue <= 0 ? "Water" : "Watered") {
                                app.waterPlant(plant.id)
                            }
                        }
                        .padding(.vertical, 9)
                        .contextMenu {
                            Button(role: .destructive) {
                                app.removePlant(plant.id)
                            } label: {
                                Label("Remove plant", systemImage: "trash")
                            }
                        }
                    }
                }
                Hairline()
                DeskAction(label: "Add a plant", systemImage: "plus") {
                    addingPlant = true
                }
                .padding(.top, 10)
            }
        }
        .padding(.top, 24)
    }

    private var fuelDivider: some View {
        Rectangle().fill(Palette.hairlineSoft).frame(width: 1).padding(.vertical, 6)
    }

    private func workoutChip(_ slot: String, title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(done ? Palette.green : Palette.subtle)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot).kickerStyle(Palette.subtle, size: 7, tracking: 1.0)
                Text(title)
                    .font(DS.label(11, weight: .semibold))
                    .foregroundStyle(done ? Palette.muted : Palette.ink)
                    .strikethrough(done, color: Palette.subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Palette.wash)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func fuelCell(_ label: String, _ value: Int, _ target: Int) -> some View {
        VStack(spacing: 3) {
            Text(label).kickerStyle(Palette.subtle, size: 7, tracking: 0.9)
            Text("\(value)")
                .font(DS.display(15))
                .monospacedDigit()
                .foregroundStyle(value >= target ? Palette.green : Palette.ink)
            Text("OF \(target)")
                .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func detailLine(_ text: String) -> some View {
        Text(text)
            .font(DS.label(11, weight: .bold))
            .foregroundStyle(Palette.subtle)
    }

    // MARK: Hourly strip

    // MARK: Around town

    private var aroundTown: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Around Town")
                .padding(.bottom, 4)

            linkRow(index: "01", kicker: "Local events · live search",
                    title: "Browse Durham events",
                    url: "https://www.discoverdurham.com/events/")
            linkRow(index: "02", kicker: "The Nasher · official calendar",
                    title: "Exhibitions, talks and events",
                    url: "https://nasher.duke.edu/events/")
            linkRow(index: "03", kicker: "Homes for sale · up to $450k",
                    title: "Browse current Durham listings",
                    url: "https://www.redfin.com/city/4909/NC/Durham/filter/max-price=450k")
            Hairline()

            // Maps quick searches
            HStack(spacing: 7) {
                mapChip("Coffee", query: "coffee shops")
                mapChip("Breweries", query: "breweries")
                mapChip("Trails", query: "hiking trails")
                mapChip("Dinner", query: "dinner restaurants")
            }
            .padding(.top, 12)

            // Free-text search, same destination: Maps near Durham.
            HStack(spacing: 8) {
                TextField("Search the map near Durham…", text: $mapQuery)
                    .font(DS.label(13, weight: .medium))
                    .padding(10)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
                    .submitLabel(.search)
                    .onSubmit { openMapSearch() }
                Button {
                    openMapSearch()
                } label: {
                    Text("GO")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Palette.paper)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(mapQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(.top, 26)
    }

    private func openMapSearch() {
        let trimmed = mapQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        if let url = URL(string: "maps://?q=\(q)&near=Durham,NC") {
            UIApplication.shared.open(url)
        }
    }

    private func linkRow(index: String, kicker: String, title: String, url: String) -> some View {
        VStack(spacing: 0) {
            Hairline()
            Button {
                if let u = URL(string: url) { openURLItem = SheetLink(url: u) }
            } label: {
                HStack(spacing: 13) {
                    Text(index)
                        .font(DS.display(18))
                        .foregroundStyle(Palette.coral)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(kicker.uppercased())
                            .kickerStyle(Palette.subtle, size: 8, tracking: 1.1)
                        Text(title)
                            .font(DS.label(14.5, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xB8B5AD))
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func mapChip(_ label: String, query: String) -> some View {
        QuietButton(label: label) {
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "maps://?q=\(q)&near=Durham,NC") {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: Sports

    private var sportsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "The Scoreboard")
            }
            .padding(.bottom, 12)

            if let game = app.dbacksGame {
                VStack(alignment: .leading, spacing: 0) {
                    gameBox(game, headline: "Diamondbacks", status: app.baseballStatus)
                    BoxScoreGrid(game: game)
                    if let next = app.dbacksNext {
                        UpNextRow(game: next)
                    }
                }
            } else {
                HStack {
                    EmptyNote(text: "No D-backs game in the current window.")
                    AgeStamp(status: app.baseballStatus)
                }
            }

            // Standings toggle
            HStack(spacing: 7) {
                standingsTab("NL West", key: "division")
                standingsTab("Wild Card", key: "wildcard")
                Spacer()
                AgeStamp(status: app.baseballStatus)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)

            let rows = standingsView == "division" ? app.nlWest : app.wildcard
            if rows.isEmpty {
                EmptyNote(text: "Standings will appear when MLB responds.")
            } else {
                standingsTable(rows)
            }
        }
        .padding(.top, 26)
    }

    private func standingsTab(_ label: String, key: String) -> some View {
        let active = standingsView == key
        return Button {
            standingsView = key
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(active ? Palette.card : Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? Palette.ink : Palette.card)
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Palette.line, lineWidth: active ? 0 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 999))
        }
        .buttonStyle(.plain)
    }

    private func standingsTable(_ rows: [StandingRow]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("TEAM").kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                Spacer()
                Text("W–L").kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                    .frame(width: 52, alignment: .trailing)
                Text("PCT").kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                    .frame(width: 44, alignment: .trailing)
                Text("GB").kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                    .frame(width: 36, alignment: .trailing)
                Text("L10").kickerStyle(Palette.subtle, size: 8, tracking: 1.0)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.vertical, 7)
            ForEach(rows) { row in
                VStack(spacing: 0) {
                    Hairline()
                    HStack {
                        StandingLogo(url: row.logoURL)
                        Text(row.name)
                            .font(DS.label(13, weight: row.isDbacks ? .bold : .medium))
                            .foregroundStyle(row.isDbacks ? Palette.coral : Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(row.wins)–\(row.losses)")
                            .font(DS.label(12, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 52, alignment: .trailing)
                        Text(row.pct)
                            .font(DS.label(12, weight: .regular))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 44, alignment: .trailing)
                        Text(row.gamesBack)
                            .font(DS.label(12, weight: .regular))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 36, alignment: .trailing)
                        Text(row.l10)
                            .font(DS.label(12, weight: .regular)).monospacedDigit()
                            .foregroundStyle(Palette.muted)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                }
            }
            Hairline()
        }
    }

    // MARK: Bulls

    private var bullsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "The Bull City")
            }
            .padding(.bottom, 12)

            if let game = app.bullsGame {
                VStack(alignment: .leading, spacing: 0) {
                    gameBox(game, headline: "Durham Bulls", status: app.bullsStatus)
                    BoxScoreGrid(game: game)
                    if let next = app.bullsNext {
                        UpNextRow(game: next)
                    }
                    StandingsTable(rows: app.bullsStandings, title: "IL · SECOND HALF")
                        .padding(.top, 12)
                }
            } else {
                HStack {
                    EmptyNote(text: "No Bulls game found in the current window.")
                    AgeStamp(status: app.bullsStatus)
                }
            }

            HStack(spacing: 10) {
                QuietButton(label: "Bulls schedule") {
                    openURLItem = URL(string: "https://www.milb.com/durham/schedule").map { SheetLink(url: $0) }
                }
                QuietButton(label: "Duke calendar") {
                    openURLItem = URL(string: "https://goduke.com/calendar").map { SheetLink(url: $0) }
                }
                QuietButton(label: "NCCU") {
                    openURLItem = URL(string: "https://nccueaglepride.com/calendar").map { SheetLink(url: $0) }
                }
            }
            .padding(.top, 12)
        }
        .padding(.top, 26)
    }

    // MARK: Practical reminders

    private var remindersSection: some View {
        let reminders = app.persisted.captures.filter { $0.kind == .reminder && !$0.done }
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Practical · Yours")
                .padding(.bottom, 4)
            if reminders.isEmpty {
                Button {
                    app.requestCapture()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.coral)
                        Text("No reminders saved — tap to add one.")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(reminders) { item in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.coral)
                            Text(item.title)
                                .font(DS.label(14, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            CircleCheck(checked: false) { app.toggleCapture(item.id) }
                        }
                        .padding(.vertical, 12)
                    }
                }
                Hairline()
            }
        }
        .padding(.top, 26)
    }
}

// MARK: - Shared game box (elevated scoreboard card)

func gameBox(_ game: GameInfo, headline: String, status: FeedStatus) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack {
            if game.isLive {
                LivePill(text: "Live · \(game.detail)")
            } else {
                Text(game.state == "Final" ? "FINAL" : "UP NEXT")
                    .font(.system(size: 9, weight: .black)).tracking(1.3)
                    .foregroundStyle(Palette.subtle)
                Spacer()
                Text(game.detail.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Palette.subtle)
            }
            if game.isLive { Spacer() }
        }
        .padding(.bottom, 12)

        teamLine(game.away, emphasized: (game.away.score ?? 0) >= (game.home.score ?? 0))
            .padding(.bottom, 9)
        teamLine(game.home, emphasized: (game.home.score ?? 0) >= (game.away.score ?? 0))

        if let venue = game.venue {
            Text(venue.uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Palette.subtle.opacity(0.7))
                .padding(.top, 10)
        }
    }
    .editorialPanel(padding: 15)
}

private func teamLine(_ team: TeamScore, emphasized: Bool) -> some View {
    HStack {
        HStack(spacing: 10) {
            TeamBadge(team: team)
            Text(team.name)
                .font(DS.label(15, weight: emphasized ? .bold : .semibold))
                .foregroundStyle(emphasized ? Palette.ink : Palette.muted)
        }
        Spacer()
        Text(team.score.map(String.init) ?? "—")
            .font(DS.display(22))
            .monospacedDigit()
            .foregroundStyle(emphasized ? Palette.ink : Palette.subtle)
    }
}

/// Team identity mark: official logo when a logo URL is known, monogram fallback.
struct TeamBadge: View {
    let team: TeamScore
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url = team.logoURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    monogram
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
    }

    private var monogram: some View {
        Text(team.abbr.isEmpty ? String(team.name.prefix(3)).uppercased() : team.abbr)
            .font(.system(size: size * 0.32, weight: .heavy))
            .foregroundStyle(Palette.paper)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.ink))
    }
}

// MARK: - The Thermostat: full Nest control

struct ThermostatSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var target: Int = 72

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE THERMOSTAT · NEST")
                        .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                        .padding(.bottom, 8)

                    if let nest = app.nestReading {
                        Text(nest.roomName)
                            .font(DS.display(28))
                            .foregroundStyle(Palette.ink)
                        InkRule().padding(.vertical, 12)

                        // Current conditions
                        HStack(alignment: .lastTextBaseline, spacing: 12) {
                            Text("\(nest.indoorF)°")
                                .font(DS.display(54))
                                .foregroundStyle(Palette.ink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(nest.hvacActive ? "RUNNING" : "IDLE")
                                    .kickerStyle(nest.hvacActive ? Palette.coral : Palette.subtle,
                                                 size: 8.5, tracking: 1.2)
                                if let humidity = nest.humidity {
                                    Text("\(humidity)% humidity")
                                        .font(DS.label(12, weight: .medium))
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                            Spacer()
                        }
                        .padding(.bottom, 18)

                        // Mode
                        Text("MODE").kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                            .padding(.bottom, 6)
                        HStack(spacing: 8) {
                            ForEach(["OFF", "HEAT", "COOL", "HEATCOOL"], id: \.self) { mode in
                                let active = nest.mode == mode
                                Button {
                                    app.nestSetMode(mode)
                                } label: {
                                    Text(mode == "HEATCOOL" ? "AUTO" : mode)
                                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                                        .foregroundStyle(active ? Palette.paper : Palette.ink)
                                        .padding(.horizontal, 13).padding(.vertical, 9)
                                        .background(Capsule().fill(active ? Palette.ink : Palette.wash))
                                        .overlay(Capsule().stroke(Palette.line, lineWidth: active ? 0 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 20)

                        // Setpoint — big controls, exact degree
                        if nest.mode != "OFF" {
                            Text("SET TO").kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                                .padding(.bottom, 6)
                            HStack(spacing: 22) {
                                bigStep("minus") { target = max(55, target - 1) }
                                Text("\(target)°")
                                    .font(DS.display(64))
                                    .foregroundStyle(target > (nest.setpointF ?? target) ? Palette.coral
                                                     : target < (nest.setpointF ?? target) ? Palette.blue
                                                     : Palette.ink)
                                    .monospacedDigit()
                                    .frame(minWidth: 130)
                                bigStep("plus") { target = min(90, target + 1) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                            Button {
                                app.nestSetTemperature(target)
                            } label: {
                                Text(app.nestAdjusting ? "SETTING…" : "SET \(target)°")
                                    .font(.system(size: 12, weight: .heavy)).tracking(1.2)
                                    .foregroundStyle(Palette.paper)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.ink))
                            }
                            .buttonStyle(.plain)
                            .disabled(app.nestAdjusting || target == nest.setpointF)
                            .opacity(target == nest.setpointF ? 0.4 : 1)
                            .padding(.bottom, 20)
                        }

                        // Fan
                        Text("FAN").kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                            .padding(.bottom, 6)
                        HStack(spacing: 8) {
                            if nest.fanRunning {
                                Button {
                                    app.nestFan(on: false)
                                } label: {
                                    Label("Stop fan", systemImage: "fan.slash")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Palette.paper)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(Capsule().fill(Palette.coral))
                                }
                                .buttonStyle(.plain)
                            } else {
                                ForEach([15, 30, 60], id: \.self) { minutes in
                                    Button {
                                        app.nestFan(on: true, minutes: minutes)
                                    } label: {
                                        Label("\(minutes)m", systemImage: "fan")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Palette.ink)
                                            .padding(.horizontal, 13).padding(.vertical, 10)
                                            .background(Capsule().fill(Palette.wash))
                                            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Spacer()
                        }
                        Text(nest.fanRunning
                             ? "The fan is on its timer."
                             : "Nest runs the fan on a timer — pick a duration.")
                            .font(DS.label(10.5, weight: .regular))
                            .foregroundStyle(Palette.subtle)
                            .padding(.top, 8)
                    } else {
                        EmptyNote(text: "No thermostat reading yet — pull to refresh the Life page first.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .onAppear {
                target = app.nestReading?.setpointF ?? 72
            }
        }
    }

    private func bigStep(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Palette.wash))
                .overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The plant file: profile, photo record, and the desk's plan

struct PlantSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let plantID: UUID

    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pendingEventKind: String?
    @State private var eventNote = ""

    private var plant: Plant? {
        app.persisted.plants.first { $0.id == plantID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plant {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("THE PLANT FILE")
                            .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                            .padding(.bottom, 8)
                        Text(plant.name)
                            .font(DS.display(28))
                            .foregroundStyle(Palette.ink)
                        Text("Watering every \(plant.waterEveryDays) days · \(plant.dueText)")
                            .font(DS.label(12, weight: .semibold))
                            .foregroundStyle(plant.daysUntilDue <= 0 ? Palette.coral : Palette.muted)
                            .padding(.top, 4)
                        InkRule().padding(.vertical, 12)

                        // The growth record
                        Text("THE RECORD").kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                            .padding(.bottom, 6)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(plant.photos.sorted { $0.taken > $1.taken }) { photo in
                                    if let image = CaptureImages.load(photo.file) {
                                        VStack(spacing: 3) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 92, height: 92)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            Text(photo.taken.shortDate())
                                                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                                                .foregroundStyle(Palette.subtle)
                                        }
                                    }
                                }
                                VStack(spacing: 6) {
                                    Button { showCamera = true } label: {
                                        photoAddTile(icon: "camera")
                                    }
                                    .buttonStyle(.plain)
                                    PhotosPicker(selection: $libraryItem, matching: .images) {
                                        photoAddTile(icon: "photo.on.rectangle")
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 16)

                        // Profile for the plan
                        Text("THE PROFILE").kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                            .padding(.bottom, 6)
                        VStack(spacing: 8) {
                            profileField("Species (pothos, monstera…)", key: \.species)
                            profileField("Pot & size (8\" terracotta…)", key: \.potSize)
                            profileField("Soil (standard potting mix…)", key: \.soil)
                            profileField("Light (bright indirect, porch sun…)", key: \.light)
                            HStack(spacing: 8) {
                                Button {
                                    app.setPlantOutdoor(plantID, outdoor: false)
                                } label: {
                                    placeChip("Indoors", icon: "house", active: !plant.outdoor)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    app.setPlantOutdoor(plantID, outdoor: true)
                                } label: {
                                    placeChip("Outdoors", icon: "sun.max", active: plant.outdoor)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                if plant.outdoor {
                                    Text("FROST & HEAT WATCH ON")
                                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                                        .foregroundStyle(Palette.subtle)
                                }
                            }
                        }
                        .padding(.bottom, 12)

                        // The journal: the file reads like a growing history
                        Text("THE JOURNAL").kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                            .padding(.bottom, 6)
                        if plant.events.isEmpty {
                            Text("Nothing filed yet — repots, blooms, and feedings live here.")
                                .font(DS.deck(12))
                                .foregroundStyle(Palette.subtle)
                                .padding(.bottom, 8)
                        } else {
                            ForEach(plant.events.sorted { $0.date > $1.date }) { event in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: event.symbol)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.green)
                                        .frame(width: 16)
                                    Text(event.label + (event.note.isEmpty ? "" : " — \(event.note)"))
                                        .font(DS.label(12, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    Spacer()
                                    Text(event.date.shortDate())
                                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                                        .foregroundStyle(Palette.subtle)
                                }
                                .padding(.vertical, 4)
                            }
                            .padding(.bottom, 4)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach([("bloom", "Bloom"), ("repot", "Repot"), ("fertilize", "Fertilize"),
                                         ("harvest", "Harvest"), ("note", "Note")], id: \.0) { kind, label in
                                    QuietButton(label: "+ \(label)") {
                                        pendingEventKind = kind
                                        eventNote = ""
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 14)

                        if app.plantPlanBusy == plantID {
                            HStack(spacing: 10) {
                                ProgressView().controlSize(.small)
                                Text("The desk is writing the plan…")
                                    .font(DS.deck(13))
                                    .foregroundStyle(Palette.muted)
                            }
                        } else {
                            DeskAction(label: plant.plan.isEmpty ? "Compose the watering plan" : "Recompose the plan",
                                       systemImage: "drop.fill") {
                                app.composePlantPlan(plantID)
                            }
                        }

                        if !plant.plan.isEmpty {
                            Text(plant.plan)
                                .font(DS.deck(14))
                                .foregroundStyle(Palette.ink)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .padding(12)
                                .background(Palette.wash)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        app.addPlantPhoto(plantID, image: image)
                    }
                    libraryItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in app.addPlantPhoto(plantID, image: image) }
                    .ignoresSafeArea()
            }
            .alert("File to the journal", isPresented: Binding(
                get: { pendingEventKind != nil },
                set: { if !$0 { pendingEventKind = nil } }
            )) {
                TextField("Note (optional)", text: $eventNote)
                Button("File it") {
                    if let kind = pendingEventKind {
                        app.addPlantEvent(plantID, kind: kind,
                                          note: eventNote.trimmingCharacters(in: .whitespaces))
                    }
                    pendingEventKind = nil
                }
                Button("Cancel", role: .cancel) { pendingEventKind = nil }
            }
        }
    }

    private func placeChip(_ label: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(active ? Palette.ink : Palette.wash)
        .foregroundStyle(active ? Palette.paper : Palette.muted)
        .clipShape(Capsule())
    }

    private func photoAddTile(icon: String) -> some View {
        VStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Palette.green)
        }
        .frame(width: 92, height: 43)
        .background(Palette.wash)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }

    private func profileField(_ placeholder: String, key: WritableKeyPath<Plant, String>) -> some View {
        TextField(placeholder, text: Binding(
            get: { app.persisted.plants.first { $0.id == plantID }?[keyPath: key] ?? "" },
            set: { value in
                if let index = app.persisted.plants.firstIndex(where: { $0.id == plantID }) {
                    app.persisted.plants[index][keyPath: key] = value
                }
            }
        ))
        .font(DS.label(13, weight: .medium))
        .padding(10)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
    }
}


struct PlantSheetTarget: Identifiable {
    let id: UUID
}
