import Foundation
import Testing
@testable import TodoKit

@MainActor
@Suite struct TodoListViewModelTests {
    let a = makeTodo(id: "a", title: "Alpha")
    let b = makeTodo(id: "b", title: "Beta", notes: "details")
    let c = makeTodo(id: "c", title: "Gamma")

    private func loadedViewModel(
        _ todos: [Todo]? = nil
    ) async -> (TodoListViewModel, FakeTodoRepository) {
        let repository = FakeTodoRepository(todos ?? [a, b])
        let viewModel = TodoListViewModel(repository: repository)
        await viewModel.load()
        return (viewModel, repository)
    }

    // MARK: - Loading

    @Test func initialLoadShowsLoadingThenTheList() async {
        let viewModel = TodoListViewModel(repository: FakeTodoRepository([a, b]))
        #expect(viewModel.list == .loading)

        await viewModel.loadIfNeeded()

        #expect(viewModel.list == .loaded([a, b]))
    }

    @Test func loadIfNeededOnlyLoadsOnce() async {
        let repository = FakeTodoRepository([a])
        let viewModel = TodoListViewModel(repository: repository)

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        #expect(await repository.calls == ["list"])
    }

    @Test func initialLoadFailureShowsErrorAndRetryRecovers() async {
        let repository = FakeTodoRepository([a])
        await repository.setFailNext(.network)
        let viewModel = TodoListViewModel(repository: repository)
        await viewModel.load()

        guard case .failed(let text) = viewModel.list else {
            Issue.record("expected .failed")
            return
        }
        #expect(text.contains("Can't reach the server"))

        await viewModel.load()
        #expect(viewModel.list == .loaded([a]))
    }

    // MARK: - Create and edit

    @Test func saveWithoutIdCreatesAndAppends() async {
        let (viewModel, _) = await loadedViewModel([a])

        await viewModel.save(id: nil, title: "  New one  ", notes: "  ")

        let created = viewModel.todos.last
        #expect(created?.title == "New one")
        #expect(created?.notes == nil)
        #expect(viewModel.todos.count == 2)
        #expect(viewModel.message == nil)
    }

    @Test func createWaitsForTheServer() async {
        let (viewModel, repository) = await loadedViewModel([a])
        let gate = Gate()
        await repository.setGate(gate)

        let save = Task { await viewModel.save(id: nil, title: "New", notes: "") }
        await repository.waitForCalls(2)
        #expect(viewModel.todos == [a]) // nothing shown until the server answers

        await gate.open()
        await save.value
        #expect(viewModel.todos.count == 2)
    }

    @Test func createFailureKeepsListAndOffersRetry() async throws {
        let (viewModel, repository) = await loadedViewModel([a])
        await repository.setFailNext(.server(status: 500, detail: "Boom"))

        await viewModel.save(id: nil, title: "New", notes: "n")

        #expect(viewModel.todos == [a])
        let message = viewModel.message
        #expect(message?.text == "Couldn't add \"New\": Boom")
        #expect(message?.retry == .create(title: "New", notes: "n"))

        await viewModel.retry(try #require(message?.retry))
        #expect(viewModel.todos.map(\.title) == ["Alpha", "New"])
    }

    @Test func blankTitleIsIgnored() async {
        let (viewModel, repository) = await loadedViewModel([a])

        await viewModel.save(id: nil, title: "   ", notes: "x")
        await viewModel.save(id: "a", title: "  ", notes: "x")

        #expect(await repository.calls == ["list"])
    }

    @Test func editSendsOnlyChangedFieldsAndSkipsNoOpSaves() async {
        let (viewModel, repository) = await loadedViewModel([a, b])

        await viewModel.save(id: "b", title: "Beta", notes: "details") // unchanged
        #expect(await repository.calls == ["list"])

        await viewModel.save(id: "b", title: "Beta 2", notes: "details") // title only
        await viewModel.save(id: "b", title: "Beta 2", notes: "") // clears notes
        #expect(await repository.calls == ["list", "update:b:Beta 2:-:-", "update:b:-::-"])
        #expect(viewModel.todos[1].title == "Beta 2")
        #expect(viewModel.todos[1].notes == nil)
    }

    @Test func editingATodoThatNoLongerExistsRemovesItWithoutRetry() async {
        let (viewModel, repository) = await loadedViewModel([a, b])
        await repository.setTodos([a]) // deleted elsewhere

        await viewModel.save(id: "b", title: "Renamed", notes: "details")

        #expect(viewModel.todos == [a])
        #expect(viewModel.message?.text.hasPrefix("That todo no longer exists") == true)
        #expect(viewModel.message?.retry == nil)
    }

    // MARK: - Toggle

    @Test func toggleIsOptimistic() async {
        let (viewModel, repository) = await loadedViewModel([a])
        let gate = Gate()
        await repository.setGate(gate)

        let toggle = Task { await viewModel.setCompleted(id: "a", completed: true) }
        await repository.waitForCalls(2)
        #expect(viewModel.todos.first?.completed == true) // shown before the server replied

        await gate.open()
        await toggle.value
        #expect(viewModel.todos.first?.completed == true)
        #expect(viewModel.message == nil)
    }

    @Test func toggleFailureRevertsAndOffersRetry() async throws {
        let (viewModel, repository) = await loadedViewModel([a])
        await repository.setFailNext(.network)

        await viewModel.setCompleted(id: "a", completed: true)

        #expect(viewModel.todos.first?.completed == false)
        let message = viewModel.message
        #expect(message?.text.hasPrefix("Couldn't update \"Alpha\"") == true)
        #expect(message?.retry == .setCompleted(id: "a", completed: true))

        await viewModel.retry(try #require(message?.retry))
        #expect(viewModel.todos.first?.completed == true)
    }

    // MARK: - Delete

    @Test func deleteIsOptimisticAndFailureRestoresTheItemInPlace() async throws {
        let (viewModel, repository) = await loadedViewModel([a, b, c])
        let gate = Gate()
        await repository.setGate(gate)
        await repository.setFailNext(.network)

        let delete = Task { await viewModel.delete(b) }
        await repository.waitForCalls(2)
        #expect(viewModel.todos == [a, c]) // gone before the server replied

        await gate.open()
        await delete.value
        #expect(viewModel.todos == [a, b, c]) // back at its original index
        #expect(viewModel.message?.retry == .delete(b))

        await repository.setGate(nil)
        await viewModel.retry(try #require(viewModel.message?.retry))
        #expect(viewModel.todos == [a, c])
    }

    @Test func deleteOfAnAlreadyDeletedTodoIsNotAnError() async {
        let (viewModel, repository) = await loadedViewModel([a, b])
        await repository.setTodos([a]) // b is already gone on the server

        await viewModel.delete(b)

        #expect(viewModel.todos == [a])
        #expect(viewModel.message == nil)
    }

    // MARK: - Refresh

    @Test func refreshFailureKeepsTheListAndShowsAMessage() async {
        let (viewModel, repository) = await loadedViewModel([a])
        await repository.setFailNext(.network)

        await viewModel.refresh()

        #expect(viewModel.list == .loaded([a]))
        #expect(viewModel.message?.text.hasPrefix("Couldn't refresh") == true)
        #expect(viewModel.message?.retry == .refresh)

        await viewModel.retry(.refresh)
        #expect(viewModel.list == .loaded([a]))
    }

    @Test func refreshPicksUpServerChanges() async {
        let (viewModel, repository) = await loadedViewModel([a])
        await repository.setTodos([a, b])

        await viewModel.refresh()

        #expect(viewModel.todos == [a, b])
    }

    // MARK: - Messages

    @Test func messageShownClearsOnlyTheMatchingMessage() async throws {
        let (viewModel, repository) = await loadedViewModel([a])
        await repository.setFailNext(.network)
        await viewModel.refresh()
        let first = try #require(viewModel.message)

        viewModel.messageShown(id: first.id + 1)
        #expect(viewModel.message == first)

        viewModel.messageShown(id: first.id)
        #expect(viewModel.message == nil)
    }
}
