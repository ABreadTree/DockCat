import Darwin
import Foundation

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

enum AgentHTTPServerStartError: Equatable {
    case socketFailed
    case bindFailed
    case listenFailed
}

final class AgentHTTPServer {
    private let state: AgentHTTPServerState

    var isRunning: Bool { state.isRunning }
    var lastStartError: AgentHTTPServerStartError? { state.lastStartError }

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
    private struct ActiveConnection: Hashable {
        let socket: Int32
        let generation: UInt64
    }

    private static let maxActiveConnections = 8

    private let port: UInt16
    private let onEvent: @Sendable (AgentEvent) -> Void
    private let lock = NSLock()
    private let connectionQueue = DispatchQueue(
        label: "DockCat.AgentHTTPServer.Connections",
        qos: .utility,
        attributes: .concurrent
    )

    private var listenerSocket: Int32 = -1
    private var listenerGeneration: UInt64 = 0
    private var connectionGeneration: UInt64 = 0
    private var running = false
    private var startError: AgentHTTPServerStartError?
    private var activeConnections: Set<ActiveConnection> = []

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    var lastStartError: AgentHTTPServerStartError? {
        lock.lock()
        defer { lock.unlock() }
        return startError
    }

    init(port: UInt16, onEvent: @escaping @Sendable (AgentEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
    }

    func start() {
        lock.lock()
        guard !running, listenerSocket < 0 else {
            lock.unlock()
            return
        }
        startError = nil
        let listener = makeListenerSocket()
        guard let socket = listener.socket else {
            startError = listener.error
            lock.unlock()
            return
        }
        listenerGeneration &+= 1
        let generation = listenerGeneration
        listenerSocket = socket
        running = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop(listenerSocket: socket, generation: generation)
        }
    }

    func stop() {
        lock.lock()
        let socket = listenerSocket
        let connections = activeConnections.map(\.socket)
        listenerGeneration &+= 1
        listenerSocket = -1
        running = false
        connections.forEach(shutdownSocket)
        lock.unlock()

        closeSocket(socket)
    }

    private func acceptLoop(listenerSocket: Int32, generation: UInt64) {
        defer { finishListenerIfCurrent(listenerSocket, generation: generation) }

        while isRunning(listenerSocket: listenerSocket, generation: generation) {
            var address = sockaddr_storage()
            var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let connection = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.accept(listenerSocket, socketAddress, &addressLength)
                }
            }

            if connection < 0 {
                if errno == EINTR {
                    continue
                }
                if isRunning(listenerSocket: listenerSocket, generation: generation) {
                    DockCatLog.app.error("\(self.posixErrorMessage("accept"))")
                }
                break
            }

            guard isRunning(listenerSocket: listenerSocket, generation: generation) else {
                closeSocket(connection)
                continue
            }

            configureConnectionSocket(connection)
            guard let activeConnection = addActiveConnection(connection, listenerGeneration: generation) else {
                closeSocket(connection)
                continue
            }
            connectionQueue.async { [weak self] in
                guard let self else {
                    closeSocket(connection)
                    return
                }
                self.handleConnection(activeConnection)
                self.closeConnection(activeConnection)
            }
        }
    }

    private func handleConnection(_ connection: ActiveConnection) {
        var requestBuffer = AgentHTTPRequestBuffer()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while isActiveConnection(connection) {
            let count = Darwin.recv(connection.socket, &buffer, buffer.count, 0)
            if count > 0 {
                let chunk = Data(buffer[0..<count])
                switch requestBuffer.append(chunk) {
                case .needsMoreData:
                    continue
                case .ready(let requestData):
                    respond(to: requestData, on: connection)
                    return
                case .badRequest:
                    sendResponse(AgentHTTPResponse(statusCode: 400), on: connection)
                    return
                }
            } else if count == 0 {
                return
            } else if errno == EINTR {
                continue
            } else {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    sendResponse(AgentHTTPResponse(statusCode: 400), on: connection)
                }
                return
            }
        }
    }

    private func respond(to data: Data, on connection: ActiveConnection) {
        let response: AgentHTTPResponse
        do {
            let request = try AgentHTTPRequestParser.parse(data)
            onEvent(request.agentEvent)
            response = AgentHTTPResponse(statusCode: 204)
        } catch {
            response = Self.response(for: error)
        }

        sendResponse(response, on: connection)
    }

    private func sendResponse(_ response: AgentHTTPResponse, on connection: ActiveConnection) {
        guard isActiveConnection(connection) else { return }
        response.data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesSent = 0
            while bytesSent < rawBuffer.count {
                let result = Darwin.send(connection.socket, baseAddress.advanced(by: bytesSent), rawBuffer.count - bytesSent, 0)
                if result > 0 {
                    bytesSent += result
                } else if errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private func makeListenerSocket() -> (socket: Int32?, error: AgentHTTPServerStartError?) {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socket >= 0 else {
            DockCatLog.app.error("\(self.posixErrorMessage("socket"))")
            return (nil, .socketFailed)
        }

        setEnabledSocketOption(SO_REUSEADDR, on: socket)
        setEnabledSocketOption(SO_NOSIGPIPE, on: socket)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(socket, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            DockCatLog.app.error("\(self.posixErrorMessage("bind"))")
            closeSocket(socket)
            return (nil, .bindFailed)
        }

        guard Darwin.listen(socket, 8) == 0 else {
            DockCatLog.app.error("\(self.posixErrorMessage("listen"))")
            closeSocket(socket)
            return (nil, .listenFailed)
        }

        return (socket, nil)
    }

    private func configureConnectionSocket(_ socket: Int32) {
        setEnabledSocketOption(SO_NOSIGPIPE, on: socket)

        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            _ = setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    private func setEnabledSocketOption(_ option: Int32, on socket: Int32) {
        var value: Int32 = 1
        _ = setsockopt(socket, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    private func addActiveConnection(_ connection: Int32, listenerGeneration generation: UInt64) -> ActiveConnection? {
        lock.lock()
        defer { lock.unlock() }
        guard running,
              listenerGeneration == generation,
              activeConnections.count < Self.maxActiveConnections else {
            return nil
        }
        connectionGeneration &+= 1
        let activeConnection = ActiveConnection(socket: connection, generation: connectionGeneration)
        activeConnections.insert(activeConnection)
        return activeConnection
    }

    private func closeConnection(_ connection: ActiveConnection) {
        lock.lock()
        let shouldClose = activeConnections.remove(connection) != nil
        lock.unlock()

        if shouldClose {
            closeSocket(connection.socket)
        }
    }

    private func isActiveConnection(_ connection: ActiveConnection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeConnections.contains(connection)
    }

    private func isRunning(listenerSocket socket: Int32, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return running && listenerSocket == socket && listenerGeneration == generation
    }

    private func finishListenerIfCurrent(_ socket: Int32, generation: UInt64) {
        lock.lock()
        let shouldClose = listenerSocket == socket && listenerGeneration == generation
        if shouldClose {
            listenerSocket = -1
            running = false
        }
        lock.unlock()

        if shouldClose {
            closeSocket(socket)
        }
    }

    private func posixErrorMessage(_ operation: String) -> String {
        let errorNumber = errno
        return "\(operation) failed: \(String(cString: strerror(errorNumber)))"
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

private func closeSocket(_ socket: Int32) {
    guard socket >= 0 else { return }
    shutdownSocket(socket)
    _ = Darwin.close(socket)
}

private func shutdownSocket(_ socket: Int32) {
    guard socket >= 0 else { return }
    _ = Darwin.shutdown(socket, SHUT_RDWR)
}
