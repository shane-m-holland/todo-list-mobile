package com.example.todo.domain

import java.time.Instant
import java.util.UUID

/** Domain model. The generated API DTOs stay in the web layer. */
data class Todo(
    val id: UUID,
    val title: String,
    val notes: String?,
    val completed: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
)

class TodoNotFoundException(val id: UUID) : RuntimeException("Todo $id does not exist.")

/** A request that is well-formed JSON but not acceptable, e.g. a PATCH that changes nothing. */
class InvalidTodoRequestException(message: String) : RuntimeException(message)
