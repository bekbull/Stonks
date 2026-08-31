import Foundation

nonisolated enum StockTicker: String, CaseIterable, Equatable, Hashable, Sendable {
    case aapl = "AAPL"
    case msft = "MSFT"
    case nvda = "NVDA"
    case amzn = "AMZN"
    case googl = "GOOGL"
    case meta = "META"
    case tsla = "TSLA"
    case jpm = "JPM"
    case xom = "XOM"
    case wmt = "WMT"

    static let configuredOrder = allCases
}

nonisolated struct StockQuote: Equatable, Sendable {
    let ticker: StockTicker
    let currentPrice: Double
    let dailyChange: Double
    let dailyChangeFraction: Double
    let previousClose: Double
    let updatedAt: Date?
}

nonisolated struct CompanyProfile: Equatable, Sendable {
    let ticker: StockTicker
    let name: String
    let industry: String?
    let exchange: String?
    let currencyCode: String?
}

nonisolated enum StockError: Error, Equatable, Sendable {
    case missingAPIKey
    case authorization
    case rateLimited
    case connectivity
    case server
    case decoding
    case unavailable
}

nonisolated struct StockCard: Equatable, Sendable {
    let ticker: StockTicker
    let quote: StockQuote?
    let profile: CompanyProfile?
    let quoteError: StockError?
    let profileError: StockError?
}

nonisolated struct MarketMover: Equatable, Sendable {
    let ticker: StockTicker
    let dailyChangeFraction: Double
}

nonisolated struct MarketMovers: Equatable, Sendable {
    let best: MarketMover
    let worst: MarketMover

    static func from(cards: [StockCard]) -> Self? {
        let eligible = cards.compactMap { card -> (index: Int, quote: StockQuote)? in
            guard
                let quote = card.quote,
                quote.dailyChangeFraction.isFinite,
                let index = StockTicker.configuredOrder.firstIndex(of: card.ticker)
            else { return nil }
            return (index, quote)
        }
        guard eligible.count >= 2 else { return nil }

        let best = eligible.max { lhs, rhs in
            if lhs.quote.dailyChangeFraction != rhs.quote.dailyChangeFraction {
                return lhs.quote.dailyChangeFraction < rhs.quote.dailyChangeFraction
            }
            return lhs.index > rhs.index
        }!
        let worst = eligible.min { lhs, rhs in
            if lhs.quote.dailyChangeFraction != rhs.quote.dailyChangeFraction {
                return lhs.quote.dailyChangeFraction < rhs.quote.dailyChangeFraction
            }
            return lhs.index < rhs.index
        }!

        return Self(
            best: MarketMover(
                ticker: best.quote.ticker,
                dailyChangeFraction: best.quote.dailyChangeFraction
            ),
            worst: MarketMover(
                ticker: worst.quote.ticker,
                dailyChangeFraction: worst.quote.dailyChangeFraction
            )
        )
    }
}
