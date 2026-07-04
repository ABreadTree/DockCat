import Foundation
@preconcurrency import Network

enum AgentHTTPRequestBufferResult: Equatable {
    case needsMoreData
    case ready(Data)
    case badRequest
}

struct AgentHTTPRequestBuffer {
    private static let headerDelimiter = Data([13, 10, 13, 10])
    private static let maxHeaderBytes = 2048
    private static let maxRequestBytes = AgentHTTPRequestParser.maxBodyBytes + maxHeaderBytes + headerDelimiter.count

    private var data = Data()

    mutating func append(_ chunk: Data) -> AgentHTTPRequestBufferResult {
        data.append(chunk)
        guard data.count <= Self.maxRequestBytes else { return .badRequest }
        guard let delimiterRange = data.range(of: Self.headerDelimiter) else {
            return data.count > Self.maxHeaderBytes ? .badRequest : .needsMoreData
        }

        let header = String(decoding: data[..<delimiterRange.lowerBound], as: UTF8.self)
        let lines = header.components(separatedBy: "\r\n")
        let contentLengthValues = lines.dropFirst().compactMap { line -> String? in
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { return nil }
            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "content-length" else { return nil }
            return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard contentLengthValues.count == 1,
              let contentLength = Int(contentLengthValues[0]),
              (0...AgentHTTPRequestParser.maxBodyBytes).contains(contentLength) else {
            return .badRequest
        }

        let requestEnd = delimiterRange.upperBound + contentLength
        guard data.count >= requestEnd else { return .needsMoreData }
        return .ready(data[..<requestEnd])
    }
}

final class AgentHTTPServer {
    private let state: AgentHTTPServerState

    var isRunning: Bool { state.isRunning }

    init(port: UInt16 = 8765, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        state = AgentHTTPServerState(port: port, onEvent: onEvent)
    }

    func start() {
        state.start()
    }

    func stop() {
        state.stop()
    }
}

private final class AgentHTTPServerState: @unchecked Sendable {
    private let port: UInt16
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let queue = DispatchQueue(label: "DockCat.AgentHTTPServer")
    private let queueKey = DispatchSpecificKey<Void>()

    private var listener: NWListener?
    private var running = false
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var requestBuffers: [ObjectIdentifier: AgentHTTPRequestBuffer] = [:]

    var isRunning: Bool {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return running
        }
        return queue.sync { running }
    }

    init(port: UInt16, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
        queue.setSpecific(key: queueKey, value: ())
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync {
                stopOnQueue()
            }
        }
    }

    private func startOnQueue() {
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
                guard let self else { return }
                switch state {
                case .ready:
                    self.running = true
                case .cancelled, .failed:
                    guard self.listener === listener else { return }
                    self.running = false
                    self.listener = nil
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            running = false
            listener = nil
            DockCatLog.app.error("Failed to start agent HTTP server: \(error.localizedDescription)")
        }
    }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        running = false
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
        requestBuffers.removeAll()
    }

    private func handle(_ connection: NWConnection) {
        guard running, listener != nil else {
            connection.cancel()
            return
        }

        let id = ObjectIdentifier(connection)
        activeConnections[id] = connection
        requestBuffers[id] = AgentHTTPRequestBuffer()
        connection.start(queue: queue)
        receive(on: connection, id: id)
    }

    private func receive(on connection: NWConnection, id: ObjectIdentifier) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: AgentHTTPRequestParser.maxBodyBytes + 2048
        ) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            guard self.activeConnections[id] != nil else { return }
            guard let data, !data.isEmpty else {
                self.close(connection, id: id)
                return
            }

            let result = self.requestBuffers[id]?.append(data) ?? .badRequest
            switch result {
            case .needsMoreData:
                if isComplete {
                    self.send(AgentHTTPResponse(statusCode: 400), on: connection, id: id)
                } else {
                    self.receive(on: connection, id: id)
                }
            case .ready(let requestData):
                self.respond(to: requestData, on: connection, id: id)
            case .badRequest:
                self.send(AgentHTTPResponse(statusCode: 400), on: connection, id: id)
            }
        }
    }

    private func respond(to data: Data, on connection: NWConnection, id: ObjectIdentifier) {
        let response: AgentHTTPResponse
        do {
            let request = try AgentHTTPRequestParser.parse(data)
            onEvent(request.agentEvent)
            response = AgentHTTPResponse(statusCode: 204)
        } catch {
            response = Self.response(for: error)
        }

        send(response, on: connection, id: id)
    }

    private func send(_ response: AgentHTTPResponse, on connection: NWConnection, id: ObjectIdentifier) {
        guard activeConnections[id] != nil else { return }
        connection.send(content: response.data, completion: .contentProcessed { [weak self] _ in
            self?.close(connection, id: id)
        })
    }

    private func close(_ connection: NWConnection, id: ObjectIdentifier) {
        requestBuffers[id] = nil
        activeConnections[id] = nil
        connection.cancel()
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
