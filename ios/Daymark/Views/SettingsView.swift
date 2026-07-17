//
//  SettingsView.swift
//  Daymark
//
//  Connections, notifications, VIP senders, news feeds, and the watchlist.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var newVIP = ""
    @State private var newFeedName = ""
    @State private var newFeedURL = ""
    @State private var newSymbol = ""
    @State private var newSymbolLabel = ""
    @State private var aiProvider = AIService.provider
    @State private var aiKeyField = AIService.isConfigured ? "••••••••••••" : ""
    @State private var aiKeyDirty = false
    @State private var newSCArtist = ""
    @State private var importing = false
    @State private var icloudUser = ICloudMailService.username ?? ""
    @State private var icloudPassword = ICloudMailService.isConfigured ? "••••••••••••" : ""
    @State private var exportURL: ExportFile?

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            settingsForm
        }
        .sheet(item: $exportURL) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: url),
               let restored = try? decoder.decode(PersistedState.self, from: data) {
                app.persisted = restored
                app.toast("Backup restored.")
            } else {
                app.toast("That file didn't read as a Daymark backup.")
            }
        }
    }

    private func exportData() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(app.persisted) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("daymark-backup-\(Date().dayKey).json")
        try? data.write(to: url, options: .atomic)
        exportURL = ExportFile(url: url)
    }

    private var settingsForm: some View {
        @Bindable var app = app
        return Form {
                Section("You") {
                    TextField("Name for the greeting", text: $app.persisted.name)
                }

                Section("Connections") {
                    connectionRow(
                        title: "Google · priority mail",
                        connected: app.googleConnected,
                        configured: AppConfig.googleConfigured,
                        note: AppConfig.googleConfigured
                            ? "Read-only triage plus mark-as-read."
                            : "Add an iOS client ID to DaymarkConfig.plist first (see README).",
                        connect: { Task { await app.connectGoogle() } },
                        disconnect: { app.disconnectGoogle() }
                    )
                    connectionRow(
                        title: "Spotify",
                        connected: app.spotifyConnected,
                        configured: AppConfig.spotifyConfigured,
                        note: "Playback state and device control.",
                        connect: { Task { await app.connectSpotify() } },
                        disconnect: { app.disconnectSpotify() }
                    )
                    if NestService.isConfigured {
                        connectionRow(
                            title: "Nest thermostat",
                            connected: app.nest.isConnected,
                            configured: true,
                            note: "Indoor temperature and HVAC state on the weather desk.",
                            connect: { Task { try? await app.nest.connect(); app.toast(app.nest.isConnected ? "Nest connected." : "Nest connection didn't complete.") } },
                            disconnect: { app.nest.disconnect() }
                        )
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calendar")
                            Text("Native EventKit — grant access when asked.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(app.calendarAccess == true ? "On" : app.calendarAccess == false ? "Off" : "—")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("you@icloud.com", text: $icloudUser)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("App-specific password", text: $icloudPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(ICloudMailService.isConfigured ? "Update iCloud Mail" : "Connect iCloud Mail") {
                        ICloudMailService.username = icloudUser.trimmingCharacters(in: .whitespaces)
                        ICloudMailService.password = icloudPassword.trimmingCharacters(in: .whitespaces)
                        icloudPassword = ICloudMailService.isConfigured ? "••••••••••••" : ""
                        app.toast(ICloudMailService.isConfigured ? "iCloud Mail connected." : "iCloud Mail cleared.")
                        Task { await app.refreshMail() }
                    }
                    if ICloudMailService.isConfigured {
                        Button("Disconnect iCloud Mail", role: .destructive) {
                            ICloudMailService.username = nil
                            ICloudMailService.password = nil
                            icloudUser = ""
                            icloudPassword = ""
                            app.toast("iCloud Mail disconnected.")
                        }
                    }
                } header: {
                    Text("iCloud Mail")
                } footer: {
                    Text("Daymark speaks IMAP directly to imap.mail.me.com — Apple has no mail API. Create an app-specific password at appleid.apple.com → Sign-In and Security. Both values live in the Keychain only. Unseen headers join priority mail with an iCloud badge; mark-read syncs back.")
                }

                Section {
                    TextField("Spotify playlist link for focus blocks", text: $app.persisted.settings.focusPlaylist)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Focus soundtrack")
                } footer: {
                    Text("Paste a playlist link and it starts on your active Spotify device when a focus block begins, and pauses when it ends.")
                }

                Section {
                    Button("Export Daymark data…") { exportData() }
                    Button("Import from backup…") { importing = true }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("A JSON file with tasks, pipeline, captures, reading queue, scores, and settings. Import replaces what's on this device.")
                }

                Section("Daily editions") {
                    Toggle("Morning brief · 7:30 AM", isOn: $app.persisted.settings.morningBrief)
                    Toggle("Evening review · 8:30 PM", isOn: $app.persisted.settings.eveningReview)
                    Toggle("Travel time to next meeting", isOn: $app.persisted.settings.travelETA)
                    Toggle("Game alerts · first pitch & finals", isOn: $app.persisted.settings.gameAlerts)
                }

                Section {
                    TextField("your-soundcloud-username", text: $app.persisted.settings.soundcloudUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ForEach(Array(app.persisted.settings.soundcloudArtists.enumerated()), id: \.offset) { index, artist in
                        Text(artist)
                    }
                    .onDelete { offsets in
                        app.persisted.settings.soundcloudArtists.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("artist-url-slug (e.g. fourtet)", text: $newSCArtist)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            if let slug = newSCArtist.nilIfEmpty?.lowercased() {
                                app.persisted.settings.soundcloudArtists.append(slug)
                                newSCArtist = ""
                            }
                        }
                        .disabled(newSCArtist.nilIfEmpty == nil)
                    }
                } header: {
                    Text("SoundCloud")
                } footer: {
                    Text("Username lights up your likes shelf; artist slugs (the part after soundcloud.com/) get a recent-uploads player each. No API key exists for SoundCloud — playback runs through their official embedded widget.")
                }

                Section {
                    Picker("Provider", selection: $aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .onChange(of: aiProvider) { _, newValue in
                        AIService.provider = newValue
                    }
                    SecureField("API key", text: $aiKeyField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: aiKeyField) { _, _ in aiKeyDirty = true }
                    if aiKeyDirty {
                        Button("Save key") {
                            let entered = aiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
                            if entered.contains("•") {
                                // The masked placeholder — never store it over the real key.
                                app.toast("That's the masked placeholder — clear the field and paste the key fresh.")
                            } else {
                                AIService.apiKey = entered
                                app.toast(AIService.isConfigured ? "AI desk is on." : "AI key cleared.")
                            }
                            aiKeyDirty = false
                            aiKeyField = AIService.isConfigured ? "••••••••••••" : ""
                        }
                    }
                } header: {
                    Text("The AI desk")
                } footer: {
                    Text("Powers the daily plan, job coach, mail triage, evening column, and horoscope. The key is stored in the Keychain, never synced or committed. Start with OpenAI; switch the picker to Anthropic when your credits run out.")
                }

                Section {
                    ForEach(app.persisted.settings.vipSenders, id: \.self) { email in
                        Text(email)
                    }
                    .onDelete { offsets in
                        app.persisted.settings.vipSenders.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("vip@example.com", text: $newVIP)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            if let email = newVIP.nilIfEmpty?.lowercased() {
                                app.persisted.settings.vipSenders.append(email)
                                newVIP = ""
                            }
                        }
                        .disabled(newVIP.nilIfEmpty == nil)
                    }
                } header: {
                    Text("VIP senders")
                } footer: {
                    Text("Mail from these addresses is pinned to the top of priority mail.")
                }

                Section {
                    ForEach(app.persisted.settings.feeds) { feed in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feed.name)
                            Text(feed.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .onDelete { offsets in
                        app.persisted.settings.feeds.remove(atOffsets: offsets)
                    }
                    VStack(spacing: 6) {
                        TextField("Feed name", text: $newFeedName)
                        HStack {
                            TextField("https://…/feed.xml", text: $newFeedURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Add") {
                                if let name = newFeedName.nilIfEmpty, let url = newFeedURL.nilIfEmpty,
                                   URL(string: url) != nil {
                                    app.persisted.settings.feeds.append(FeedSource(name: name, url: url))
                                    newFeedName = ""; newFeedURL = ""
                                }
                            }
                            .disabled(newFeedName.nilIfEmpty == nil || newFeedURL.nilIfEmpty == nil)
                        }
                    }
                } header: {
                    Text("News feeds (RSS)")
                }

                Section {
                    ForEach(app.persisted.settings.watchlist) { symbol in
                        HStack {
                            Text(symbol.label)
                            Spacer()
                            Text(symbol.symbol).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        app.persisted.settings.watchlist.remove(atOffsets: offsets)
                    }
                    HStack {
                        TextField("Label", text: $newSymbolLabel)
                        TextField("^spx / aapl.us", text: $newSymbol)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            if let label = newSymbolLabel.nilIfEmpty, let symbol = newSymbol.nilIfEmpty {
                                app.persisted.settings.watchlist.append(
                                    WatchSymbol(symbol: symbol.lowercased(), label: label)
                                )
                                newSymbolLabel = ""; newSymbol = ""
                            }
                        }
                        .disabled(newSymbolLabel.nilIfEmpty == nil || newSymbol.nilIfEmpty == nil)
                    }
                } header: {
                    Text("Markets watchlist")
                } footer: {
                    Text("Indexes like ^spx, ^dji, ^ndq; plain US tickers like AAPL.")
                }

                Section {
                    Picker("Appearance", selection: appearanceBinding) {
                        Text("Auto — follows the sun").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Auto runs the day paper until sunset, then the night edition until sunrise.")
                }

                Section {
                    LabeledContent("Version", value: "1.0 · native edition")
                    LabeledContent("Data honesty", value: "Feeds are stamped live, cached, or unavailable — never invented.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await app.syncNotifications() }
                        dismiss()
                    }
                }
            }
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { app.persisted.settings.appearance },
            set: { app.persisted.settings.appearance = $0 }
        )
    }

    @ViewBuilder
    private func connectionRow(
        title: String,
        connected: Bool,
        configured: Bool,
        note: String,
        connect: @escaping () -> Void,
        disconnect: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if connected {
                Button("Disconnect", role: .destructive, action: disconnect)
                    .font(.footnote)
            } else if configured {
                Button("Connect", action: connect)
                    .font(.footnote.bold())
            } else {
                Text("Not configured").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}


/// Identifiable wrapper so a fresh export re-presents the share sheet.
struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// UIActivityViewController bridge for the backup file.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
