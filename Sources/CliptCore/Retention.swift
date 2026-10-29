import Foundation

public struct RetentionPolicy: Sendable, Equatable {
    /// nil = unlimited.
    public var maxItems: Int?
    /// nil = forever.
    public var maxAge: TimeInterval?

    public init(maxItems: Int? = 1000, maxAge: TimeInterval? = nil) {
        self.maxItems = maxItems
        self.maxAge = maxAge
    }

    public static let `default` = RetentionPolicy(maxItems: 1000, maxAge: nil)
    public static let itemOptions: [Int?] = [200, 1000, 5000, nil]
    public static let ageOptions: [TimeInterval?] = [86_400, 604_800, 2_592_000, nil]
}
