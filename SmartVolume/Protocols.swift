import Foundation

public protocol OutputWatching: AnyObject {
    var current: AudioOutput? { get }
    var onChange: ((AudioOutput?) -> Void)? { get set }
    func start()
}

public protocol KeyIntercepting: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
    var onKey: ((MediaKeyEvent) -> InterceptAction)? { get set }
    var onSend: ((RemoteKey) -> Void)? { get set }
}

public protocol MonitorLinking: AnyObject {
    var state: LinkState { get }
    var onStateChange: ((LinkState) -> Void)? { get set }
    /// Loads the monitor's saved token, then opens the connection.
    func connect(to monitor: PairedMonitor)
    func send(_ key: RemoteKey)
    func disconnect()
    func handleSystemWake()
}

/// None of these block the caller. Operations run in the order they're called.
public protocol TokenStoring: AnyObject {
    /// Calls back on the main queue.
    func token(for deviceID: String, completion: @escaping (String?) -> Void)
    func save(_ token: String, for deviceID: String)
    func delete(for deviceID: String)
}

public protocol PresenceApplying: AnyObject {
    func apply(_ mode: PresenceMode)
}

public protocol LoginItemControlling: AnyObject {
    func setEnabled(_ enabled: Bool) throws
}

public final class InMemoryTokenStore: TokenStoring {
    private var tokens: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func token(for deviceID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return tokens[deviceID]
    }

    /// Calls back right away, which keeps tests deterministic.
    public func token(for deviceID: String, completion: @escaping (String?) -> Void) {
        completion(token(for: deviceID))
    }

    public func save(_ token: String, for deviceID: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[deviceID] = token
    }

    public func delete(for deviceID: String) {
        lock.lock(); defer { lock.unlock() }
        tokens[deviceID] = nil
    }
}
