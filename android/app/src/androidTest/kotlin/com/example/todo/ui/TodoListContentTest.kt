package com.example.todo.ui

import androidx.compose.material3.SnackbarHostState
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.example.todo.data.Todo
import com.example.todo.ui.theme.TodoTheme
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TodoListContentTest {

    @get:Rule
    val compose = createComposeRule()

    private val groceries = Todo("a", "Buy groceries", "Milk", false, Instant.EPOCH, Instant.EPOCH)
    private val saved = mutableListOf<Triple<String?, String, String>>()
    private val toggled = mutableListOf<Pair<String, Boolean>>()

    private fun setContent(todos: List<Todo> = listOf(groceries)) {
        compose.setContent {
            TodoTheme {
                TodoListContent(
                    state = TodoListUiState(list = ListState.Loaded(todos)),
                    snackbarHostState = SnackbarHostState(),
                    onRetryLoad = {},
                    onRefresh = {},
                    onSave = { id, title, notes -> saved += Triple(id, title, notes) },
                    onCompletedChange = { id, done -> toggled += id to done },
                    onDelete = {},
                )
            }
        }
    }

    @Test
    fun addFlow_savesNewTodoAndClosesEditor() {
        setContent()

        compose.onNodeWithContentDescription("Add todo").performClick()
        compose.onNodeWithText("New todo").assertExists()
        compose.onNodeWithText("Save").assertIsNotEnabled()

        compose.onNodeWithTag("editor_title").performTextInput("Walk the dog")
        compose.onNodeWithTag("editor_notes").performTextInput("Before 6pm")
        compose.onNodeWithText("Save").performClick()

        compose.waitForIdle()
        assertEquals(listOf(Triple(null, "Walk the dog", "Before 6pm")), saved)
        compose.onNodeWithTag("editor_title").assertDoesNotExist()
    }

    @Test
    fun tappingRow_opensPrefilledEditor() {
        setContent()

        compose.onNodeWithText("Buy groceries").performClick()

        compose.onNodeWithText("Edit todo").assertExists()
        compose.onNodeWithTag("editor_title").assertTextContains("Buy groceries")
        compose.onNodeWithTag("editor_title").performTextReplacement("Buy more groceries")
        compose.onNodeWithText("Save").performClick()

        compose.waitForIdle()
        assertEquals(listOf(Triple("a", "Buy more groceries", "Milk")), saved)
    }

    @Test
    fun checkbox_reportsToggle() {
        setContent()

        compose.onNodeWithTag("todo_checkbox_a").performClick()

        assertEquals(listOf("a" to true), toggled)
    }

    @Test
    fun emptyList_showsHint() {
        setContent(todos = emptyList())

        compose.onNodeWithText("Nothing to do yet.", substring = true).assertExists()
        compose.onNodeWithText("0 open").assertExists()
    }
}
