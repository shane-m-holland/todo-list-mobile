package com.example.todo.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun TodoListScreen(viewModel: TodoListViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    Scaffold { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            when (val s = state) {
                TodoListUiState.Loading -> CircularProgressIndicator()
                is TodoListUiState.Error -> Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(s.message)
                    Button(onClick = viewModel::refresh) { Text("Retry") }
                }
                is TodoListUiState.Content -> LazyColumn(Modifier.fillMaxSize()) {
                    items(s.todos, key = { it.id }) { todo ->
                        ListItem(
                            headlineContent = { Text(todo.title) },
                            supportingContent = todo.notes?.let { { Text(it) } },
                            trailingContent = { Text(if (todo.completed) "✓" else "") },
                        )
                    }
                }
            }
        }
    }
}
