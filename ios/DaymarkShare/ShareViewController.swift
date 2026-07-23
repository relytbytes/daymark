//
//  ShareViewController.swift
//  DaymarkShare — the share sheet's filing window: grab the page (or
//  text), ask which desk it belongs to, queue it in the App Group,
//  and get out of the way.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadSharedContent { [weak self] title, url in
            guard let self else { return }
            let card = ShareCard(
                title: title,
                url: url,
                onFile: { kind in
                    SharedCaptures.enqueue(SharedCaptures.Item(
                        kind: kind, title: title,
                        url: url, note: nil))
                    self.finish()
                },
                onCancel: {
                    self.extensionContext?.cancelRequest(withError: NSError(
                        domain: "com.relytbytes.daymark.share", code: 0))
                }
            )
            let host = UIHostingController(rootView: card)
            host.view.backgroundColor = .clear
            self.addChild(host)
            self.view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
            ])
            host.didMove(toParent: self)
        }
    }

    private func finish() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Pull a title and URL out of whatever the host app handed over.
    private func loadSharedContent(completion: @escaping (String, String?) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let fallbackTitle = items.first?.attributedContentText?.string
            ?? items.first?.attributedTitle?.string
        let attachments = items.flatMap { $0.attachments ?? [] }

        let group = DispatchGroup()
        var foundURL: String?
        var foundText: String?

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    if let url = item as? URL { foundURL = foundURL ?? url.absoluteString }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    if let text = item as? String { foundText = foundText ?? text }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let title = fallbackTitle?.nilIfBlank
                ?? foundText?.nilIfBlank
                ?? foundURL.flatMap { URL(string: $0)?.host }
                ?? "Shared item"
            completion(String(title.prefix(140)), foundURL)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

// MARK: - The filing card

private struct ShareCard: View {
    let title: String
    let url: String?
    let onFile: (String) -> Void
    let onCancel: () -> Void

    @State private var filed: String?

    private let paper = Color(red: 0.992, green: 0.992, blue: 0.988)
    private let ink = Color(red: 0.078, green: 0.078, blue: 0.070)
    private let muted = Color(red: 0.459, green: 0.447, blue: 0.424)
    private let red = Color(red: 0.784, green: 0.063, blue: 0.180)
    private let coral = Color(red: 0.910, green: 0.290, blue: 0.235)

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("FILE TO DAYMARK")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(red)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(muted)
                    }
                }
                .padding(.bottom, 10)

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(3)
                if let url, let host = URL(string: url)?.host {
                    Text(host.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1)
                        .foregroundStyle(muted)
                        .padding(.top, 3)
                }

                if let filed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.055, green: 0.624, blue: 0.431))
                        Text(filed)
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    HStack(spacing: 8) {
                        fileButton("Read later", icon: "book", kind: "reading",
                                   confirmation: "On the reading queue.")
                        fileButton("Job lead", icon: "briefcase", kind: "job",
                                   confirmation: "In the job pipeline.")
                        fileButton("Task", icon: "tray", kind: "task",
                                   confirmation: "In the inbox.")
                    }
                    .padding(.top, 16)
                }
            }
            .padding(18)
            .background(paper)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
    }

    private func fileButton(_ label: String, icon: String, kind: String,
                            confirmation: String) -> some View {
        Button {
            filed = confirmation
            onFile(kind)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(coral.opacity(0.12))
            .foregroundStyle(coral)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
