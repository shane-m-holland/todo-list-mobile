package com.example.todo.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.todo.data.Todo
import kotlinx.coroutines.launch

/** One todo: tap to edit, checkbox to toggle, swipe right-to-left to delete. */
@Composable
fun TodoRow(
    todo: Todo,
    onClick: () -> Unit,
    onCompletedChange: (Boolean) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dismissState = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()

    SwipeToDismissBox(
        state = dismissState,
        modifier = modifier.testTag("todo_row_${todo.id}"),
        enableDismissFromStartToEnd = false,
        onDismiss = {
            onDelete()
            // Settle again in case the delete fails and the row comes back.
            scope.launch { dismissState.snapTo(SwipeToDismissBoxValue.Settled) }
        },
        backgroundContent = {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.errorContainer)
                    .padding(horizontal = 24.dp),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        },
    ) {
        ListItem(
            modifier = Modifier.clickable(onClickLabel = "Edit", onClick = onClick),
            leadingContent = {
                Checkbox(
                    checked = todo.completed,
                    onCheckedChange = onCompletedChange,
                    modifier = Modifier
                        .testTag("todo_checkbox_${todo.id}")
                        // Without a label a screen reader (and the e2e journey) can't tell the checkboxes apart.
                        .semantics { contentDescription = "Complete ${todo.title}" },
                )
            },
            headlineContent = {
                Text(
                    todo.title,
                    textDecoration = if (todo.completed) TextDecoration.LineThrough else null,
                    color = if (todo.completed) {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
            },
            supportingContent = todo.notes?.let { notes ->
                { Text(notes, maxLines = 2, overflow = TextOverflow.Ellipsis) }
            },
        )
    }
}
