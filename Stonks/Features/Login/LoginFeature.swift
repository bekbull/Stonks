import ComposableArchitecture
import Foundation

struct LoginFeature: @MainActor ComposableArchitecture.Reducer {
    @ObservableState
    struct State: Equatable {
        enum Phase: Equatable, Sendable {
            case idle
            case submitting
        }

        var username = ""
        var password = ""
        var phase: Phase = .idle
        var errorMessage: LoginErrorMessage?

        var canSubmit: Bool {
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.isEmpty
                && phase == .idle
        }
    }

    @CasePathable
    enum Action: Sendable, ViewAction {
        case view(View)
        case loginSucceeded
        case loginFailed(AuthError)
        case delegate(Delegate)

        @CasePathable
        enum View: BindableAction, Sendable {
            case binding(BindingAction<State>)
            case loginButtonTapped
        }

        @CasePathable
        enum Delegate: Sendable {
            case authenticated
        }
    }

    @Dependency(AuthClient.self) private var authClient

    var body: some ReducerOf<Self> {
        BindingReducer(action: \.view)
        Reduce { state, action in
            switch action {
            case .view(.binding(\.username)),
                 .view(.binding(\.password)):
                state.errorMessage = nil
                return .none

            case .view(.binding):
                return .none

            case .view(.loginButtonTapped):
                guard state.canSubmit else { return .none }
                let credentials = Credentials(
                    username: state.username.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    password: state.password
                )
                state.phase = .submitting
                state.errorMessage = nil
                return .run { send in
                    do {
                        try await authClient.login(credentials)
                        await send(.loginSucceeded)
                    } catch is CancellationError {
                    } catch let error as AuthError {
                        await send(.loginFailed(error))
                    } catch {
                        await send(.loginFailed(.server))
                    }
                }

            case .loginSucceeded:
                state.phase = .idle
                return .send(.delegate(.authenticated))

            case .loginFailed(let error):
                state.phase = .idle
                state.errorMessage = LoginErrorMessage(error)
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
