//
//  MoreView.swift
//  Daymark
//
//  Section E · Media: the news brief, markets, music, and reading.
//

import SwiftUI
import UIKit

struct MoreView: View {
    @Environment(AppState.self) private var app
    @Binding var showSettings: Bool
    @State private var openURLItem: SheetLink?
    @State private var showWireArchive = false

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: "Section E · Media", showSettings: $showSettings, index: [
            (label: "Brief", anchor: "more-news"),
            (label: "Markets", anchor: "more-markets"),
            (label: "Music", anchor: "more-music"),
            (label: "Wire", anchor: "more-wire"),
            (label: "Reading", anchor: "more-reading"),
        ]) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Masthead(
                        dateline: context.date.dateline(),
                        phaseLabel: phase.label,
                        accent: phase.accent,
                        title: Text("Media")
                    )
                    GlanceRibbon(cells: app.glanceMore())
                }
            }

            newsSection.id("more-news")
            marketsSection.id("more-markets")
            spotifySection.id("more-music")
            discoverySection.id("more-wire")
            soundcloudSection
            readingSection.id("more-reading")
            watchSection
        }
        .sheet(item: $openURLItem) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showWireArchive) { WireArchiveView() }
        .sheet(item: Binding(
            get: { app.presentedGist },
            set: { app.presentedGist = $0 }
        )) { gist in
            GistSheet(gist: gist)
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
                ForEach(app.news.prefix(20)) { article in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                openURLItem = SheetLink(url: article.link)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(article.source.uppercased())
                                            .kickerStyle(Palette.coral, size: 8, tracking: 1.2)
                                        if !article.otherSources.isEmpty {
                                            Text("+\(article.otherSources.count) SOURCE\(article.otherSources.count == 1 ? "" : "S")")
                                                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                                                .foregroundStyle(Palette.muted)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Capsule().fill(Palette.wash))
                                                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                                        }
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

                            // One tap files it in the reading queue — no
                            // open-copy-paste-capture dance.
                            Button {
                                app.addCapture(kind: .reading, title: article.title,
                                               url: article.link.absoluteString,
                                               note: article.source)
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Palette.subtle)
                                    .padding(.top, 12)
                            }
                            .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button {
                                app.addCapture(kind: .reading, title: article.title,
                                               url: article.link.absoluteString,
                                               note: article.source)
                            } label: {
                                Label("Read later", systemImage: "book")
                            }
                            Button {
                                openURLItem = SheetLink(url: article.link)
                            } label: {
                                Label("Open", systemImage: "safari")
                            }
                        }
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
                Text("DAILY CLOSES · YAHOO · DELAYED")
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
                Button {
                    app.requestCapture()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.coral)
                        Text("The queue is clear — tap to save something to read.")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                                    if app.todaysReadID == item.id {
                                        Text("TODAY'S READ")
                                            .font(.system(size: 7, weight: .heavy)).tracking(1.0)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Palette.coral)
                                            .clipShape(Capsule())
                                    }
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

extension MoreView {
    // MARK: The Discovery Wire

    @ViewBuilder
    var discoverySection: some View {
        if app.spotifyConnected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionRuleHeader(title: "The Discovery Wire")
                    AgeStamp(status: app.discoveryStatus)
                }
                .padding(.bottom, 4)

                if app.discoveryWire.isEmpty {
                    EmptyNote(text: app.discoveryStatus == .unavailable
                              ? "The wire came back empty — it retries on the next refresh."
                              : "Reading your listening history and walking the artist graph…")
                } else {
                    Text("Twenty for today, seeded by what you actually play. Thumbs teach tomorrow's wire.")
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.bottom, 8)
                    HStack(spacing: 8) {
                        QuietButton(label: app.wireQueueBusy ? "Queueing…" : "▶ Play the wire") {
                            app.playWire()
                        }
                        .disabled(app.wireQueueBusy)
                        if !app.persisted.wireArchive.isEmpty {
                            QuietButton(label: "The archive") { showWireArchive = true }
                        }
                        Spacer()
                    }
                    .padding(.bottom, 6)
                    ForEach(app.discoveryWire) { track in
                        discoveryRow(track)
                    }
                    Hairline()
                }
            }
            .padding(.top, 26)
        }
    }

    private func discoveryRow(_ track: DiscoveryTrack) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 11) {
                Button {
                    app.togglePreview(track)
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        AsyncImage(url: track.artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(Palette.paperDeep)
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Image(systemName: app.previewingTrackID == track.id ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white, Palette.ink.opacity(0.85))
                            .offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(.plain)
                .disabled(track.previewURL == nil)

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(DS.label(13.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(DS.label(11.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    Text(track.reason.uppercased())
                        .kickerStyle(track.isWildcard ? Palette.violet : Palette.subtle, size: 7.5, tracking: 0.8)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                HStack(spacing: 12) {
                    Button { app.discoveryLike(track) } label: {
                        Image(systemName: app.persisted.musicLikes.contains(track.artist.lowercased())
                              ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.green)
                    }
                    Button { app.discoveryPass(track) } label: {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.subtle)
                    }
                    Menu {
                        if let url = track.spotifySearchURL {
                            Button("Open in Spotify") { UIApplication.shared.open(url) }
                        }
                        if let url = track.soundcloudSearchURL {
                            Button("Find on SoundCloud") { UIApplication.shared.open(url) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 9)
        }
    }

    // MARK: SoundCloud shelf

    @ViewBuilder
    var soundcloudSection: some View {
        let user = app.persisted.settings.soundcloudUser.trimmingCharacters(in: .whitespaces)
        let artists = app.persisted.settings.soundcloudArtists.filter { !$0.isEmpty }
        if !user.isEmpty || !artists.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "The SoundCloud Shelf")
                    .padding(.bottom, 10)

                if !user.isEmpty {
                    Text("YOUR LIKES").kickerStyle(Palette.subtle, size: 8, tracking: 1.2)
                        .padding(.bottom, 6)
                    SoundCloudWidget(resourceURL: "https://soundcloud.com/\(user)/likes", height: 166)
                        .frame(height: 166)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)
                }

                ForEach(artists, id: \.self) { artist in
                    Text(artist.uppercased()).kickerStyle(Palette.subtle, size: 8, tracking: 1.2)
                        .padding(.bottom, 6)
                    SoundCloudWidget(resourceURL: "https://soundcloud.com/\(artist)", height: 166)
                        .frame(height: 166)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 14)
                }

                Text("Played by SoundCloud's own embedded player — their API has been closed to new apps for years, so this is the supported route.")
                    .font(DS.label(10, weight: .regular))
                    .foregroundStyle(Palette.subtle)
            }
            .padding(.top, 26)
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

// MARK: - The Wire Archive: discovery listening history, kept in-house

private struct WireArchiveView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var days: [(day: String, entries: [WireArchiveEntry])] {
        let grouped = Dictionary(grouping: app.persisted.wireArchive, by: \.day)
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE WIRE ARCHIVE")
                        .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                        .padding(.bottom, 8)
                    Text("Every discovery, on the record.")
                        .font(DS.display(28))
                        .foregroundStyle(Palette.ink)
                    Text("Tap a track to find it in Spotify. ♥ liked · ✕ passed.")
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 6)
                    InkRule().padding(.vertical, 14)

                    let monthKey = String(Date().dayKey.prefix(7))
                    if let column = app.persisted.musicReviews[monthKey] {
                        Text("THE MONTH IN MUSIC")
                            .kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                            .padding(.bottom, 6)
                        Text(column)
                            .font(DS.deck(14))
                            .foregroundStyle(Palette.ink)
                            .lineSpacing(4)
                            .padding(12)
                            .background(Palette.wash)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 8)
                    }
                    if app.musicReviewBusy {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("The critic is writing…")
                                .font(DS.deck(13))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.bottom, 10)
                    } else {
                        DeskAction(label: app.persisted.musicReviews[monthKey] == nil
                                       ? "Compose the month in music"
                                       : "Recompose the column",
                                   systemImage: "music.quarternote.3") {
                            app.composeMonthInMusic()
                        }
                        .padding(.bottom, 10)
                    }

                    ForEach(days, id: \.day) { group in
                        Text(displayDay(group.day))
                            .kickerStyle(Palette.subtle, size: 9, tracking: 1.2)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(group.entries) { entry in
                            archiveRow(entry)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private func archiveRow(_ entry: WireArchiveEntry) -> some View {
        VStack(spacing: 0) {
            Hairline()
            Button {
                if let url = entry.spotifySearchURL { UIApplication.shared.open(url) }
            } label: {
                HStack(spacing: 10) {
                    Text(entry.verdict == "like" ? "♥" : entry.verdict == "pass" ? "✕" : "·")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(entry.verdict == "like" ? Palette.green
                                         : entry.verdict == "pass" ? Palette.subtle : Palette.line)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(DS.label(13.5, weight: .semibold))
                            .foregroundStyle(entry.verdict == "pass" ? Palette.subtle : Palette.ink)
                            .lineLimit(1)
                        Text("\(entry.artist)\(entry.reason.isEmpty ? "" : " · \(entry.reason)")")
                            .font(DS.label(11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func displayDay(_ dayKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return dayKey }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMMM d"
        return out.string(from: date).uppercased()
    }
}


// MARK: - The Gist: a saved story, boiled down

struct GistSheet: View {
    @Environment(\.dismiss) private var dismiss
    let gist: ReadingGist

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE GIST")
                        .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                        .padding(.bottom, 8)
                    Text(gist.title)
                        .font(DS.display(24))
                        .foregroundStyle(Palette.ink)
                    InkRule().padding(.vertical, 12)
                    Text(gist.text)
                        .font(DS.deck(15))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 30)
            }
            .background(Palette.paper)
            .presentationDetents([.medium, .large])
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }
}
