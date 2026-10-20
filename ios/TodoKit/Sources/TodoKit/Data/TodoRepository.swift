/// All methods throw ``TodoError`` on failure.
protocol TodoRepository: Sendable {
    func list() async throws -> [Todo]

    func create(title: String, notes: String?) async throws -> Todo

    /// Absent (`nil`) arguments are left unchanged. Pass `notes: ""` to clear notes.
    func update(id: String, title: String?, notes: String?, completed: Bool?) async throws -> Todo

    func delete(id: String) async throws
}

extension TodoRepository {
    func update(id: String, title: String? = nil, notes: String? = nil, completed: Bool? = nil) async throws -> Todo {
        try await update(id: id, title: title, notes: notes, completed: completed)
    }
}
