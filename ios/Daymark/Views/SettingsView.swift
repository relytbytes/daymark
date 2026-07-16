//
//  SettingsView.swift
//  Daymark
//
//  Connections, notifications, VIP senders, news feeds, and the watchlist.
//

import SwiftUI

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

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
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

                Section("Daily editions") {
                    Toggle("Morning brief · 7:30 AM", isOn: $app.persisted.settings.morningBrief)
                    Toggle("Evening review · 8:30 PM", isOn: $app.persisted.settings.eveningReview)
                    Toggle("Travel time to next meeting", isOn: $app.persisted.settings.travelETA)
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
                            AIService.apiKey = aiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
                            aiKeyDirty = false
                            aiKeyField = AIService.isConfigured ? "••••••••••••" : ""
                            app.toast(AIService.isConfigured ? "AI desk is on." : "AI key cleared.")
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
                    Text("Stooq symbols: indexes like ^spx, ^dji; US tickers as aapl.us.")
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
