import ComposableArchitecture

struct AppClients: Sendable {
    let authClient: AuthClient
    let stockClient: StockClient

    @MainActor
    static func live(
        httpClient: HTTPClient,
        authClock: AuthClock,
        stockConfiguration: Result<StockAPIConfiguration, StockError>
    ) -> Self {
        let authClient = AuthClient.live(httpClient: httpClient, clock: authClock)
        let stockClient: StockClient
        switch stockConfiguration {
        case let .success(configuration):
            stockClient = StockClient.live(
                api: FinnhubStockAPI.live(configuration: configuration, httpClient: httpClient)
            )
        case let .failure(error):
            stockClient = StockClient.failing(error)
        }
        return Self(authClient: authClient, stockClient: stockClient)
    }
}
