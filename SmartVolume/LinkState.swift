import Foundation

public enum LinkState: Equatable {
    case unpaired, connecting, connected, unreachable
}

/// Reconnect delays: 1, 2, 4, 8, 16, then 30 seconds forever.
public struct Backoff {
    private static let steps: [TimeInterval] = [1, 2, 4, 8, 16, 30]
    private var index = 0

    public init() {}

    public mutating func next() -> TimeInterval {
        let delay = Self.steps[min(index, Self.steps.count - 1)]
        index += 1
        return delay
    }

    public mutating func reset() {
        index = 0
    }
}
