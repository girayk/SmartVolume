import Foundation

/// Keeps a WebSocket open to the monitor's remote-control channel and sends volume keys over it.
/// All state changes happen on the main queue.
public final class WebSocketMonitorLink: NSObject, MonitorLinking, URLSessionDelegate {
    public private(set) var state: LinkState = .unpaired {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((LinkState) -> Void)?

    var pingInterval: TimeInterval = 20
    /// A ping without a pong for this long means the socket is dead.
    var pongTimeout: TimeInterval = 5
    /// Covers the Allow prompt on the monitor plus a slow network.
    var connectTimeout: TimeInterval = 35

    private let tokens: TokenStoring
    private let scheme: String
    private let port: Int
    private let appName: String
    private let clock: Scheduling
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var monitor: PairedMonitor?
    private var backoff = Backoff()
    private var reconnectWork: ScheduledWork?
    private var pingWork: ScheduledWork?
    private var pongDeadline: ScheduledWork?
    private var connectDeadline: ScheduledWork?
    /// The token for the current monitor, cached so reconnects never touch the Keychain.
    private var currentToken: String?
    /// True while connect() waits for the token. Opening a socket then would raise an Allow prompt.
    private var loadingToken = false
    /// Bumped whenever a socket is torn down, so callbacks from old sockets are ignored.
    private var generation = 0

    public init(
        tokens: TokenStoring,
        scheme: String = "wss",
        port: Int = 8002,
        appName: String = SmartVolumeInfo.appName,
        clock: Scheduling = DispatchScheduling()
    ) {
        self.tokens = tokens
        self.scheme = scheme
        self.port = port
        self.appName = appName
        self.clock = clock
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    public func connect(to monitor: PairedMonitor) {
        self.monitor = monitor
        backoff.reset()
        teardownSocket()
        currentToken = nil
        loadingToken = true
        state = .connecting
        let gen = generation
        tokens.token(for: monitor.deviceID) { [weak self] token in
            guard let self, gen == self.generation else { return }
            self.loadingToken = false
            self.currentToken = token
            self.open()
        }
    }

    public func send(_ key: RemoteKey) {
        guard state == .connected, let task else { return }
        let gen = generation
        let text = String(decoding: SamsungRemote.clickCommand(key), as: UTF8.self)
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.failed(gen) }
        }
        probe(gen)
    }

    public func disconnect() {
        monitor = nil
        currentToken = nil
        loadingToken = false
        teardownSocket()
        state = .unpaired
    }

    public func handleSystemWake() {
        // While the token loads, the pending connect opens a fresh socket anyway.
        guard monitor != nil, state != .unpaired, !loadingToken else { return }
        backoff.reset()
        open()
    }

    // MARK: - Socket lifecycle

    private func open() {
        guard let monitor else { return }
        teardownSocket()
        let gen = generation
        state = .connecting
        let url = SamsungRemote.url(host: monitor.host, appName: appName, token: currentToken, scheme: scheme, port: port)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receive(task, gen)
        connectDeadline = clock.schedule(after: connectTimeout) { [weak self] in
            guard let self, gen == self.generation, self.state == .connecting else { return }
            self.failed(gen)
        }
    }

    private func teardownSocket() {
        generation += 1
        reconnectWork?.cancel()
        reconnectWork = nil
        pingWork?.cancel()
        pingWork = nil
        pongDeadline?.cancel()
        pongDeadline = nil
        connectDeadline?.cancel()
        connectDeadline = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receive(_ task: URLSessionWebSocketTask, _ gen: Int) {
        task.receive { [weak self] result in
            DispatchQueue.main.async { self?.handleReceive(result, task, gen) }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>, _ task: URLSessionWebSocketTask, _ gen: Int) {
        guard gen == generation else { return }
        switch result {
        case .failure:
            failed(gen)
        case .success(let message):
            let text: String
            switch message {
            case .string(let string): text = string
            case .data(let data): text = String(decoding: data, as: UTF8.self)
            @unknown default: text = ""
            }
            switch SamsungRemote.parse(text) {
            case .connected(let token):
                if let token, let monitor {
                    tokens.save(token, for: monitor.deviceID)
                    currentToken = token
                }
                connectDeadline?.cancel()
                connectDeadline = nil
                backoff.reset()
                state = .connected
                schedulePing(gen)
            case .unauthorized:
                if let monitor { tokens.delete(for: monitor.deviceID) }
                currentToken = nil
                teardownSocket()
                state = .unpaired
                return
            case .timedOut:
                // Nobody pressed Allow. Wait for the user to pair again rather than re-prompting.
                teardownSocket()
                state = .unpaired
                return
            case .other:
                break
            }
            receive(task, gen)
        }
    }

    private func failed(_ gen: Int) {
        guard gen == generation, monitor != nil else { return }
        teardownSocket()
        // Without a token, reconnecting would raise a new Allow prompt on the monitor.
        // Only an explicit Pair or Re-pair may do that.
        guard currentToken != nil else {
            state = .unpaired
            return
        }
        state = .unreachable
        reconnectWork = clock.schedule(after: backoff.next()) { [weak self] in
            self?.open()
        }
    }

    private func schedulePing(_ gen: Int) {
        guard gen == generation else { return }
        pingWork?.cancel()
        pingWork = clock.schedule(after: pingInterval) { [weak self] in
            self?.probe(gen)
        }
    }

    /// Sends a ping and fails the link if no pong arrives in time. A silent peer never
    /// calls the ping handler, so the deadline is what detects it.
    private func probe(_ gen: Int) {
        guard gen == generation, pongDeadline == nil, let task else { return }
        pongDeadline = clock.schedule(after: pongTimeout) { [weak self] in
            self?.failed(gen)
        }
        task.sendPing { [weak self] error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.pongDeadline?.cancel()
                self.pongDeadline = nil
                if error != nil { self.failed(gen) } else { self.schedulePing(gen) }
            }
        }
    }

    // MARK: - URLSessionDelegate

    /// The monitor serves a self-signed certificate. Trust it for the paired host only.
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let monitor, space.host == monitor.host,
           let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
