import Foundation

nonisolated struct Credentials: Equatable, Sendable {
    let username: String
    let password: String
}

nonisolated struct TokenPair: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

nonisolated struct AuthTokenResponse: Equatable, Sendable {
    let tokens: TokenPair
    let accessExpiry: Date
}

nonisolated struct TokenLease: Equatable, Sendable {
    let accessToken: String
    let generation: UInt64
    let revision: UInt64
}

nonisolated struct AuthenticatedUser: Equatable, Sendable {
    let id: Int
    let username: String
}
