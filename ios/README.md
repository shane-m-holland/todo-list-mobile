# iOS client

SwiftUI + Observation (`@Observable`), iOS 17+, Swift 6 language mode. The API client is generated from `../contract/openapi.yaml` by Apple's [swift-openapi-generator](https://github.com/apple/swift-openapi-generator) at build time and uses the `swift-openapi-urlsession` transport. Generated code is never committed; it lands in DerivedData.

## Layout

| Path | What it is |
|---|---|
| `Todo.xcodeproj` | Thin app target. `App/TodoApp.swift` shows `TodoRootView`. `Config/Info-Debug.plist` holds the debug-only ATS exception (cleartext HTTP to `localhost` only). |
| `TodoKit/` | Local Swift package with everything else, so the unit tests run without hosting an app. |
| `TodoKit/Sources/TodoKit/openapi.yaml` | Symlink to `contract/openapi.yaml`, the generator's input. `openapi-generator-config.yaml` next to it asks for `types` and `client`. |
| `TodoKit/Sources/TodoKit/Data/` | `Todo` (app model), `TodoError`, the `TodoRepository` protocol, and `NetworkTodoRepository`, which is the only code that touches generated types. |
| `TodoKit/Sources/TodoKit/UI/` | `TodoListViewModel` and the SwiftUI views. |

Layering matches Android: generated types → `TodoRepository` → app `Todo` → view model → views. `NetworkTodoRepository` maps HTTP and IO failures to `TodoError` (`network`, `notFound`, `validation` with field errors, `server(status:)`, `unexpected`) and decodes RFC 9457 problem bodies, including for status codes the contract doesn't list.

Two deliberate details:

- PATCH bodies omit absent fields. The generated `UpdateTodo` uses optionals that encode only when set, so the client never sends `"title": null`, which the contract rejects. `notes: ""` clears notes.
- `FlexibleDateTranscoder` accepts `date-time` with or without fractional seconds. The mock sends whole seconds; a Spring backend may not.

## UI

One screen, mirroring the Android app: a list with a toggle circle, tap-to-edit sheet (title and notes, Save disabled while the title is blank, 200 / 2000 character limits), swipe-to-delete, a `+` button, pull-to-refresh, an empty state, a full-screen load error with Retry, and a transient error banner with Retry.

Toggle and delete are optimistic and roll back on failure. Create and edit wait for the server. Deleting something already gone (404) counts as success. Edits send only the changed fields.

## Running

Start the mock, then run the app:

```bash
make mock-up
```

Open `ios/Todo.xcodeproj` in Xcode, pick a simulator and press Run. The first build asks you to trust the OpenAPI generator plugin; accept it. The app talks to `http://localhost:8080/api/v1`, which the Simulator reaches on the host directly. To point at something else, set `TODO_API_BASE_URL` in the scheme's environment variables.

Try `make mock-fail-on` for the error states (and `make mock-fail-off` to recover), and `make mock-slow` to see the optimistic updates. Check that changes persist with `curl localhost:8080/api/v1/todos`.

## Build and test from the command line

```bash
make ios-build
```

```bash
make ios-test
```

Both need an iOS Simulator runtime that matches the installed Xcode's SDK (Xcode > Settings > Components), and use `IOS_DEST` (default `platform=iOS Simulator,name=iPhone 17`) as the destination.

## Tests

Swift Testing, in `TodoKit/Tests/TodoKitTests`:

- `NetworkTodoRepositoryTests` drives the repository through a stubbed `ClientTransport`. Request and response bodies come from `components.examples` in the contract, read by `ContractExamples` with Yams, so contract edits that break the client fail here.
- `TodoListViewModelTests` uses `FakeTodoRepository` (with failure injection and a gate that holds calls in flight): optimistic updates, rollback, retry and refresh.
