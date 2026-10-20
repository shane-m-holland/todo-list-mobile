# todo-list-mobile

Proof-of-concept sandbox for trying out development and workflow techniques with a ToDo app. It has three parts:

| Part | Path | Stack | Status |
|---|---|---|---|
| API contract | `contract/` | OpenAPI 3.1 | Done |
| Mock API | `mock/` | WireMock (container) | Done |
| Android client | `android/` | Kotlin, Compose, Retrofit, Hilt | MVP done (mock backend) |
| Backend API | `backend/` | Kotlin, Spring Boot 3, PostgreSQL | Done (in-memory or Postgres) |
| iOS client | `ios/` | Swift, SwiftUI, swift-openapi-generator | MVP done (mock backend) |

The contract is the source of truth. Client and server code is generated from `contract/openapi.yaml`.

## Prerequisites

- A container runtime. Podman is the default; pass `CONTAINER=docker` to use Docker.
- `jq` for the mock smoke test.
- JDK 21 for Gradle, Android and backend (Homebrew: `brew install openjdk@21`; override the location with `JDK21_HOME`).
- Android Studio and an emulator.
- Xcode 16+ with an iOS Simulator runtime matching its SDK (Xcode > Settings > Components).

## Common tasks

```bash
make help
```

```bash
make lint-contract
```

```bash
make contract-docs
```

```bash
make mock-up
```

See [mock/README.md](mock/README.md) for the mock's targets (reset, smoke test, failure mode, delays).

```bash
make backend-run
```

```bash
make backend-run-postgres
```

See [backend/README.md](backend/README.md) for how it's generated from the contract and tested.

```bash
make android-test
```

```bash
make android-install
```

Add `ANDROID_FLAVOR=local` to `make android-install` or `make android-build` to point the app at the Spring Boot backend instead of the mock.

See [android/README.md](android/README.md) for the Android project layout.

```bash
make e2e-android
```

Runs the whole user journey (create, complete, close, reopen, delete) on an emulator against a real server and writes a Markdown report with screenshots; see [scripts/e2e/README.md](scripts/e2e/README.md). The screen can be driven with `adb` (default) or [Maestro](https://github.com/mobile-dev-inc/maestro) (`make e2e-android E2E_DRIVER=maestro`). The latest published runs are in [docs/e2e/android-journey/](docs/e2e/android-journey/README.md) (`adb`) and [docs/e2e/android-journey-maestro/](docs/e2e/android-journey-maestro/README.md) (Maestro). General guidance for making apps drivable and verifiable by agents is in [ai-mobile-validation-guidelines.md](ai-mobile-validation-guidelines.md).

```bash
make ios-test
```

```bash
make ios-build
```

See [ios/README.md](ios/README.md) for the iOS project layout and how to run it in the Simulator.

## Roadmap

1. **CP0** Repo bootstrap ✅
2. **CP1** API contract ✅
3. **CP2** WireMock mock API ✅
4. **CP3** Android skeleton + generated client ✅
5. **CP4** Android UI (MVP complete) ✅
6. **CP5** Spring Boot backend ✅ (in-memory and PostgreSQL)
7. **CP6** iOS client ✅
8. **CP7** CI and contract breaking-change checks
