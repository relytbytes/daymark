//
//  CaptureSheet.swift
//  Daymark
//
//  Quick capture: get it out of your head — task, job lead, reading, reminder.
//

import SwiftUI

struct CaptureSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CaptureKind = .task
    @State private var title = ""
    @State private var url = ""
    @State private var note = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("QUICK CAPTURE").kickerStyle(Palette.coral, size: 9, tracking: 1.5)
                    Text("Get it out of your head.")
                        .font(DS.display(28))
                        .foregroundStyle(Palette.ink)
                }

                // type selector
                HStack(spacing: 7) {
                    ForEach(CaptureKind.allCases) { candidate in
                        let active = kind == candidate
                        Button {
                            kind = candidate
                        } label: {
                            Text(candidate.label)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(active ? Palette.card : Palette.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(active ? Palette.ink : Palette.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 999)
                                        .stroke(Palette.line, lineWidth: active ? 0 : 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 999))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    captureField("What needs your attention?", text: $title)
                        .focused($titleFocused)
                    if kind == .reading || kind == .job {
                        captureField("Link (optional)", text: $url, keyboard: .URL)
                    }
                    captureField(kind == .job ? "Role (optional)" : "Note or next step (optional)", text: $note)
                }

                AcidButton(label: "Save to Daymark", systemImage: "tray.and.arrow.down.fill") {
                    save()
                }
                .disabled(title.nilIfEmpty == nil)
                .opacity(title.nilIfEmpty == nil ? 0.5 : 1)

                Spacer()
            }
            .padding(22)
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { titleFocused = true }
    }

    private func captureField(_ placeholder: String, text: Binding<String>,
                              keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
            .autocorrectionDisabled(keyboard == .URL)
            .font(DS.label(15, weight: .medium))
            .padding(13)
            .background(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func save() {
        guard let cleanTitle = title.nilIfEmpty else { return }
        app.addCapture(kind: kind, title: cleanTitle, url: url.nilIfEmpty, note: note.nilIfEmpty)
        dismiss()
    }
}
