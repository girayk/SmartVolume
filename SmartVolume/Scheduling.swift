import Foundation

public protocol ScheduledWork {
    func cancel()
}

public protocol Scheduling {
    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledWork
}

extension DispatchWorkItem: ScheduledWork {}

/// Runs work on the main queue after a delay.
public struct DispatchScheduling: Scheduling {
    public init() {}

    @discardableResult
    public func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledWork {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return item
    }
}
