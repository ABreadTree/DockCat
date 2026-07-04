import Foundation
import Network

final class AgentHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let queue = DispatchQueue(label: "DockCat.AgentHTTPServer")
    private var listener: NWListener?

    private(set) var isRunning = false

    init(port: UInt16 = 8765, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
    }

    func start() {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let loopback = IPv4Address("127.0.0.1") else {
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(loopback), port: nwPort)

            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                case .cancelled, .failed:
                    self?.isRunning = false
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            isRunning = false
            DockCatLog.app.error("Failed to start agent HTTP server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: AgentHTTPRequestParser.maxBodyBytes + 2048
        ) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }

            let response: AgentHTTPResponse
            do {
                let request = try AgentHTTPRequestParser.parse(data)
                self.onEvent(request.agentEvent)
                response = AgentHTTPResponse(statusCode: 204)
            } catch {
                response = Self.response(for: error)
            }

            connection.send(content: response.data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func response(for error: Error) -> AgentHTTPResponse {
        switch error {
        case AgentHTTPRequestParser.ParseError.notFound:
            return AgentHTTPResponse(statusCode: 404)
        case AgentHTTPRequestParser.ParseError.methodNotAllowed:
            return AgentHTTPResponse(statusCode: 405)
        default:
            return AgentHTTPResponse(statusCode: 400)
        }
    }
}
