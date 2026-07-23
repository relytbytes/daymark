//
//  SpiritView.swift
//  Daymark
//
//  The Spirit Desk: today's horoscope, a question-led tarot spread,
//  the daily oracle card, the crystal cabinet, chakra of the day, and
//  a composed meditation. Daily draws hold steady all day; the tarot
//  answers whatever you ask it.
//

import SwiftUI

struct SpiritSectionsView: View {
    @Environment(AppState.self) private var app

    @State private var question = ""
    @State private var spread: [TarotCard] = []
    @State private var tarotReading: String?
    @State private var tarotError: String?
    @State private var tarotBusy = false
    @State private var meditation: String?
    @State private var meditationBusy = false
    @State private var oracleReading: String?
    @State private var oracleBusy = false
    @State private var oracleError: String?
    @State private var showCabinet = false
    @State private var showChakraGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            horoscopeSection
            tarotSection
            oracleSection
            crystalSection
            chakraSection
            meditationSection
        }
        .sheet(isPresented: $showCabinet) { CrystalCabinetView() }
        .sheet(isPresented: $showChakraGuide) { ChakraGuideView() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE SPIRIT DESK")
                .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                .padding(.bottom, 8)
            Text("The inner edition.")
                .font(DS.display(28))
                .foregroundStyle(Palette.ink)
            InkRule().padding(.top, 12)
        }
        .padding(.top, 34)
    }

    // MARK: Horoscope (shares the Sky Desk's engine + output)

    @ViewBuilder
    private var horoscopeSection: some View {
        if let astro = app.astro {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Today's Horoscope")
                    .padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TAURUS · APRIL 21").kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                        Spacer()
                        if astro.mercuryRetrograde {
                            StatusChip(text: "Mercury Rx", foreground: Palette.coral, background: Palette.coralSoft)
                        }
                    }
                    Text("Sun in \(astro.sunSign) · Moon in \(astro.moon.zodiacSign) · \(astro.moon.phaseName)")
                        .font(DS.label(12, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(app.aiHoroscope ?? "The desk writes today's horoscope from the real computed sky.")
                        .font(DS.deck(14))
                        .foregroundStyle(app.aiHoroscope == nil ? Palette.muted : Palette.ink)
                        .lineSpacing(3)
                    if AIService.isConfigured {
                        if app.aiBusy.contains("horoscope") {
                            ProgressView().controlSize(.small)
                        } else {
                            DeskAction(label: app.aiHoroscope == nil ? "Write it" : "Rewrite",
                                       systemImage: app.aiHoroscope == nil ? "pencil.line" : "arrow.clockwise") {
                                app.runHoroscope()
                            }
                        }
                    }
                }
                .inkPanel(padding: 15)
            }
            .padding(.top, 20)
        }
    }

    // MARK: Tarot

    private var tarotSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Cards")
                .padding(.bottom, 10)

            Text("Ask a question — or draw open-handed.")
                .font(DS.deck(13))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                TextField("What do I need to know about…", text: $question, axis: .vertical)
                    .font(DS.label(13, weight: .medium))
                    .padding(10)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
                Button {
                    drawSpread()
                } label: {
                    Text(spread.isEmpty ? "DRAW" : "REDRAW")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Palette.paper)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Palette.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(tarotBusy)
            }
            .padding(.bottom, 12)

            if !spread.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(spread.enumerated()), id: \.element.id) { index, card in
                        tarotCardFace(card, position: ["PAST", "PRESENT", "FUTURE"][min(index, 2)])
                    }
                }
                .padding(.bottom, 12)

                if let tarotReading {
                    Text(tarotReading)
                        .font(DS.deck(14))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(14)
                        .background(Palette.wash)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if tarotBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading the spread…")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                    }
                } else if let tarotError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tarotError)
                            .font(DS.label(11, weight: .medium))
                            .foregroundStyle(Palette.down)
                        DeskAction(label: "Read again", systemImage: "arrow.clockwise") {
                            requestReading()
                        }
                    }
                } else if !AIService.isConfigured {
                    Text("Add an AI key in Settings and the desk reads the spread against your question.")
                        .font(DS.label(11, weight: .regular))
                        .foregroundStyle(Palette.subtle)
                }
            }
        }
        .padding(.top, 24)
    }

    private func tarotCardFace(_ card: TarotCard, position: String) -> some View {
        VStack(spacing: 6) {
            Text(position)
                .kickerStyle(Palette.subtle, size: 7.5, tracking: 1.2)
            VStack(spacing: 4) {
                Text(card.reversed ? "⟲" : "✦")
                    .font(.system(size: 18))
                    .foregroundStyle(card.reversed ? Palette.violet : Palette.gold)
                Text(card.name)
                    .font(DS.display(13))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                if card.reversed {
                    Text("REVERSED")
                        .font(.system(size: 6.5, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Palette.violet)
                }
                Text(card.meaning)
                    .font(DS.label(9, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .padding(8)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(card.reversed ? Palette.violet.opacity(0.4) : Palette.line, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    private func drawSpread() {
        spread = Tarot.spread()
        requestReading()
    }

    /// Ask the desk to read the current spread; failures surface with a
    /// retry instead of vanishing.
    private func requestReading() {
        tarotReading = nil
        tarotError = nil
        guard AIService.isConfigured, !spread.isEmpty else { return }
        tarotBusy = true
        let cards = spread.enumerated().map { index, card in
            (position: ["Past", "Present", "Future"][min(index, 2)],
             name: card.name + (card.reversed ? " (reversed)" : ""),
             meaning: card.meaning)
        }
        let asked = question
        Task {
            defer { tarotBusy = false }
            do {
                tarotReading = try await AIDesk.tarotReading(question: asked, cards: cards)
            } catch let error as AIError {
                tarotError = error.readable
            } catch {
                tarotError = error.localizedDescription
            }
        }
    }

    // MARK: Oracle

    private var oracleSection: some View {
        let card = Oracle.daily()
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Oracle")
                .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S CARD").kickerStyle(Palette.coral, size: 8, tracking: 1.3)
                Text(card.name)
                    .font(DS.display(22))
                    .foregroundStyle(Palette.ink)
                Text(card.message)
                    .font(DS.deck(14))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(3)

                if let oracleReading {
                    InkRule().padding(.vertical, 8)
                    Text(oracleReading)
                        .font(DS.deck(14))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else if oracleBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading deeper…")
                            .font(DS.deck(13))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 8)
                } else if let oracleError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(oracleError)
                            .font(DS.label(11, weight: .medium))
                            .foregroundStyle(Palette.down)
                        DeskAction(label: "Read again", systemImage: "arrow.clockwise") {
                            Task { await loadOracleReading(force: true) }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialPanel()
        }
        .padding(.top, 24)
        .task { await loadOracleReading(force: false) }
    }

    /// The desk unfolds the daily card once per day; the reading is
    /// cached so reopening the page never redraws or re-bills.
    private func loadOracleReading(force: Bool) async {
        let card = Oracle.daily()
        // v2: the desk's voice moved to second person; retire v1 caches.
        let cacheKey = "daymark-oracle-reading-v2-\(Date().dayKey)-\(card.name)"
        if !force, let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
            oracleReading = cached
            return
        }
        guard AIService.isConfigured, !oracleBusy else { return }
        oracleBusy = true
        oracleError = nil
        defer { oracleBusy = false }
        do {
            let text = try await AIDesk.oracleReading(card: card.name, message: card.message)
            oracleReading = text
            UserDefaults.standard.set(text, forKey: cacheKey)
        } catch let error as AIError {
            oracleError = error.readable
        } catch {
            oracleError = error.localizedDescription
        }
    }

    // MARK: Crystal

    private var crystalSection: some View {
        let crystal = Crystals.daily()
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Crystal Cabinet")
                .padding(.bottom, 10)
            Button {
                showCabinet = true
            } label: {
                HStack(spacing: 12) {
                    Text("◆")
                        .font(.system(size: 26))
                        .foregroundStyle(Palette.violet)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(crystal.name)
                            .font(DS.label(15, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        Text("For \(crystal.property) — \(crystal.use).")
                            .font(DS.label(12, weight: .regular))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.leading)
                        Text("OPEN THE CABINET ›")
                            .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(Palette.coral)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Palette.coralSoft))
                            .padding(.top, 6)
                    }
                    Spacer()
                }
                .editorialPanel(padding: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
    }

    // MARK: Chakra

    private var chakraSection: some View {
        let chakra = Chakras.daily()
        return VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Chakra of the Day")
                .padding(.bottom, 10)
            Button {
                showChakraGuide = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(chakra.name.uppercased()) · \(chakra.sanskrit.uppercased())")
                            .kickerStyle(Palette.coral, size: 9, tracking: 1.3)
                        Spacer()
                        Circle().fill(chakraColor(chakra.color)).frame(width: 12, height: 12)
                    }
                    Text(chakra.theme.capitalized)
                        .font(DS.display(18))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text(chakra.practice)
                        .font(DS.deck(13.5))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.leading)
                    Text("THE FULL WHEEL ›")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Palette.coral)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(Palette.coralSoft))
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .editorialPanel()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
    }

    private func chakraColor(_ name: String) -> Color {
        switch name {
        case "red": return Color(hex: 0xC0392B)
        case "orange": return Color(hex: 0xE67E22)
        case "yellow": return Color(hex: 0xF1C40F)
        case "green": return Color(hex: 0x27AE60)
        case "blue": return Color(hex: 0x2980B9)
        case "indigo": return Color(hex: 0x34495E)
        default: return Color(hex: 0x8E44AD)
        }
    }

    // MARK: Meditation

    private var meditationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Sit")
                .padding(.bottom, 10)

            if let meditation {
                Text(meditation)
                    .font(DS.deck(15))
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .padding(.bottom, 12)
                HStack(spacing: 10) {
                    QuietButton(label: "Compose another") { composeMeditation() }
                    if !app.focusRunning {
                        QuietButton(label: "Sit for 5 minutes") { app.startFocus(cappedToMinutes: 5) }
                    }
                }
            } else if meditationBusy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Composing today's sit…")
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.muted)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A short guided meditation, composed for today — the weather, the moon, the chakra, the shape of your calendar.")
                        .font(DS.deck(13.5))
                        .foregroundStyle(Palette.muted)
                    if AIService.isConfigured {
                        AcidButton(label: "Compose today's sit", systemImage: "leaf.fill") {
                            composeMeditation()
                        }
                    } else {
                        Text("Add an AI key in Settings first.")
                            .font(DS.label(11, weight: .regular))
                            .foregroundStyle(Palette.subtle)
                    }
                }
            }
        }
        .padding(.top, 24)
    }

    private func composeMeditation() {
        meditationBusy = true
        let chakra = Chakras.daily()
        var theme = "Chakra focus: \(chakra.name) — \(chakra.theme)."
        if let weather = app.weather {
            theme += " Weather: \(weather.tempF)°, \(weather.description)."
        }
        if let astro = app.astro {
            theme += " Moon: \(astro.moon.phaseName) in \(astro.moon.zodiacSign)."
        }
        theme += " Open items today: \(app.openLoops)."
        Task {
            defer { meditationBusy = false }
            meditation = try? await AIDesk.meditation(theme: theme)
        }
    }
}

// MARK: - The full crystal cabinet

private struct CrystalCabinetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var openStone: String?
    private let today = Crystals.daily()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE CRYSTAL CABINET")
                        .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                        .padding(.bottom, 8)
                    Text("Fourteen stones, one shelf.")
                        .font(DS.display(28))
                        .foregroundStyle(Palette.ink)
                    Text("Tap a stone for what it's best used for and how to work with it. One rotates through the desk each day.")
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 6)
                    InkRule().padding(.vertical, 14)

                    VStack(spacing: 10) {
                        ForEach(Crystals.cabinet, id: \.name) { crystal in
                            stoneRow(crystal)
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

    private func stoneRow(_ crystal: Crystal) -> some View {
        let isOpen = openStone == crystal.name
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                openStone = isOpen ? nil : crystal.name
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("◆")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.violet)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(crystal.name)
                                .font(DS.label(14, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            if crystal == today {
                                Text("TODAY")
                                    .font(.system(size: 7, weight: .heavy)).tracking(1.0)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Palette.coral)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(crystal.property.capitalized)
                            .font(DS.label(11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.subtle)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                if isOpen {
                    HStack(spacing: 6) {
                        ForEach(crystal.intentions, id: \.self) { intention in
                            Text(intention.uppercased())
                                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(Palette.violet)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Palette.violet.opacity(0.09))
                                .clipShape(Capsule())
                        }
                    }
                    Text(crystal.practice)
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.ink)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialPanel(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The chakra wheel guide

private struct ChakraGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var openChakra: String?
    private let today = Chakras.daily()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("THE CHAKRA WHEEL")
                        .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                        .padding(.bottom, 8)
                    Text("Seven centers, one ladder.")
                        .font(DS.display(28))
                        .foregroundStyle(Palette.ink)
                    Text(Chakras.systemNote)
                        .font(DS.deck(13))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(3)
                        .padding(.top, 8)
                    InkRule().padding(.vertical, 14)

                    VStack(spacing: 10) {
                        ForEach(Chakras.wheel.reversed(), id: \.name) { chakra in
                            chakraRow(chakra)
                        }
                    }
                    Text("Listed crown to root, the way the wheel sits in the body — balanced from the bottom up.")
                        .font(DS.label(10, weight: .regular))
                        .foregroundStyle(Palette.subtle)
                        .padding(.top, 10)
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

    private func chakraRow(_ chakra: Chakra) -> some View {
        let isOpen = openChakra == chakra.name
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                openChakra = isOpen ? nil : chakra.name
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Circle().fill(color(chakra.color)).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(chakra.name) · \(chakra.sanskrit)")
                                .font(DS.label(14, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            if chakra == today {
                                Text("TODAY")
                                    .font(.system(size: 7, weight: .heavy)).tracking(1.0)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Palette.coral)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(chakra.theme.capitalized)
                            .font(DS.label(11, weight: .regular))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.subtle)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                if isOpen {
                    detailLine(kicker: "WHERE", text: chakra.location)
                    detailLine(kicker: "OUT OF BALANCE", text: chakra.signs)
                    detailLine(kicker: "TO BALANCE", text: chakra.practice)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialPanel(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func detailLine(kicker: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker)
                .font(.system(size: 7.5, weight: .heavy)).tracking(1.1)
                .foregroundStyle(Palette.coral)
            Text(text)
                .font(DS.deck(13))
                .foregroundStyle(Palette.ink)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
        }
    }

    private func color(_ name: String) -> Color {
        switch name {
        case "red": return Color(hex: 0xC0392B)
        case "orange": return Color(hex: 0xE67E22)
        case "yellow": return Color(hex: 0xF1C40F)
        case "green": return Color(hex: 0x27AE60)
        case "blue": return Color(hex: 0x2980B9)
        case "indigo": return Color(hex: 0x34495E)
        default: return Color(hex: 0x8E44AD)
        }
    }
}
