import Foundation
@testable import TodoKit

/// Lets a test hold a repository call in flight, then release it.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// In-memory ``TodoRepository`` with failure injection and an optional gate to hold calls in flight.
actor FakeTodoRepository: TodoRepository {
    private(set) var todos: [Todo]
    private(set) var calls: [String] = []

    /// Thrown (once) by the next call.
    var failNext: TodoError?
    /// When set, calls suspend until it opens (after being recorded in `calls`).
    var gate: Gate?
    private var nextId = 100

    init(_ initial: [Todo] = []) {
        todos = initial
    }

    func setFailNext(_ error: TodoError?) { failNext = error }
    func setGate(_ gate: Gate?) { self.gate = gate }
    func setTodos(_ todos: [Todo]) { self.todos = todos }

    func list() async throws -> [Todo] {
        try await intercept("list")
        return todos
    }

    func create(title: String, notes: String?) async throws -> Todo {
        try await intercept("create:\(title)")
        let created = makeTodo(id: "id-\(nextId)", title: title, notes: notes)
        nextId += 1
        todos.append(created)
        return created
    }

    func update(id: String, title: String?, notes: String?, completed: Bool?) async throws -> Todo {
        try await intercept("update:\(id):\(title ?? "-"):\(notes ?? "-"):\(completed.map(String.init) ?? "-")")
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            throw TodoError.notFound(detail: "Todo \(id) does not exist.")
        }
        var todo = todos[index]
        if let title { todo.title = title }
        if let notes { todo.notes = notes.isEmpty ? nil : notes }
        if let completed { todo.completed = completed }
        todos[index] = todo
        return todo
    }

    func delete(id: String) async throws {
        try await intercept("delete:\(id)")
        guard todos.contains(where: { $0.id == id }) else {
            throw TodoError.notFound(detail: "Todo \(id) does not exist.")
        }
        todos.removeAll { $0.id == id }
    }

    /// Suspends until at least `count` calls have been made.
    func waitForCalls(_ count: Int) async {
        while calls.count < count { await Task.yield() }
    }

    private func intercept(_ call: String) async throws {
        calls.append(call)
        if let gate { await gate.wait() }
        if let error = failNext {
            failNext = nil
            throw error
        }
    }
}

func makeTodo(id: String, title: String? = nil, notes: String? = nil, completed: Bool = false) -> Todo {
    Todo(
        id: id, title: title ?? "Todo \(id)", notes: notes, completed: completed,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0)
    )
}
