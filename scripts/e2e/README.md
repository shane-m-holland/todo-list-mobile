# End-to-end journeys

`android-journey.sh` drives the real Android app on an emulator against a real server, the way a user would, and checks every step on the screen **and** on the server. It writes a Markdown report with a screenshot per step and the server's state after it.

```bash
make e2e-android
```

| Variable | Values | Effect |
|---|---|---|
| `E2E_TARGET` | `memory` (default), `postgres`, `mock` | Which server. `postgres` also restarts the backend mid-journey to prove the data is durable. `mock` runs the same journey against WireMock. |
| `E2E_DRIVER` | `adb` (default), `maestro` | What drives the screen. See [Drivers](#drivers). |
| `E2E_PUBLISH` | `1` | On success, copy the report to `docs/e2e/android-journey/` (the `adb` demo) or `docs/e2e/android-journey-maestro/`. |
| `E2E_AVD` | an AVD name | Which emulator to boot if none is running. Default: the first one. |

Output goes to `build/e2e/<timestamp>-<target>/` (`journey.md`, `img/`, server logs); `build/e2e/latest` points at the newest run. The exit code is 0 only if every check passed. A failed run still writes a report that ends at the failing step, with a screenshot.

## The journey

The 12 steps (start the backend and app, create Walk the dog and Grocery shopping, complete one, close and reopen, delete, complete, add Make dinner reservation, close and reopen), plus an extra phase where the server goes away and comes back.

Choices that make it a real test and not a replay:

- **The server starts empty and the app's data is cleared**, so the list is exactly what the journey made.
- **While the app is closed, the script edits a todo on the server.** After reopening, that edit has to be on screen. The app could not have known about it, so this only passes if it reads from the server. (The app keeps no local copy today, so without this a reopen would pass trivially.)
- **Closing is `am force-stop`**, so no process state survives.
- **Nothing is found by coordinates or fixed sleeps.** Both drivers find elements by label and wait for a condition (the `adb` driver polls, Maestro waits on its own) until a timeout fails the run.
- **It refuses to run if the server port is taken** (8081 for the backend, which the app's `local` flavor expects) and never kills what it didn't start.

## Drivers

The journey script owns everything except the screen: the backend lifecycle, resetting data, the server checks and the report. A **driver** owns the screen: launching, tapping, typing, swiping and asserting what is shown. Both drivers implement the same ten functions (`drv_launch_empty`, `drv_add_todo`, `drv_assert_screen`, and so on; the list is at the top of `driver-adb.sh`), so the journey reads the same either way.

| | `adb` (default) | `maestro` |
|---|---|---|
| Needs | The Android SDK, `python3` | `brew install mobile-dev-inc/tap/maestro`, Java 17 or 21 |
| Acts through | `adb shell input`, `am start` | Small YAML flows in `maestro/`, run with `maestro test` |
| Reads the screen through | `uiautomator dump`, parsed by `ui.py` | Maestro's own selectors and assertions |
| "Screen matches server" | Compares the parsed list with the server's list | Generates a flow from the server's state (`maestro/screen.jq`) and runs it: counter, one row per todo with its checked state and notes, and no extra rows |
| Waiting | The script polls | Maestro waits and retries on its own |
| Speed | One quick call per check | One `maestro test` process per action or check (a few seconds of startup each) |

Every Maestro run here sets `JAVA_HOME` to JDK 21 and turns off analytics, the update check and the AI-analysis notice (`MAESTRO_CLI_NO_ANALYTICS`, `MAESTRO_DISABLE_UPDATE_CHECK`, `MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED`), for that command only. Maestro still writes a small `~/.maestro/analytics.json` (a random id with `enabled: false`) and a `deps` folder of helper tools.

## Files

- `android-journey.sh`: the journey, the server checks and the report.
- `lib.sh`: waiting, assertions, report writing and server queries.
- `driver-adb.sh`, `ui.py`: the `adb` driver. `ui.py` reads the screen over `adb uiautomator dump`, standard library only.
- `driver-maestro.sh`, `maestro/`: the Maestro driver and its flows (`add-todo.yaml`, `complete-todo.yaml`, `delete-todo.yaml`, ...), plus `screen.jq`.

Requirements: `adb`, `curl`, `jq`, `python3`, `sips` (macOS), JDK 21, Podman or Docker for the `postgres` and `mock` targets, and Maestro for the `maestro` driver.

## Known limits

- It runs on macOS (uses `sips`; written for bash 3.2).
- The emulator stays running afterwards, so repeat runs are fast.
- Timeouts are generous for a warm machine. A cold emulator boot adds a minute or two.
