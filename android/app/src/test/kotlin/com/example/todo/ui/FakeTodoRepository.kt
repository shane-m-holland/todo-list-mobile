package com.example.todo.ui

import com.example.todo.data.Todo
import com.example.todo.data.TodoError
import com.example.todo.data.TodoRepository
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred

/** In-memory [TodoRepository] with failure injection and an optional gate to hold calls in flight. */
class FakeTodoRepository(initial: List<Todo> = emptyList()) : TodoRepository {
    val todos = initial.toMutableList()
    val calls = mutableListOf<String>()

    /** Thrown (once) by the next call. */
    var failNext: TodoError? = null

    /** When set, calls suspend until it completes. */
    var gate: CompletableDeferred<Unit>? = null

    private var nextId = 100

    override suspend fun list(): List<Todo> = intercept("list") { todos.toList() }

    override suspend fun create(title: String, notes: String?): Todo = intercept("create:$title") {
        todo(id = "id-${nextId++}", title = title, notes = notes).also { todos += it }
    }

    override suspend fun update(id: String, title: String?, notes: String?, completed: Boolean?): Todo =
        intercept("update:$id:$title:$notes:$completed") {
            val index = todos.indexOfFirst { it.id == id }
            if (index < 0) throw TodoError.NotFound("Todo $id does not exist.")
            val current = todos[index]
            current.copy(
                title = title ?: current.title,
                notes = when (notes) {
                    null -> current.notes
                    "" -> null
                    else -> notes
                },
                completed = completed ?: current.completed,
            ).also { todos[index] = it }
        }

    override suspend fun delete(id: String) = intercept("delete:$id") {
        if (!todos.removeIf { it.id == id }) throw TodoError.NotFound("Todo $id does not exist.")
    }

    private suspend fun <T> intercept(call: String, block: () -> T): T {
        calls += call
        gate?.await()
        failNext?.let { failNext = null; throw it }
        return block()
    }
}

fun todo(id: String, title: String = "Todo $id", notes: String? = null, completed: Boolean = false) =
    Todo(id, title, notes, completed, Instant.EPOCH, Instant.EPOCH)

fun networkError() = TodoError.Network(java.io.IOException("offline"))
