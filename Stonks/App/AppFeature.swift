import ComposableArchitecture

@MainActor
enum AppFeature: @MainActor ComposableArchitecture.CaseReducer {
    case login(LoginFeature)
    case stocks(StocksFeature)

    @ObservableState
    @CasePathable
    @dynamicMemberLookup
    enum State: Equatable, @MainActor ComposableArchitecture.CaseReducerState {
        typealias StateReducer = AppFeature

        case login(LoginFeature.State)
        case stocks(StocksFeature.State)
    }

    @CasePathable
    enum Action: Sendable {
        case login(LoginFeature.Action)
        case stocks(StocksFeature.Action)
        case sceneBecameActive
        case sessionValidationSucceeded
        case sessionValidationFailed(AuthError)
    }

    @CasePathable
    @dynamicMemberLookup
    enum CaseScope: ComposableArchitecture._CaseScopeProtocol {
        case login(StoreOf<LoginFeature>)
        case stocks(StoreOf<StocksFeature>)
    }

    @MainActor
    static func scope(_ store: Store<State, Action>) -> CaseScope {
        switch store.state {
        case .login:
            .login(store.scope(\.login, action: \.login)!)
        case .stocks:
            .stocks(store.scope(\.stocks, action: \.stocks)!)
        }
    }

    static var body: some ReducerOf<Self> {
        Reduce { state, action in
            @Dependency(AuthClient.self) var authClient

            switch action {
            case .login(.delegate(.authenticated)):
                state = .stocks(StocksFeature.State())
                return validateSession(using: authClient)

            case .sceneBecameActive:
                guard case .stocks = state else { return .none }
                return validateSession(using: authClient)

            case .sessionValidationSucceeded:
                guard case .stocks = state else { return .none }
                return .none

            case .sessionValidationFailed(.sessionExpired):
                guard case .stocks = state else { return .none }
                state = .login(
                    LoginFeature.State(errorMessage: .sessionExpired)
                )
                return .cancel(id: AppFeatureCancelID.sessionValidation)

            case .stocks(.delegate(.logoutRequested)):
                state = .login(LoginFeature.State())
                return .merge(
                    .cancel(id: AppFeatureCancelID.sessionValidation),
                    .run { _ in await authClient.logout() }
                )

            case .sessionValidationFailed:
                guard case .stocks = state else { return .none }
                return .none

            case .login, .stocks:
                return .none
            }
        }
        .ifCaseLet(\.login, action: \.login) {
            LoginFeature()
        }
        .ifCaseLet(\.stocks, action: \.stocks) {
            StocksFeature()
        }
    }

    private static func validateSession(
        using authClient: AuthClient
    ) -> Effect<Action> {
        .run { send in
            do {
                try await authClient.validateSession()
                await send(.sessionValidationSucceeded)
            } catch is CancellationError {
            } catch let error as AuthError {
                await send(.sessionValidationFailed(error))
            } catch {
                await send(.sessionValidationFailed(.server))
            }
        }
        .cancellable(id: AppFeatureCancelID.sessionValidation, cancelInFlight: true)
    }
}


nonisolated private enum AppFeatureCancelID: Hashable, Sendable {
    case sessionValidation
}
