import Foundation

enum TodoAPI {
    /// The Simulator reaches the host's localhost directly, so this is the WireMock mock
    /// (`make mock-up`). Set `TODO_API_BASE_URL` in the scheme's environment to point elsewhere.
    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["TODO_API_BASE_URL"], let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8080/api/v1")!
    }
}
