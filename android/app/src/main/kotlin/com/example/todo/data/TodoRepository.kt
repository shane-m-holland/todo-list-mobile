package com.example.todo.data

/** All methods throw [TodoError] on failure. */
interface TodoRepository {
    suspend fun list(): List<Todo>

    suspend fun create(title: String, notes: String? = null): Todo

    /** Absent (`null`) arguments are left unchanged. Pass `notes = ""` to clear notes. */
    suspend fun update(
        id: String,
        title: String? = null,
        notes: String? = null,
        completed: Boolean? = null,
    ): Todo

    suspend fun delete(id: String)
}
