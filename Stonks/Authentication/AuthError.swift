nonisolated enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case connectivity
    case server
    case decoding
    case sessionExpired
    case sessionChanged
    case staleOperation
}

nonisolated enum LoginErrorMessage: Equatable, Sendable {
    case invalidCredentials
    case connectivity
    case generic
    case sessionExpired

    init(_ error: AuthError) {
        switch error {
        case .invalidCredentials: self = .invalidCredentials
        case .connectivity: self = .connectivity
        case .sessionExpired: self = .sessionExpired
        case .server, .decoding, .sessionChanged, .staleOperation: self = .generic
        }
    }

    var text: String {
        switch self {
        case .invalidCredentials: "Invalid username or password."
        case .connectivity: "Couldn't connect. Try again."
        case .generic: "Something went wrong. Try again."
        case .sessionExpired: "Your session expired. Log in again."
        }
    }
}
