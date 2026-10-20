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
import kotlinx.coroutines.launch

sealed interface TodoListUiState {
    data object Loading : TodoListUiState
    data class Content(val todos: List<Todo>) : TodoListUiState
    data class Error(val message: String) : TodoListUiState
}

/** CP3 placeholder: proves the network wiring end to end. CP4 adds mutations and real UI. */
@HiltViewModel
class TodoListViewModel @Inject constructor(
    private val repository: TodoRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<TodoListUiState>(TodoListUiState.Loading)
    val uiState: StateFlow<TodoListUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.value = TodoListUiState.Loading
        viewModelScope.launch {
            _uiState.value = try {
                TodoListUiState.Content(repository.list())
            } catch (e: TodoError) {
                TodoListUiState.Error(e.message ?: "Something went wrong")
            }
        }
    }
}
