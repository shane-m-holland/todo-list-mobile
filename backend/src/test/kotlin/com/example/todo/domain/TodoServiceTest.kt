package com.example.todo.domain

import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TodoServiceTest {

    private val t0 = Instant.parse("2026-10-20T14:00:00.123456789Z")
    private val clock = MutableClock(t0)
    private val repository = InMemoryTodoRepository()
    private val service = TodoService(repository, clock)

    @Test
    fun `create starts open and stamps millisecond timestamps`() {
        val todo = service.create("Buy groceries", "Milk")

        assertEquals("Buy groceries", todo.title)
        assertEquals("Milk", todo.notes)
        assertFalse(todo.completed)
        assertEquals(Instant.parse("2026-10-20T14:00:00.123Z"), todo.createdAt)
        assertEquals(todo.createdAt, todo.updatedAt)
    }

    @Test
    fun `create treats empty notes as absent`() {
        assertNull(service.create("A", "").notes)
    }

    @Test
    fun `list keeps creation order`() {
        val titles = listOf("c", "a", "b").map { service.create(it, null).title }

        assertEquals(titles, service.list().map { it.title })
    }

    @Test
    fun `update changes only provided fields and bumps updatedAt`() {
        val created = service.create("A", "notes")
        clock.advanceSeconds(60)

        val updated = service.update(created.id, title = null, notes = null, completed = true)

        assertEquals("A", updated.title)
        assertEquals("notes", updated.notes)
        assertTrue(updated.completed)
        assertEquals(created.createdAt, updated.createdAt)
        assertEquals(created.updatedAt.plusSeconds(60), updated.updatedAt)
    }

    @Test
    fun `update with empty notes clears them`() {
        val created = service.create("A", "notes")

        assertNull(service.update(created.id, null, "", null).notes)
    }

    @Test
    fun `update with nothing to change is rejected`() {
        val created = service.create("A", null)

        assertFailsWith<InvalidTodoRequestException> { service.update(created.id, null, null, null) }
    }

    @Test
    fun `unknown ids raise not found`() {
        val id = UUID.randomUUID()

        assertFailsWith<TodoNotFoundException> { service.get(id) }
        assertFailsWith<TodoNotFoundException> { service.update(id, "x", null, null) }
        assertFailsWith<TodoNotFoundException> { service.delete(id) }
    }

    @Test
    fun `delete removes the todo`() {
        val created = service.create("A", null)

        service.delete(created.id)

        assertTrue(service.list().isEmpty())
        assertFailsWith<TodoNotFoundException> { service.delete(created.id) }
    }
}

/** A [Clock] tests can move forward. */
class MutableClock(private var now: Instant) : Clock() {
    override fun getZone() = ZoneOffset.UTC
    override fun withZone(zone: java.time.ZoneId?): Clock = this
    override fun instant(): Instant = now
    fun advanceSeconds(seconds: Long) {
        now = now.plusSeconds(seconds)
    }
}
