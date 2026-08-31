import Foundation

nonisolated struct HTTPResponse: Equatable, Sendable {
    let data: Data
    let statusCode: Int
}

nonisolated enum HTTPClientError: Error, Equatable, Sendable {
    case nonHTTPResponse
}

nonisolated struct HTTPClient: Sendable {
    var execute: @Sendable (URLRequest) async throws -> HTTPResponse

    static func live(session: URLSession = makeCredentialFreeURLSession()) -> Self {
        Self { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw HTTPClientError.nonHTTPResponse
            }
            return HTTPResponse(data: data, statusCode: response.statusCode)
        }
    }
}

nonisolated func makeCredentialFreeSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    return configuration
}

nonisolated func makeCredentialFreeURLSession() -> URLSession {
    URLSession(configuration: makeCredentialFreeSessionConfiguration())
}
