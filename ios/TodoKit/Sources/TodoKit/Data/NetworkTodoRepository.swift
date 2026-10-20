import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// ``TodoRepository`` backed by the client generated from `contract/openapi.yaml`.
struct NetworkTodoRepository: TodoRepository {
    private let api: any APIProtocol

    init(api: any APIProtocol) {
        self.api = api
    }

    init(baseURL: URL, transport: any ClientTransport) {
        self.init(api: Client(
            serverURL: baseURL,
            configuration: .init(dateTranscoder: FlexibleDateTranscoder()),
            transport: transport
        ))
    }

    static func live(baseURL: URL = TodoAPI.baseURL, session: URLSession = .shared) -> NetworkTodoRepository {
        NetworkTodoRepository(baseURL: baseURL, transport: URLSessionTransport(configuration: .init(session: session)))
    }

    func list() async throws -> [Todo] {
        switch try await call({ try await api.listTodos() }) {
        case .ok(let ok):
            return try await decoding { try ok.body.json.map(Todo.init) }
        case .internalServerError(let response):
            throw error(status: 500, problem: try? response.body.application_problem_plus_json)
        case .undocumented(let status, let payload):
            throw await error(status: status, payload: payload)
        }
    }

    func create(title: String, notes: String?) async throws -> Todo {
        let body = Components.Schemas.CreateTodo(title: title, notes: notes?.nilIfBlank)
        switch try await call({ try await api.createTodo(body: .json(body)) }) {
        case .created(let created):
            return try await decoding { Todo(try created.body.json) }
        case .badRequest(let response):
            throw error(status: 400, problem: try? response.body.application_problem_plus_json)
        case .internalServerError(let response):
            throw error(status: 500, problem: try? response.body.application_problem_plus_json)
        case .undocumented(let status, let payload):
            throw await error(status: status, payload: payload)
        }
    }

    func update(id: String, title: String?, notes: String?, completed: Bool?) async throws -> Todo {
        // Optionals that are nil are omitted from the JSON (never sent as null), which is what
        // PATCH needs: absent means "leave unchanged".
        let body = Components.Schemas.UpdateTodo(title: title, notes: notes, completed: completed)
        switch try await call({ try await api.updateTodo(path: .init(todoId: id), body: .json(body)) }) {
        case .ok(let ok):
            return try await decoding { Todo(try ok.body.json) }
        case .badRequest(let response):
            throw error(status: 400, problem: try? response.body.application_problem_plus_json)
        case .notFound(let response):
            throw error(status: 404, problem: try? response.body.application_problem_plus_json)
        case .internalServerError(let response):
            throw error(status: 500, problem: try? response.body.application_problem_plus_json)
        case .undocumented(let status, let payload):
            throw await error(status: status, payload: payload)
        }
    }

    func delete(id: String) async throws {
        switch try await call({ try await api.deleteTodo(path: .init(todoId: id)) }) {
        case .noContent:
            return
        case .notFound(let response):
            throw error(status: 404, problem: try? response.body.application_problem_plus_json)
        case .internalServerError(let response):
            throw error(status: 500, problem: try? response.body.application_problem_plus_json)
        case .undocumented(let status, let payload):
            throw await error(status: status, payload: payload)
        }
    }

    // MARK: - Error mapping

    /// Runs a generated-client call, translating thrown transport failures into ``TodoError``.
    private func call<T>(_ block: () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch let error as TodoError {
            throw error
        } catch {
            throw TodoError(transportFailure: error)
        }
    }

    private func decoding<T>(_ block: () throws -> T) async throws -> T {
        do {
            return try block()
        } catch {
            throw TodoError.unexpected(message: "Unexpected response from the server.")
        }
    }

    private func error(status: Int, problem: Components.Schemas.ProblemDetails?) -> TodoError {
        let detail = problem?.detail
        switch status {
        case 400:
            let fields = (problem?.errors ?? []).reduce(into: [String: String]()) { $0[$1.field] = $1.message }
            return .validation(detail: detail, fieldErrors: fields)
        case 404:
            return .notFound(detail: detail)
        default:
            return .server(status: status, detail: detail)
        }
    }

    /// Responses with a status the contract doesn't list. The body may still be a problem document.
    private func error(status: Int, payload: UndocumentedPayload) async -> TodoError {
        var problem: Components.Schemas.ProblemDetails?
        if let body = payload.body, let data = try? await Data(collecting: body, upTo: 64 * 1024) {
            problem = try? JSONDecoder().decode(Components.Schemas.ProblemDetails.self, from: data)
        }
        return error(status: status, problem: problem)
    }
}

private extension TodoError {
    /// The generated client wraps everything it throws in a `ClientError`; look through it.
    init(transportFailure error: any Error) {
        let underlying = (error as? ClientError)?.underlyingError ?? error
        if underlying is URLError {
            self = .network
        } else {
            self = .unexpected(message: "Unexpected response from the server.")
        }
    }
}

private extension Todo {
    init(_ dto: Components.Schemas.Todo) {
        self.init(
            id: dto.id,
            title: dto.title,
            notes: dto.notes,
            completed: dto.completed,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
