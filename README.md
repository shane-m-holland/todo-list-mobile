# todo-list-mobile

Proof-of-concept sandbox for trying out development and workflow techniques with a ToDo app. It has three parts:

| Part | Path | Stack | Status |
|---|---|---|---|
| API contract | `contract/` | OpenAPI 3.1 | MVP |
| Mock API | `mock/` | WireMock (container) | MVP |
| Android client | `android/` | Kotlin, Compose, Retrofit, Hilt | MVP |
| Backend API | `backend/` | Kotlin, Spring Boot 3 | Planned |
| iOS client | `ios/` | Swift, SwiftUI | Planned |

The contract is the source of truth. Client and server code is generated from `contract/openapi.yaml`.

## Prerequisites

- A container runtime. Podman is the default; pass `CONTAINER=docker` to use Docker.
- JDK 21 for Gradle (Homebrew: `brew install openjdk@21`).
- Android Studio and an emulator.
- Xcode (later, for iOS).

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

## Roadmap

1. **CP0** Repo bootstrap
2. **CP1** API contract
3. **CP2** WireMock mock API
4. **CP3** Android skeleton + generated client
5. **CP4** Android UI (MVP complete)
6. **CP5** Spring Boot backend
7. **CP6** iOS client
8. **CP7** CI and contract breaking-change checks
