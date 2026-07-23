//
//  DaymarkWatchApp.swift
//  DaymarkWatch — the paper on the wrist: a glance, the Essential
//  Three (checkable), and the scoreboard line. Data arrives from the
//  phone over WatchConnectivity and is cached for offline reading.
//

import SwiftUI
import WatchConnectivity

// MARK: - Sync

@Observable
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    var updated: Date?
    var weatherLine = ""
    var eventLine = ""
    var openLoops = 0
    var gameLine = ""
    var essentials: [(id: String, kicker: String, title: String, done: Bool)] = []

    private static let cacheKey = "daymark-watch-context"

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        if let cached = UserDefaults.standard.dictionary(forKey: Self.cacheKey) {
            apply(cached)
        }
    }

    func toggle(_ id: String) {
        guard let index = essentials.firstIndex(where: { $0.id == id }) else { return }
        essentials[index].done.toggle()
        pushCache()
        WCSession.default.transferUserInfo(["toggle": id])
    }

    private func apply(_ context: [String: Any]) {
        weatherLine = context["weather"] as? String ?? ""
        eventLine = context["event"] as? String ?? ""
        openLoops = context["loops"] as? Int ?? 0
        gameLine = context["game"] as? String ?? ""
        updated = context["updated"] as? Date
        let raw = context["essentials"] as? [[String: Any]] ?? []
        essentials = raw.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let title = entry["title"] as? String else { return nil }
            return (id, entry["kicker"] as? String ?? "", title, entry["done"] as? Bool ?? false)
        }
    }

    private func pushCache() {
        var cached = UserDefaults.standard.dictionary(forKey: Self.cacheKey) ?? [:]
        cached["essentials"] = essentials.map {
            ["id": $0.id, "kicker": $0.kicker, "title": $0.title, "done": $0.done] as [String: Any]
        }
        UserDefaults.standard.set(cached, forKey: Self.cacheKey)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in
            UserDefaults.standard.set(context, forKey: Self.cacheKey)
            self.apply(context)
        }
    }
}

// MARK: - App

@main
struct DaymarkWatchApp: App {
    @State private var sync = WatchSync.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                GlancePage(sync: sync)
                EssentialsPage(sync: sync)
            }
            .tabViewStyle(.verticalPage)
            .onAppear { sync.activate() }
        }
    }
}

// MARK: - Pages

private let paper = Color(red: 0.075, green: 0.075, blue: 0.067)
private let ink = Color(red: 0.929, green: 0.922, blue: 0.894)
private let muted = Color(red: 0.647, green: 0.635, blue: 0.592)
private let coral = Color(red: 0.937, green: 0.396, blue: 0.329)
private let green = Color(red: 0.263, green: 0.706, blue: 0.529)

struct GlancePage: View {
    let sync: WatchSync

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                Text("DAYMARK")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(coral)
                Text(Date().formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(ink)

                if !sync.weatherLine.isEmpty {
                    row("cloud.sun.fill", sync.weatherLine)
                }
                if !sync.eventLine.isEmpty {
                    row("calendar", sync.eventLine)
                }
                row("tray.full", sync.openLoops == 0 ? "Inbox clear" : "\(sync.openLoops) open loops")
                if !sync.gameLine.isEmpty {
                    row("baseball", sync.gameLine)
                }

                if sync.updated == nil {
                    Text("Open Daymark on the phone once to fill the wire.")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(muted)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(paper)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(muted)
            Text(text)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(2)
        }
    }
}

struct EssentialsPage: View {
    @Bindable var sync: WatchSync

    private var remaining: Int { sync.essentials.filter { !$0.done }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE ESSENTIAL THREE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(coral)

                if sync.essentials.isEmpty {
                    Text("The slate arrives with the phone's next open.")
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(muted)
                } else {
                    ForEach(sync.essentials, id: \.id) { task in
                        Button {
                            sync.toggle(task.id)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(task.done ? green : muted)
                                Text(task.title)
                                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
                                    .foregroundStyle(ink)
                                    .strikethrough(task.done, color: muted)
                                    .opacity(task.done ? 0.5 : 1)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text(remaining == 0 ? "All clear." : "\(remaining) still open.")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(remaining == 0 ? green : muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(paper)
    }
}
