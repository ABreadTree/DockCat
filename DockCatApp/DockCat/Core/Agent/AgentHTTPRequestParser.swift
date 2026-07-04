import Foundation

struct AgentHTTPRequest {
    let agentEvent: AgentEvent
}

struct AgentHTTPResponse: Equatable {
    let statusCode: Int

    init(statusCode: Int) {
        switch statusCode {
        case 204, 400, 404, 405:
            self.statusCode = statusCode
        default:
            self.statusCode = 500
        }
    }

    var data: Data {
        let reason: String
        switch statusCode {
        case 204:
            reason = "No Content"
        case 400:
            reason = "Bad Request"
        case 404:
            reason = "Not Found"
        case 405:
            reason = "Method Not Allowed"
        default:
            reason = "Internal Server Error"
        }
        return "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".data(using: .utf8)!
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
        guard let delimiterRange = data.range(of: Data([13, 10, 13, 10])) else {
            throw ParseError.badRequest
        }

        let header = String(decoding: data[..<delimiterRange.lowerBound], as: UTF8.self)
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw ParseError.badRequest }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { throw ParseError.badRequest }
        guard parts[0] == "POST" else { throw ParseError.methodNotAllowed }
        guard parts[1] == "/agent-events" else { throw ParseError.notFound }

        let contentLengthValues = lines.dropFirst().compactMap { line -> String? in
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { return nil }
            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "content-length" else { return nil }
            return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard contentLengthValues.count == 1,
              let contentLength = Int(contentLengthValues[0]),
              (0...maxBodyBytes).contains(contentLength) else {
            throw ParseError.badRequest
        }

        let bodyStart = delimiterRange.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= contentLength else {
            throw ParseError.badRequest
        }
        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        let bodyData = data[bodyStart..<bodyEnd]
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
