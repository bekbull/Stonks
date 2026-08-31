import ComposableArchitecture
import SwiftUI

@ViewAction(for: StocksFeature.self)
struct StocksView: View {
    let store: StoreOf<StocksFeature>

    var body: some View {
        NavigationStack {
            Group {
                if store.cards.isEmpty && store.screenMessage == nil && store.phase != .refreshing {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading stocks").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    stockList
                }
            }
            .task { await send(.task).finish() }
            .navigationTitle("Stocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log out", systemImage: "rectangle.portrait.and.arrow.right") {
                        send(.logoutButtonTapped)
                    }
                }
            }
        }
    }

    private var stockList: some View {
        List {
            if let message = store.screenMessage {
                Section { Label(message.text, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
            }
            Section("Daily movers") { DailyMoversView(movers: store.marketMovers) }
            Section("Stocks") {
                ForEach(store.cards, id: \.ticker) { card in StockCardView(card: card) }
            }
        }
        .refreshable { await send(.refresh).finish() }
    }
}

struct DailyMoversView: View {
    let movers: MarketMovers?

    var body: some View {
        if let movers {
            VStack(alignment: .leading, spacing: 6) {
                moverRow(title: "Best", mover: movers.best)
                moverRow(title: "Worst", mover: movers.worst)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Not enough quote data").foregroundStyle(.secondary)
        }
    }

    private func moverRow(title: String, mover: MarketMover) -> some View {
        AdaptiveMoverRow(title: title, mover: mover)
    }
}

struct AdaptiveMoverRow: View {
    let title: String
    let mover: MarketMover

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalRow
            verticalRow
        }
    }

    private var horizontalRow: some View {
        HStack {
            titleText
            tickerText
            Spacer()
            percentText
        }
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                titleText
                tickerText
            }
            percentText
        }
    }

    private var titleText: some View {
        Text(title).font(.subheadline.weight(.semibold)).fixedSize()
    }

    private var tickerText: some View {
        Text(mover.ticker.rawValue).font(.subheadline).fixedSize()
    }

    private var percentText: some View {
        Text(signedPercent(mover.dailyChangeFraction))
            .foregroundStyle(changeColor(mover.dailyChangeFraction))
            .font(.subheadline.monospacedDigit())
            .fixedSize()
    }
}

struct StockCardView: View {
    let card: StockCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdaptiveStockHeader(card: card)
            Text(card.profile?.name ?? "Company information unavailable")
                .font(.subheadline).foregroundStyle(.secondary)
            if let quote = card.quote {
                Text(signedPercent(quote.dailyChangeFraction))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(changeColor(quote.dailyChangeFraction))
            }
            if let industry = card.profile?.industry, !industry.isEmpty {
                Text(industry).font(.caption).foregroundStyle(.secondary)
            }
            if let exchange = card.profile?.exchange, !exchange.isEmpty {
                Text(exchange).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let company = card.profile?.name ?? "Company information unavailable"
        let price = card.quote.map { $0.currentPrice.formatted(.currency(code: card.profile?.currencyCode ?? "USD")) } ?? (card.profile == nil ? "Data unavailable" : "Quote unavailable")
        let change = card.quote.map { signedPercent($0.dailyChangeFraction) } ?? "change unavailable"
        return "\(card.ticker.rawValue), \(company), price \(price), daily change \(change)"
    }
}

struct AdaptiveStockHeader: View {
    let card: StockCard

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalHeader
            verticalHeader
        }
    }

    private var horizontalHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            tickerLabel
            Spacer()
            priceLabel
        }
    }

    private var verticalHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            tickerLabel
            priceLabel
        }
    }

    private var tickerLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(card.ticker.rawValue).font(.headline).fixedSize()
        }
    }

    @ViewBuilder
    private var priceLabel: some View {
        if let quote = card.quote {
            Text(quote.currentPrice.formatted(.currency(code: card.profile?.currencyCode ?? "USD")))
                .font(.headline.monospacedDigit())
                .fixedSize()
        } else {
            UnavailableStockValueLabel(text: card.profile == nil ? "Data unavailable" : "Quote unavailable")
        }
    }
}

struct UnavailableStockValueLabel: View {
    let text: String

    var body: some View {
        Text(text).foregroundStyle(.secondary)
    }
}

private func signedPercent(_ fraction: Double) -> String {
    let magnitude = abs(fraction).formatted(.percent.precision(.fractionLength(2)))
    if fraction > 0 { return "+\(magnitude)" }
    if fraction < 0 { return "-\(magnitude)" }
    return magnitude
}

private func changeColor(_ fraction: Double) -> Color {
    if fraction > 0 { return .green }
    if fraction < 0 { return .red }
    return .secondary
}

#Preview("Loaded") {
    let cards = StocksPreviewFixtures.loadedCards
    return StocksView(store: Store(initialState: StocksFeature.State(cards: cards, phase: .idle)) { StocksFeature() } withDependencies: {
        $0.stockClient.load = { _, _ in cards }
    })
}

#Preview("Partial") {
    let state = StocksPreviewFixtures.partialState
    return StocksView(store: Store(initialState: state) { StocksFeature() } withDependencies: {
        $0.stockClient.load = { _, _ in StocksPreviewFixtures.partialCards }
    })
}

#Preview("Loading") {
    StocksView(store: Store(initialState: StocksFeature.State()) { StocksFeature() } withDependencies: {
        $0.stockClient = StocksPreviewFixtures.loadingClient
    })
}

nonisolated enum StocksPreviewFixtures {
    static let loadedCards: [StockCard] = StockTicker.configuredOrder.prefix(2).map { ticker in
        StockCard(ticker: ticker, quote: StockQuote(ticker: ticker, currentPrice: 100, dailyChange: 1, dailyChangeFraction: 0.01, previousClose: 99, updatedAt: nil), profile: CompanyProfile(ticker: ticker, name: "\(ticker.rawValue) Company", industry: "Technology", exchange: "NASDAQ", currencyCode: "USD"), quoteError: nil, profileError: nil)
    }

    static let partialCards: [StockCard] = [
        StockCard(ticker: .aapl, quote: nil, profile: CompanyProfile(ticker: .aapl, name: "AAPL Company", industry: "Technology", exchange: "NASDAQ", currencyCode: "USD"), quoteError: .rateLimited, profileError: nil)
    ]

    @MainActor static let partialState = StocksFeature.State(cards: partialCards, phase: .idle, screenMessage: .rateLimited)

    static var loadingClient: StockClient {
        StockClient(load: { _, _ in
            try await Task.sleep(for: .seconds(86_400))
            return []
        })
    }
}
