import Foundation
@testable import SmartVolume

final class FakeScheduler: Scheduling {
    final class Work: ScheduledWork {
        let delay: TimeInterval
        let block: () -> Void
        var cancelled = false
        init(delay: TimeInterval, block: @escaping () -> Void) { self.delay = delay; self.block = block }
        func cancel() { cancelled = true }
    }

    private(set) var scheduled: [Work] = []
    var delays: [TimeInterval] { scheduled.map(\.delay) }

    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> ScheduledWork {
        let item = Work(delay: delay, block: work)
        scheduled.append(item)
        return item
    }
}

final class FakeOutputWatcher: OutputWatching {
    var current: AudioOutput?
    var onChange: ((AudioOutput?) -> Void)?
    func start() {}
    func emit(_ output: AudioOutput?) { current = output; onChange?(output) }
}

final class FakeKeys: KeyIntercepting {
    private(set) var isEnabled = false
    var onKey: ((MediaKeyEvent) -> InterceptAction)?
    var onSend: ((RemoteKey) -> Void)?
    func setEnabled(_ enabled: Bool) { isEnabled = enabled }
}

final class FakeLink: MonitorLinking {
    var state: LinkState = .unpaired { didSet { onStateChange?(state) } }
    var onStateChange: ((LinkState) -> Void)?
    private(set) var connected: [PairedMonitor] = []
    private(set) var sent: [RemoteKey] = []
    private(set) var wakes = 0
    func connect(to monitor: PairedMonitor) { connected.append(monitor); state = .connecting }
    func send(_ key: RemoteKey) { sent.append(key) }
    func disconnect() { state = .unpaired }
    func handleSystemWake() { wakes += 1 }
}

/// Holds token reads until the test releases them, like a slow Keychain.
final class DeferredTokenStore: TokenStoring {
    var stored: String?
    private var pending: [(String?) -> Void] = []
    func token(for deviceID: String, completion: @escaping (String?) -> Void) { pending.append(completion) }
    func save(_ token: String, for deviceID: String) { stored = token }
    func delete(for deviceID: String) { stored = nil }
    func release() {
        let reads = pending
        pending = []
        reads.forEach { $0(stored) }
    }
}

final class FakePresence: PresenceApplying {
    private(set) var applied: [PresenceMode] = []
    func apply(_ mode: PresenceMode) { applied.append(mode) }
}

final class FakeLoginItem: LoginItemControlling {
    private(set) var enabled: Bool?
    func setEnabled(_ enabled: Bool) throws { self.enabled = enabled }
}
