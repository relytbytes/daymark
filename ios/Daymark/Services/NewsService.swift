//
//  NewsService.swift
//  Daymark
//
//  Morning headlines aggregated from user-configurable RSS/Atom feeds.
//

import Foundation

enum NewsService {
    static func fetch(feeds: [FeedSource]) async -> [NewsArticle] {
        var articles: [NewsArticle] = []
        await withTaskGroup(of: [NewsArticle].self) { group in
            for feed in feeds {
                group.addTask {
                    guard let url = URL(string: feed.url),
                          let data = try? await HTTP.data(url)
                    else { return [] }
                    return RSSParser().parse(data: data, source: feed.name)
                }
            }
            for await batch in group {
                articles.append(contentsOf: batch)
            }
        }
        // Cluster the same story across feeds, newest first, keep it a brief.
        return cluster(articles).prefix(24).map { $0 }
    }

    /// Collapse articles whose titles share most of their significant words —
    /// the same story carried by several feeds becomes one item with a
    /// "+N sources" note.
    static func cluster(_ articles: [NewsArticle]) -> [NewsArticle] {
        let stopWords: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "for", "and", "as", "at", "is", "are", "with", "after", "over", "new"]
        func tokens(_ title: String) -> Set<String> {
            Set(title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) })
        }

        let sorted = articles.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        var out: [NewsArticle] = []
        var outTokens: [Set<String>] = []

        for article in sorted {
            let t = tokens(article.title)
            var merged = false
            for index in out.indices where !t.isEmpty {
                let overlap = t.intersection(outTokens[index]).count
                let smaller = min(t.count, outTokens[index].count)
                if smaller >= 3, Double(overlap) >= 0.6 * Double(smaller) {
                    if out[index].source != article.source,
                       !out[index].otherSources.contains(article.source) {
                        out[index].otherSources.append(article.source)
                    }
                    merged = true
                    break
                }
            }
            if !merged {
                out.append(article)
                outTokens.append(t)
            }
        }
        return out
    }
}

/// Tolerant RSS 2.0 + Atom parser built on Foundation's XMLParser.
final class RSSParser: NSObject, XMLParserDelegate {
    private var articles: [NewsArticle] = []
    private var source = ""

    private var inItem = false
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private var atomLink = ""
    private var dateText = ""

    func parse(data: Data, source: String) -> [NewsArticle] {
        self.source = source
        articles = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return articles
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let name = element.lowercased()
        if name == "item" || name == "entry" {
            inItem = true
            title = ""; link = ""; atomLink = ""; dateText = ""
        } else if inItem {
            currentElement = name
            if name == "link", let href = attributes["href"] {
                let rel = attributes["rel"] ?? "alternate"
                if rel == "alternate" || atomLink.isEmpty { atomLink = href }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "pubdate", "published", "updated", "dc:date": dateText += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inItem, currentElement == "title",
              let text = String(data: CDATABlock, encoding: .utf8) else { return }
        title += text
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        let name = element.lowercased()
        if name == "item" || name == "entry" {
            inItem = false
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = rawLink.isEmpty ? atomLink : rawLink
            if !cleanTitle.isEmpty, let url = URL(string: resolved), url.scheme?.hasPrefix("http") == true {
                articles.append(NewsArticle(
                    title: cleanTitle,
                    link: url,
                    source: source,
                    published: Self.parseDate(dateText.trimmingCharacters(in: .whitespacesAndNewlines))
                ))
            }
        } else {
            currentElement = ""
        }
    }

    private static let formatters: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss Z",
         "EEE, dd MMM yyyy HH:mm:ss zzz",
         "yyyy-MM-dd'T'HH:mm:ssZ",
         "yyyy-MM-dd'T'HH:mm:ss.SSSZ"].map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f
        }
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    static func parseDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: text) { return date }
        }
        return isoFormatter.date(from: text)
    }
}
