import Foundation
import Network

/// A local plain-`ws` stand-in for the monitor's remote-control channel.
final class FakeSamsungServer {
    enum Mode {
        case accept(token: String?)
        case reject
        case timeOut
        /// Accepts the socket but never answers.
        case silent
    }

    var mode: Mode
    var onReceive: ((String) -> Void)?
    var onConnection: (() -> Void)?
    private(set) var port: Int = 0

    private let listener: NWListener
    private let queue = DispatchQueue(label: "FakeSamsungServer")
    private var connections: [NWConnection] = []

    init(mode: Mode) throws {
        self.mode = mode
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        port = Int(listener.port?.rawValue ?? 0)
    }

    func stop() {
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
        listener.cancel()
    }

    /// Drops every open connection but keeps listening.
    func dropConnections() {
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        switch mode {
        case .accept(let token):
            if let token {
                send(#"{"event":"ms.channel.connect","data":{"token":"\#(token)"}}"#, on: connection)
            } else {
                send(#"{"event":"ms.channel.connect","data":{"clients":[]}}"#, on: connection)
            }
        case .reject:
            send(#"{"event":"ms.channel.unauthorized"}"#, on: connection)
        case .timeOut:
            send(#"{"event":"ms.channel.timeOut"}"#, on: connection)
        case .silent:
            break
        }
        receive(on: connection)
        onConnection?()
    }

    private func send(_ text: String, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            // Only text frames are commands; pings and pongs are control frames.
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if metadata?.opcode == .text, let data, let text = String(data: data, encoding: .utf8) {
                self?.onReceive?(text)
            }
            if error == nil { self?.receive(on: connection) }
        }
    }
}
