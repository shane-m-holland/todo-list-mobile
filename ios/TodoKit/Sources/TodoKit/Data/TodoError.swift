import Foundation

/// Failures surfaced by ``TodoRepository``, already translated from HTTP / IO terms.
enum TodoError: Error, Equatable, Sendable {
    /// The server could not be reached (offline, timeout, mock not running, ...).
    case network
    case notFound(detail: String?)
    case validation(detail: String?, fieldErrors: [String: String])
    case server(status: Int, detail: String?)
    case unexpected(message: String)

    /// Wraps anything thrown by a repository, which should only ever be a `TodoError`.
    init(_ error: any Error) {
        self = (error as? TodoError) ?? .unexpected(message: error.localizedDescription)
    }

    /// Text that is safe to show to the user.
    var userText: String {
        switch self {
        case .network: "Can't reach the server. Check your connection."
        case .notFound(let detail): detail ?? "Todo not found"
        case .validation(let detail, _): detail ?? "Invalid request"
        case .server(let status, let detail): detail ?? "Server error (\(status))"
        case .unexpected(let message): message.isEmpty ? "Something went wrong." : message
        }
    }
}
