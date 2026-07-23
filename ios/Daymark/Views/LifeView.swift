//
//  LifeView.swift
//  Daymark
//
//  Section C · Durham: the weather feature, the hourly strip, around town,
//  the Bulls, and practical reminders.
//

import SwiftUI
import UIKit

struct LifeView: View {
    @Environment(AppState.self) private var app
    @Binding var showSettings: Bool
    @State private var openURLItem: SheetLink?
    @State private var mapQuery = ""
    @State private var showThermostat = false

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: "Section C · Durham", showSettings: $showSettings, index: [
            (label: "Home", anchor: "life-home"),
            (label: "Sky", anchor: "life-sky"),
            (label: "Durham", anchor: "life-durham"),
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
            SkySectionsView().id("life-sky")
            trainingDesk
            aroundTown.id("life-durham")
            bullsSection
            remindersSection
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
