package com.example.todo.domain

import java.util.UUID
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Repository

/** Default storage (profile `memory`): nothing to set up, everything is lost on restart. */
@Repository
@Profile("memory")
class InMemoryTodoRepository : TodoRepository {
    // LinkedHashMap keeps insertion order, which is creation order. All access goes through `lock`.
    private val todos = LinkedHashMap<UUID, Todo>()
    private val lock = Any()

    override fun findAll(): List<Todo> = synchronized(lock) { todos.values.toList() }

    override fun findById(id: UUID): Todo? = synchronized(lock) { todos[id] }

    override fun insert(todo: Todo): Todo = synchronized(lock) {
        check(todo.id !in todos) { "Duplicate todo id ${todo.id}" }
        todo.also { todos[it.id] = it }
    }

    override fun update(id: UUID, transform: (Todo) -> Todo): Todo? = synchronized(lock) {
        val current = todos[id] ?: return null
        transform(current).also { todos[id] = it }
    }

    override fun delete(id: UUID): Boolean = synchronized(lock) { todos.remove(id) != null }

    /** For tests and dev resets. */
    fun clear() = synchronized(lock) { todos.clear() }
}
