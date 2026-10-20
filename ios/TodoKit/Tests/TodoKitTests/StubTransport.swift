import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A `ClientTransport` that replays queued responses and records what the client sent.
final class StubTransport: ClientTransport, @unchecked Sendable {
    struct Sent {
        let method: HTTPRequest.Method
        let path: String
        let body: Data?
        let json: [String: Any]?

        init(method: HTTPRequest.Method, path: String, body: Data?) {
            self.method = method
            self.path = path
            self.body = body
            self.json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    enum Reply {
        case response(status: Int, contentType: String?, body: Data?)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var replies: [Reply] = []
    private var recorded: [Sent] = []

    var sent: [Sent] { lock.withLock { recorded } }

    func enqueue(_ status: Int, json: Data? = nil, contentType: String = "application/json") {
        lock.withLock { replies.append(.response(status: status, contentType: json == nil ? nil : contentType, body: json)) }
    }

    func enqueueProblem(_ status: Int, example: String) {
        enqueue(status, json: ContractExamples.json(example), contentType: "application/problem+json")
    }

    func enqueueFailure(_ error: any Error) {
        lock.withLock { replies.append(.failure(error)) }
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var data: Data?
        if let body { data = try await Data(collecting: body, upTo: 1_000_000) }
        let reply: Reply = lock.withLock {
            recorded.append(Sent(method: request.method, path: request.path ?? "", body: data))
            return replies.isEmpty ? .failure(URLError(.cannotConnectToHost)) : replies.removeFirst()
        }
        switch reply {
        case .failure(let error):
            throw error
        case .response(let status, let contentType, let body):
            var response = HTTPResponse(status: .init(code: status))
            if let contentType { response.headerFields[.contentType] = contentType }
            return (response, body.map { HTTPBody($0) })
        }
    }
}
