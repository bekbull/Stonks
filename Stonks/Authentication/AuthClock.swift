import Foundation

nonisolated struct AuthClock: Sendable {
    var now: @Sendable () async -> Date

    static let live = Self(now: { Date() })
}
