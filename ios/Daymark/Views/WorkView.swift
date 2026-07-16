//
//  WorkView.swift
//  Daymark
//
//  Section B: applications pipeline, the Veraya sprint, decisions,
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
            decisionsSection
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
                    EmptyNote(text: app.landedStatus == .unavailable
                              ? "Could not reach the Landed sheet — check that this Google account can open it."
                              : "Reading the pipeline from Landed…")
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
                                StatusChip(
                                    text: role.status,
                                    foreground: role.stageRank <= 1 ? Color(hex: 0x0E7A54) : Palette.coral,
                                    background: role.stageRank <= 1 ? Palette.greenSoft : Palette.coralSoft
                                )
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    Hairline()

                    Button {
                        if let url = URL(string: "https://job-search-command-center-brown.vercel.app") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("OPEN LANDED ↗")
                            .kickerStyle(Palette.coral, size: 9, tracking: 1.2)
                            .padding(.top, 10)
                    }
                    .buttonStyle(.plain)
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
                EmptyNote(text: "No applications tracked yet. Add the first real role you want to move.")
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
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.title)
                            .font(DS.label(14, weight: .medium))
                            .foregroundStyle(app.sprintDone(milestone.id) ? Color(hex: 0xA3A299) : Palette.ink)
                            .strikethrough(app.sprintDone(milestone.id), color: Color(hex: 0xA3A299))
                        Text(milestone.detail)
                            .font(DS.label(11, weight: .regular))
                            .foregroundStyle(Palette.subtle)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.top, 26)
    }

    // MARK: Decisions

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Open Decisions")
                .padding(.bottom, 12)

            ForEach(Array(DecisionDefinition.defaults.enumerated()), id: \.element.id) { index, decision in
                let choice = app.persisted.decisions[decision.id]
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(DS.display(18))
                            .foregroundStyle(Palette.coral)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(decision.title)
                                .font(DS.label(14.5, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(decision.detail)
                                .font(DS.label(11.5, weight: .regular))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                    if let choice {
                        HStack(spacing: 8) {
                            StatusChip(text: "Decided · \(choice)")
                            Button("Revisit") { app.choose(decision.id, option: "") }
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.subtle)
                        }
                        .padding(.leading, 34)
                    } else {
                        HStack(spacing: 7) {
                            ForEach(decision.options, id: \.self) { option in
                                QuietButton(label: option) {
                                    app.choose(decision.id, option: option)
                                    if option == "Open", let url = Self.decisionURL(decision.id) {
                                        UIApplication.shared.open(url)
                                    } else {
                                        app.toast("Noted: \(option).")
                                    }
                                }
                            }
                        }
                        .padding(.leading, 34)
                    }
                }
                .padding(.vertical, 12)
                if index < DecisionDefinition.defaults.count - 1 { Hairline() }
            }
        }
        .padding(.top, 26)
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

    private static func decisionURL(_ id: String) -> URL? {
        switch id {
        case "duke": return URL(string: "https://careers.duke.edu/")
        case "housing": return URL(string: "https://www.redfin.com/city/4909/NC/Durham/filter/max-price=450k")
        default: return nil
        }
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
