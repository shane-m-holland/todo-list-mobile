package com.example.todo.data

/** Failures surfaced by [TodoRepository], already translated from HTTP / IO terms. */
sealed class TodoError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** The server could not be reached (offline, timeout, mock not running, ...). */
    class Network(cause: Throwable) : TodoError("Network unavailable", cause)

    class NotFound(detail: String?) : TodoError(detail ?: "Todo not found")

    class Validation(detail: String?, val fieldErrors: Map<String, String>) :
        TodoError(detail ?: "Invalid request")

    class Server(val status: Int, detail: String?) : TodoError(detail ?: "Server error ($status)")

    class Unexpected(cause: Throwable) : TodoError(cause.message ?: "Unexpected error", cause)
}
