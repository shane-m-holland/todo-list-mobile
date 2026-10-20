package com.example.todo.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.todo.data.Todo
import com.example.todo.data.TodoError
import com.example.todo.data.TodoRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

sealed interface ListState {
    data object Loading : ListState
    data class Loaded(val todos: List<Todo>) : ListState
    data class Failed(val message: String) : ListState
}

/** A mutation that failed and can be retried from the snackbar. */
sealed interface Operation {
    data object Refresh : Operation
    data class Create(val title: String, val notes: String?) : Operation
    data class Edit(val id: String, val title: String?, val notes: String?) : Operation
    data class SetCompleted(val id: String, val completed: Boolean) : Operation
    data class Delete(val todo: Todo) : Operation
}

data class UserMessage(val id: Long, val text: String, val retry: Operation?)

data class TodoListUiState(
    val list: ListState = ListState.Loading,
    val isRefreshing: Boolean = false,
    val message: UserMessage? = null,
)

@HiltViewModel
class TodoListViewModel @Inject constructor(
    private val repository: TodoRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(TodoListUiState())
    val uiState: StateFlow<TodoListUiState> = _uiState.asStateFlow()

    private var nextMessageId = 0L

    init {
        load()
    }

    /** Full-screen load, used on start and from the error screen's Retry. */
    fun load() {
        _uiState.update { it.copy(list = ListState.Loading) }
        viewModelScope.launch {
            val list = try {
                ListState.Loaded(repository.list())
            } catch (e: TodoError) {
                ListState.Failed(e.userText())
            }
            _uiState.update { it.copy(list = list) }
        }
    }

    /** Pull-to-refresh: keeps the current list visible and reports failures in the snackbar. */
    fun refresh() {
        _uiState.update { it.copy(isRefreshing = true) }
        viewModelScope.launch {
            try {
                val todos = repository.list()
                _uiState.update { it.copy(list = ListState.Loaded(todos), isRefreshing = false) }
            } catch (e: TodoError) {
                _uiState.update { it.copy(isRefreshing = false) }
                showError(e, "Couldn't refresh", Operation.Refresh)
            }
        }
    }

    /** Creates a new todo when [id] is null, otherwise edits it. Unchanged fields are not sent. */
    fun save(id: String?, title: String, notes: String) {
        val cleanTitle = title.trim()
        val cleanNotes = notes.trim()
        if (cleanTitle.isEmpty()) return
        if (id == null) {
            create(cleanTitle, cleanNotes.ifEmpty { null })
            return
        }
        val current = todos().firstOrNull { it.id == id } ?: return
        val newTitle = cleanTitle.takeIf { it != current.title }
        val newNotes = cleanNotes.takeIf { it != current.notes.orEmpty() }
        if (newTitle != null || newNotes != null) edit(id, newTitle, newNotes)
    }

    fun setCompleted(id: String, completed: Boolean) {
        val before = todos().firstOrNull { it.id == id } ?: return
        replace(before.copy(completed = completed)) // optimistic
        viewModelScope.launch {
            try {
                replace(repository.update(id, completed = completed))
            } catch (e: TodoError) {
                replace(before)
                showError(e, "Couldn't update \"${before.title}\"", Operation.SetCompleted(id, completed))
            }
        }
    }

    fun delete(todo: Todo) {
        val index = todos().indexOfFirst { it.id == todo.id }
        if (index < 0) return
        updateTodos { it - todo } // optimistic
        viewModelScope.launch {
            try {
                repository.delete(todo.id)
            } catch (e: TodoError.NotFound) {
                // Already gone on the server: the optimistic removal was right.
            } catch (e: TodoError) {
                updateTodos { it.toMutableList().apply { add(index.coerceAtMost(size), todo) } }
                showError(e, "Couldn't delete \"${todo.title}\"", Operation.Delete(todo))
            }
        }
    }

    fun retry(operation: Operation) {
        when (operation) {
            Operation.Refresh -> refresh()
            is Operation.Create -> create(operation.title, operation.notes)
            is Operation.Edit -> edit(operation.id, operation.title, operation.notes)
            is Operation.SetCompleted -> setCompleted(operation.id, operation.completed)
            is Operation.Delete -> delete(operation.todo)
        }
    }

    fun messageShown(id: Long) {
        _uiState.update { state -> if (state.message?.id == id) state.copy(message = null) else state }
    }

    private fun create(title: String, notes: String?) {
        viewModelScope.launch {
            try {
                val created = repository.create(title, notes)
                updateTodos { it + created }
            } catch (e: TodoError) {
                showError(e, "Couldn't add \"$title\"", Operation.Create(title, notes))
            }
        }
    }

    private fun edit(id: String, title: String?, notes: String?) {
        viewModelScope.launch {
            try {
                replace(repository.update(id, title = title, notes = notes))
            } catch (e: TodoError.NotFound) {
                updateTodos { todos -> todos.filterNot { it.id == id } }
                showError(e, "That todo no longer exists", retry = null)
            } catch (e: TodoError) {
                showError(e, "Couldn't save changes", Operation.Edit(id, title, notes))
            }
        }
    }

    private fun todos(): List<Todo> = (_uiState.value.list as? ListState.Loaded)?.todos.orEmpty()

    private fun updateTodos(transform: (List<Todo>) -> List<Todo>) {
        _uiState.update { state ->
            val list = state.list as? ListState.Loaded ?: return@update state
            state.copy(list = ListState.Loaded(transform(list.todos)))
        }
    }

    private fun replace(todo: Todo) = updateTodos { todos -> todos.map { if (it.id == todo.id) todo else it } }

    private fun showError(error: TodoError, prefix: String, retry: Operation?) {
        val message = UserMessage(nextMessageId++, "$prefix: ${error.userText()}", retry)
        _uiState.update { it.copy(message = message) }
    }
}

private fun TodoError.userText(): String = when (this) {
    is TodoError.Network -> "Can't reach the server. Check your connection."
    else -> message ?: "Something went wrong."
}
