import Foundation
import Observation

enum ListState: Equatable {
    case loading
    case loaded([Todo])
    case failed(String)
}

/// A mutation that failed and can be retried from the error banner.
enum Operation: Equatable {
    case refresh
    case create(title: String, notes: String?)
    case edit(id: String, title: String?, notes: String?)
    case setCompleted(id: String, completed: Bool)
    case delete(Todo)
}

struct UserMessage: Equatable, Identifiable {
    let id: Int
    let text: String
    let retry: Operation?
}

@MainActor
@Observable
final class TodoListViewModel {
    private(set) var list: ListState = .loading
    private(set) var message: UserMessage?

    private let repository: any TodoRepository
    private var nextMessageId = 0
    private var started = false

    init(repository: any TodoRepository) {
        self.repository = repository
    }

    var todos: [Todo] {
        if case .loaded(let todos) = list { todos } else { [] }
    }

    // MARK: - Loading

    /// Loads once; later calls (e.g. the view reappearing) are no-ops.
    func loadIfNeeded() async {
        guard !started else { return }
        await load()
    }

    /// Full-screen load, used on start and from the error screen's Retry.
    func load() async {
        started = true
        list = .loading
        do {
            list = .loaded(try await fetchList())
        } catch {
            list = .failed(TodoError(error).userText)
        }
    }

    /// Pull-to-refresh: keeps the current list visible and reports failures in the banner.
    func refresh() async {
        do {
            list = .loaded(try await fetchList())
        } catch {
            showError(TodoError(error), prefix: "Couldn't refresh", retry: .refresh)
        }
    }

    /// `.task` and `.refreshable` cancel their task when the view updates or goes away. Running the
    /// request in an unstructured task keeps that from surfacing as a spurious "cancelled" failure.
    private func fetchList() async throws -> [Todo] {
        let repository = repository
        return try await Task { try await repository.list() }.value
    }

    // MARK: - Mutations

    /// Creates a new todo when `id` is nil, otherwise edits it. Unchanged fields are not sent.
    func save(id: String?, title: String, notes: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        guard let id else {
            await create(title: cleanTitle, notes: cleanNotes.isEmpty ? nil : cleanNotes)
            return
        }
        guard let current = todos.first(where: { $0.id == id }) else { return }
        let newTitle = cleanTitle == current.title ? nil : cleanTitle
        let newNotes = cleanNotes == (current.notes ?? "") ? nil : cleanNotes
        if newTitle != nil || newNotes != nil {
            await edit(id: id, title: newTitle, notes: newNotes)
        }
    }

    /// Optimistic: the row flips immediately and is restored if the server call fails.
    func setCompleted(id: String, completed: Bool) async {
        guard let before = todos.first(where: { $0.id == id }) else { return }
        var optimistic = before
        optimistic.completed = completed
        replace(optimistic)
        do {
            replace(try await repository.update(id: id, title: nil, notes: nil, completed: completed))
        } catch {
            replace(before)
            showError(
                TodoError(error),
                prefix: "Couldn't update \"\(before.title)\"",
                retry: .setCompleted(id: id, completed: completed)
            )
        }
    }

    /// Optimistic: the row disappears immediately and is put back in place if the server call fails.
    func delete(_ todo: Todo) async {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        updateTodos { $0.remove(at: index) }
        do {
            try await repository.delete(id: todo.id)
        } catch let error as TodoError {
            if case .notFound = error { return } // Already gone on the server: the removal was right.
            restore(todo, at: index, error: error)
        } catch {
            restore(todo, at: index, error: TodoError(error))
        }
    }

    func retry(_ operation: Operation) async {
        switch operation {
        case .refresh: await refresh()
        case .create(let title, let notes): await create(title: title, notes: notes)
        case .edit(let id, let title, let notes): await edit(id: id, title: title, notes: notes)
        case .setCompleted(let id, let completed): await setCompleted(id: id, completed: completed)
        case .delete(let todo): await delete(todo)
        }
    }

    func messageShown(id: Int) {
        if message?.id == id { message = nil }
    }

    // MARK: - Private

    private func create(title: String, notes: String?) async {
        do {
            let created = try await repository.create(title: title, notes: notes)
            updateTodos { $0.append(created) }
        } catch {
            showError(TodoError(error), prefix: "Couldn't add \"\(title)\"", retry: .create(title: title, notes: notes))
        }
    }

    private func edit(id: String, title: String?, notes: String?) async {
        do {
            replace(try await repository.update(id: id, title: title, notes: notes, completed: nil))
        } catch let error as TodoError {
            if case .notFound = error {
                updateTodos { $0.removeAll { $0.id == id } }
                showError(error, prefix: "That todo no longer exists", retry: nil)
            } else {
                showError(error, prefix: "Couldn't save changes", retry: .edit(id: id, title: title, notes: notes))
            }
        } catch {
            showError(TodoError(error), prefix: "Couldn't save changes", retry: .edit(id: id, title: title, notes: notes))
        }
    }

    private func restore(_ todo: Todo, at index: Int, error: TodoError) {
        updateTodos { $0.insert(todo, at: min(index, $0.count)) }
        showError(error, prefix: "Couldn't delete \"\(todo.title)\"", retry: .delete(todo))
    }

    private func updateTodos(_ transform: (inout [Todo]) -> Void) {
        guard case .loaded(var todos) = list else { return }
        transform(&todos)
        list = .loaded(todos)
    }

    private func replace(_ todo: Todo) {
        updateTodos { todos in
            if let index = todos.firstIndex(where: { $0.id == todo.id }) { todos[index] = todo }
        }
    }

    private func showError(_ error: TodoError, prefix: String, retry: Operation?) {
        message = UserMessage(id: nextMessageId, text: "\(prefix): \(error.userText)", retry: retry)
        nextMessageId += 1
    }
}
