# Android client

Kotlin, Jetpack Compose, Hilt, Retrofit + OkHttp + kotlinx.serialization. AGP 9.4 (built-in Kotlin), Gradle 9.8, compileSdk/targetSdk 37, minSdk 26.

## Modules

| Module | What it is |
|---|---|
| `:core:network` | Pure JVM. Retrofit `TodosApi` and DTOs are **generated** from `../contract/openapi.yaml` (openapi-generator `kotlin` / `jvm-retrofit2`) into `build/`. Also holds the hand-written `TodoApiFactory` and `TodoJson`. |
| `:app` | Compose UI, ViewModels, Hilt wiring. `data/` maps DTOs to the domain `Todo` and HTTP failures to `TodoError`, so the UI never touches generated types. |

`TodoJson` reuses the generated adapters but sets `encodeDefaults = false` and `explicitNulls = false`. The generated default sends `"title": null` on PATCH, which the contract rejects.

## UI

A single screen: `TodoListScreen` → `TodoListContent`. `TodoListContent` is stateless so UI tests can drive it directly.

- The list has a checkbox to toggle a todo, tap to edit, and swipe right-to-left to delete. Pull to refresh reloads it.
- The FAB opens `TodoEditorSheet`, a bottom sheet with title and notes. Save is disabled while the title is blank, and the contract's max lengths are enforced.
- `TodoListViewModel` keeps a single `TodoListUiState`:
  - `list` is `Loading`, `Loaded` or `Failed`. Failed is the full-screen error with Retry.
  - `isRefreshing` tracks pull-to-refresh.
  - `message` is a one-shot snackbar carrying a retryable `Operation`.
- Toggle and delete update the list immediately and revert if the server call fails. Create and edit wait for the server, since it assigns ids and timestamps. Deleting something that's already gone (404) counts as success.

## Flavors

| Flavor | Base URL | Notes |
|---|---|---|
| `mock` | `http://10.0.2.2:8080/api/v1/` | WireMock on the host (`make mock-up`). App id suffix `.mock`. |
| `local` | `http://10.0.2.2:8081/api/v1/` | Spring Boot backend on the host (`make backend-run`). App id suffix `.local`. |

Both can be installed side by side. `make android-install ANDROID_FLAVOR=local` builds and launches the `local` one. Cleartext HTTP is allowed only in debug builds, and only to `10.0.2.2` and `localhost` (see `src/debug/`).

## Tests

- `:core:network:test` checks JSON encoding and decoding of the generated models.
- `:app:testMockDebugUnitTest` runs `NetworkTodoRepository` against OkHttp MockWebServer. The response and request bodies come from `components.examples` in the contract (`ContractExamples`), so contract edits that break the client fail here. It also covers `TodoListViewModel` against `FakeTodoRepository` (Turbine plus a test dispatcher): optimistic updates, rollback, retry and refresh.
- `make e2e-android` (repo root) is the full-stack check: the real app and a real server, with a report. See `scripts/e2e/README.md`.
- `:app:connectedMockDebugAndroidTest` runs Compose UI tests for `TodoListContent` (add flow, edit, toggle, empty state). It needs a running emulator.

## Running from Android Studio

Open `android/`. Set **Settings → Build Tools → Gradle → Gradle JDK** to a JDK 21, pick the `mockDebug` or `localDebug` build variant, and start the matching server first (`make mock-up` or `make backend-run`).
