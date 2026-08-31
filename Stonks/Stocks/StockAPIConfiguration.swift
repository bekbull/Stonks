import Foundation

nonisolated struct StockAPIConfiguration: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String

    init(
        baseURL: URL = URL(string: "https://finnhub.io/api/v1")!,
        apiKey: String
    ) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedKey != "local-key-here" else {
            throw StockError.missingAPIKey
        }
        self.baseURL = baseURL
        self.apiKey = trimmedKey
    }

    static func load(from propertyList: [String: Any]) throws -> Self {
        guard let apiKey = propertyList["FINNHUB_API_KEY"] as? String else {
            throw StockError.missingAPIKey
        }
        return try Self(apiKey: apiKey)
    }

    @MainActor
    static func loadFromMainBundle() throws -> Self {
        let urls = [
            Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            Bundle.main.url(
                forResource: "Secrets",
                withExtension: "plist",
                subdirectory: "Configuration"
            ),
        ]
        guard let url = urls.compactMap({ $0 }).first,
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else {
            throw StockError.missingAPIKey
        }
        return try load(from: propertyList)
    }
}
