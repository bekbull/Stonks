import ComposableArchitecture
import SwiftUI

@ViewAction(for: LoginFeature.self)
struct LoginView: View {
    @Bindable var store: StoreOf<LoginFeature>
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username
        case password
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $store.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $store.password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit { send(.loginButtonTapped) }
                }

                if let errorMessage = store.errorMessage {
                    Text(errorMessage.text)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(errorMessage.text)")
                }

                Button {
                    focusedField = nil
                    send(.loginButtonTapped)
                } label: {
                    HStack {
                        Spacer()
                        if store.phase == .submitting {
                            ProgressView()
                                .accessibilityLabel("Logging in")
                        } else {
                            Text("Log in")
                        }
                        Spacer()
                    }
                }
                .disabled(!store.canSubmit)
                .accessibilityHint("Signs in with the entered username and password")
            }
            .disabled(store.phase == .submitting)
            .navigationTitle("Stonks")
            .safeAreaInset(edge: .top) {
                Text("Sign in to continue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }
        }
    }
}

#Preview {
    LoginView(
        store: Store(initialState: LoginFeature.State()) {
            LoginFeature()
        } withDependencies: {
            $0.authClient.login = { _ in }
        }
    )
}
