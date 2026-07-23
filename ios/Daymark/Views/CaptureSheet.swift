//
//  CaptureSheet.swift
//  Daymark
//
//  Quick capture: get it out of your head — task, job lead, reading, reminder.
//

import SwiftUI
import PhotosUI

struct CaptureSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CaptureKind = .task
    @State private var title = ""
    @State private var url = ""
    @State private var note = ""
    @State private var photo: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
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

                Text(destinationNote)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.subtle)

                VStack(alignment: .leading, spacing: 12) {
                    captureField("What needs your attention?", text: $title)
                        .focused($titleFocused)
                    if kind == .reading || kind == .job {
                        captureField("Link (optional)", text: $url, keyboard: .URL)
                    }
                    captureField(kind == .job ? "Role (optional)" : "Note or next step (optional)", text: $note)
                    photoRow
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

    // MARK: Photo

    /// Attach a photo to a task or reminder — snap it or pull it from
    /// the library. Job leads and reading save elsewhere, so no photo.
    @ViewBuilder
    private var photoRow: some View {
        if kind == .task || kind == .reminder {
            if let photo {
                HStack(spacing: 12) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line, lineWidth: 1))
                    Text("PHOTO ATTACHED")
                        .kickerStyle(Palette.subtle, size: 8.5, tracking: 1.2)
                    Spacer()
                    Button {
                        self.photo = nil
                        libraryItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.subtle)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(Palette.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Label("Photo library", systemImage: "photo.on.rectangle")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(Palette.line, lineWidth: 1))
                    }
                    Spacer()
                }
                .onChange(of: libraryItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            photo = image
                        }
                    }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { image in photo = image }
                        .ignoresSafeArea()
                }
            }
        }
    }

    /// Where this capture lands — the fan-out, made visible.
    private var destinationNote: String {
        switch kind {
        case .task: return "Files to: Today's inbox"
        case .job: return "Files to: the job pipeline (Work)"
        case .reading: return "Files to: the Reading List (Media)"
        case .reminder: return "Files to: Practical reminders (Life)"
        }
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
        let imageFile = (kind == .task || kind == .reminder) ? photo.flatMap(CaptureImages.save) : nil
        app.addCapture(kind: kind, title: cleanTitle, url: url.nilIfEmpty, note: note.nilIfEmpty,
                       imageFile: imageFile)
        dismiss()
    }
}

/// The system camera, feeding one still back to the capture sheet.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
