import Foundation
import Testing
@testable import TodoKit

@Suite struct NetworkTodoRepositoryTests {
    let transport = StubTransport()
    let repository: NetworkTodoRepository

    init() {
        repository = NetworkTodoRepository(baseURL: URL(string: "http://localhost:8080/api/v1")!, transport: transport)
    }

    // MARK: - Success paths

    @Test func listMapsContractExampleToDomainTodos() async throws {
        transport.enqueue(200, json: ContractExamples.json("TodoList"))

        let todos = try await repository.list()

        #expect(todos.count == 2)
        #expect(todos[0].id == "3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90")
        #expect(todos[0].title == "Buy groceries")
        #expect(todos[0].notes == "Milk, eggs, coffee")
        #expect(todos[0].completed == false)
        #expect(todos[0].createdAt == Date(timeIntervalSince1970: 1_792_504_800)) // 2026-10-20T14:00:00Z
        #expect(todos[1].title == "Renew passport")
        #expect(todos[1].notes == nil)
        #expect(todos[1].completed == true)
        #expect(transport.sent.map(\.method) == [.get])
        #expect(transport.sent.first?.path == "/todos")
    }

    @Test func listDecodesFractionalSecondTimestamps() async throws {
        let json = #"[{"id":"a","title":"T","completed":false,"createdAt":"2026-10-20T14:00:00.250Z","updatedAt":"2026-10-20T14:00:00Z"}]"#
        transport.enqueue(200, json: Data(json.utf8))

        let todo = try #require(try await repository.list().first)

        #expect(todo.createdAt == Date(timeIntervalSince1970: 1_792_504_800.25))
        #expect(todo.updatedAt == Date(timeIntervalSince1970: 1_792_504_800))
    }

    @Test func createPostsTitleAndNotes() async throws {
        transport.enqueue(201, json: ContractExamples.json("Todo"))

        let created = try await repository.create(title: "Buy groceries", notes: "Milk, eggs, coffee")

        #expect(created.id == "3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90")
        let sent = try #require(transport.sent.first)
        #expect(sent.method == .post)
        #expect(sent.path == "/todos")
        #expect(sent.json as NSDictionary? == ContractExamples.object("CreateTodo") as NSDictionary)
    }

    @Test(arguments: [nil, "", "   "] as [String?])
    func createOmitsBlankNotes(notes: String?) async throws {
        transport.enqueue(201, json: ContractExamples.json("Todo"))

        _ = try await repository.create(title: "Buy groceries", notes: notes)

        #expect(try #require(transport.sent.first?.json) as NSDictionary == ["title": "Buy groceries"])
    }

    @Test func updateSendsOnlyProvidedFields() async throws {
        transport.enqueue(200, json: ContractExamples.json("CompletedTodo"))

        let updated = try await repository.update(
            id: "3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90", title: nil, notes: nil, completed: true
        )

        #expect(updated.completed == true)
        let sent = try #require(transport.sent.first)
        #expect(sent.method == .patch)
        #expect(sent.path == "/todos/3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90")
        // Matches the contract's CompleteTodo example, and in particular has no `title: null`.
        #expect(sent.json as NSDictionary? == ContractExamples.object("CompleteTodo") as NSDictionary)
        #expect(String(decoding: try #require(sent.body), as: UTF8.self).contains("null") == false)
    }

    @Test func updateSendsEmptyNotesToClearThem() async throws {
        transport.enqueue(200, json: ContractExamples.json("Todo"))

        _ = try await repository.update(id: "3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90", title: nil, notes: "", completed: nil)

        #expect(try #require(transport.sent.first?.json) as NSDictionary == ["notes": ""])
    }

    @Test func deleteSucceedsOn204() async throws {
        transport.enqueue(204)

        try await repository.delete(id: "3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90")

        #expect(transport.sent.map(\.method) == [.delete])
        #expect(transport.sent.first?.path == "/todos/3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90")
    }

    // MARK: - Failures

    @Test func notFoundProblemMapsToNotFound() async {
        transport.enqueueProblem(404, example: "NotFoundProblem")

        await #expect(throws: TodoError.notFound(detail: "Todo 00000000-0000-0000-0000-000000000000 does not exist.")) {
            try await repository.delete(id: "00000000-0000-0000-0000-000000000000")
        }
    }

    @Test func validationProblemMapsToValidationWithFieldErrors() async {
        transport.enqueueProblem(400, example: "ValidationProblem")

        await #expect(throws: TodoError.validation(
            detail: "Request body failed validation.",
            fieldErrors: ["title": "must not be blank"]
        )) {
            try await repository.create(title: " ", notes: nil)
        }
    }

    @Test func internalProblemMapsToServer() async {
        transport.enqueueProblem(500, example: "InternalProblem")

        await #expect(throws: TodoError.server(status: 500, detail: nil)) {
            try await repository.list()
        }
    }

    @Test func undocumentedStatusStillMapsToServerWithTheProblemDetail() async {
        let body = Data(#"{"title":"Service Unavailable","status":503,"detail":"Try later."}"#.utf8)
        transport.enqueue(503, json: body, contentType: "application/problem+json")

        await #expect(throws: TodoError.server(status: 503, detail: "Try later.")) {
            try await repository.list()
        }
    }

    @Test func nonProblemErrorBodyStillMapsByStatus() async {
        transport.enqueue(502, json: Data("<html>Bad gateway</html>".utf8), contentType: "text/html")

        await #expect(throws: TodoError.server(status: 502, detail: nil)) {
            try await repository.list()
        }
    }

    @Test func connectionFailureMapsToNetwork() async {
        transport.enqueueFailure(URLError(.cannotConnectToHost))

        await #expect(throws: TodoError.network) {
            try await repository.list()
        }
    }

    @Test func malformedSuccessBodyMapsToUnexpected() async {
        transport.enqueue(200, json: Data("{}".utf8))

        await #expect(throws: TodoError.self) {
            try await repository.list()
        }
    }
}
