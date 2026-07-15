//
//  MarketsService.swift
//  Daymark
//
//  Watchlist quotes from Stooq CSV (no key; delayed data, labeled as such).
//

import Foundation

enum MarketsService {
    static func fetch(_ symbols: [WatchSymbol]) async -> [MarketQuote] {
        var quotes: [MarketQuote] = []
        await withTaskGroup(of: MarketQuote?.self) { group in
            for symbol in symbols {
                group.addTask { await quote(for: symbol) }
            }
            for await quote in group {
                if let quote { quotes.append(quote) }
            }
        }
        // Preserve the user's watchlist ordering.
        let order = Dictionary(uniqueKeysWithValues: symbols.enumerated().map { ($1.symbol, $0) })
        return quotes.sorted { (order[$0.symbol] ?? 99) < (order[$1.symbol] ?? 99) }
    }

    private static func quote(for symbol: WatchSymbol) async -> MarketQuote? {
        // Last ~3 weeks of daily closes; the final row is the latest session.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let d1 = formatter.string(from: Date().addingDays(-21))
        let d2 = formatter.string(from: Date())
        let encoded = symbol.symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol.symbol
        guard let url = URL(string: "https://stooq.com/q/d/l/?s=\(encoded)&i=d&d1=\(d1)&d2=\(d2)"),
              let data = try? await HTTP.data(url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        // CSV: Date,Open,High,Low,Close,Volume
        let closes: [Double] = text
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let cells = line.split(separator: ",", omittingEmptySubsequences: false)
                guard cells.count >= 5 else { return nil }
                return Double(String(cells[4]))
            }
        guard closes.count >= 2, let last = closes.last else { return nil }
        let previous = closes[closes.count - 2]
        let change = last - previous
        let pct = previous != 0 ? (change / previous) * 100 : 0
        return MarketQuote(
            symbol: symbol.symbol,
            label: symbol.label,
            price: last,
            change: change,
            changePct: pct
        )
    }
}
