import ComposableArchitecture

@DependencyClient
nonisolated struct StockClient: Sendable {
    var load: @Sendable (
        _ tickers: [StockTicker],
        _ reusedProfiles: [StockTicker: CompanyProfile]
    ) async throws -> [StockCard]
}

extension StockClient: TestDependencyKey {
    static let testValue = Self()
}

extension StockClient: DependencyKey {
    static let liveValue = Self.failing(.missingAPIKey)
}

extension DependencyValues {
    var stockClient: StockClient {
        get { self[StockClient.self] }
        set { self[StockClient.self] = newValue }
    }
}

extension StockClient {
    static func live(api: FinnhubStockAPI, maxConcurrentTickers: Int = 5) -> Self {
        let limit = max(1, maxConcurrentTickers)
        return Self(load: { tickers, reusedProfiles in
            guard !tickers.isEmpty else { return [] }
            let api = api
            var ordered = Array<StockCard?>(repeating: nil, count: tickers.count)
            var nextIndex = min(limit, tickers.count)

            try await withThrowingTaskGroup(of: IndexedCard.self) { group in
                for index in 0..<nextIndex {
                    try Task.checkCancellation()
                    let enqueued = group.addTaskUnlessCancelled {
                        try await Self.loadCard(tickers[index], index: index, api: api, reusedProfile: reusedProfiles[tickers[index]])
                    }
                    guard enqueued else { throw CancellationError() }
                }
                while let indexed = try await group.next() {
                    ordered[indexed.index] = indexed.card
                    try Task.checkCancellation()
                    if nextIndex < tickers.count {
                        let index = nextIndex
                        nextIndex += 1
                        let enqueued = group.addTaskUnlessCancelled {
                            try await Self.loadCard(tickers[index], index: index, api: api, reusedProfile: reusedProfiles[tickers[index]])
                        }
                        guard enqueued else { throw CancellationError() }
                    }
                }
            }
            return ordered.compactMap { $0 }
        })
    }

    static func failing(_ error: StockError) -> Self {
        Self(load: { _, _ in throw error })
    }
}

private struct IndexedCard: Sendable {
    let index: Int
    let card: StockCard
}

private enum StockEndpointResult: Sendable {
    case quote(Result<StockQuote, StockError>)
    case profile(Result<CompanyProfile, StockError>)
}

private extension StockClient {
    static func loadCard(_ ticker: StockTicker, index: Int, api: FinnhubStockAPI, reusedProfile: CompanyProfile?) async throws -> IndexedCard {
        var quote: Result<StockQuote, StockError>?
        var profile: Result<CompanyProfile, StockError>?

        do {
            try await withThrowingTaskGroup(of: StockEndpointResult.self) { group in
                group.addTask { .quote(try await endpointResult { try await api.quote(ticker) }) }
                if reusedProfile == nil {
                    group.addTask { .profile(try await endpointResult { try await api.profile(ticker) }) }
                }
                while let result = try await group.next() {
                    switch result {
                    case let .quote(value): quote = value
                    case let .profile(value): profile = value
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        }

        let card = StockCard(
            ticker: ticker,
            quote: quote?.successValue,
            profile: reusedProfile ?? profile?.successValue,
            quoteError: quote?.failureValue,
            profileError: profile?.failureValue
        )
        return IndexedCard(index: index, card: card)
    }

    static func endpointResult<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Result<Value, StockError> {
        do { return .success(try await operation()) }
        catch is CancellationError { throw CancellationError() }
        catch let error as StockError { return .failure(error) }
        catch { return .failure(.server) }
    }
}

private extension Result where Failure == StockError {
    var successValue: Success? { if case let .success(value) = self { value } else { nil } }
    var failureValue: StockError? { if case let .failure(error) = self { error } else { nil } }
}
