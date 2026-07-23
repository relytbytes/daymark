//
//  RootView.swift
//  Daymark
//
//  The app shell: section pages, editorial tab bar, capture, settings, toast.
//

import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today, work, sky, life, media
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .today: return "house"
        case .work: return "briefcase"
        case .sky: return "moon.stars"
        case .life: return "mappin.and.ellipse"
        case .media: return "newspaper"
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var section: AppSection = .today
    @State private var showCapture = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.paper.ignoresSafeArea()

            Group {
                switch section {
                case .today: TodayView(showSettings: $showSettings)
                case .work: WorkView(showSettings: $showSettings)
                case .sky: SkyTabView(showSettings: $showSettings)
                case .life: LifeView(showSettings: $showSettings)
                case .media: MoreView(showSettings: $showSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .sheet(isPresented: $showCapture) { CaptureSheet() }
        .onChange(of: app.captureRequested) { _, requested in
            if requested {
                showCapture = true
                app.captureRequested = false
            }
        }
        .onChange(of: app.requestedTab) { _, tab in
            if let tab, let destination = AppSection(rawValue: tab) {
                section = destination
                app.requestedTab = nil
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .overlay(alignment: .bottom) { toast }
        .task {
            await app.refreshAll(force: false)
            await app.syncNotifications()
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.today)
            tabButton(.work)
            tabButton(.sky)
            tabButton(.life)
            tabButton(.media)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            Palette.paper.opacity(0.92)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.ink.opacity(0.8)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ target: AppSection) -> some View {
        let selected = section == target
        return Button {
            if section == target { return }
            section = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: target.icon)
                    .font(.system(size: 19, weight: .regular))
                    .symbolVariant(selected ? .fill : .none)
                Text(target.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
            }
            .foregroundStyle(selected ? Palette.ink : Color(hex: 0xA3A299))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }


    // MARK: Toast

    @ViewBuilder
    private var toast: some View {
        if let message = app.toastMessage {
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Palette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: app.toastMessage)
        }
    }
}

/// Shared scroll scaffold every section page uses.
struct SectionPage<Content: View>: View {
    @Environment(AppState.self) private var app
    let tag: String
    @Binding var showSettings: Bool
    var index: [(label: String, anchor: String)] = []
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    MastheadTopline(
                        tag: tag,
                        refreshing: app.isRefreshing,
                        onRefresh: { Task { await app.refreshAll(force: true) } },
                        onCapture: { app.requestCapture() },
                        onSettings: { showSettings = true }
                    )
                    .padding(.bottom, index.isEmpty ? 14 : 8)

                    if index.isEmpty {
                        content
                        footer
                    } else {
                        // The index pins to the top while the page scrolls,
                        // so any desk is one tap away from anywhere.
                        Section {
                            content
                            footer
                        } header: {
                            indexRow(proxy)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 108)
            }
            .scrollIndicators(.hidden)
            .refreshable { await app.refreshAll(force: true) }
            .background(Palette.paper)
            .onChange(of: app.pendingAnchor) { _, anchor in
                consumeAnchor(anchor, proxy: proxy)
            }
            .onAppear {
                consumeAnchor(app.pendingAnchor, proxy: proxy)
            }
        }
    }

    /// Cross-tab deep links land here: scroll to the requested anchor
    /// once the page is on screen, then clear the request.
    private func consumeAnchor(_ anchor: String?, proxy: ScrollViewProxy) {
        guard let anchor else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.snappy(duration: 0.35)) {
                proxy.scrollTo(anchor, anchor: .top)
            }
            app.pendingAnchor = nil
        }
    }

    /// The section index: one tap jumps a long page to its desks.
    private func indexRow(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(index, id: \.anchor) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.35)) {
                            proxy.scrollTo(item.anchor, anchor: .top)
                        }
                    } label: {
                        Text(item.label.uppercased())
                            .font(.system(size: 11, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Palette.wash))
                            .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairlineSoft).frame(height: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            BrandMark().padding(.top, 44)
            Text("That\u{2019}s the brief.")
                .font(DS.deck(15))
                .foregroundStyle(Palette.muted)
            Text("DAYMARK KEEPS THE SIGNAL. YOU KEEP THE DAY.")
                .kickerStyle(Palette.subtle, size: 7.5, tracking: 1.4)
        }
        .frame(maxWidth: .infinity)
    }
}
