# Mock API (WireMock)

A stateful WireMock server that serves `contract/openapi.yaml` on `http://localhost:8080/api/v1`. It uses WireMock 3 with the [state extension](https://github.com/wiremock/wiremock-state-extension), so created, updated and deleted todos persist until the container restarts or you run `make mock-reset`.

From the repo root:

```bash
make mock-up
```

```bash
make mock-smoke
```

| Target | Effect |
|---|---|
| `mock-up` / `mock-down` | Build and start the mock (with seeding) / stop it |
| `mock-reset` | Clear all state and re-seed 3 sample todos |
| `mock-smoke` | CRUD smoke test (`smoke.sh`, needs `jq`) |
| `mock-fail-on` / `mock-fail-off` | Every `/api/v1/*` call returns a 500 problem / back to normal |
| `mock-slow` / `mock-fast` | Global response delay (`MOCK_DELAY_MS`, default 2000) on / off |

You can also fail a single request by sending the header `X-Mock-Fail: true`.

From the Android emulator, the mock is at `http://10.0.2.2:8080/api/v1/`. From the iOS Simulator, use `http://localhost:8080/api/v1/`.

## How it works

- Each todo is a state context keyed by its id, holding its fields plus `fullBody`, the rendered JSON. The `todos` context holds an ordered list of ids used for `GET /todos`.
- The new todo's id is WireMock's `request.id`, so the `Location` header and the body agree.
- Request bodies are checked with `matchesJsonSchema`, using schemas copied from the contract. Stub priorities route requests as follows: valid (5) → invalid body 400 (7) → unknown id 404 (9). Failure mode has priority 1.
- Response bodies are Handlebars templates in `__files/`. String values go through `toJson`, so quotes and newlines are escaped correctly.

## Known gaps

- The JSON schemas in the mappings are copies of the contract's. If the contract changes, update them too. CP5 adds contract validation so drift gets caught.
- 400 responses have no field-level `errors` list.
