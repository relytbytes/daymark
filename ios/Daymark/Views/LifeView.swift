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
    @State private var showSky = false

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: "Section C · Durham", showSettings: $showSettings) {
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

            weatherFeature
            hourlyStrip
            aroundTown
            bullsSection
            remindersSection
        }
        .sheet(item: $openURLItem) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showSky) {
            SkyView()
        }
    }

    // MARK: Weather feature

    private var weatherFeature: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WEATHER").kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                Spacer()
                AgeStamp(status: app.weatherStatus)
            }
            .padding(.bottom, 6)

            if let weather = app.weather {
                Button {
                    showSky = true
                } label: {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(weather.tempF)°")
                                .font(DS.display(56))
                                .foregroundStyle(Palette.ink)
                            Text("\(weather.description)\(abs(weather.feels - weather.tempF) >= 3 ? " · feels \(weather.feels)°" : "")")
                                .font(DS.label(12, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x4A4940))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            detailLine("H \(weather.high) · L \(weather.low)")
                            detailLine("Rain \(weather.rainPct)%")
                            detailLine("Sunset \(weather.sunset.clockText())")
                            Text("FULL SKY DESK ↗")
                                .kickerStyle(Palette.coral, size: 8, tracking: 1.1)
                                .padding(.top, 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            } else {
                EmptyNote(text: app.weatherStatus == .unavailable
                          ? "Could not reach the weather source. It will retry quietly."
                          : "Checking Durham weather…")
            }
            Hairline()
        }
        .padding(.top, 22)
    }

    private func detailLine(_ text: String) -> some View {
        Text(text)
            .font(DS.label(11, weight: .bold))
            .foregroundStyle(Palette.subtle)
    }

    // MARK: Hourly strip

    @ViewBuilder
    private var hourlyStrip: some View {
        if let weather = app.weather, !weather.hourly.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(weather.hourly) { hour in
                        VStack(spacing: 6) {
                            Text(hour.time.clockText())
                                .kickerStyle(Palette.subtle, size: 8, tracking: 0.6)
                            Image(systemName: weatherSymbol(hour.code))
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.gold)
                            Text("\(hour.temp)°")
                                .font(DS.display(15))
                                .foregroundStyle(Palette.ink)
                            Text(hour.precip > 0 ? "\(hour.precip)%" : " ")
                                .font(DS.label(8.5, weight: .bold))
                                .foregroundStyle(Palette.blue)
                        }
                        .frame(width: 56)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(alignment: .bottom) { Hairline() }
        }
    }

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
                mapChip("Open houses", query: "open houses")
                mapChip("Trails", query: "hiking trails")
                mapChip("Dinner", query: "dinner restaurants")
            }
            .padding(.top, 12)
        }
        .padding(.top, 26)
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
                gameBox(game, headline: "Durham Bulls", status: app.bullsStatus)
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
                EmptyNote(text: "Nothing practical is nagging. Capture the thing that cannot slip.")
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
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.ink))
    }
}
