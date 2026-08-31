import ComposableArchitecture

@DependencyClient
nonisolated struct AuthClient: Sendable {
    var login: @Sendable (Credentials) async throws -> Void
    var validateSession: @Sendable () async throws -> Void
    var logout: @Sendable () async -> Void
}

extension AuthClient: TestDependencyKey {
    static let testValue = Self()
}

extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}

extension AuthClient: DependencyKey {
    static let liveValue = Self.live(
        httpClient: .live(),
        clock: .live
    )
}

extension AuthClient {
    static func live(httpClient: HTTPClient, clock: AuthClock) -> Self {
        let api = DummyJSONAuthAPI(httpClient: httpClient, clock: clock)
        let session = AuthSession(
            clock: clock,
            refresh: { refreshToken in
                try await api.refresh(using: refreshToken)
            }
        )
        let authenticated = AuthenticatedDummyJSONClient(
            session: session,
            api: api
        )
        return Self(
            login: { credentials in
                let response = try await api.login(credentials)
                await session.install(response)
            },
            validateSession: {
                try await authenticated.validateSession()
            },
            logout: {
                await session.logout()
            }
        )
    }
}
