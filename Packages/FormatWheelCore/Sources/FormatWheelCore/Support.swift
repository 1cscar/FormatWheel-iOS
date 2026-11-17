import Foundation

/// An error whose message is shown to the user as-is (upstream `FWError`, Support.swift).
public struct FWError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

    /// The user cancelled a running action.
    public static let cancelled = FWError("已取消")
}

/// Progress callback, 0...1 (upstream `ProgressFn`).
public typealias ProgressFn = @Sendable (Double) -> Void
