import ComposableArchitecture
import SwiftUI

@MainActor
struct AppView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        switch store.case {
        case .login(let loginStore):
            LoginView(store: loginStore)
        case .stocks(let stocksStore):
            StocksView(store: stocksStore)
        }
    }
}
