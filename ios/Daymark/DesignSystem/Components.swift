//
//  Components.swift
//  Daymark
//
//  Reusable editorial components: masthead, At-a-Glance ribbon, rules,
//  section headers, chips, buttons.
//

import SwiftUI
import SafariServices

// MARK: - Rules & marks

struct InkRule: View {
    var height: CGFloat = 2
    var body: some View {
        Rectangle().fill(Palette.ink).frame(height: height)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

/// The Daymark brand mark: three ascending bars, third in coral.
struct BrandMark: View {
    var scale: CGFloat = 1
    var body: some View {
        HStack(alignment: .bottom, spacing: 2 * scale) {
            Capsule().fill(Palette.subtle).frame(width: 3 * scale, height: 5 * scale)
            Capsule().fill(Palette.subtle).frame(width: 3 * scale, height: 8 * scale)
            Capsule().fill(Palette.coral).frame(width: 3 * scale, height: 11 * scale)
        }
    }
}

// MARK: - Masthead

/// Brand microline: tiny "DAYMARK" + section tag + utility buttons.
struct MastheadTopline: View {
    let tag: String
    var refreshing: Bool = false
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                BrandMark()
                Text("DAYMARK").kickerStyle(Palette.subtle, size: 9, tracking: 1.6)
            }
            Spacer()
            Text(tag.uppercased()).kickerStyle(Palette.subtle, size: 9, tracking: 1.3)
                .lineLimit(1)
            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(refreshing ? Palette.coral : Palette.subtle)
                        .rotationEffect(.degrees(refreshing ? 180 : 0))
                        .animation(refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: refreshing)
                }
                .accessibilityLabel("Refresh")
            }
            if let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.subtle)
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}

/// Dateline, phase, big serif title, ink rule.
struct Masthead: View {
    let dateline: String
    let phaseLabel: String
    let accent: Color
    let title: Text
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dateline.uppercased()).kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(phaseLabel.uppercased()).kickerStyle(Palette.subtle, size: 9, tracking: 0.8)
                }
            }
            .padding(.bottom, 10)

            title
                .font(DS.display(42))
                .foregroundStyle(Palette.ink)
                .lineSpacing(-2)
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            if let note {
                Text(note)
                    .font(DS.deck(15))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 7)
            }

            InkRule().padding(.top, 13)
        }
    }
}

// MARK: - At a Glance

struct GlanceCellModel: Identifiable {
    let id: String
    let label: String
    let value: String
    let sub: String
    var accent: Bool = false
    var symbol: String?
    var symbolColor: Color = Palette.gold
}

struct GlanceRibbon: View {
    let cells: [GlanceCellModel]

    var body: some View {
        VStack(spacing: 0) {
            Text("AT A GLANCE")
                .kickerStyle(Palette.subtle, size: 8, tracking: 1.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            Hairline()
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    if index > 0 {
                        Rectangle().fill(Palette.hairlineSoft)
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, 6)
                    }
                    GlanceCell(model: cell)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Hairline()
        }
    }
}

private struct GlanceCell: View {
    let model: GlanceCellModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.label.uppercased())
                .kickerStyle(Palette.subtle, size: 7.5, tracking: 1.0)
                .lineLimit(1)
                .padding(.bottom, 7)
            HStack(spacing: 4) {
                if let symbol = model.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.symbolColor)
                }
                Text(model.value)
                    .font(DS.display(19))
                    .foregroundStyle(model.accent ? Palette.coral : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            Text(model.sub)
                .font(DS.label(8.5))
                .foregroundStyle(Palette.subtle)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .padding(.horizontal, 3)
    }
}

/// Thin day-progress bar under the ribbon.
struct DayProgressBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.paperDeep)
                Capsule().fill(accent)
                    .frame(width: max(3, geo.size.width * progress))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Section headers

/// Hairline — TITLE — hairline, serif smallcaps (the newspaper section header).
struct SectionRuleHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.ink.opacity(0.25)).frame(height: 1)
            Text(title.uppercased())
                .font(DS.display(14))
                .tracking(1.0)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
            Rectangle().fill(Palette.ink.opacity(0.25)).frame(height: 1)
        }
    }
}

/// Coral kicker over a serif headline, with optional trailing accessory.
struct SectionKickerHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var trailing: Trailing

    init(kicker: String, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.kicker = kicker
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker.uppercased()).kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                Text(title)
                    .font(DS.display(26))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

// MARK: - Chips & buttons

struct StatusChip: View {
    let text: String
    var foreground: Color = Palette.acidInk
    var background: Color = Palette.acid

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Full-width acid call-to-action (the "Begin — 25:00" button).
struct AcidButton: View {
    let label: String
    var systemImage: String = "play.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .black))
                Text(label).font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Palette.acid)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Small round-cornered secondary action.
struct QuietButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.card)
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(Palette.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 999))
        }
        .buttonStyle(.plain)
    }
}

/// Data-freshness stamp, honest about staleness like the web app.
struct AgeStamp: View {
    let status: FeedStatus

    var body: some View {
        Text(status.label.uppercased())
            .kickerStyle(statusColor, size: 8, tracking: 1.0)
    }

    private var statusColor: Color {
        switch status {
        case .live: return Palette.subtle
        case .cached: return Palette.gold
        case .unavailable: return Palette.coral
        default: return Palette.subtle
        }
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.deck(14))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
}

/// Circular tap-to-complete check, roman-numeral rows use it.
struct CircleCheck: View {
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(checked ? Palette.ink : Color(hex: 0x9A978D), lineWidth: 1.5)
                    .background(Circle().fill(checked ? Palette.ink : .clear))
                    .frame(width: 24, height: 24)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.acid)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(checked ? "Completed" : "Mark complete")
    }
}

// MARK: - Safari

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Palette.ink)
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
