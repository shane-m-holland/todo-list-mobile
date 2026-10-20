import Foundation

/// App-side model. The UI never sees the generated network types.
struct Todo: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var title: String
    var notes: String?
    var completed: Bool
    var createdAt: Date
    var updatedAt: Date
}
