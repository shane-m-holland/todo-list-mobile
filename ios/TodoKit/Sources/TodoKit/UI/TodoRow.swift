import SwiftUI

/// One todo: the circle toggles it, tapping the text edits it, swipe left deletes (see the list).
struct TodoRow: View {
    let todo: Todo
    let onTap: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.completed ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.completed ? "Mark as not done" : "Mark as done")
            .accessibilityIdentifier("todo_checkbox_\(todo.id)")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.completed)
                    .foregroundStyle(todo.completed ? .secondary : .primary)
                if let notes = todo.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit")
            .accessibilityIdentifier("todo_row_\(todo.id)")
        }
        .padding(.vertical, 4)
    }
}
