# Backend (Spring Boot)

Kotlin, Spring Boot 3.5, Java 21. Implements `contract/openapi.yaml` on `http://localhost:8081/api/v1` (8080 is the WireMock mock).

## Storage profiles

| Profile | Storage | Use |
|---|---|---|
| `memory` (default) | In process. Seeded with three sample todos; everything is lost on restart. | Zero setup. `make backend-run` |
| `postgres` | PostgreSQL, schema managed by Flyway. Not seeded unless `TODO_SEED_ENABLED=true`, and then only into an empty table. | Persistence. `make backend-run-postgres` |

From the repo root:

```bash
make backend-run
```

```bash
make backend-run-postgres
```

`backend-run-postgres` starts a local PostgreSQL container first (`make db-up`, host port **5433** so it can't clash with a Postgres on 5432). Its data lives in a named volume, so it survives `make db-down`; `make db-reset` deletes it. Connection settings default to that container (`todo`/`todo` on `localhost:5433`, a local-development credential) and can be overridden with `DB_URL`, `DB_USER` and `DB_PASSWORD`.

```bash
make backend-test
```

```bash
make backend-smoke
```

`backend-smoke` runs the same `scripts/smoke.sh` as `mock-smoke`, so the mock and the backend are held to the same behavior. Health check: `GET /actuator/health`.

## How it's built

- **Contract first.** `openApiGenerate` (openapi-generator `kotlin-spring`, `interfaceOnly`) writes the `TodosApi` controller interface and the DTOs into `build/` (never committed). `TodosController` implements the interface, so a contract change the server doesn't follow fails to compile.
- **Layers.** `web/` (controller, DTO mapping, error handling) → `domain/` (`TodoService`, `TodoRepository` port, domain `Todo`). The generated DTOs stay in the web layer. The port has two adapters, `InMemoryTodoRepository` (profile `memory`) and `JdbcTodoRepository` (profile `postgres`, Spring `JdbcClient`), chosen by profile; the service doesn't know which.
- **Schema.** `src/main/resources/db/migration/V1__create_todos.sql`. Native `uuid` and `timestamptz` columns, an identity column that keeps creation order for todos created in the same millisecond, and CHECK constraints that mirror the contract (non-blank title ≤ 200, non-empty notes ≤ 2000). Updates lock the row (`SELECT … FOR UPDATE`) so concurrent writes can't overwrite each other. In the `memory` profile the datasource, JDBC and Flyway auto-configuration are switched off, so no database is needed.
- **Validation** comes from the generated DTOs (`@Valid`). The server also rejects unknown JSON properties, because the contract sets `additionalProperties: false`, and omits `notes` instead of sending null.
- **Errors** are RFC 9457 `application/problem+json` for everything, including 404/405/415 from Spring itself. Validation failures carry the contract's `errors: [{field, message}]` list. The content type doesn't depend on the client's `Accept` header.
- **Path prefix.** The contract's paths are `/todos`, and its `servers` URL ends in `/api/v1`. `AppConfig` adds the `/api/v1` prefix to controllers implementing `TodosApi`.

## Tests

- `TodoServiceTest` covers the domain rules (partial updates, clearing notes, timestamps, ordering).
- `AbstractTodosApiContractTest` runs the real HTTP stack through MockMvc and checks **every request and response against `contract/openapi.yaml`** (swagger-request-validator). For tests that send an invalid request on purpose, only the response is checked. It runs once per store: `TodosApiContractMemoryTest` and `TodosApiContractPostgresTest`.
- `AbstractTodoRepositoryTest` is the behavior every repository must have (round trip, ordering, atomic updates under 20 concurrent writers, delete). `InMemoryTodoRepositoryTest` and `JdbcTodoRepositoryTest` run it; the latter also checks the Flyway migration and the database constraints.
- The Postgres tests use **Testcontainers** (`postgres:17-alpine`, one container for the whole run). `make backend-test` points Testcontainers at Podman's socket. They are skipped, not failed, when no container runtime is available, so check the test report's skipped count if you rely on them.

Drift is caught at two points: compile time (generated DTOs and interface) and test time (the validator). Both were checked by temporarily editing the contract. The concurrency test was checked the same way: without the row lock it fails.

## Known gaps

- An explicit `"notes": null` in a PATCH is treated as "not provided" rather than rejected. Jackson can't tell it from an absent field.
- No pagination: `GET /todos` returns every row.
- No connection-pool or Hikari tuning, and no production profile.
