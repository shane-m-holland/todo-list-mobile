package com.example.todo.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.todo.data.Todo

@Composable
fun TodoListScreen(viewModel: TodoListViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    state.message?.let { message ->
        LaunchedEffect(message.id) {
            val result = snackbarHostState.showSnackbar(
                message = message.text,
                actionLabel = if (message.retry != null) "Retry" else null,
                duration = SnackbarDuration.Long,
            )
            if (result == SnackbarResult.ActionPerformed) message.retry?.let(viewModel::retry)
            viewModel.messageShown(message.id)
        }
    }

    TodoListContent(
        state = state,
        snackbarHostState = snackbarHostState,
        onRetryLoad = viewModel::load,
        onRefresh = viewModel::refresh,
        onSave = viewModel::save,
        onCompletedChange = viewModel::setCompleted,
        onDelete = viewModel::delete,
    )
}

/** Stateless screen body. Editor visibility is UI state and survives rotation. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoListContent(
    state: TodoListUiState,
    snackbarHostState: SnackbarHostState,
    onRetryLoad: () -> Unit,
    onRefresh: () -> Unit,
    onSave: (id: String?, title: String, notes: String) -> Unit,
    onCompletedChange: (id: String, completed: Boolean) -> Unit,
    onDelete: (Todo) -> Unit,
) {
    var editorOpen by rememberSaveable { mutableStateOf(false) }
    var editingId by rememberSaveable { mutableStateOf<String?>(null) }
    val loaded = state.list as? ListState.Loaded

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("ToDo")
                        if (loaded != null) {
                            val open = loaded.todos.count { !it.completed }
                            Text("$open open", style = MaterialTheme.typography.labelMedium)
                        }
                    }
                },
            )
        },
        floatingActionButton = {
            if (loaded != null) {
                FloatingActionButton(onClick = { editingId = null; editorOpen = true }) {
                    Icon(Icons.Filled.Add, contentDescription = "Add todo")
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (val list = state.list) {
                ListState.Loading -> CircularProgressIndicator(Modifier.align(Alignment.Center))
                is ListState.Failed -> LoadError(list.message, onRetryLoad, Modifier.align(Alignment.Center))
                is ListState.Loaded -> PullToRefreshBox(
                    isRefreshing = state.isRefreshing,
                    onRefresh = onRefresh,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    if (list.todos.isEmpty()) {
                        EmptyList(Modifier.align(Alignment.Center))
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize().testTag("todo_list"),
                            contentPadding = PaddingValues(bottom = 88.dp), // clear the FAB
                        ) {
                            items(list.todos, key = { it.id }) { todo ->
                                TodoRow(
                                    todo = todo,
                                    onClick = { editingId = todo.id; editorOpen = true },
                                    onCompletedChange = { onCompletedChange(todo.id, it) },
                                    onDelete = { onDelete(todo) },
                                    modifier = Modifier.animateItem(),
                                )
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    if (editorOpen) {
        val editing = editingId?.let { id -> loaded?.todos?.firstOrNull { it.id == id } }
        TodoEditorSheet(
            todo = editing,
            onSave = { title, notes ->
                onSave(editing?.id, title, notes)
                editorOpen = false
            },
            onDismiss = { editorOpen = false },
        )
    }
}

@Composable
private fun LoadError(message: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(message, textAlign = TextAlign.Center)
        Button(onClick = onRetry) { Text("Retry") }
    }
}

@Composable
private fun EmptyList(modifier: Modifier = Modifier) {
    Text(
        "Nothing to do yet.\nTap + to add a todo.",
        modifier = modifier.padding(24.dp),
        textAlign = TextAlign.Center,
        style = MaterialTheme.typography.bodyLarge,
    )
}
