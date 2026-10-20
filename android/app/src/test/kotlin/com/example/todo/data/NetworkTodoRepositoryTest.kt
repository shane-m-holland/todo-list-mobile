package com.example.todo.data

import com.example.todo.network.client.TodoApiFactory
import java.time.Instant
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class NetworkTodoRepositoryTest {

    private val server = MockWebServer()
    private lateinit var repository: NetworkTodoRepository

    @Before
    fun setUp() {
        server.start()
        val api = TodoApiFactory.create(server.url("/api/v1/").toString(), OkHttpClient())
        repository = NetworkTodoRepository(api)
    }

    @After
    fun tearDown() {
        server.close()
    }

    private fun enqueue(code: Int, body: String? = null, contentType: String = "application/json") {
        server.enqueue(
            MockResponse.Builder()
                .code(code)
                .apply { if (body != null) body(body).addHeader("Content-Type", contentType) }
                .build(),
        )
    }

    private fun enqueueProblem(code: Int, example: String) =
        enqueue(code, ContractExamples.json(example), "application/problem+json")

    @Test
    fun `list maps contract example to domain todos`() = runTest {
        enqueue(200, ContractExamples.json("TodoList"))

        val todos = repository.list()

        assertEquals(listOf("Buy groceries", "Renew passport"), todos.map { it.title })
        assertEquals("Milk, eggs, coffee", todos[0].notes)
        assertNull(todos[1].notes)
        assertTrue(todos[1].completed)
        assertEquals(Instant.parse("2026-10-19T09:15:00Z"), todos[1].createdAt)
        server.takeRequest().let {
            assertEquals("GET", it.method)
            assertEquals("/api/v1/todos", it.url.encodedPath)
        }
    }

    @Test
    fun `create posts title and notes`() = runTest {
        enqueue(201, ContractExamples.json("Todo"))

        val todo = repository.create("Buy groceries", "Milk, eggs, coffee")

        assertEquals("3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90", todo.id)
        assertFalse(todo.completed)
        server.takeRequest().let {
            assertEquals("POST", it.method)
            assertEquals(ContractExamples.json("CreateTodo"), it.body?.utf8())
        }
    }

    @Test
    fun `create omits blank notes`() = runTest {
        enqueue(201, ContractExamples.json("Todo"))

        repository.create("Buy groceries", "  ")

        assertEquals("""{"title":"Buy groceries"}""", server.takeRequest().body?.utf8())
    }

    @Test
    fun `update sends only provided fields`() = runTest {
        enqueue(200, ContractExamples.json("CompletedTodo"))

        val todo = repository.update("3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90", completed = true)

        assertTrue(todo.completed)
        server.takeRequest().let {
            assertEquals("PATCH", it.method)
            assertEquals("/api/v1/todos/3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90", it.url.encodedPath)
            assertEquals(ContractExamples.json("CompleteTodo"), it.body?.utf8())
        }
    }

    @Test
    fun `delete succeeds on 204`() = runTest {
        enqueue(204)

        repository.delete("3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90")

        assertEquals("DELETE", server.takeRequest().method)
    }

    @Test
    fun `404 problem maps to NotFound`() = runTest {
        enqueueProblem(404, "NotFoundProblem")

        val error = runCatching { repository.delete("00000000-0000-0000-0000-000000000000") }.exceptionOrNull()

        assertTrue(error is TodoError.NotFound)
        assertEquals("Todo 00000000-0000-0000-0000-000000000000 does not exist.", error?.message)
    }

    @Test
    fun `400 problem maps to Validation with field errors`() = runTest {
        enqueueProblem(400, "ValidationProblem")

        val error = runCatching { repository.create(" ") }.exceptionOrNull()

        assertTrue(error is TodoError.Validation)
        assertEquals(mapOf("title" to "must not be blank"), (error as TodoError.Validation).fieldErrors)
    }

    @Test
    fun `500 problem maps to Server`() = runTest {
        enqueueProblem(500, "InternalProblem")

        val error = runCatching { repository.list() }.exceptionOrNull()

        assertTrue(error is TodoError.Server)
        assertEquals(500, (error as TodoError.Server).status)
    }

    @Test
    fun `connection failure maps to Network`() = runTest {
        server.close()

        val error = runCatching { repository.list() }.exceptionOrNull()

        assertTrue("was $error", error is TodoError.Network)
    }
}
