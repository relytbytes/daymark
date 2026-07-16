//
//  MoreView.swift
//  Daymark
//
//  Section D · Arts & Media: the news brief, markets, the D-backs,
//  Spotify, and the reading queue.
//

import SwiftUI
import UIKit

struct MoreView: View {
    @Environment(AppState.self) private var app
    @Binding var showSettings: Bool
    @State private var openURLItem: SheetLink?
    @State private var standingsView = "division"

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: "Section D · Arts & Media", showSettings: $showSettings) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Masthead(
                        dateline: context.date.dateline(),
                        phaseLabel: phase.label,
                        accent: phase.accent,
                        title: Text("More")
                    )
                    GlanceRibbon(cells: app.glanceMore())
                }
            }

            newsSection
            marketsSection
            sportsSection
            spotifySection
            readingSection
            watchSection
        }
        .sheet(item: $openURLItem) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }

    // MARK: News brief

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "The Brief")
            }
            .padding(.bottom, 4)

            if app.news.isEmpty {
                HStack {
                    EmptyNote(text: app.newsStatus == .unavailable
                              ? "Feeds unreachable — the brief will retry quietly."
                              : "Assembling the headlines…")
                    AgeStamp(status: app.newsStatus)
                }
            } else {
                ForEach(app.news.prefix(10)) { article in
                    VStack(spacing: 0) {
                        Hairline()
                        Button {
                            openURLItem = SheetLink(url: article.link)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(article.source.uppercased())
                                        .kickerStyle(Palette.coral, size: 8, tracking: 1.2)
                                    Spacer()
                                    if let published = article.published {
                                        Text(relativeAge(published))
                                            .font(DS.label(9.5, weight: .semibold))
                                            .foregroundStyle(Palette.subtle)
                                    }
                                }
                                Text(article.title)
                                    .font(DS.deck(16, weight: 500, italic: false))
                                    .foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Hairline()
            }
        }
        .padding(.top, 24)
    }

    // MARK: Markets

    private var marketsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "Markets")
            }
            .padding(.bottom, 12)

            if app.markets.isEmpty {
                HStack {
                    EmptyNote(text: "Quotes unavailable right now.")
                    AgeStamp(status: app.marketsStatus)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(app.markets.prefix(4).enumerated()), id: \.element.id) { index, quote in
                        if index > 0 {
                            Rectangle().fill(Palette.hairlineSoft)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .padding(.vertical, 4)
                        }
                        VStack(spacing: 4) {
                            Text(quote.label.uppercased())
                                .kickerStyle(Palette.subtle, size: 7.5, tracking: 0.8)
                                .lineLimit(1)
                            Text(String(format: "%+.2f%%", quote.changePct))
                                .font(DS.display(18))
                                .foregroundStyle(quote.isUp ? Palette.green : Palette.down)
                            Text(formatPrice(quote.price))
                                .font(DS.label(9.5, weight: .semibold))
                                .foregroundStyle(Palette.subtle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                Text("DAILY CLOSES · STOOQ · DELAYED")
                    .kickerStyle(Palette.subtle, size: 7, tracking: 1.2)
                    .padding(.top, 6)
            }
        }
        .padding(.top, 26)
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 2
        formatter.minimumFractionDigits = value >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    // MARK: Sports

    private var sportsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "Box Score")
            }
            .padding(.bottom, 12)

            if let game = app.dbacksGame {
                gameBox(game, headline: "Diamondbacks", status: app.baseballStatus)
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
                    }
                    .padding(.vertical, 9)
                }
            }
            Hairline()
        }
    }

    // MARK: Spotify

    private var spotifySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "Now Playing")
            }
            .padding(.bottom, 12)

            if !app.spotifyConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bring Spotify into the brief")
                        .font(DS.label(14, weight: .semibold))
                    Text("See what's playing, control the active device, and keep your recent listening at hand.")
                        .font(DS.label(12, weight: .regular))
                        .foregroundStyle(Palette.muted)
                    AcidButton(label: "Connect Spotify", systemImage: "music.note") {
                        Task { await app.connectSpotify() }
                    }
                }
                .editorialPanel()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let playback = app.playback {
                        HStack(spacing: 12) {
                            AsyncImage(url: playback.artURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Palette.paperDeep)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(playback.isPlaying ? "PLAYING" : "PAUSED")
                                    .font(.system(size: 8, weight: .black)).tracking(1.2)
                                    .foregroundStyle(Palette.coral)
                                Text(playback.track)
                                    .font(DS.label(14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text(playback.artist + (playback.deviceName.map { " · \($0)" } ?? ""))
                                    .font(DS.label(11, weight: .regular))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        HStack(spacing: 18) {
                            controlButton("backward.fill") { app.spotifyControl(.previous) }
                            controlButton(playback.isPlaying ? "pause.fill" : "play.fill") {
                                app.spotifyControl(playback.isPlaying ? .pause : .play)
                            }
                            controlButton("forward.fill") { app.spotifyControl(.next) }
                            Spacer()
                            Button {
                                if let url = URL(string: "spotify:") { UIApplication.shared.open(url) }
                            } label: {
                                Text("Open Spotify")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    } else {
                        Text("Nothing playing — recent listening below.")
                            .font(DS.label(12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }

                    if !app.recentTracks.isEmpty {
                        Hairline()
                        ForEach(app.recentTracks.prefix(4)) { track in
                            HStack(spacing: 9) {
                                Circle().fill(Palette.coral.opacity(0.85)).frame(width: 5, height: 5)
                                Text(track.track)
                                    .font(DS.label(12, weight: .medium))
                                    .foregroundStyle(Palette.ink.opacity(0.9))
                                    .lineLimit(1)
                                Text("· \(track.artist)")
                                    .font(DS.label(11, weight: .regular))
                                    .foregroundStyle(Palette.subtle)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                }
                .editorialPanel()
            }
        }
        .padding(.top, 26)
    }

    private func controlButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Palette.wash))
                .overlay(Circle().stroke(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Reading

    private var readingSection: some View {
        let queue = app.persisted.readingQueue.filter { !$0.done }
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Reading List")
                .padding(.bottom, 4)

            if queue.isEmpty {
                EmptyNote(text: "The queue is clear. Save a link from Capture and it lands here.")
            } else {
                ForEach(queue) { item in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            Button {
                                if let raw = item.url, let url = URL(string: raw) {
                                    openURLItem = SheetLink(url: url)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(DS.label(14, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Text("saved \(relativeAge(item.savedAt))"
                                         + ((item.url?.nilIfEmpty.flatMap { URL(string: $0)?.host }).map { " · \($0)" } ?? ""))
                                        .font(DS.label(10.5, weight: .regular))
                                        .foregroundStyle(Palette.subtle)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            CircleCheck(checked: false) { app.toggleReading(item.id) }
                        }
                        .padding(.vertical, 12)
                    }
                    .contextMenu {
                        Button(role: .destructive) { app.removeReading(item.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Hairline()
            }

            // standing sources
            HStack(spacing: 8) {
                QuietButton(label: "Jacobin") { openURLItem = URL(string: "https://jacobin.com/").map { SheetLink(url: $0) } }
                QuietButton(label: "Longreads") { openURLItem = URL(string: "https://longreads.com/").map { SheetLink(url: $0) } }
                QuietButton(label: "n+1") { openURLItem = URL(string: "https://www.nplusonemag.com/online-only/").map { SheetLink(url: $0) } }
            }
            .padding(.top, 12)
        }
        .padding(.top, 26)
    }

    // MARK: Watch lanes

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Watch With Intent")
                .padding(.bottom, 12)
            HStack(spacing: 8) {
                watchChip("Chelsea", query: "Chelsea FC analysis")
                watchChip("D-backs", query: "Arizona Diamondbacks analysis")
                watchChip("Design", query: "modern product design documentary")
                watchChip("History", query: "history documentary long form")
            }
        }
        .padding(.top, 26)
    }

    private func watchChip(_ label: String, query: String) -> some View {
        QuietButton(label: label) {
            let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            if let url = URL(string: "https://www.youtube.com/results?search_query=\(q)") {
                UIApplication.shared.open(url)
            }
        }
    }
}

/// Small official team mark for standings rows.
struct StandingLogo: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Circle().fill(Palette.paperDeep)
                }
            } else {
                Circle().fill(Palette.paperDeep)
            }
        }
        .frame(width: 20, height: 20)
    }
}
