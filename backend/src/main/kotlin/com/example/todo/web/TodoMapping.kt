package com.example.todo.web

import java.time.ZoneOffset
import com.example.todo.api.model.Todo as TodoDto
import com.example.todo.domain.Todo

internal fun Todo.toDto() = TodoDto(
    id = id,
    title = title,
    notes = notes,
    completed = completed,
    createdAt = createdAt.atOffset(ZoneOffset.UTC),
    updatedAt = updatedAt.atOffset(ZoneOffset.UTC),
)
