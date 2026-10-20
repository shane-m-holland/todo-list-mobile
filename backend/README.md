# Backend (Spring Boot)

Kotlin, Spring Boot 3.5, Java 21. Implements `contract/openapi.yaml` on `http://localhost:8081/api/v1` (8080 is the WireMock mock). Data is **in memory** and seeded with three sample todos at startup, so it resets whenever the app restarts.

From the repo root:

```bash
make backend-run
```

```bash
make backend-test
```

```bash
make backend-smoke
```

`backend-smoke` runs the same `scripts/smoke.sh` as `mock-smoke`, so the mock and the backend are held to the same behavior. Health check: `GET /actuator/health`.

## How it's built

- **Contract first.** `openApiGenerate` (openapi-generator `kotlin-spring`, `interfaceOnly`) writes the `TodosApi` controller interface and the DTOs into `build/` (never committed). `TodosController` implements the interface, so a contract change the server doesn't follow fails to compile.
- **Layers.** `web/` (controller, DTO mapping, error handling) → `domain/` (`TodoService`, `TodoRepository` port, domain `Todo`). The generated DTOs stay in the web layer. `InMemoryTodoRepository` is the only adapter; a Postgres one can replace it without touching the service.
- **Validation** comes from the generated DTOs (`@Valid`). The server also rejects unknown JSON properties, because the contract sets `additionalProperties: false`, and omits `notes` instead of sending null.
- **Errors** are RFC 9457 `application/problem+json` for everything, including 404/405/415 from Spring itself. Validation failures carry the contract's `errors: [{field, message}]` list. The content type doesn't depend on the client's `Accept` header.
- **Path prefix.** The contract's paths are `/todos`, and its `servers` URL ends in `/api/v1`. `AppConfig` adds the `/api/v1` prefix to controllers implementing `TodosApi`.

## Tests

- `TodoServiceTest` covers the domain rules (partial updates, clearing notes, timestamps, ordering).
- `TodosApiContractTest` runs the real HTTP stack through MockMvc and checks **every request and response against `contract/openapi.yaml`** (swagger-request-validator). For tests that send an invalid request on purpose, only the response is checked.

Drift is caught at two points: compile time (generated DTOs and interface) and test time (the validator). Both were checked by temporarily editing the contract.

## Known gaps

- An explicit `"notes": null` in a PATCH is treated as "not provided" rather than rejected. Jackson can't tell it from an absent field.
- Storage is in memory. Postgres, Flyway and Testcontainers come next.
