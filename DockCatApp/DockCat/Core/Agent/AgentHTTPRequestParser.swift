import Foundation

struct AgentHTTPRequest {
    let agentEvent: AgentEvent
}

struct AgentHTTPResponse: Equatable {
    let statusCode: Int

    var data: Data {
        let responseCode: Int
        let reason: String
        switch statusCode {
        case 204:
            responseCode = 204
            reason = "No Content"
        case 400:
            responseCode = 400
            reason = "Bad Request"
        case 404:
            responseCode = 404
            reason = "Not Found"
        case 405:
            responseCode = 405
            reason = "Method Not Allowed"
        default:
            responseCode = 500
            reason = "Internal Server Error"
        }
        return "HTTP/1.1 \(responseCode) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".data(using: .utf8)!
    }
}

enum AgentHTTPRequestParser {
    static let maxBodyBytes = 8 * 1024

    enum ParseError: Error {
        case badRequest
        case notFound
        case methodNotAllowed
    }

    static func parse(_ data: Data) throws -> AgentHTTPRequest {
        let request = String(decoding: data, as: UTF8.self)
        guard let headerRange = request.range(of: "\r\n\r\n") else {
            throw ParseError.badRequest
        }

        let header = String(request[..<headerRange.lowerBound])
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw ParseError.badRequest }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { throw ParseError.badRequest }
        guard parts[0] == "POST" else { throw ParseError.methodNotAllowed }
        guard parts[1] == "/agent-events" else { throw ParseError.notFound }

        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2, pieces[0].lowercased() == "content-length" else { return nil }
            return Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }.first ?? 0

        guard contentLength <= maxBodyBytes else { throw ParseError.badRequest }

        let bodyStart = headerRange.upperBound
        let body = String(request[bodyStart...])
        guard body.utf8.count >= contentLength else { throw ParseError.badRequest }
        let bodyData = Data(body.utf8.prefix(contentLength))
        return AgentHTTPRequest(agentEvent: try AgentEvent.decode(from: bodyData))
    }

    static func response(for data: Data) -> AgentHTTPResponse {
        do {
            _ = try parse(data)
            return AgentHTTPResponse(statusCode: 204)
        } catch ParseError.notFound {
            return AgentHTTPResponse(statusCode: 404)
        } catch ParseError.methodNotAllowed {
            return AgentHTTPResponse(statusCode: 405)
        } catch {
            return AgentHTTPResponse(statusCode: 400)
        }
    }
}
