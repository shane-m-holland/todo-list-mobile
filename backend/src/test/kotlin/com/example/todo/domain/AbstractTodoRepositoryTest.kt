package com.example.todo.domain

import java.time.Instant
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Behavior every [TodoRepository] must have. Subclasses supply the implementation. */
abstract class AbstractTodoRepositoryTest {

    abstract val repository: TodoRepository

    private val t0 = Instant.parse("2026-10-20T14:00:00.123Z")

    protected fun todo(title: String = "A", notes: String? = null, at: Instant = t0) = Todo(
        id = UUID.randomUUID(),
        title = title,
        notes = notes,
        completed = false,
        createdAt = at,
        updatedAt = at,
    )

    @Test
    fun `insert then findById round trips every field`() {
        val todo = todo(title = "Zażółć gęślą \"jaźń\" & 日本語", notes = "line 1\nline 2")
        repository.insert(todo)

        assertEquals(todo, repository.findById(todo.id))
    }

    @Test
    fun `null notes stay null`() {
        val todo = repository.insert(todo(notes = null))

        assertNull(repository.findById(todo.id)?.notes)
    }

    @Test
    fun `unknown ids are absent`() {
        assertNull(repository.findById(UUID.randomUUID()))
        assertNull(repository.update(UUID.randomUUID()) { it })
        assertFalse(repository.delete(UUID.randomUUID()))
    }

    @Test
    fun `findAll keeps creation order, even for identical timestamps`() {
        val titles = (1..10).map { "todo $it" }
        titles.forEach { repository.insert(todo(title = it)) } // all created at the same instant

        assertEquals(titles, repository.findAll().map { it.title })
    }

    @Test
    fun `update applies the transform and persists it`() {
        val todo = repository.insert(todo(title = "before"))

        val updated = repository.update(todo.id) { it.copy(title = "after", completed = true) }

        assertEquals("after", updated?.title)
        assertEquals(updated, repository.findById(todo.id))
        assertEquals(listOf(todo.id), repository.findAll().map { it.id }) // no duplicate row
    }

    @Test
    fun `delete removes the todo exactly once`() {
        val todo = repository.insert(todo())

        assertTrue(repository.delete(todo.id))
        assertFalse(repository.delete(todo.id))
        assertTrue(repository.findAll().isEmpty())
    }

    @Test
    fun `concurrent updates do not lose writes`() {
        val todo = repository.insert(todo(notes = null))
        val threads = 20
        val pool = Executors.newFixedThreadPool(threads)
        val start = CountDownLatch(1)

        val futures = (1..threads).map {
            pool.submit {
                start.await()
                repository.update(todo.id) { current -> current.copy(notes = current.notes.orEmpty() + "x") }
            }
        }
        start.countDown()
        futures.forEach { it.get(30, TimeUnit.SECONDS) }
        pool.shutdown()

        assertEquals("x".repeat(threads), repository.findById(todo.id)?.notes)
    }
}
