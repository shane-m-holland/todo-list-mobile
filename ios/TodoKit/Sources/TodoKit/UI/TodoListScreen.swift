import SwiftUI

/// What the editor sheet is open for.
private enum EditorTarget: Identifiable {
    case new
    case edit(Todo)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let todo): todo.id
        }
    }
}

struct TodoListScreen: View {
    let viewModel: TodoListViewModel
    @State private var editor: EditorTarget?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("ToDo")
                .toolbar {
                    if case .loaded = viewModel.list {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add todo", systemImage: "plus") { editor = .new }
                                .accessibilityIdentifier("add_todo")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let message = viewModel.message {
                        ErrorBanner(
                            message: message,
                            onRetry: { operation in
                                viewModel.messageShown(id: message.id)
                                Task { await viewModel.retry(operation) }
                            },
                            onDismiss: { viewModel.messageShown(id: message.id) }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.default, value: viewModel.message)
        }
        .task { await viewModel.loadIfNeeded() }
        .sheet(item: $editor) { target in
            TodoEditorSheet(todo: target.todo) { title, notes in
                Task { await viewModel.save(id: target.todo?.id, title: title, notes: notes) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.list {
        case .loading:
            ProgressView().accessibilityIdentifier("loading")
        case .failed(let text):
            LoadError(text: text) { Task { await viewModel.load() } }
        case .loaded(let todos):
            List {
                Section {
                    ForEach(todos) { todo in
                        TodoRow(
                            todo: todo,
                            onTap: { editor = .edit(todo) },
                            onToggle: { Task { await viewModel.setCompleted(id: todo.id, completed: !todo.completed) } }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.delete(todo) }
                            }
                        }
                    }
                } header: {
                    Text("\(todos.filter { !$0.completed }.count) open")
                        .textCase(nil)
                        .accessibilityIdentifier("open_count")
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("todo_list")
            .animation(.default, value: todos)
            .refreshable { await viewModel.refresh() }
            .overlay {
                if todos.isEmpty {
                    ContentUnavailableView(
                        "Nothing to do yet",
                        systemImage: "checklist",
                        description: Text("Tap + to add a todo.")
                    )
                    .accessibilityIdentifier("empty_state")
                }
            }
        }
    }
}

private extension EditorTarget {
    var todo: Todo? {
        if case .edit(let todo) = self { todo } else { nil }
    }
}

private struct LoadError: View {
    let text: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("load_error")
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retry_load")
        }
        .padding(24)
    }
}

private struct ErrorBanner: View {
    let message: UserMessage
    let onRetry: (Operation) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("error_banner")
            if let operation = message.retry {
                Button("Retry") { onRetry(operation) }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("banner_retry")
            }
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("banner_dismiss")
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.4)))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .task(id: message.id) {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { onDismiss() }
        }
    }
}
