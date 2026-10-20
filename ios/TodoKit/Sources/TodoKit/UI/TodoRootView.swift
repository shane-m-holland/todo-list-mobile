import SwiftUI

/// Entry point for the app target: wires the live repository into the single screen.
public struct TodoRootView: View {
    @State private var viewModel = TodoListViewModel(repository: NetworkTodoRepository.live())

    public init() {}

    public var body: some View {
        TodoListScreen(viewModel: viewModel)
    }
}
