# End-to-end journeys

`android-journey.sh` drives the real Android app on an emulator against a real server, the way a user would, and checks every step on the screen **and** on the server. It writes a Markdown report with a screenshot per step and the server's state after it.

```bash
make e2e-android
```

| Variable | Values | Effect |
|---|---|---|
| `E2E_TARGET` | `memory` (default), `postgres`, `mock` | Which server. `postgres` also restarts the backend mid-journey to prove the data is durable. `mock` runs the same journey against WireMock. |
| `E2E_PUBLISH` | `1` | On success, copy the report to `docs/e2e/android-journey/` (the committed demo). |
| `E2E_AVD` | an AVD name | Which emulator to boot if none is running. Default: the first one. |

Output goes to `build/e2e/<timestamp>-<target>/` (`journey.md`, `img/`, server logs); `build/e2e/latest` points at the newest run. The exit code is 0 only if every check passed. A failed run still writes a report that ends at the failing step, with a screenshot.

## The journey

The 12 steps (start the backend and app, create Walk the dog and Grocery shopping, complete one, close and reopen, delete, complete, add Make dinner reservation, close and reopen), plus an extra phase where the server goes away and comes back.

Choices that make it a real test and not a replay:

- **The server starts empty and the app's data is cleared**, so the list is exactly what the journey made.
- **While the app is closed, the script edits a todo on the server.** After reopening, that edit has to be on screen. The app could not have known about it, so this only passes if it reads from the server. (The app keeps no local copy today, so without this a reopen would pass trivially.)
- **Closing is `am force-stop`**, so no process state survives.
- **Nothing is found by coordinates or fixed sleeps.** `ui.py` reads the screen through `uiautomator` and the script polls until a condition holds or a timeout fails the run.
- **It refuses to run if the server port is taken** (8081 for the backend, which the app's `local` flavor expects) and never kills what it didn't start.

## Files

- `android-journey.sh`: the journey and the report.
- `lib.sh`: waiting, assertions, report writing, UI actions (add, complete, swipe-delete) and server queries.
- `ui.py`: screen inspection over `adb uiautomator dump`, standard library only.

Requirements: `adb`, `curl`, `jq`, `python3`, `sips` (macOS), JDK 21, and Podman or Docker for the `postgres` and `mock` targets.

## Known limits

- It runs on macOS (uses `sips`; written for bash 3.2).
- The emulator stays running afterwards, so repeat runs are fast.
- Timeouts are generous for a warm machine. A cold emulator boot adds a minute or two.
