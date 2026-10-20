package com.example.todo.data

import java.time.Instant

/** App-side model. The UI never sees the generated network DTOs. */
data class Todo(
    val id: String,
    val title: String,
    val notes: String?,
    val completed: Boolean,
    val createdAt: Instant,
    val updatedAt: Instant,
)
