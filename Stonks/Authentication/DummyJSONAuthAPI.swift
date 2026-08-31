import Foundation

nonisolated struct DummyJSONAuthAPI: Sendable {
    private let httpClient: HTTPClient
    private let clock: AuthClock
    private let baseURL = URL(string: "https://dummyjson.com")!

    init(httpClient: HTTPClient, clock: AuthClock) {
        self.httpClient = httpClient
        self.clock = clock
    }

    func login(_ credentials: Credentials) async throws -> AuthTokenResponse {
        let requestStart = await clock.now()
        var request = URLRequest(url: baseURL.appending(path: "auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(
            LoginRequest(
                username: credentials.username,
                password: credentials.password,
                expiresInMins: 1
            )
        )
        let response = try await send(request)
        switch response.statusCode {
        case 200..<300:
            let dto: TokenResponseDTO = try decode(from: response.data)
            return AuthTokenResponse(
                tokens: TokenPair(
                    accessToken: dto.accessToken,
                    refreshToken: dto.refreshToken
                ),
                accessExpiry: requestStart.addingTimeInterval(60)
            )
        case 400, 401:
            throw AuthError.invalidCredentials
        default:
            throw AuthError.server
        }
    }

    func refresh(using refreshToken: String) async throws -> AuthTokenResponse {
        let requestStart = await clock.now()
        var request = URLRequest(url: baseURL.appending(path: "auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(
            RefreshRequest(refreshToken: refreshToken, expiresInMins: 1)
        )
        let response = try await send(request)
        switch response.statusCode {
        case 200..<300:
            let dto: TokenResponseDTO = try decode(from: response.data)
            return AuthTokenResponse(
                tokens: TokenPair(
                    accessToken: dto.accessToken,
                    refreshToken: dto.refreshToken
                ),
                accessExpiry: requestStart.addingTimeInterval(60)
            )
        case 400, 401:
            throw AuthError.sessionExpired
        default:
            throw AuthError.server
        }
    }
}

nonisolated enum CurrentUserResult: Equatable, Sendable {
    case success(AuthenticatedUser)
    case unauthorized
}

nonisolated extension DummyJSONAuthAPI {
    func currentUser(accessToken: String) async throws -> CurrentUserResult {
        var request = URLRequest(url: baseURL.appending(path: "auth/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response = try await send(request)
        switch response.statusCode {
        case 200..<300:
            let dto: CurrentUserDTO = try decode(from: response.data)
            return .success(AuthenticatedUser(id: dto.id, username: dto.username))
        case 401:
            return .unauthorized
        default:
            throw AuthError.server
        }
    }
}

private nonisolated struct LoginRequest: Encodable, Sendable {
    let username: String
    let password: String
    let expiresInMins: Int
}

private nonisolated struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
    let expiresInMins: Int
}

private nonisolated struct TokenResponseDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}

private nonisolated struct CurrentUserDTO: Decodable, Sendable {
    let id: Int
    let username: String
}

private nonisolated extension DummyJSONAuthAPI {
    static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
    ]

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await httpClient.execute(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where Self.connectivityCodes.contains(error.code) {
            throw AuthError.connectivity
        } catch {
            throw AuthError.server
        }
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try JSONEncoder().encode(value) }
        catch { throw AuthError.server }
    }

    func decode<T: Decodable>(from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AuthError.decoding }
    }
}
