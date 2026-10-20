# Android client

Kotlin, Jetpack Compose, Hilt, Retrofit + OkHttp + kotlinx.serialization. AGP 9.4 (built-in Kotlin), Gradle 9.8, compileSdk/targetSdk 37, minSdk 26.

## Modules

| Module | What it is |
|---|---|
| `:core:network` | Pure JVM. Retrofit `TodosApi` and DTOs are **generated** from `../contract/openapi.yaml` (openapi-generator `kotlin` / `jvm-retrofit2`) into `build/`. Also holds the hand-written `TodoApiFactory` and `TodoJson`. |
| `:app` | Compose UI, ViewModels, Hilt wiring. `data/` maps DTOs to the domain `Todo` and HTTP failures to `TodoError`, so the UI never touches generated types. |

`TodoJson` reuses the generated adapters but sets `encodeDefaults = false` and `explicitNulls = false`. The generated default sends `"title": null` on PATCH, which the contract rejects.

## Flavors

| Flavor | Base URL | Notes |
|---|---|---|
| `mock` | `http://10.0.2.2:8080/api/v1/` | WireMock on the host (`make mock-up`). App id suffix `.mock`. |

A `local` flavor (Spring Boot backend) comes with CP5. Cleartext HTTP is allowed only in debug builds, and only to `10.0.2.2` and `localhost` (see `src/debug/`).

## Tests

- `:core:network:test` checks JSON encoding and decoding of the generated models.
- `:app:testMockDebugUnitTest` runs `NetworkTodoRepository` against OkHttp MockWebServer. The response and request bodies come from `components.examples` in the contract (`ContractExamples`), so contract edits that break the client fail here.

## Running from Android Studio

Open `android/`. Set **Settings → Build Tools → Gradle → Gradle JDK** to a JDK 21, pick the `mockDebug` build variant, and start the mock first with `make mock-up`.
