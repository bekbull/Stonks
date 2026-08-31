import ComposableArchitecture

struct StocksFeature: @MainActor ComposableArchitecture.Reducer {
    @ObservableState
    struct State: Equatable {
        enum Phase: Equatable, Sendable { case idle, initialLoading, refreshing }
        enum ScreenMessage: Equatable, Sendable {
            case missingAPIKey, authorization, rateLimited, connectivity, generic
            var text: String {
                switch self {
                case .missingAPIKey: "Finnhub API key is missing."
                case .authorization: "Finnhub access was rejected."
                case .rateLimited: "Finnhub rate limit reached. Try again shortly."
                case .connectivity: "Couldn't connect. Pull to refresh."
                case .generic: "Quotes unavailable. Pull to refresh."
                }
            }
        }
        var tickers = StockTicker.configuredOrder
        var cards: [StockCard] = []
        var phase: Phase = .idle
        var loadGeneration: UInt64 = 0
        var screenMessage: ScreenMessage?
        var marketMovers: MarketMovers? { MarketMovers.from(cards: cards) }
    }

    @CasePathable
    enum Action: Sendable, ViewAction {
        case view(View)
        case loadResponse(generation: UInt64, result: Result<[StockCard], StockError>)
        case delegate(Delegate)

        @CasePathable
        enum View: Sendable {
            case task
            case refresh
            case logoutButtonTapped
        }

        @CasePathable
        enum Delegate: Sendable {
            case logoutRequested
        }
    }

    @Dependency(StockClient.self) private var stockClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.task):
                guard state.cards.isEmpty else { return .none }
                return startLoad(state: &state, phase: .initialLoading)
            case .view(.refresh):
                state.screenMessage = nil
                return startLoad(state: &state, phase: .refreshing)
            case .view(.logoutButtonTapped):
                return .send(.delegate(.logoutRequested))
            case let .loadResponse(generation, .success(cards)):
                guard generation == state.loadGeneration else { return .none }
                state.cards = cards
                state.phase = .idle
                state.screenMessage = message(for: cards)
                return .none
            case let .loadResponse(generation, .failure(error)):
                guard generation == state.loadGeneration else { return .none }
                state.phase = .idle
                state.screenMessage = error == .missingAPIKey ? .missingAPIKey : .generic
                return .none
            case .delegate:
                return .none
            }
        }
    }

    private func startLoad(state: inout State, phase: State.Phase) -> Effect<Action> {
        state.loadGeneration += 1
        state.phase = phase
        let generation = state.loadGeneration
        let tickers = state.tickers
        let reused = Dictionary(uniqueKeysWithValues: state.cards.compactMap { card in
            card.profile.map { (card.ticker, $0) }
        })
        return .run { [stockClient] send in
            do {
                let cards = try await stockClient.load(tickers, reused)
                try Task.checkCancellation()
                await send(.loadResponse(generation: generation, result: .success(cards)))
            } catch is CancellationError {
            } catch let error as StockError {
                await send(.loadResponse(generation: generation, result: .failure(error)))
            } catch {
                await send(.loadResponse(generation: generation, result: .failure(.server)))
            }
        }
        .cancellable(id: StocksFeatureCancelID.load, cancelInFlight: true)
    }

    private func message(for cards: [StockCard]) -> State.ScreenMessage? {
        let quoteCards = cards.filter { $0.quote == nil }
        guard cards.allSatisfy({ $0.quote == nil }) else { return nil }
        let errors: [StockError] = quoteCards.compactMap { $0.quoteError }
        if !errors.isEmpty && errors.allSatisfy({ $0 == .authorization }) { return .authorization }
        if errors.contains(.rateLimited) { return .rateLimited }
        if !errors.isEmpty && errors.allSatisfy({ $0 == .connectivity }) { return .connectivity }
        return .generic
    }
}

nonisolated private enum StocksFeatureCancelID: Hashable, Sendable { case load }
