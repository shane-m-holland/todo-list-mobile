import SwiftUI

/// Add (when `todo` is nil) or edit a todo. Limits mirror the contract's `maxLength` constraints.
struct TodoEditorSheet: View {
    static let titleMax = 200
    static let notesMax = 2000

    let todo: Todo?
    let onSave: (_ title: String, _ notes: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @FocusState private var titleFocused: Bool

    init(todo: Todo?, onSave: @escaping (_ title: String, _ notes: String) -> Void) {
        self.todo = todo
        self.onSave = onSave
        _title = State(initialValue: todo?.title ?? "")
        _notes = State(initialValue: todo?.notes ?? "")
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFocused)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .accessibilityIdentifier("editor_title")
                }
                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("editor_notes")
                }
            }
            .navigationTitle(todo == nil ? "New todo" : "Edit todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("editor_cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, notes)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("editor_save")
                }
            }
            .onChange(of: title) { _, new in
                if new.count > Self.titleMax { title = String(new.prefix(Self.titleMax)) }
            }
            .onChange(of: notes) { _, new in
                if new.count > Self.notesMax { notes = String(new.prefix(Self.notesMax)) }
            }
            .onAppear { titleFocused = todo == nil }
        }
        .presentationDetents([.medium, .large])
    }
}
