import Foundation

nonisolated struct FinnhubStockAPI: Sendable {
    var quote: @Sendable (StockTicker) async throws -> StockQuote
    var profile: @Sendable (StockTicker) async throws -> CompanyProfile

    static func live(configuration: StockAPIConfiguration, httpClient: HTTPClient) -> Self {
        Self(
            quote: { ticker in
                let request = try Self.request(path: "quote", ticker: ticker, configuration: configuration)
                let response = try await Self.send(request, using: httpClient)
                let data = try Self.validate(response)
                let dto: QuoteDTO
                do { dto = try JSONDecoder().decode(QuoteDTO.self, from: data) }
                catch { throw StockError.decoding }
                guard
                    dto.currentPrice.isFinite,
                    dto.dailyChange.isFinite,
                    dto.dailyChangeFraction.isFinite,
                    dto.previousClose.isFinite,
                    dto.currentPrice != 0 || dto.dailyChange != 0 || dto.dailyChangeFraction != 0 || dto.previousClose != 0 || dto.timestamp != 0
                else { throw StockError.unavailable }
                return StockQuote(
                    ticker: ticker,
                    currentPrice: dto.currentPrice,
                    dailyChange: dto.dailyChange,
                    dailyChangeFraction: dto.dailyChangeFraction / 100,
                    previousClose: dto.previousClose,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(dto.timestamp))
                )
            },
            profile: { ticker in
                let request = try Self.request(path: "stock/profile2", ticker: ticker, configuration: configuration)
                let response = try await Self.send(request, using: httpClient)
                let data = try Self.validate(response)
                let dto: ProfileDTO
                do { dto = try JSONDecoder().decode(ProfileDTO.self, from: data) }
                catch { throw StockError.decoding }
                let requested = ticker.rawValue
                guard dto.ticker.trimmingCharacters(in: .whitespacesAndNewlines) == requested else {
                    throw StockError.unavailable
                }
                let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw StockError.unavailable }
                return CompanyProfile(
                    ticker: ticker,
                    name: name,
                    industry: Self.optionalTrimmed(dto.industry),
                    exchange: Self.optionalTrimmed(dto.exchange),
                    currencyCode: Self.optionalTrimmed(dto.currency)
                )
            }
        )
    }
}

private nonisolated struct QuoteDTO: Decodable, Sendable {
    let currentPrice: Double
    let dailyChange: Double
    let dailyChangeFraction: Double
    let previousClose: Double
    let timestamp: Int

    enum CodingKeys: String, CodingKey {
        case currentPrice = "c"
        case dailyChange = "d"
        case dailyChangeFraction = "dp"
        case previousClose = "pc"
        case timestamp = "t"
    }
}

private nonisolated struct ProfileDTO: Decodable, Sendable {
    let ticker: String
    let name: String
    let industry: String?
    let exchange: String?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case ticker, name
        case industry = "finnhubIndustry"
        case exchange, currency
    }
}

private nonisolated extension FinnhubStockAPI {
    static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .timedOut, .networkConnectionLost,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
    ]

    static func request(path: String, ticker: StockTicker, configuration: StockAPIConfiguration) throws -> URLRequest {
        var components = URLComponents(url: configuration.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "symbol", value: ticker.rawValue)]
        guard let url = components?.url else { throw StockError.server }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        return request
    }

    static func send(_ request: URLRequest, using httpClient: HTTPClient) async throws -> HTTPResponse {
        do { return try await httpClient.execute(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as URLError where connectivityCodes.contains(error.code) { throw StockError.connectivity }
        catch { throw StockError.server }
    }

    static func validate(_ response: HTTPResponse) throws -> Data {
        switch response.statusCode {
        case 200..<300: response.data
        case 401, 403: throw StockError.authorization
        case 429: throw StockError.rateLimited
        default: throw StockError.server
        }
    }

    static func optionalTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
