//
//  MarketsService.swift
//  Daymark
//
//  Watchlist quotes from Yahoo Finance's chart API (no key; delayed
//  data, labeled as such). Stooq, the previous source, now sits behind
//  a JavaScript proof-of-work wall and can't be fetched natively.
//

import Foundation

enum MarketsService {
    /// Legacy Stooq-style index symbols map to Yahoo's tickers; plain
    /// stock symbols pass through unchanged.
    private static let yahooAliases = [
        "^spx": "^GSPC",
        "^dji": "^DJI",
        "^ndq": "^IXIC",
    ]

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
        let ticker = yahooAliases[symbol.symbol.lowercased()] ?? symbol.symbol.uppercased()
        let encoded = ticker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticker
        guard let url = URL(string:
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1mo&interval=1d")
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
                         forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) != false
        else { return nil }

        struct Chart: Decodable {
            struct Wrapper: Decodable { let result: [Result]? }
            struct Result: Decodable {
                struct Indicators: Decodable {
                    struct Quote: Decodable { let close: [Double?]? }
                    let quote: [Quote]?
                }
                let indicators: Indicators?
            }
            let chart: Wrapper
        }
        // The final close is the live/latest session; the one before it
        // is the prior close the change is measured against.
        guard let parsed = try? JSONDecoder().decode(Chart.self, from: data),
              let closes = parsed.chart.result?.first?.indicators?.quote?.first?.close?
                  .compactMap({ $0 }),
              closes.count >= 2,
              let last = closes.last
        else { return nil }

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
