//
//  ArticleService.swift
//  Daymark
//
//  Fetches a saved page and boils it down to readable text — enough
//  for the desk to summarize a story or read it aloud. Deliberately
//  simple: strip the chrome, keep the paragraphs.
//

import Foundation

enum ArticleService {
    /// Fetch a page and return its readable text, capped for prompts.
    static func extract(_ url: URL, limit: Int = 7000) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone) Daymark/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        let text = readableText(from: html)
        guard text.count > 200 else { return nil }   // paywall shells and error pages
        return String(text.prefix(limit))
    }

    static func readableText(from html: String) -> String {
        var work = html
        // Cut the parts that are never prose.
        for tag in ["script", "style", "noscript", "svg", "nav", "header", "footer", "form", "aside"] {
            work = work.replacingOccurrences(
                of: "<\(tag)[\\s\\S]*?</\(tag)>", with: " ",
                options: [.regularExpression, .caseInsensitive])
        }
        // Prefer the article body when the page marks one.
        if let range = work.range(of: "<article[\\s\\S]*?</article>",
                                  options: [.regularExpression, .caseInsensitive]) {
            work = String(work[range])
        }
        // Paragraph and heading breaks become newlines, then all tags go.
        work = work.replacingOccurrences(of: "</(p|h1|h2|h3|li|blockquote)>",
                                         with: "\n", options: [.regularExpression, .caseInsensitive])
        work = work.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // The entities that actually show up in prose.
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&rsquo;", "'"), ("&lsquo;", "'"),
            ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}"), ("&hellip;", "…"),
        ]
        for (entity, plain) in entities {
            work = work.replacingOccurrences(of: entity, with: plain)
        }
        work = work.replacingOccurrences(of: "&#(\\d+);", with: " ", options: .regularExpression)
        // Collapse whitespace, keep paragraph breaks.
        let lines = work
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 40 }    // drop menu crumbs and bylines-of-noise
        return lines.joined(separator: "\n\n")
    }
}
