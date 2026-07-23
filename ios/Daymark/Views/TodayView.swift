//
//  TodayView.swift
//  Daymark
//
//  The front page: greeting masthead, At a Glance, lead story, focus block,
//  the Essential Three, the day timeline, meeting prep, priority mail,
//  waiting-on, the inbox, and the evening review.
//

import SwiftUI
import UIKit
import EventKit
import EventKitUI

struct TodayView: View {
    @Environment(AppState.self) private var app
    @Binding var showSettings: Bool
    @State private var openURLItem: SheetLink?
    @State private var openEssential: String?
    @State private var captureImageItem: CaptureImageSheet?
    @State private var editingEvent: EventEditTarget?
    @State private var spokenTick = 0
    @State private var showThermostat = false

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: phase.sectionTag, showSettings: $showSettings) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Masthead(
                        dateline: context.date.dateline(),
                        phaseLabel: phase.label,
                        accent: phase.accent,
                        title: greetingTitle(phase: phase)
                    )
                    GlanceRibbon(cells: app.glanceToday())
                    DayProgressBar(progress: app.dayProgress, accent: phase.accent)
                        .padding(.top, 12)
                }
            }

            alertBanner
            gardenWatchLine
            spokenRow
            leadSection(phase: phase)
            focusBulletin
            essentialsSection(phase: phase)
            aiPlanSection(phase: phase)
            timelineSection.id("today-day")
            meetingPrepSection.id("today-prep")
            mailSection
            aiTriageSection
            inboxSection.id("today-inbox")
            if app.weekReviewWindowOpen || !app.persisted.weekReview.isEmpty && app.persisted.weekReviewKey == Date().weekKey {
                weekReviewSection
            }
            if phase.isEndOfDay {
                eveningReviewSection.id("today-close")
                aiEveningSection
            }
        }
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
        .sheet(item: $editingEvent) { target in
            EventEditorView(eventID: target.eventID, store: app.calendarService.eventStore) {
                editingEvent = nil
                Task {
                    await app.refreshCalendar()
                    app.publishWidgetSnapshot()
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $captureImageItem) { item in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
                .background(Palette.ink)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func greetingTitle(phase: DayPhase) -> Text {
        Text("\(phase.greetingWord), ")
            + Text("\(app.persisted.name).").font(DS.display(42, italic: true))
    }

    // MARK: Lead

    private func leadSection(phase: DayPhase) -> some View {
        let lead = app.leadStory(for: phase)
        return VStack(alignment: .leading, spacing: 0) {
            Text(lead.kicker.uppercased())
                .kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                .padding(.bottom, 8)
            Text(lead.headline)
                .font(DS.display(30))
                .foregroundStyle(Palette.ink)
                .lineSpacing(-1)
            Text(lead.deck)
                .font(DS.deck(15))
                .foregroundStyle(Color(hex: 0x4A4940))
                .padding(.top, 10)
        }
        .padding(.top, 22)
    }

    // MARK: Focus bulletin

    private var focusBulletin: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NOW · FOCUS")
                    .font(.system(size: 9, weight: .black)).tracking(1.4)
                    .foregroundStyle(Palette.coral)
                Spacer()
                Text("\(app.persisted.focusMinutes) MIN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Palette.subtle)
            }
            .padding(.bottom, 11)

            Text(app.focusTaskTitle)
                .font(DS.deck(21, weight: 500, italic: false))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 15)

            if app.focusRunning {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 10) {
                        Text(countdownText)
                            .font(DS.display(30))
                            .foregroundStyle(Palette.coral)
                            .monospacedDigit()
                        Spacer()
                        Button("End early") { app.stopFocus() }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.muted)
                    }
                }
            } else {
                AcidButton(label: "Begin — \(app.persisted.focusMinutes):00") {
                    app.startFocus()
                }
            }
        }
        .inkPanel()
        .padding(.top, 22)
    }

    private var countdownText: String {
        guard let remaining = app.focusRemaining else { return "Done." }
        let total = Int(remaining)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Essential three

    private func essentialsSection(phase: DayPhase) -> some View {
        let tasks = EssentialTask.forPhase(phase)
        let numerals = ["I.", "II.", "III."]
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Essential Three")
                .padding(.bottom, 4)
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                let isOpen = openEssential == task.id
                VStack(spacing: 0) {
                    Hairline()
                    HStack(alignment: .center, spacing: 14) {
                        Text(numerals[min(index, 2)])
                            .font(DS.display(22))
                            .foregroundStyle(Palette.coral)
                            .frame(width: 34, alignment: .leading)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                openEssential = isOpen ? nil : task.id
                            }
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(task.kicker.uppercased())
                                        .kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                                    Text(task.title)
                                        .font(DS.label(15, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .strikethrough(app.essentialDone(task.id), color: Palette.subtle)
                                        .opacity(app.essentialDone(task.id) ? 0.45 : 1)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if !(app.persisted.taskNotes[task.id] ?? "").isEmpty {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.gold)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Palette.subtle)
                                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        CircleCheck(checked: app.essentialDone(task.id)) {
                            app.toggleEssential(task.id)
                        }
                    }
                    .padding(.vertical, 14)

                    if isOpen {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.detail)
                                .font(DS.deck(13))
                                .foregroundStyle(Palette.muted)
                                .lineSpacing(3)
                            TextField("Note what this means today…",
                                      text: taskNoteBinding(task.id), axis: .vertical)
                                .font(DS.label(12, weight: .regular))
                                .lineLimit(1...4)
                                .padding(9)
                                .background(Palette.wash)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        .padding(.leading, 48)
                        .padding(.bottom, 12)
                    }
                }
            }
            Hairline()
        }
        .padding(.top, 26)
    }

    private var journalBinding: Binding<String> {
        Binding(
            get: { app.persisted.journal[Date().dayKey] ?? "" },
            set: { app.persisted.journal[Date().dayKey] = $0.nilIfEmpty ?? nil }
        )
    }

    private func taskNoteBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { app.persisted.taskNotes[id] ?? "" },
            set: { app.persisted.taskNotes[id] = $0.nilIfEmpty ?? nil }
        )
    }

    // MARK: Day timeline

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "The Day")
                QuietButton(label: "+ Event") {
                    editingEvent = EventEditTarget(eventID: nil)
                }
            }
            .padding(.bottom, 12)

            if app.calendarAccess == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calendar access is off")
                        .font(DS.label(14, weight: .semibold))
                    Text("Allow calendar access in iOS Settings and the day timeline builds itself from your real schedule.")
                        .font(DS.label(12, weight: .regular))
                        .foregroundStyle(Palette.muted)
                }
                .editorialPanel()
            } else {
                let entries = app.timelineEntries()
                if entries.isEmpty {
                    EmptyNote(text: "No events on the calendar today.")
                } else {
                    ForEach(entries) { entry in
                        timelineRow(entry)
                    }
                }
            }
        }
        .padding(.top, 26)
    }

    @ViewBuilder
    private func timelineRow(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .event(let event):
            let live = event.start <= Date() && Date() < event.end
            HStack(alignment: .top, spacing: 12) {
                Text(event.isAllDay ? "—" : event.start.clockText())
                    .font(DS.display(15))
                    .foregroundStyle(live ? Palette.coral : Palette.ink)
                    .frame(width: 46, alignment: .leading)
                Rectangle()
                    .fill(live ? Palette.coral : Palette.hairline)
                    .frame(width: live ? 2.5 : 1)
                    .frame(maxHeight: .infinity)
                // Tap the body of the row to edit the event in place.
                Button {
                    editingEvent = EventEditTarget(eventID: event.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(event.title)
                                .font(DS.label(14, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if live {
                                StatusChip(text: "Now", foreground: .white, background: Palette.coral)
                            }
                        }
                        Text(event.timeRangeText + (event.location.map { " · \($0)" } ?? ""))
                            .font(DS.label(11, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtle)
                    .padding(.top, 2)
                if let join = event.joinURL {
                    Button {
                        UIApplication.shared.open(join)
                    } label: {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Palette.paper)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Palette.ink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)

        case .freeBlock(let start, let minutes):
            HStack(alignment: .top, spacing: 12) {
                Text(start.clockText())
                    .font(DS.display(15))
                    .foregroundStyle(Palette.subtle)
                    .frame(width: 46, alignment: .leading)
                Rectangle().fill(Palette.coral)
                    .frame(width: 2.5)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPEN BLOCK · \(formatMinutes(minutes))")
                        .kickerStyle(Palette.coral, size: 9, tracking: 1.1)
                    Text("Good for a focused push on Veraya.")
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if !app.focusRunning {
                    QuietButton(label: "Focus") { app.startFocus(cappedToMinutes: minutes) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: Weather alerts (NWS)

    /// Frost or heat guidance for the outdoor plants, when it matters.
    @ViewBuilder private var gardenWatchLine: some View {
        if let watch = app.gardenWatch {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: watch.hasPrefix("Frost") ? "snowflake" : "sun.max.trianglebadge.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(watch.hasPrefix("Frost") ? Palette.blue : Palette.coral)
                Text(watch)
                    .font(DS.label(12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Palette.wash)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .onTapGesture { app.navigate(tab: "life", anchor: "life-garden") }
        }
    }

    @ViewBuilder
    private var alertBanner: some View {
        ForEach(app.weatherAlerts) { alert in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(alert.isUrgent ? Palette.coral : Palette.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.event.uppercased())
                        .kickerStyle(alert.isUrgent ? Palette.coral : Palette.gold,
                                     size: 9, tracking: 1.2)
                    Text(alert.headline)
                        .font(DS.label(11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                    if let ends = alert.ends {
                        Text("Until \(ends.timeText())")
                            .font(DS.label(10, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background((alert.isUrgent ? Palette.coralSoft : Palette.wash))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(alert.isUrgent ? Palette.coral.opacity(0.4) : Palette.line, lineWidth: 1))
            .padding(.top, 12)
        }
    }

    // MARK: The Spoken Edition

    /// One tap and the brief reads itself — car, kitchen, dog walk.
    private var spokenRow: some View {
        HStack {
            Spacer()
            Button {
                app.spokenEdition.toggle(script: app.spokenScript())
                spokenTick += 1
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: app.spokenEdition.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                    Text(app.spokenEdition.isSpeaking ? "STOP" : "SPOKEN EDITION")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(1.0)
                }
                .foregroundStyle(Palette.coral)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .id(spokenTick)
        }
        .padding(.top, 10)
    }

    // MARK: The Week in Review

    private var weekReviewSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Week in Review")
                .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 8) {
                if !app.persisted.weekReview.isEmpty {
                    Text(app.persisted.weekReview)
                        .font(DS.deck(14.5))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                    DeskAction(label: "Rewrite the column", systemImage: "arrow.clockwise") {
                        app.composeWeekReview(force: true)
                    }
                    .disabled(app.weekReviewBusy)
                } else if app.weekReviewBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("The desk is writing the Sunday column…")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    Text(AIService.isConfigured
                         ? "The Sunday column composes from the week's scores, pipeline movement, and discoveries."
                         : "Add an AI key in Settings and the desk writes the Sunday column.")
                        .font(DS.label(11.5, weight: .regular))
                        .foregroundStyle(Palette.subtle)
                    if AIService.isConfigured {
                        DeskAction(label: "Write the column", systemImage: "pencil.line") {
                            app.composeWeekReview()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialPanel()
        }
        .padding(.top, 26)
    }

    // MARK: Meeting prep

    @ViewBuilder
    private var meetingPrepSection: some View {
        if let meeting = app.nextMeeting {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Meeting Prep")
                    .padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(timeUntil(meeting.start).uppercased())
                            .kickerStyle(Palette.coral, size: 9, tracking: 1.2)
                        Spacer()
                        if let travel = app.travel, travel.eventID == meeting.id {
                            Label("\(travel.minutes) min drive", systemImage: "car.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Text(meeting.title)
                        .font(DS.display(22))
                        .foregroundStyle(Palette.ink)
                    Text(meeting.timeRangeText + (meeting.location.map { " · \($0)" } ?? ""))
                        .font(DS.label(12, weight: .medium))
                        .foregroundStyle(Palette.muted)

                    if !meeting.attendees.isEmpty {
                        attendeeRow(meeting.attendees)
                    }

                    if let notes = meeting.notes {
                        Text(notes)
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(3)
                    }

                    HStack(spacing: 8) {
                        if let join = meeting.joinURL {
                            AcidButton(label: "Join meeting", systemImage: "video.fill") {
                                UIApplication.shared.open(join)
                            }
                        }
                        ForEach(Array(meeting.links.prefix(2).enumerated()), id: \.offset) { _, link in
                            QuietButton(label: link.host ?? "Link") { openURLItem = SheetLink(url: link) }
                        }
                    }

                    prepBrief(for: meeting)
                }
                .editorialPanel()
            }
            .padding(.top, 26)
        }
    }

    /// The desk's prep brief, composed on demand and cached per event.
    @ViewBuilder
    private func prepBrief(for meeting: CalendarEventLite) -> some View {
        if app.meetingPrepFor == meeting.id, let output = app.meetingPrepOutput {
            VStack(alignment: .leading, spacing: 8) {
                InkRule()
                HStack {
                    Text("THE DESK BRIEF").kickerStyle(Palette.coral, size: 8, tracking: 1.3)
                    Spacer()
                    Button {
                        app.runMeetingPrep(force: true)
                    } label: {
                        Text("REFRESH")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(Palette.subtle)
                    }
                    .buttonStyle(.plain)
                    .disabled(app.meetingPrepBusy)
                }
                Text(output)
                    .font(DS.deck(13.5))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        } else if app.meetingPrepBusy {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("The desk is composing your brief…")
                    .font(DS.deck(13))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.top, 4)
        } else if let error = app.meetingPrepError {
            VStack(alignment: .leading, spacing: 6) {
                Text(error)
                    .font(DS.label(11, weight: .medium))
                    .foregroundStyle(Palette.down)
                DeskAction(label: "Try again", systemImage: "arrow.clockwise") {
                    app.runMeetingPrep(force: true)
                }
            }
            .padding(.top, 4)
        } else if AIService.isConfigured {
            DeskAction(label: "Prep me — the desk brief", systemImage: "text.book.closed.fill") {
                app.runMeetingPrep()
            }
            .padding(.top, 6)
        }
    }

    private func attendeeRow(_ names: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(names.prefix(4), id: \.self) { name in
                HStack(spacing: 5) {
                    Text(initials(of: name))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Palette.paper)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.ink))
                    Text(name.split(separator: " ").first.map(String.init) ?? name)
                        .font(DS.label(11, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.trailing, 4)
            }
            if names.count > 4 {
                Text("+\(names.count - 4)")
                    .font(DS.label(11, weight: .bold))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }

    private func timeUntil(_ date: Date) -> String {
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Happening now" }
        if minutes < 60 { return "Next · in \(minutes) min" }
        return "Next · at \(date.timeText())"
    }

    // MARK: Priority mail

    private var mailSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                SectionRuleHeader(title: "Priority Mail")
            }
            .padding(.bottom, 12)

            if !app.googleConnected && !ICloudMailService.isConfigured {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect Gmail")
                        .font(DS.label(14, weight: .semibold))
                    Text(AppConfig.googleConfigured
                         ? "See unread priority mail, spot what needs a reply, and clear it without opening the inbox."
                         : "Add your Google iOS client ID (see the README), then connect here.")
                        .font(DS.label(12, weight: .regular))
                        .foregroundStyle(Palette.muted)
                    if AppConfig.googleConfigured {
                        AcidButton(label: "Connect Google", systemImage: "envelope.fill") {
                            Task { await app.connectGoogle() }
                        }
                    }
                }
                .editorialPanel()
            } else if app.mail.isEmpty {
                HStack {
                    EmptyNote(text: "Inbox zero on priority mail. Well managed.")
                    AgeStamp(status: app.mailStatus)
                }
            } else {
                HStack {
                    Spacer()
                    AgeStamp(status: app.mailStatus)
                }
                ForEach(app.mail) { message in
                    mailRow(message)
                }
            }
        }
        .padding(.top, 26)
    }

    private func mailRow(_ message: EmailMessage) -> some View {
        VStack(spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(message.fromName)
                        .font(DS.label(13.5, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if message.id.hasPrefix("icloud-") {
                        StatusChip(text: "iCloud", foreground: Palette.blue, background: Palette.blueSoft)
                    }
                    if message.isVIP {
                        StatusChip(text: "VIP")
                    }
                    if message.needsReply {
                        StatusChip(text: "Reply", foreground: Color(hex: 0xC23C1E), background: Palette.coralSoft)
                    }
                    Spacer()
                    if let date = message.date {
                        Text(relativeAge(date))
                            .font(DS.label(10, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                    }
                }
                Text(message.subject)
                    .font(DS.label(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(message.snippet)
                    .font(DS.label(12, weight: .regular))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    QuietButton(label: "Mark read") { app.markMailRead(message) }
                    QuietButton(label: "Track reply") { app.waitingFromMail(message) }
                }
                .padding(.top, 3)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: Waiting on

    @ViewBuilder
    private var waitingSection: some View {
        let open = app.waitingOpen
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Waiting On")
                    .padding(.bottom, 4)
                ForEach(open) { item in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.who)
                                    .font(DS.label(14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text("\(item.what) · since \(relativeAge(item.since))")
                                    .font(DS.label(11, weight: .regular))
                                    .foregroundStyle(Palette.subtle)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let due = item.due, due < Date() {
                                StatusChip(text: "Overdue", foreground: .white, background: Palette.coral)
                            }
                            CircleCheck(checked: false) { app.completeWaiting(item.id) }
                        }
                        .padding(.vertical, 12)
                    }
                }
                Hairline()
            }
            .padding(.top, 26)
        }
    }

    // MARK: Inbox (captures)

    @ViewBuilder
    private var inboxSection: some View {
        let open = app.persisted.captures.filter { !$0.done }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Captured for Later")
                    .padding(.bottom, 4)
                ForEach(open) { item in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            if let file = item.imageFile, let image = CaptureImages.load(file) {
                                Button {
                                    captureImageItem = CaptureImageSheet(image: image, title: item.title)
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.kind.label.uppercased())
                                    .kickerStyle(Palette.subtle, size: 8, tracking: 1.1)
                                Text(item.title)
                                    .font(DS.label(14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                if let note = item.note?.nilIfEmpty {
                                    Text(note)
                                        .font(DS.label(11, weight: .regular))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            CircleCheck(checked: false) { app.toggleCapture(item.id) }
                        }
                        .padding(.vertical, 12)
                    }
                    .contextMenu {
                        Button(role: .destructive) { app.removeCapture(item.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Hairline()
            }
            .padding(.top, 26)
        }
    }

    // MARK: Evening review

    private var eveningReviewSection: some View {
        @Bindable var app = app
        let review = app.eveningReview()
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Close")
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(review.essentialsDone) of \(review.essentialsTotal)")
                        .font(DS.display(34))
                        .foregroundStyle(Palette.coral)
                    Text("essentials landed · \(review.capturesCleared) loops cleared")
                        .font(DS.label(12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }

                // One line for the record — the part only you can write.
                VStack(alignment: .leading, spacing: 5) {
                    Text("FOR THE RECORD").kickerStyle(Palette.subtle, size: 8, tracking: 1.2)
                    TextField("One line about today…", text: journalBinding, axis: .vertical)
                        .font(DS.deck(14))
                        .lineLimit(1...3)
                        .padding(10)
                        .background(Palette.wash)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if let lastWeek = app.persisted.journal[Date().addingDays(-7).dayKey]?.nilIfEmpty {
                        Text("A week ago tonight: \u{201C}\(lastWeek)\u{201D}")
                            .font(DS.deck(12))
                            .foregroundStyle(Palette.subtle)
                    }
                }

                VStack(spacing: 7) {
                    ForEach(review.scoreLines, id: \.label) { line in
                        HStack {
                            Text(line.label)
                                .font(DS.label(12, weight: .semibold))
                                .foregroundStyle(Palette.ink.opacity(0.85))
                            Spacer()
                            Text("\(line.done)/\(line.target)")
                                .font(DS.display(14))
                                .foregroundStyle(line.done >= line.target ? Palette.green : Palette.subtle)
                        }
                    }
                }

                Hairline()

                VStack(alignment: .leading, spacing: 6) {
                    Text("TOMORROW")
                        .font(.system(size: 9, weight: .black)).tracking(1.4)
                        .foregroundStyle(Palette.coral)
                    if let first = review.tomorrowFirst {
                        Text("\(first.start.timeText()) — \(first.title)")
                            .font(DS.label(13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("\(review.tomorrowCount) event\(review.tomorrowCount == 1 ? "" : "s") on the calendar")
                            .font(DS.label(11, weight: .regular))
                            .foregroundStyle(Palette.subtle)
                    } else {
                        Text("No events yet — the morning is yours.")
                            .font(DS.label(13, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    TextField(
                        "",
                        text: $app.persisted.tomorrowFirstMove,
                        prompt: Text("Tomorrow's first move…").foregroundStyle(Palette.subtle)
                    )
                    .font(DS.label(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .padding(10)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                }
            }
            .inkPanel()

            weekAheadLedger
        }
        .padding(.top, 26)
    }

    @ViewBuilder
    private var weekAheadLedger: some View {
        let week = app.weekAhead()
        if !week.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("THE WEEK AHEAD")
                    .kickerStyle(Palette.subtle, size: 8.5, tracking: 1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                ForEach(week.prefix(7), id: \.day) { entry in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.day.shortDate().uppercased())
                                .kickerStyle(Palette.coral, size: 9, tracking: 0.8)
                                .frame(width: 78, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(entry.events.prefix(2)) { event in
                                    Text(event.isAllDay ? event.title : "\(event.start.clockText()) \(event.title)")
                                        .font(DS.label(12, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                }
                                if entry.events.count > 2 {
                                    Text("+ \(entry.events.count - 2) more")
                                        .font(DS.label(10, weight: .semibold))
                                        .foregroundStyle(Palette.subtle)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                }
                Hairline()
            }
            .padding(.top, 14)
        }
    }
}

extension TodayView {
    @ViewBuilder
    func aiPlanSection(phase: DayPhase) -> some View {
        if !phase.isEndOfDay {
            AIDeskCard(
                kicker: "The AI desk · today's plan",
                emptyPrompt: "Have the desk read your calendar, pipeline, captures, and the weather — and propose the Essential Three plus a first move.",
                output: app.aiPlan,
                busy: app.aiBusy.contains("plan"),
                run: { app.runDailyPlan() }
            )
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    var aiTriageSection: some View {
        if app.googleConnected, !app.mail.isEmpty {
            AIDeskCard(
                kicker: "The AI desk · mail triage",
                emptyPrompt: "One line per message: why it matters and the next step.",
                output: app.aiMailTriage,
                busy: app.aiBusy.contains("triage"),
                run: { app.runMailTriage() }
            )
            .padding(.top, 14)
        }
    }

    @ViewBuilder
    var aiEveningSection: some View {
        AIDeskCard(
            kicker: "The AI desk · evening column",
            emptyPrompt: "A short column about how the day actually went.",
            output: app.aiEveningNote,
            busy: app.aiBusy.contains("evening"),
            run: { app.runEveningNarrative() }
        )
        .padding(.top, 14)
    }
}

struct SheetLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct CaptureImageSheet: Identifiable {
    let image: UIImage
    let title: String
    var id: String { title }
}

struct EventEditTarget: Identifiable {
    let id = UUID()
    let eventID: String?    // nil = create a new event
}

/// The system calendar editor, so events are created and changed
/// without leaving the paper. Writes go straight to EventKit and sync
/// to every calendar account on the phone.
struct EventEditorView: UIViewControllerRepresentable {
    let eventID: String?
    let store: EKEventStore
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        if let eventID, let event = store.event(withIdentifier: eventID) {
            controller.event = event
        }
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onFinish()
        }
    }
}
