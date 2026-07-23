//
//  WorkView.swift
//  Daymark
//
//  Section B: applications pipeline, the Veraya sprint,
//  waiting-on ledger, and the weekly scorecard.
//

import SwiftUI
import UIKit

struct WorkView: View {
    @Environment(AppState.self) private var app
    @Binding var showSettings: Bool
    @State private var editingApplication: JobApplication?
    @State private var creatingApplication = false
    @State private var addingWaiting = false
    @State private var deskSheet: JobDeskSheet?
    @State private var openMilestone: String?
    @State private var editingNextActionFor: LandedRole?
    @State private var nextActionDraft = ""

    var body: some View {
        let phase = DayPhase.current()

        SectionPage(tag: "Section B", showSettings: $showSettings) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 0) {
                    Masthead(
                        dateline: context.date.dateline(),
                        phaseLabel: phase.label,
                        accent: phase.accent,
                        title: Text("Work")
                    )
                    GlanceRibbon(cells: app.glanceWork())
                }
            }

            landedSection
            applicationsSection
            aiCoachSection
            sprintSection
            waitingSection
            scorecardSection
        }
        .sheet(item: $editingApplication) { application in
            ApplicationEditor(application: application)
        }
        .sheet(isPresented: $creatingApplication) {
            ApplicationEditor(application: nil)
        }
        .sheet(isPresented: $addingWaiting) {
            WaitingEditor()
        }
        .sheet(item: $deskSheet) { sheet in
            JobDeskSheetView(sheet: sheet)
        }
        .alert("Next action", isPresented: Binding(
            get: { editingNextActionFor != nil },
            set: { if !$0 { editingNextActionFor = nil } }
        )) {
            TextField("Follow up Friday, send the deck…", text: $nextActionDraft)
            Button("Save to the sheet") {
                if let role = editingNextActionFor {
                    app.updateLandedNextAction(role, to: nextActionDraft)
                }
                editingNextActionFor = nil
            }
            Button("Cancel", role: .cancel) { editingNextActionFor = nil }
        } message: {
            Text(editingNextActionFor.map { "\($0.company) — \($0.role)" } ?? "")
        }
    }

    // MARK: Landed pipeline (live from the job-search-command-center sheet)

    @ViewBuilder
    private var landedSection: some View {
        if AppConfig.landedConfigured, app.googleConnected {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionRuleHeader(title: "The Landed Wire")
                    AgeStamp(status: app.landedStatus)
                }
                .padding(.bottom, 4)

                if app.landedRoles.isEmpty {
                    EmptyNote(text: app.landedError
                              ?? (app.landedStatus == .unavailable
                                  ? "Could not reach the Landed sheet — check that this Google account can open it."
                                  : "Reading the pipeline from Landed…"))
                } else {
                    Text("\(app.landedRoles.count) open roles · \(app.landedFocusQueue.count) worth attention today")
                        .font(DS.label(11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(.bottom, 8)

                    ForEach(app.landedFocusQueue) { role in
                        VStack(spacing: 0) {
                            Hairline()
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(role.company) — \(role.role)")
                                        .font(DS.label(13.5, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(role.nextAction.nilIfEmpty ?? role.track.nilIfEmpty ?? role.location)
                                        .font(DS.label(11, weight: .regular))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if app.isGhosting(role), let days = app.daysSinceTouch(role) {
                                    StatusChip(text: "Cold · \(days)d",
                                               foreground: Palette.muted, background: Palette.paperDeep)
                                }
                                StatusChip(
                                    text: role.status,
                                    foreground: role.stageRank <= 1 ? Color(hex: 0x0E7A54) : Palette.coral,
                                    background: role.stageRank <= 1 ? Palette.greenSoft : Palette.coralSoft
                                )
                                // Visible menu — same actions the long-press hides.
                                Menu {
                                    if role.stageRank <= 2 {
                                        Button {
                                            app.runInterviewPrep(role)
                                            deskSheet = JobDeskSheet(role: role, kind: .prep)
                                        } label: {
                                            Label("Interview prep", systemImage: "text.book.closed")
                                        }
                                    }
                                    Button {
                                        app.runFollowUp(role)
                                        deskSheet = JobDeskSheet(role: role, kind: .followUp)
                                    } label: {
                                        Label("Draft follow-up", systemImage: "envelope")
                                    }
                                    Divider()
                                    // Write-back: stage and next action land in the sheet.
                                    Menu {
                                        ForEach(AppState.landedStages, id: \.self) { stage in
                                            Button {
                                                app.updateLandedStatus(role, to: stage)
                                            } label: {
                                                if role.status.localizedCaseInsensitiveContains(stage) {
                                                    Label(stage, systemImage: "checkmark")
                                                } else {
                                                    Text(stage)
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("Set stage", systemImage: "arrow.right.circle")
                                    }
                                    Button {
                                        nextActionDraft = role.nextAction
                                        editingNextActionFor = role
                                    } label: {
                                        Label("Edit next action", systemImage: "pencil.line")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(Palette.subtle)
                                }
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .contextMenu {
                                if role.stageRank <= 2 {
                                    Button {
                                        app.runInterviewPrep(role)
                                        deskSheet = JobDeskSheet(role: role, kind: .prep)
                                    } label: {
                                        Label("Interview prep", systemImage: "text.book.closed")
                                    }
                                }
                                Button {
                                    app.runFollowUp(role)
                                    deskSheet = JobDeskSheet(role: role, kind: .followUp)
                                } label: {
                                    Label("Draft follow-up", systemImage: "envelope")
                                }
                            }
                        }
                    }
                    Hairline()

                    DeskAction(label: "Open Landed", systemImage: "arrow.up.right") {
                        if let url = URL(string: "https://job-search-command-center-brown.vercel.app") {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.top, 26)
        }
    }

    // MARK: AI coach

    @ViewBuilder
    private var aiCoachSection: some View {
        if !app.persisted.applications.filter({ $0.status != .closed }).isEmpty {
            AIDeskCard(
                kicker: "The AI desk · job coach",
                emptyPrompt: "Which roles deserve attention today, and what exactly to do for each.",
                output: app.aiJobCoach,
                busy: app.aiBusy.contains("coach"),
                run: { app.runJobCoach() }
            )
            .padding(.top, 14)
        }
    }

    // MARK: Applications

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionKickerHeader(kicker: "Job Search", title: "Applications in play") {
                QuietButton(label: "+ Add") { creatingApplication = true }
            }
            .padding(.bottom, 10)

            if app.persisted.applications.isEmpty {
                Button {
                    creatingApplication = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.coral)
                        Text(app.landedRoles.isEmpty
                             ? "No applications tracked yet — tap to add the first real role."
                             : "The pipeline lives in Landed (\(app.applicationsActive) open roles above) — tap to add a one-off outside the sheet.")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(app.persisted.applications) { application in
                    VStack(spacing: 0) {
                        Hairline()
                        Button {
                            editingApplication = application
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(application.role) · \(application.organization)")
                                        .font(DS.label(14.5, weight: .semibold))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(application.nextStep)
                                        .font(DS.label(11.5, weight: .regular))
                                        .foregroundStyle(Palette.subtle)
                                        .lineLimit(1)
                                }
                                Spacer()
                                StatusChip(
                                    text: application.status.rawValue,
                                    foreground: application.status.chipColors.fg,
                                    background: application.status.chipColors.bg
                                )
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            app.removeApplication(application.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                Hairline()
            }
        }
        .padding(.top, 24)
    }

    // MARK: Sprint

    private var sprintSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionKickerHeader(kicker: "Veraya · Current Sprint", title: "Choose the next proof") {
                VStack(spacing: 2) {
                    Text("\(app.sprintPercent)%")
                        .font(DS.display(24))
                        .foregroundStyle(Palette.ink)
                    Text("COMPLETE").kickerStyle(Palette.subtle, size: 7.5, tracking: 1.0)
                }
            }
            .padding(.bottom, 12)

            // progress track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.paperDeep)
                    Capsule().fill(Palette.ink)
                        .frame(width: max(4, geo.size.width * Double(app.sprintPercent) / 100))
                }
            }
            .frame(height: 7)
            .padding(.bottom, 14)

            ForEach(SprintMilestone.defaults) { milestone in
                let isOpen = openMilestone == milestone.id
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 11) {
                        Button {
                            app.toggleSprint(milestone.id)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(app.sprintDone(milestone.id) ? Palette.ink : Color(hex: 0x9A978D), lineWidth: 1.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(app.sprintDone(milestone.id) ? Palette.ink : .clear)
                                    )
                                    .frame(width: 20, height: 20)
                                if app.sprintDone(milestone.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Palette.paper)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                openMilestone = isOpen ? nil : milestone.id
                            }
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(milestone.title)
                                        .font(DS.label(14, weight: .medium))
                                        .foregroundStyle(app.sprintDone(milestone.id) ? Color(hex: 0xA3A299) : Palette.ink)
                                        .strikethrough(app.sprintDone(milestone.id), color: Color(hex: 0xA3A299))
                                        .multilineTextAlignment(.leading)
                                    Text(milestone.detail)
                                        .font(DS.label(11, weight: .regular))
                                        .foregroundStyle(Palette.subtle)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if !app.sprintNote(milestone.id).isEmpty {
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
                    }
                    .padding(.vertical, 6)

                    if isOpen {
                        TextField("What was decided, tried, or proven…",
                                  text: milestoneNoteBinding(milestone.id), axis: .vertical)
                            .font(DS.label(12, weight: .regular))
                            .lineLimit(2...5)
                            .padding(9)
                            .background(Palette.wash)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .padding(.leading, 31)
                            .padding(.bottom, 8)
                            .onSubmit { app.updateSprintLedger() }
                    }
                }
            }

            ledgerPanel
        }
        .padding(.top, 26)
    }

    private func milestoneNoteBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { app.sprintNote(id) },
            set: { app.setSprintNote(id, $0) }
        )
    }

    /// The desk's running record of the sprint — what the checkmarks and
    /// notes mean, kept current as they change.
    @ViewBuilder
    private var ledgerPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("THE LEDGER").kickerStyle(Palette.coral, size: 8, tracking: 1.3)
                Spacer()
                if app.sprintLedgerBusy {
                    ProgressView().controlSize(.mini)
                } else if let at = app.persisted.sprintLedgerAt {
                    Text(at.formatted(.dateTime.day().month(.abbreviated))
                            .uppercased() + " " + at.timeText())
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Palette.subtle)
                }
            }
            if app.persisted.sprintLedger.isEmpty {
                Text(AIService.isConfigured
                     ? "Check a proof or add a note and the desk starts the record here — what was decided, what it means, and the next move."
                     : "Add an AI key in Settings and the desk keeps a running record of this sprint.")
                    .font(DS.label(11.5, weight: .regular))
                    .foregroundStyle(Palette.subtle)
            } else {
                Text(app.persisted.sprintLedger)
                    .font(DS.deck(13.5))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            if !app.persisted.sprintLedger.isEmpty || AIService.isConfigured {
                DeskAction(label: "Update the ledger", systemImage: "arrow.clockwise") {
                    app.updateSprintLedger()
                }
                .disabled(app.sprintLedgerBusy)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialPanel(padding: 13)
        .padding(.top, 10)
    }

    // MARK: Waiting-on ledger

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionKickerHeader(kicker: "Follow-ups", title: "Waiting on them") {
                QuietButton(label: "+ Track") { addingWaiting = true }
            }
            .padding(.bottom, 6)

            let open = app.waitingOpen
            if open.isEmpty {
                EmptyNote(text: "Nothing owed to you right now. Track a reply and Daymark will nudge you.")
            } else {
                ForEach(open) { item in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.who)
                                    .font(DS.label(14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text("\(item.what) · since \(relativeAge(item.since))"
                                     + (item.due.map { " · follow up \($0.shortDate())" } ?? ""))
                                    .font(DS.label(11, weight: .regular))
                                    .foregroundStyle(Palette.subtle)
                                    .lineLimit(2)
                            }
                            Spacer()
                            CircleCheck(checked: false) { app.completeWaiting(item.id) }
                        }
                        .padding(.vertical, 12)
                    }
                }
                Hairline()
            }
        }
        .padding(.top, 26)
    }

    // MARK: Scorecard

    private var scorecardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Weekly Scorecard")
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(ScoreCategory.defaults) { category in
                    let done = app.score(category.key)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(category.label)
                                    .font(DS.label(14, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                if app.scoreIsAuto(category.key) {
                                    Text("AUTO")
                                        .font(.system(size: 7, weight: .heavy)).tracking(0.8)
                                        .foregroundStyle(Color(hex: 0x0E7A54))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Palette.greenSoft))
                                }
                            }
                            Text("\(done) of \(category.target)")
                                .font(DS.label(10.5, weight: .regular))
                                .foregroundStyle(Palette.subtle)
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach(0..<category.target, id: \.self) { index in
                                Circle()
                                    .fill(index < done ? category.color : Palette.paperDeep)
                                    .frame(width: 11, height: 11)
                            }
                        }
                        HStack(spacing: 4) {
                            stepButton("minus") { app.bumpScore(category, by: -1) }
                            stepButton("plus") { app.bumpScore(category, by: 1) }
                        }
                    }
                    .padding(.vertical, 11)
                    if category.key != ScoreCategory.defaults.last?.key { Hairline() }
                }

                if !app.persisted.scoreHistory.isEmpty {
                    Hairline()
                    Text("EIGHT-WEEK TREND")
                        .kickerStyle(Palette.subtle, size: 8, tracking: 1.2)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    ForEach(ScoreCategory.defaults) { category in
                        HStack(spacing: 10) {
                            Text(category.label)
                                .font(DS.label(11, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 76, alignment: .leading)
                            trendBars(for: category)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .editorialPanel()
        }
        .padding(.top, 26)
    }

    /// Last 8 weeks (history + current) as a compact bar strip, same visual
    /// language as the markets card.
    private func trendBars(for category: ScoreCategory) -> some View {
        let weeks = app.persisted.scoreHistory.keys.sorted().suffix(7)
        var values = weeks.map { app.persisted.scoreHistory[$0]?[category.key] ?? 0 }
        values.append(app.score(category.key))
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let ratio = min(1, Double(value) / Double(max(1, category.target)))
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(index == values.count - 1
                          ? category.color
                          : (ratio >= 1 ? category.color.opacity(0.55) : Palette.paperDeep))
                    .frame(width: 14, height: max(3, 22 * ratio))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24, alignment: .bottom)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 26, height: 26)
                .background(Circle().strokeBorder(Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Application editor sheet

struct ApplicationEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let application: JobApplication?
    @State private var organization = ""
    @State private var role = ""
    @State private var url = ""
    @State private var status: ApplicationStatus = .applied
    @State private var nextStep = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Organization", text: $organization)
                    TextField("Role title", text: $role)
                    TextField("Listing link (optional)", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Pipeline") {
                    Picker("Status", selection: $status) {
                        ForEach(ApplicationStatus.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    TextField("Next step", text: $nextStep)
                }
            }
            .navigationTitle(application == nil ? "Add application" : "Edit application")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(organization.trimmingCharacters(in: .whitespaces).isEmpty
                                  || role.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let application {
                    organization = application.organization
                    role = application.role
                    url = application.url ?? ""
                    status = application.status
                    nextStep = application.nextStep
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        var updated = application ?? JobApplication(organization: "", role: "")
        updated.organization = organization.trimmingCharacters(in: .whitespaces)
        updated.role = role.trimmingCharacters(in: .whitespaces)
        updated.url = url.nilIfEmpty
        updated.status = status
        updated.nextStep = nextStep.nilIfEmpty ?? "Choose next step"
        updated.updatedAt = Date()
        app.upsertApplication(updated)
        app.toast("Pipeline updated.")
        dismiss()
    }
}

// MARK: - Waiting editor sheet

struct WaitingEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var who = ""
    @State private var what = ""
    @State private var hasDue = true
    @State private var due = Date().addingDays(2)

    var body: some View {
        NavigationStack {
            Form {
                Section("Who owes you a reply?") {
                    TextField("Person or company", text: $who)
                    TextField("About what?", text: $what)
                }
                Section("Follow-up") {
                    Toggle("Remind me", isOn: $hasDue)
                    if hasDue {
                        DatePicker("On", selection: $due, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Track a reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Track") {
                        app.addWaiting(who: who, what: what.nilIfEmpty ?? "A reply", due: hasDue ? due : nil)
                        app.toast("Tracking it.")
                        dismiss()
                    }
                    .disabled(who.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Job desk sheet (interview prep / follow-up draft)

struct JobDeskSheet: Identifiable {
    let role: LandedRole
    let kind: Kind
    enum Kind { case prep, followUp }
    var id: String { role.company + role.role + (kind == .prep ? "p" : "f") }
}

struct JobDeskSheetView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let sheet: JobDeskSheet

    private var key: String { sheet.role.company + "|" + sheet.role.role }
    private var output: String? {
        sheet.kind == .prep ? app.aiPrep[key] : app.aiFollowUp[key]
    }
    private var busy: Bool {
        app.aiBusy.contains((sheet.kind == .prep ? "prep-" : "follow-") + key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(sheet.kind == .prep ? "INTERVIEW PREP" : "FOLLOW-UP DRAFT")
                        .kickerStyle(Palette.coral, size: 10, tracking: 1.4)
                    Text("\(sheet.role.company) — \(sheet.role.role)")
                        .font(DS.display(24))
                        .foregroundStyle(Palette.ink)
                    InkRule()

                    if let output {
                        Text(output)
                            .font(DS.label(14, weight: .regular))
                            .foregroundStyle(Palette.ink)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                        if sheet.kind == .followUp {
                            AcidButton(label: "Open in Mail", systemImage: "envelope.fill") {
                                openInMail(output)
                            }
                        }
                    } else if busy {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("The desk is writing…")
                                .font(DS.deck(14))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.top, 20)
                    } else {
                        Text(AIService.isConfigured
                             ? "Nothing yet — close and long-press the role again."
                             : "Add an AI key in Settings first.")
                            .font(DS.deck(14))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func openInMail(_ draft: String) {
        var subject = "\(sheet.role.role) — following up"
        var body = draft
        if draft.lowercased().hasPrefix("subject:"),
           let firstBreak = draft.firstIndex(of: "\n") {
            subject = String(draft[draft.index(draft.startIndex, offsetBy: 8)..<firstBreak])
                .trimmingCharacters(in: .whitespaces)
            body = String(draft[draft.index(after: firstBreak)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var components = URLComponents(string: "mailto:")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}
