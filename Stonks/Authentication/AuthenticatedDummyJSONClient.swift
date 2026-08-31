import Foundation

nonisolated struct AuthenticatedDummyJSONClient: Sendable {
    let session: AuthSession
    let api: DummyJSONAuthAPI

    func validateSession() async throws {
        let firstLease = try await session.validLease()
        try Task.checkCancellation()

        let firstResult = try await api.currentUser(accessToken: firstLease.accessToken)
        try Task.checkCancellation()
        switch firstResult {
        case .success:
            return
        case .unauthorized:
            try await recoverAndRetry(rejected: firstLease)
        }
    }

    private func recoverAndRetry(rejected: TokenLease) async throws {
        let retryLease = try await session.recover(afterRejecting: rejected)
        try Task.checkCancellation()

        let retryResult = try await api.currentUser(accessToken: retryLease.accessToken)
        try Task.checkCancellation()

        switch retryResult {
        case .success:
            return
        case .unauthorized:
            try await session.invalidate(ifCurrent: retryLease)
            throw AuthError.sessionExpired
        }
    }
}
