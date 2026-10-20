package com.example.todo.network.client

import com.example.todo.network.models.ProblemDetails
import com.example.todo.network.models.Todo
import com.example.todo.network.models.UpdateTodo
import java.time.OffsetDateTime
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TodoJsonTest {

    @Test
    fun `partial update omits absent fields`() {
        assertEquals("""{"completed":true}""", TodoJson.encodeToString(UpdateTodo(completed = true)))
    }

    @Test
    fun `decodes todo with contextual uuid and timestamps`() {
        val todo = TodoJson.decodeFromString<Todo>(
            """
            {"id":"3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90","title":"Buy groceries","completed":false,
             "createdAt":"2026-10-20T14:00:00Z","updatedAt":"2026-10-20T14:00:00Z","futureField":1}
            """,
        )
        assertEquals(UUID.fromString("3f9c2a4e-8b1d-4c6e-9a7f-2d5e8b1c4a90"), todo.id)
        assertEquals(OffsetDateTime.parse("2026-10-20T14:00:00Z"), todo.createdAt)
        assertNull(todo.notes)
    }

    @Test
    fun `decodes problem details`() {
        val problem = TodoJson.decodeFromString<ProblemDetails>("""{"title":"Not Found","status":404}""")
        assertEquals(404, problem.status)
        assertEquals("about:blank", problem.type)
    }
}
