import Foundation

actor AuthSession {
    typealias Refresh = @Sendable (String) async throws -> AuthTokenResponse

    private struct SessionTokens: Sendable {
        var pair: TokenPair
        var accessExpiry: Date
        let generation: UInt64
        var revision: UInt64

        var lease: TokenLease {
            TokenLease(
                accessToken: pair.accessToken,
                generation: generation,
                revision: revision
            )
        }
    }

    private struct RefreshFlight: Sendable {
        let generation: UInt64
        let sourceRevision: UInt64
        let task: Task<TokenLease, Error>
    }

    private enum RefreshOutcome: Sendable {
        case success(AuthTokenResponse)
        case failure(AuthError)
        case cancelled
    }

    private let clock: AuthClock
    private let refresh: Refresh
    private var generation: UInt64 = 0
    private var session: SessionTokens?
    private var inFlightRefresh: RefreshFlight?

    init(clock: AuthClock, refresh: @escaping Refresh) {
        self.clock = clock
        self.refresh = refresh
    }

    func install(_ response: AuthTokenResponse) {
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
        generation &+= 1
        session = SessionTokens(
            pair: response.tokens,
            accessExpiry: response.accessExpiry,
            generation: generation,
            revision: 0
        )
    }

    func logout() {
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
        session = nil
        generation &+= 1
    }

    func validLease() async throws -> TokenLease {
        let now = await clock.now()
        try Task.checkCancellation()
        guard let current = session else { throw AuthError.sessionExpired }
        if current.accessExpiry > now.addingTimeInterval(5) {
            return current.lease
        }
        return try await refreshLease(from: current)
    }

    func recover(afterRejecting rejected: TokenLease) async throws -> TokenLease {
        guard let current = session else { throw AuthError.sessionExpired }
        guard current.generation == rejected.generation else {
            throw AuthError.sessionChanged
        }
        guard current.revision == rejected.revision else {
            guard current.revision > rejected.revision else {
                throw AuthError.staleOperation
            }
            let lease = try await validLease()
            guard lease.generation == rejected.generation else {
                throw AuthError.sessionChanged
            }
            return lease
        }
        return try await refreshLease(from: current)
    }

    func invalidate(ifCurrent lease: TokenLease) throws {
        guard generation == lease.generation else {
            throw AuthError.sessionChanged
        }
        guard let current = session else { throw AuthError.sessionExpired }
        guard current.revision == lease.revision else {
            throw AuthError.staleOperation
        }
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
        session = nil
        generation &+= 1
    }

}

private extension AuthSession {
    private func refreshLease(from source: SessionTokens) async throws -> TokenLease {
        let task: Task<TokenLease, Error>
        if let flight = inFlightRefresh {
            guard flight.generation == source.generation else {
                throw AuthError.sessionChanged
            }
            guard flight.sourceRevision == source.revision else {
                throw AuthError.staleOperation
            }
            task = flight.task
        } else {
            let refresh = self.refresh
            let refreshToken = source.pair.refreshToken
            let generation = source.generation
            let revision = source.revision
            let created = Task<TokenLease, Error> {
                let outcome: RefreshOutcome
                do {
                    outcome = .success(try await refresh(refreshToken))
                } catch is CancellationError {
                    outcome = .cancelled
                } catch let error as AuthError {
                    outcome = .failure(error)
                } catch {
                    outcome = .failure(.server)
                }
                return try self.finishRefresh(
                    outcome,
                    generation: generation,
                    sourceRevision: revision
                )
            }
            inFlightRefresh = RefreshFlight(
                generation: generation,
                sourceRevision: revision,
                task: created
            )
            task = created
        }

        let lease = try await task.value
        try Task.checkCancellation()
        guard let current = session else { throw AuthError.sessionChanged }
        guard current.generation == lease.generation else {
            throw AuthError.sessionChanged
        }
        guard current.revision == lease.revision else {
            throw AuthError.staleOperation
        }
        return lease
    }

    private func finishRefresh(
        _ outcome: RefreshOutcome,
        generation expectedGeneration: UInt64,
        sourceRevision: UInt64
    ) throws -> TokenLease {
        guard let current = session,
              current.generation == expectedGeneration
        else {
            clearFlightIfMatching(generation: expectedGeneration, revision: sourceRevision)
            throw AuthError.sessionChanged
        }
        guard current.revision == sourceRevision else {
            clearFlightIfMatching(generation: expectedGeneration, revision: sourceRevision)
            throw AuthError.staleOperation
        }
        guard let flight = inFlightRefresh,
              flight.generation == expectedGeneration,
              flight.sourceRevision == sourceRevision
        else { throw AuthError.staleOperation }

        switch outcome {
        case .success(let response):
            let rotated = SessionTokens(
                pair: response.tokens,
                accessExpiry: response.accessExpiry,
                generation: expectedGeneration,
                revision: sourceRevision &+ 1
            )
            session = rotated
            inFlightRefresh = nil
            return rotated.lease

        case .failure(.connectivity):
            inFlightRefresh = nil
            throw AuthError.connectivity

        case .failure(.server):
            inFlightRefresh = nil
            throw AuthError.server

        case .failure(.sessionExpired), .failure(.decoding),
             .failure(.invalidCredentials):
            session = nil
            inFlightRefresh = nil
            generation &+= 1
            throw AuthError.sessionExpired

        case .failure(.sessionChanged):
            inFlightRefresh = nil
            throw AuthError.sessionChanged

        case .failure(.staleOperation):
            inFlightRefresh = nil
            throw AuthError.staleOperation

        case .cancelled:
            inFlightRefresh = nil
            throw CancellationError()
        }
    }

    private func clearFlightIfMatching(generation: UInt64, revision: UInt64) {
        guard let flight = inFlightRefresh,
              flight.generation == generation,
              flight.sourceRevision == revision
        else { return }
        inFlightRefresh = nil
    }
}
