package com.example.todo.web

import com.example.todo.domain.InMemoryTodoRepository
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest(properties = ["todo.seed.enabled=false"])
@AutoConfigureMockMvc
class TodosApiContractMemoryTest : AbstractTodosApiContractTest() {

    @Autowired lateinit var repository: InMemoryTodoRepository

    override fun resetStore() = repository.clear()
}
