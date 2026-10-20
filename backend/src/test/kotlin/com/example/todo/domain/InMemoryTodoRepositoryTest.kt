package com.example.todo.domain

class InMemoryTodoRepositoryTest : AbstractTodoRepositoryTest() {
    override val repository = InMemoryTodoRepository()
}
