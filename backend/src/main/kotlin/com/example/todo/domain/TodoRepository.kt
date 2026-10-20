package com.example.todo.domain

import java.util.UUID

/** Storage port. Implementations must keep [findAll] in creation order. */
interface TodoRepository {
    fun findAll(): List<Todo>

    fun findById(id: UUID): Todo?

    fun insert(todo: Todo): Todo

    /** Atomically applies [transform] to the stored todo. Returns null if there is none. */
    fun update(id: UUID, transform: (Todo) -> Todo): Todo?

    /** Returns whether a todo was removed. */
    fun delete(id: UUID): Boolean
}
