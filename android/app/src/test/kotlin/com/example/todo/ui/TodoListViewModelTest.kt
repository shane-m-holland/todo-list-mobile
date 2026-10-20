@file:OptIn(ExperimentalCoroutinesApi::class)

package com.example.todo.ui

import app.cash.turbine.test
import com.example.todo.data.Todo
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class TodoListViewModelTest {

    @get:Rule
    val mainDispatcher = MainDispatcherRule()

    private val a = todo("a", "Alpha")
    private val b = todo("b", "Beta", notes = "details")

    private fun TodoListViewModel.todos(): List<Todo> = (uiState.value.list as ListState.Loaded).todos

    @Test
    fun `initial load shows loading then the list`() = runTest {
        val viewModel = TodoListViewModel(FakeTodoRepository(listOf(a, b)))

        viewModel.uiState.test {
            assertEquals(ListState.Loading, awaitItem().list)
            assertEquals(ListState.Loaded(listOf(a, b)), awaitItem().list)
        }
    }

    @Test
    fun `initial load failure shows error and retry recovers`() = runTest {
        val repository = FakeTodoRepository(listOf(a)).apply { failNext = networkError() }
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        val failed = viewModel.uiState.value.list as ListState.Failed
        assertTrue(failed.message.contains("Can't reach the server"))

        viewModel.load()
        advanceUntilIdle()
        assertEquals(listOf(a), viewModel.todos())
    }

    @Test
    fun `save without id creates and appends`() = runTest {
        val viewModel = TodoListViewModel(FakeTodoRepository(listOf(a)))
        advanceUntilIdle()

        viewModel.save(id = null, title = "  New one  ", notes = "  ")
        advanceUntilIdle()

        val created = viewModel.todos().last()
        assertEquals("New one", created.title)
        assertNull(created.notes)
    }

    @Test
    fun `create failure keeps list and offers retry`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        repository.failNext = networkError()
        viewModel.save(null, "New one", "")
        advanceUntilIdle()

        assertEquals(listOf(a), viewModel.todos())
        val message = viewModel.uiState.value.message!!
        assertEquals(Operation.Create("New one", null), message.retry)

        viewModel.retry(message.retry!!)
        advanceUntilIdle()
        assertEquals(listOf("Alpha", "New one"), viewModel.todos().map { it.title })
    }

    @Test
    fun `blank title is ignored`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        viewModel.save(null, "   ", "notes")
        advanceUntilIdle()

        assertEquals(listOf("list"), repository.calls)
    }

    @Test
    fun `edit sends only changed fields and skips no-op saves`() = runTest {
        val repository = FakeTodoRepository(listOf(a, b))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        viewModel.save("b", "Beta", "details") // unchanged
        viewModel.save("b", "Beta", "") // clear notes only
        advanceUntilIdle()

        assertEquals(listOf("list", "update:b:null::null"), repository.calls)
        assertNull(viewModel.todos()[1].notes)
    }

    @Test
    fun `toggle is optimistic`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()
        repository.gate = CompletableDeferred()

        viewModel.setCompleted("a", true)

        assertTrue("updated before the server answers", viewModel.todos().single().completed)
        repository.gate!!.complete(Unit)
        advanceUntilIdle()
        assertTrue(viewModel.todos().single().completed)
    }

    @Test
    fun `toggle failure reverts and offers retry`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1) // current state
            repository.failNext = networkError()
            viewModel.setCompleted("a", true)

            assertTrue(awaitItem().let { (it.list as ListState.Loaded).todos.single().completed })
            assertEquals(false, (awaitItem().list as ListState.Loaded).todos.single().completed)
            assertEquals(Operation.SetCompleted("a", true), awaitItem().message?.retry)
        }
    }

    @Test
    fun `delete is optimistic and failure restores the item in place`() = runTest {
        val c = todo("c", "Gamma")
        val repository = FakeTodoRepository(listOf(a, b, c))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()
        repository.gate = CompletableDeferred()
        repository.failNext = networkError()

        viewModel.delete(b)
        assertEquals(listOf(a, c), viewModel.todos())

        repository.gate!!.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf(a, b, c), viewModel.todos())
        assertEquals(Operation.Delete(b), viewModel.uiState.value.message?.retry)
    }

    @Test
    fun `delete of an already-deleted todo is not an error`() = runTest {
        val repository = FakeTodoRepository(listOf(a, b))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()
        repository.todos.remove(b) // deleted elsewhere

        viewModel.delete(b)
        advanceUntilIdle()

        assertEquals(listOf(a), viewModel.todos())
        assertNull(viewModel.uiState.value.message)
    }

    @Test
    fun `refresh failure keeps the list and shows a message`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        repository.failNext = networkError()
        viewModel.refresh()
        assertTrue(viewModel.uiState.value.isRefreshing)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals(false, state.isRefreshing)
        assertEquals(listOf(a), viewModel.todos())
        assertEquals(Operation.Refresh, state.message?.retry)
    }

    @Test
    fun `refresh picks up server changes`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()

        repository.todos += b
        viewModel.refresh()
        advanceUntilIdle()

        assertEquals(listOf(a, b), viewModel.todos())
    }

    @Test
    fun `messageShown clears only the matching message`() = runTest {
        val repository = FakeTodoRepository(listOf(a))
        val viewModel = TodoListViewModel(repository)
        advanceUntilIdle()
        repository.failNext = networkError()
        viewModel.refresh()
        advanceUntilIdle()
        val id = viewModel.uiState.value.message!!.id

        viewModel.messageShown(id + 1)
        assertEquals(id, viewModel.uiState.value.message?.id)
        viewModel.messageShown(id)
        assertNull(viewModel.uiState.value.message)
    }
}
