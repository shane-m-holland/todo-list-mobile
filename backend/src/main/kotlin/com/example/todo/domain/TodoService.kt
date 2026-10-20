package com.example.todo.domain

import java.time.Clock
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import org.springframework.stereotype.Service

@Service
class TodoService(
    private val repository: TodoRepository,
    private val clock: Clock,
) {
    fun list(): List<Todo> = repository.findAll()

    fun get(id: UUID): Todo = repository.findById(id) ?: throw TodoNotFoundException(id)

    fun create(title: String, notes: String?): Todo {
        val now = now()
        return repository.insert(
            Todo(
                id = UUID.randomUUID(),
                title = title,
                notes = notes?.takeIf { it.isNotEmpty() },
                completed = false,
                createdAt = now,
                updatedAt = now,
            ),
        )
    }

    /** Absent (`null`) arguments are left unchanged. `notes = ""` clears the notes. */
    fun update(id: UUID, title: String?, notes: String?, completed: Boolean?): Todo {
        if (title == null && notes == null && completed == null) {
            throw InvalidTodoRequestException("At least one of title, notes or completed must be provided.")
        }
        val now = now()
        return repository.update(id) { current ->
            current.copy(
                title = title ?: current.title,
                notes = if (notes == null) current.notes else notes.ifEmpty { null },
                completed = completed ?: current.completed,
                updatedAt = now,
            )
        } ?: throw TodoNotFoundException(id)
    }

    fun delete(id: UUID) {
        if (!repository.delete(id)) throw TodoNotFoundException(id)
    }

    // Millisecond precision: that is what survives a JSON round trip on every client.
    private fun now(): Instant = Instant.now(clock).truncatedTo(ChronoUnit.MILLIS)
}
