//
//  StonksApp.swift
//  Stonks
//
//  Created by Bekbol Bolatov on 24.08.2026.
//

import ComposableArchitecture
import SwiftUI

@main
@MainActor
struct StonksApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let store: StoreOf<AppFeature>

    init() {
        let httpClient = HTTPClient.live()
        let stockConfiguration: Result<StockAPIConfiguration, StockError> = Result {
            try StockAPIConfiguration.loadFromMainBundle()
        }.mapError { _ in .missingAPIKey }
        let clients = AppClients.live(
            httpClient: httpClient,
            authClock: .live,
            stockConfiguration: stockConfiguration
        )
        self.store = withDependencies {
            $0.authClient = clients.authClient
            $0.stockClient = clients.stockClient
        } operation: {
            Store(initialState: AppFeature.State.login(LoginFeature.State())) {
                AppFeature.body
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    store.send(.sceneBecameActive)
                }
        }
    }
}
