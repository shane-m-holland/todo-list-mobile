package com.example.todo.web

import com.example.todo.api.TodosApi
import com.example.todo.api.model.CreateTodo
import com.example.todo.api.model.UpdateTodo
import com.example.todo.domain.TodoService
import java.util.UUID
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.servlet.support.ServletUriComponentsBuilder
import com.example.todo.api.model.Todo as TodoDto

/** Implements the interface generated from contract/openapi.yaml. Validation comes from the generated DTOs. */
@RestController
class TodosController(private val service: TodoService) : TodosApi {

    override fun listTodos(): ResponseEntity<List<TodoDto>> =
        ResponseEntity.ok(service.list().map { it.toDto() })

    override fun createTodo(createTodo: CreateTodo): ResponseEntity<TodoDto> {
        val todo = service.create(createTodo.title, createTodo.notes)
        val location = ServletUriComponentsBuilder.fromCurrentRequestUri()
            .path("/{id}")
            .buildAndExpand(todo.id)
            .toUri()
        return ResponseEntity.created(location).body(todo.toDto())
    }

    override fun getTodo(todoId: UUID): ResponseEntity<TodoDto> =
        ResponseEntity.ok(service.get(todoId).toDto())

    override fun updateTodo(todoId: UUID, updateTodo: UpdateTodo): ResponseEntity<TodoDto> =
        ResponseEntity.ok(
            service.update(todoId, updateTodo.title, updateTodo.notes, updateTodo.completed).toDto(),
        )

    override fun deleteTodo(todoId: UUID): ResponseEntity<Unit> {
        service.delete(todoId)
        return ResponseEntity.noContent().build()
    }
}
