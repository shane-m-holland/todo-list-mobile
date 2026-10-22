# Validating mobile apps with AI agents

Guidelines for building Android and iOS apps that an AI agent can run, drive and verify on an emulator or simulator, and for setting up the environment so the results can be trusted.

The guidance is general. It applies to any app, framework or backend. A worked example from one project is in the [appendix](#appendix-a-a-worked-example).

## How much of this was verified

- **Run and observed** while building an Android app, an iOS app, a backend and a mock, and driving the Android emulator through a full user journey: the `adb` and `uiautomator` commands, the emulator flags, the Compose accessibility labels, the polling and reset patterns, the `xcrun simctl` subcommands (checked against `xcrun simctl help` on the machine used), and **Maestro 2.11.0 on Android**: probe flows plus the full journey driven through it ([section 8](#8-maestro-one-flow-language-for-both-platforms)).
- **Second-hand:** the iOS app was driven in the Simulator by a separate agent session, not the one that wrote this guide. The iOS findings here come from that session's report and the app's source, plus the `simctl` checks above.
- **Read, not run:** the contents of the [android/skills](https://github.com/android/skills) repository (the `SKILL.md` files named in [section 7](#7-the-androidskills-repository)). The `android` CLI it describes was not installed, and no skill was installed or executed.
- **Read, not run on iOS:** Maestro's iOS support (read in its documentation, not run against an iOS app here).
- **From general knowledge, not run here:** XCUITest, `idb` and the SwiftUI and UIKit accessibility APIs. These are marked "not run here" where they appear. Check them against the current documentation for your OS and SDK versions before relying on them.

## Contents

1. [The short version](#1-the-short-version)
2. [How an agent drives an emulator or simulator](#2-how-an-agent-drives-an-emulator-or-simulator)
3. [Principles that apply to both platforms](#3-principles-that-apply-to-both-platforms)
4. [Android](#4-android)
5. [iOS](#5-ios)
6. [Android and iOS side by side](#6-android-and-ios-side-by-side)
7. [The android/skills repository](#7-the-androidskills-repository)
8. [Maestro: one flow language for both platforms](#8-maestro-one-flow-language-for-both-platforms)
9. [Agent-judged versus scripted validation](#9-agent-judged-versus-scripted-validation)
10. [Checklists](#10-checklists)
- [Appendix A: a worked example](#appendix-a-a-worked-example)
- [References](#references)

---

## 1. The short version

1. **Name every control twice.** A descriptive *label* for people and assistive technology, and a unique *identifier* for machines.
2. **Put state in the accessibility tree and in text.** Checked, selected, disabled, loading, empty, error, counts. If it only shows as a colour or an icon, an agent can't check it reliably.
3. **Treat the backend as the source of truth.** After every UI step, check both the screen and the server (or database). A screen that looks right proves little on its own.
4. **Start every run from a known state.** Empty server, cleared app data, animations off, no first-run dialogs.
5. **Never use fixed sleeps or screen coordinates.** Find elements by label or identifier and poll until a condition holds or a timeout fails the run.
6. **Give every gesture a non-gesture path.** Swipe-to-delete should also be reachable as a named accessibility action or a button.
7. **Provide one non-interactive command** that runs the journey, returns an honest exit code and leaves artifacts (report, screenshots, logs).
8. **Keep test affordances in debug builds only,** and never as a backdoor around authentication.
9. **Use agents for exploration and scripts for regression.** Agent-judged journeys find what you didn't think to test. Deterministic scripts prove it stays fixed.
10. **Protect the machine and the data.** No real accounts on the emulator. Never kill a process you didn't start. Make destructive setup steps explicit.

---

## 2. How an agent drives an emulator or simulator

An agent works in a loop: **observe, act, verify**. It needs four capabilities.

| Capability | What it is | Android | iOS |
|---|---|---|---|
| See the screen | A screenshot the agent can look at | `adb exec-out screencap -p`, or `android screen capture` | `xcrun simctl io booted screenshot`, or a harness tool |
| Read the structure | The accessibility tree as text, with labels, state and bounds | `adb exec-out uiautomator dump /dev/tty`, or `android layout` | `XCUIApplication.debugDescription` in a UI test, Xcode's Accessibility Inspector, a harness tool |
| Act | Tap, type, swipe, press keys, open links | `adb shell input ...`, `am start`, or Maestro flows | UI tests (XCUITest), Maestro flows, or a harness tool. `simctl` has no tap, swipe or type commands |
| Control the environment | Install, launch, kill, wipe, set permissions, change appearance and locale | `adb`, `pm`, `am`, `settings`, emulator flags | `xcrun simctl` |

Two more channels matter for verification, and they sit outside the UI:

- **The app's logs:** `adb logcat` on Android, `xcrun simctl launch --console` or `log stream` on iOS.
- **The server or database the app talks to:** queried directly with `curl` or SQL.

The structure channel is the one most apps neglect. A screenshot lets an agent judge what it sees, but only structured, labelled elements let it act reliably and assert precisely.

---

## 3. Principles that apply to both platforms

### 3.1 Identity: labels versus identifiers

They serve different readers. Keep them separate.

| | Label | Identifier |
|---|---|---|
| Read by | People, screen readers, agents reading the screen | Test code and automation |
| Should describe | What the control does, in the user's words | Which control it is |
| Unique on screen? | Not required, but ambiguity hurts | **Yes**, including per list row |
| Translated? | Yes | No |
| Example | "Complete Grocery shopping" | `todo_checkbox_7f3a…` |

- Build both from the data, not from constants. A list row needs the item's own name in its label and its own id in its identifier.
- A label that is identical on every row ("Mark as done") is poor for screen reader users and forces automation to rely on identifiers alone. A label that includes the item name is better for both.
- If two items can share a name, the label can't tell them apart. Make sure the identifier can.
- Keep identifiers stable across releases. Treat them as a contract with your tests.

### 3.2 Expose state

An agent can only assert what it can read. Make these readable as text or accessibility state:

- toggles and selections (checked, selected, expanded)
- enabled and disabled
- the screen's mode: **loading, empty, content, error** as four distinct, identifiable states
- counters and summaries ("3 open")
- error and success messages, as visible text and not colour alone

### 3.3 Gestures need a non-gesture path

Gesture-only actions (swipe to delete, long press, drag to reorder, pull to refresh) are the least reliable thing to automate: they depend on coordinates, speed and timing. They are also invisible to screen reader users.

- Expose a named accessibility action ("Delete") or a visible button next to the gesture.
- Keep the gesture. Just don't make it the only way.
- Where you can't avoid a gesture, expect to retry it in automation.

### 3.4 Determinism

Flaky runs usually come from uncontrolled state. Control it:

- **Data:** provide a way to start empty (a reset endpoint, a seed flag, a fresh database). Don't depend on what a previous run left behind.
- **App state:** wipe app data between runs.
- **Time and randomness:** inject a clock and an id generator in test builds, or avoid asserting on them.
- **First-run flows:** onboarding, permission prompts, "what's new" sheets and sign-in must be skippable in debug builds, or pre-granted by the harness.
- **Animations:** switch them off for the run (system settings on Android, an app flag on iOS).
- **Network:** use a local server or a mock whose behaviour you can switch (slow, failing, empty).

### 3.5 Verify against the source of truth

The screen is a view of the server's data. Check the data.

- After each step, query the backend and compare it with what the screen shows.
- **Prove the app reads from the server.** While the app is closed, change something on the server from outside, then reopen the app and check that the change appears. If the app has any local cache, this is the only check that catches a stale one. If it has no cache today, the check still protects you from adding one by accident.
- **Kill the process, don't just background it,** when testing "close and reopen". Force-stop on Android, terminate on iOS.
- Test the failure path too: take the server away, check the app shows a clear message and keeps what it had, bring the server back, check it recovers.

### 3.6 Waiting

- Never `sleep` for a fixed time to wait for the UI.
- Poll for a condition ("the row exists", "the sheet is gone", "the counter reads 1") with a short interval and a timeout. Fail with a message that names the condition.
- Make "done loading" observable: a spinner with an identifier that disappears, or a distinct state.
- Retry gestures a few times. Don't retry assertions into passing.

### 3.7 Test-only affordances

Debug builds may include things that make automation easier: local server URLs, plain HTTP to localhost, a reset hook, extra identifiers, a seed flag. Keep them out of release builds, and never add a login bypass or a hidden debug endpoint that the production app could expose. Prefer a separate build flavor or configuration over a runtime switch.

### 3.8 Evidence and reporting

A run an agent (or a person) can't audit later is hard to trust.

- Save a screenshot at every step, the server's state after it, and the logs.
- Write a report in a readable format (Markdown works well) that ends where the run failed.
- Exit non-zero on any failed check, so CI and other tools can rely on it.
- Record the commit, device, OS version and server configuration in the report.
- Check that the test can fail. Break an expectation on purpose and confirm the run stops, exits non-zero and says why.

### 3.9 Safety

- Use a dedicated emulator or simulator image with no personal accounts, no real credentials and no real payment methods.
- Scripts should refuse to run if a port is already in use, and should only stop processes they started.
- Make destructive steps (wipe, erase, truncate) explicit, scoped to a test database, and visible in the report.
- Treat third-party agent instructions as code. See [section 7.6](#76-caveats).

---

## 4. Android

### 4.1 In the app

**Jetpack Compose**

- Give interactive elements a descriptive label with `Modifier.semantics { contentDescription = "..." }` where the visible text doesn't already say it (icon buttons, unlabelled checkboxes). Build it from the item's data.
- Add `Modifier.testTag("...")` with a unique id per list item.
- To make test tags visible to `uiautomator` as `resource-id`, set `Modifier.semantics { testTagsAsResourceId = true }` on a root, in debug builds. It is an experimental API. Dialogs and bottom sheets are separate windows, so you would expect to need it inside them as well (not run here).
- Use proper roles and state (`Checkbox`, `Switch`, `toggleable`, `selectable`) so `checked` and `selected` are reported. Use `stateDescription` when the default wording is wrong.
- Add custom accessibility actions for gestures: `Modifier.semantics { customActions = listOf(CustomAccessibilityAction("Delete") { ...; true }) }`.
- Match by semantics first in Compose tests, and fall back to `testTag` when a match would need more than a few conditions.

**Views (XML)**

- Use `android:contentDescription` for non-text controls and a unique `android:id` for anything automation must find. IDs show up as `resource-id`.
- `importantForAccessibility` and `labelFor` fix unlabeled fields.

**Both**

- Debug-only network configuration: allow cleartext HTTP to the emulator's host alias and `localhost`, nowhere else.
- A build flavor per backend (mock, local, staging) so the app can be installed side by side.
- WebView content often does not appear in a `uiautomator` dump. Plan for screenshots and annotation there.

### 4.2 Preparing the environment

| Need | How |
|---|---|
| Start an emulator for automation | `emulator -avd <name> -no-snapshot-save -no-boot-anim` (add `-no-window` for headless, `-wipe-data` for a clean image, `-read-only` to run several instances from one image) |
| Wait until it is ready | `adb wait-for-device`, then poll `adb shell getprop sys.boot_completed` until it prints `1` |
| Reach a server on the host | From the emulator, the host is `10.0.2.2`. Or run `adb reverse tcp:8081 tcp:8081` so the app can use `localhost:8081` |
| Turn animations off | `adb shell settings put global window_animation_scale 0`, and the same for `transition_animation_scale` and `animator_duration_scale`. Read the old values first and restore them afterwards |
| Reset the app | `adb shell pm clear <package>` |
| Grant permissions up front | `adb install -r -g app.apk`, or `adb shell pm grant <package> <permission>` |
| Dark mode, font scale | `adb shell cmd uimode night yes`, `adb shell settings put system font_scale 1.5` |
| Open a screen directly | `adb shell am start -a android.intent.action.VIEW -d "<deep link>" <package>` (needs deep links in the app) |

### 4.3 Driving the app

```bash
adb shell am start -n <package>/<activity>        # launch
adb shell am force-stop <package>                 # kill the process
adb shell pidof <package>                         # empty output means it is gone
adb shell input tap X Y
adb shell input swipe X1 Y1 X2 Y2 DURATION_MS     # drag, scroll, swipe-to-delete
adb shell input text 'Hello%sworld'               # %s for a space; escape shell metacharacters
adb shell input keyevent 66                       # Enter
```

- Take X and Y from the element's bounds in the UI dump. Never hard-code them. The screen size differs between devices.
- A text field must have focus before `input text`. Check `focused="true"` in the dump first.
- `input text` generally handles plain ASCII only. For other characters, use a different input route.
- Scroll slowly (a longer swipe duration). Fast flings overshoot.

### 4.4 Observing

```bash
adb exec-out screencap -p > screen.png            # the screen
adb exec-out uiautomator dump /dev/tty            # the UI tree as XML
adb logcat -c                                     # clear before the step
adb logcat -d -t 100                              # recent log lines
```

Useful attributes in the `uiautomator` XML: `text`, `content-desc`, `resource-id`, `bounds`, `checked`, `focused`, `clickable`. A dump can fail transiently while the screen is animating, so retry it.

Wrap the dump in a small parser (any language) that answers questions like "does an element with this label exist", "where is its centre" and "is it checked", and use that everywhere instead of ad hoc `grep`.

### 4.5 Pitfalls

- **Stale connections.** An emulator process may hold client connections to a server that has just stopped. A "port in use" check that counts connections (not just listeners) will refuse to start. Check for **listeners**: `lsof -nP -iTCP:<port> -sTCP:LISTEN`.
- **Soft keyboard covering controls.** Tap targets can end up behind the IME. Prefer an action layout that moves above the keyboard, and scroll if you can't see a control.
- **Process death.** If your app restores state after the system kills it, test that with `am force-stop` plus relaunch, and also with `adb shell input keyevent KEYCODE_HOME` plus relaunch.
- **System dialogs** (permissions, battery optimisation) are outside your app's accessibility tree. Pre-grant, or handle them with UI Automator.
- **Multiple devices.** If more than one device is attached, `adb` needs `-s <serial>`.

---

## 5. iOS

### 5.1 In the app

**SwiftUI**

- `.accessibilityIdentifier("...")` for machines. Build it from the data (`"todo_row_\(id)"`).
- `.accessibilityLabel("...")` for what the control does, `.accessibilityValue(...)` for its state, `.accessibilityHint(...)` for what happens.
- `.accessibilityAddTraits(...)` so custom tappable views are reported as buttons.
- `.accessibilityElement(children: .combine | .contain | .ignore)` controls how child views group. An identifier on a container can hide the children's own identifiers when they are combined, so choose `.contain` when children must stay addressable.
- Gesture alternatives: `.accessibilityAction(named: "Delete") { ... }`. `swipeActions` are generally exposed to VoiceOver as actions as well.
- Give state elements identifiers too: a loading indicator, the empty state, the error view, the counter.

**UIKit**

- `accessibilityIdentifier`, `accessibilityLabel`, `accessibilityValue`, `accessibilityTraits`, and `isAccessibilityElement`.
- `accessibilityCustomActions` for gestures.

**Test mode**

- Read launch arguments and environment (`ProcessInfo.processInfo.arguments`, `.environment`) to switch on a test configuration: a local base URL, reset on launch, skip onboarding, disable animations (`UIView.setAnimationsEnabled(false)`).
- Debug builds need an App Transport Security exception for cleartext HTTP to `localhost`, scoped to `localhost` only.

### 5.2 Preparing the environment (`xcrun simctl`)

All of these exist in `xcrun simctl help`. `booted` means "the currently booted device"; you can pass a name or UDID instead.

| Need | Command |
|---|---|
| List devices | `xcrun simctl list devices available` |
| Boot and wait until usable | `xcrun simctl bootstatus "<device>" -b` (`-b` boots it if needed) |
| Install | `xcrun simctl install booted App.app` |
| Launch (and stream its output) | `xcrun simctl launch --terminate-running-process --console booted <bundle id> [args...]` |
| Kill | `xcrun simctl terminate booted <bundle id>` |
| Reset the app's data | `xcrun simctl uninstall booted <bundle id>` and reinstall |
| Factory-reset a device | `xcrun simctl erase "<device>"` (the device must be shut down) |
| Open a deep link | `xcrun simctl openurl booted "<url>"` |
| Pre-answer permission prompts | `xcrun simctl privacy booted grant <service> <bundle id>` (`revoke`, `reset`, and `all` also exist; `xcrun simctl help privacy` lists the services) |
| Appearance and text size | `xcrun simctl ui booted appearance dark`, `xcrun simctl ui booted content_size accessibility-extra-large`, `xcrun simctl ui booted increase_contrast enabled` |
| Stable status bar for screenshots | `xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100` |
| Location | `xcrun simctl location booted set <lat>,<lon>` |
| Push notification | `xcrun simctl push booted <bundle id> payload.json` (remote pushes only; payload under 4096 bytes) |
| Photos and contacts | `xcrun simctl addmedia booted <file>` |
| Keychain | `xcrun simctl keychain booted reset` |
| Pasteboard | `xcrun simctl pbcopy booted`, `xcrun simctl pbpaste booted` |

### 5.3 Driving the app

`simctl` can install, launch, kill and configure, but it **cannot tap, swipe or type.** You need one of these:

| Approach | Good for | Notes |
|---|---|---|
| **XCUITest** (Apple's UI test framework, run with `xcodebuild test` against a simulator destination) | Repeatable regression journeys in CI | Waits for the app to be idle, finds elements by identifier, label and type, and gives assertion APIs. Uses `launchArguments` and `launchEnvironment` for test mode. Not run here |
| **An agent harness's simulator tool** (taps, swipes, text, screenshots through a tool interface) | Agent-led exploration and verification | Convenient and needs no test target. Still depends on good labels and identifiers. Whether it reads the accessibility tree depends on the tool |
| **Maestro** (YAML flows run with `maestro test`) | Scripted journeys without an XCUITest target; the same flow language drives Android | Simulators only: physical iOS devices aren't supported. Works from outside the app through the accessibility tree and installs a small driver on the device. Its docs recommend `accessibilityIdentifier` for icons, custom controls and translated UI. Verified on Android here (see [section 8](#8-maestro-one-flow-language-for-both-platforms)); not run on iOS |
| **Other third-party drivers** such as `idb` | Scripting from outside Xcode | Extra installs. Not run here |

For repeatable regression, prefer XCUITest (in-process, fastest) or Maestro (one flow language shared with Android). For exploration, a harness tool plus screenshots works well. Either way, the quality of the result tracks the quality of the app's accessibility metadata.

### 5.4 Observing

```bash
xcrun simctl io booted screenshot shot.png        # PNG of the screen
xcrun simctl io booted recordVideo demo.mp4       # screen recording
xcrun simctl launch --console booted <bundle id>  # app stdout and stderr
xcrun simctl spawn booted log stream --predicate 'subsystem == "<your subsystem>"'
```

- In a UI test, `app.debugDescription` prints the element tree. Xcode's Accessibility Inspector shows what each element exposes.
- Log with a subsystem and category (`Logger`) so a predicate can pick out your app's lines.
- `xcodebuild test -resultBundlePath ...` produces an `.xcresult` with screenshots and logs from the run.

### 5.5 Pitfalls

- **The runtime has to match the Xcode SDK.** `xcodebuild` reports "iOS X is not installed" and finds no destinations if the simulator runtime for the installed SDK isn't downloaded. The platform can be roughly 8 GB. Install it in Xcode's Settings under Components before planning a CI run.
- **The simulator shares the Mac's network.** An app can reach a server on the Mac as `localhost`, unlike the Android emulator, which needs `10.0.2.2`.
- **The simulator is not a device.** Push delivery, camera, biometrics and some hardware features are limited or simulated. Say in the report what was not covered.
- **Hardware keyboard.** If the simulator is set to use the Mac's keyboard, the software keyboard doesn't appear, which changes layout and sometimes hides issues.
- **Permission dialogs** are system UI. Pre-grant them with `simctl privacy`, or handle them in a UI test with an interruption monitor.
- **Identifiers on containers.** In SwiftUI, an identifier on a combined container can replace its children's identifiers. If a child "disappears" from the tree, check the grouping.
- **Tap targets and `contentShape`.** A tappable view with `onTapGesture` may be reported as a plain element. Add the button trait so it is findable and its role is clear.

---

## 6. Android and iOS side by side

| Concern | Android | iOS |
|---|---|---|
| Label for people | `contentDescription` | `accessibilityLabel` |
| Id for machines | `testTag` / `android:id` (`resource-id`) | `accessibilityIdentifier` |
| Expose a gesture as an action | `customActions` in semantics | `accessibilityAction(named:)` |
| Reach the host's server | `10.0.2.2` or `adb reverse` | `localhost` |
| Cleartext HTTP in debug | Network security config | App Transport Security exception |
| Reset the app | `pm clear` | `uninstall` then `install` |
| Kill the process | `am force-stop` | `simctl terminate` |
| Wait for boot | `sys.boot_completed` | `simctl bootstatus -b` |
| Skip first-run prompts | `install -g`, `pm grant` | `simctl privacy grant` |
| Deep link | `am start -a VIEW -d` | `simctl openurl` |
| UI tree as text | `uiautomator dump`, `android layout` | UI test `debugDescription`, Accessibility Inspector |
| Tap and type from a script | `adb shell input` | UI tests, a harness tool, or a third-party driver. Not `simctl` |
| Screenshot | `screencap` | `simctl io ... screenshot` |
| App logs | `logcat` | `launch --console`, `log stream` |
| Native UI test framework | Compose tests, Espresso, UI Automator | XCUITest |
| One flow for both platforms | Maestro, with the package name as `appId` | Maestro, with the bundle id as `appId` |
| Appearance and font size | `cmd uimode night`, `font_scale` | `simctl ui appearance`, `content_size` |
| Animations off | System settings | App flag in test mode |

---

## 7. The android/skills repository

[github.com/android/skills](https://github.com/android/skills) is a public Google repository (Apache-2.0) of "AI-optimized, modular instructions and resources, to help agents better understand and execute specific patterns" for Android development. Each skill is a folder with a `SKILL.md` that an agent loads when the task matches.

### 7.1 What it gives you

- **Development:** current, vendor-written procedures for common Android work (migrations, performance, adaptive UI, build upgrades), so an agent doesn't have to work from stale training data.
- **Validation:** a testing-strategy skill, and an official `android` CLI skill that teaches an agent how to inspect and drive a device, including a journey format.

### 7.2 Installing

From the repository README (not run here):

- **Android CLI:** `android skills add <name> --project=.` installs one skill into the current project. `android skills add --all` installs all of them for detected agents.
- **Claude Code:** `/plugin marketplace add android/skills`, then `/plugin install android-skills@android-skills`.
- **Codex:** `codex plugin marketplace add android/skills`, then `codex plugin add android-skills@android-skills`.

Agents activate the relevant skill on their own. The README's example prompt is "Make my app UI edge-to-edge."

### 7.3 Skills most relevant to development and validation

The descriptions below come from each skill's `SKILL.md` front matter and body. I read them but did not run them.

| Skill | What it does | How it helps |
|---|---|---|
| `devtools/android-cli` | Installs and teaches the `android` CLI: SDK management, project creation, emulators, running apps, a JSON UI tree (`android layout`), screenshots (`android screen capture`, with `--annotate` and `screen resolve`), docs search, and skill management. Includes interaction rules and a journey format | Validation: the agent gets a supported way to see and drive an emulator |
| `testing/testing-setup` | Analyses an app's test setup and builds a strategy: dependency injection and fakes, unit tests, Compose or Espresso UI tests (run under Robolectric where possible), screenshot tests, a small number of end-to-end tests, coverage | Validation: sets up the layers underneath a journey, so the journey doesn't carry all the load |
| `jetpack-compose/jetpack-compose-performance` | Diagnoses and fixes recomposition overhead, dropped frames and lag in Compose UI | Development, and validation of smoothness |
| `jetpack-compose/adaptive` | Makes UI adapt to phones, tablets, foldables, desktop and more, including window sizes and keeping state across configuration changes | Development, and a source of window-size scenarios to test |
| `system/edge-to-edge` | Migrates to edge-to-edge and fixes controls hidden behind system bars or the keyboard | Development, and a common cause of "tap lands on nothing" |
| `performance/anr-audit-and-fix` | Scans code for ANR risks and diagnoses ANR stack dumps | Validation of responsiveness |
| `performance/r8-analyzer` | Reviews R8 keep rules for redundancy and over-breadth | Development: release-build size and correctness |
| `profilers/android-profiler` | Records and analyses traces (CPU, memory, jank, startup, battery) | Validation of performance regressions |
| `build-system/agp/agp-9-upgrade` | Upgrades a project to Android Gradle Plugin 9 (not for Kotlin Multiplatform) | Development |

The repository also contains these directories, which I have **not** read: `camera/camerax`, `cars/android-for-cars-parked-apps`, `device-ai`, `identity`, `jetpack-compose/migration/migrate-xml-views-to-jetpack-compose`, `jetpack-compose/theming/styles`, `media/media3-cast-integration`, `navigation`, `play`, `security`, `tv/leanback-to-compose-tv-migration`, `wear` and `xr`. Check the repository for what each one covers.

### 7.4 How the `android-cli` skill maps to this guide

The skill's approach matches the practices above, which is a good sign. Its rules:

- Use `android layout` as the **primary** way to examine the app (a JSON tree with `text`, `resource-id`, `content-desc`, `interactions`, `state`, `bounds` and `center`). Use screenshots as the **secondary** way, for images, WebViews and visual checks.
- `android screen capture --annotate` overlays numbered boxes on elements, and `android screen resolve` turns a number into coordinates. This helps when an element is missing from the tree, which is exactly what happens when an app has poor labels.
- Make sure a text field is `FOCUSED` before typing, scroll slowly, and wait and re-read the layout when content is slow to load.
- Input still goes through `adb shell input`.

If you can use the official CLI, prefer it to writing your own UI-tree parser. It does what a `uiautomator` wrapper does, with less custom code to maintain. (In the project in the appendix a small parser was written instead, because the CLI wasn't installed.)

### 7.5 The skill's journey format

The CLI skill defines a **journey**: an XML file of ordered `<action>` elements in plain language ("Tap the Home icon", "Verify that the app is on its Home screen"). The agent executes each one literally and writes a Markdown result file with commands, screenshots and a pass or fail mark per action. A journey fails if any action fails, or if the app crashes or freezes.

This is a different style of test from a script. See [section 9](#9-agent-judged-versus-scripted-validation).

### 7.6 Caveats

- **Skills are instructions that an agent will follow.** Treat them like code you run: review what you install, prefer project-scoped installs (`--project`), and watch for changes. The skills carry `last-updated` dates in 2026, so they change often.
- **The repository does not accept public contributions** at the moment; feedback goes through issues.
- **Journeys judge "visible state" from the screen only.** They don't query your backend. Add server-side checks yourself (see [3.5](#35-verify-against-the-source-of-truth)).
- **Agent-judged results vary.** The same journey can read slightly differently between runs. Use scripts where you need identical results every time.
- **Skills don't replace app-side readiness.** Labels, identifiers and a reset path still decide how well any agent does.

---

## 8. Maestro: one flow language for both platforms

[Maestro](https://github.com/mobile-dev-inc/maestro) is an open-source (Apache-2.0) UI automation tool for mobile and web. You write a **flow** as a YAML list of commands (`launchApp`, `tapOn`, `inputText`, `assertVisible`, `swipe`, ...) and run it with `maestro test`. It drives Android emulators and devices and iOS **simulators** (its README says physical iOS devices are not supported yet). It works from outside the app, through the accessibility tree and device-level input, and waits for the screen to settle on its own, so flows contain no sleeps. It ships a free visual editor (Maestro Studio, not open source), a paid cloud service, and an MCP server.

Everything below marked "verified" was run with Maestro 2.11.0 against the Android app in this project. Statements about iOS come from its documentation.

### 8.1 What it changes in this guide

The principles in [section 3](#3-principles-that-apply-to-both-platforms) don't change. These do:

| Topic | Without Maestro | With Maestro |
|---|---|---|
| Driving | A parser plus `adb input` on Android, an XCUITest target on iOS | One tool and one syntax on both |
| Waiting | Your own polling loop | Built in, plus `extendedWaitUntil` for longer waits |
| Finding elements | Whatever your parser supports | Selectors by visible text, `id`, position (`index`), state (`checked`, `enabled`, `focused`, `selected`) and relation (`below`, `childOf`). `text` and `id` are **regular expressions** |
| Labels and identifiers | Matter to any tool | Matter more, because one flow can serve two apps: **keep label wording and identifiers the same on both platforms**. Its docs advise visible text first, and identifiers for icons, images and translated apps |
| Compose test tags | Need `testTagsAsResourceId` to show as resource ids | Same: `id` selects by resource id, so it needs that flag. Text and `contentDescription` need nothing extra |
| Server checks | Shell, SQL | Flows can also call HTTP from JavaScript (`http.get`, `http.post`, `http.request`, `json()`) to set up or verify backend state. Not used here: the shell script keeps this job |
| Reports | Your own | `--format JUNIT` or `HTML`, `--test-output-dir`, `takeScreenshot`, `startRecording` |
| Agents | `adb` or a harness tool | The `maestro mcp` server (see [8.5](#85-with-an-agent-the-maestro-mcp-server)) |

### 8.2 What was verified on Android

- `tapOn: "Complete Walk the dog"` found the checkbox through its `contentDescription`. A selector's `text` matches an element's label as well as its visible text.
- `checked: true` and `checked: false` filter the elements. The matching assertion passes and its opposite fails.
- `{text: "Complete .*", index: N}` picks the Nth match. `assertNotVisible` at index N proves there are no more than N rows, and `assertVisible` at N-1 proves there are at least N. Both directions fail when they should (an extra row, a missing row).
- `swipe` with `from: {text: ...}` and `direction: LEFT` performed the swipe-to-delete on the first try. `stopApp` then `launchApp` gave a cold start. A swipe from 25% to 65% of the screen height did pull-to-refresh.
- `-e KEY=VALUE` on the command line becomes `${KEY}` in the flow, including in the `appId` header. Because selectors are regexes, text like `Plan (v1.0) [beta]` has to be escaped before it is used as a selector. A wrong value failed the assertion, so the substitution is real. The CLI log prints the variables unexpanded, which is cosmetic.
- Text with a line break needs `(?s)` for `.*` to match across it (the empty-state hint has one).
- A failing assertion exits with code 1 and names the assertion.

### 8.3 A pattern worth copying: generate the expected screen from the server

The Maestro driver in this project never writes the expected screen by hand. After each step, a small `jq` program (`scripts/e2e/maestro/screen.jq`) turns the server's actual list of todos into a flow that asserts:

- the "N open" counter,
- one row per todo, with its checked state,
- each todo's notes,
- and **no further rows** (`assertNotVisible` at index N).

The server is the source of truth, so the check can't drift from the data, and an extra, missing or stale row fails it. Generating assertions from the source of truth is a good fit for any tool, not only Maestro.

### 8.4 Costs and cautions

- **Speed.** Each `maestro test` is a separate process. The journey makes 24 of them and took 238 s, against 146 s for the `adb` driver. Fewer, larger flows are faster, but this journey needs the script to act between steps.
- **Auto-waiting can hide slowness.** A screen that takes ten seconds can still pass. Set explicit timeouts where speed matters.
- **Java.** It needs Java 17 or higher, and its docs recommend 17 or 21 because very new versions can misbehave. Pin `JAVA_HOME` for the command if your default is newer.
- **Telemetry.** Analytics, the update check and an AI-analysis notice each have an environment switch (`MAESTRO_CLI_NO_ANALYTICS`, `MAESTRO_DISABLE_UPDATE_CHECK`, `MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED`). Even with analytics off, it creates `~/.maestro/` with a small `analytics.json` (a random id and `enabled: false`) and a `deps` folder of helper tools.
- **AI features.** It has an `assertWithAI` command and an `--analyze` option, both marked beta. They weren't used. Review them against your data policy first.
- **Black box.** It can't read your app's logs or internals, so exposed state ([3.2](#32-expose-state)) and server checks still matter.
- **Gestures.** `swipe` worked, but the documentation I read doesn't say whether Maestro can trigger a custom accessibility action. Keep the non-gesture path ([3.3](#33-gestures-need-a-non-gesture-path)).
- **iOS.** Simulators only. Not run here.

### 8.5 With an agent: the Maestro MCP server

`maestro mcp` starts an MCP server that ships inside the CLI. Its tools are `list_devices`, `inspect_screen` (the screen's element tree as compact JSON), `take_screenshot`, `run` (execute inline YAML or flow files), `cheat_sheet`, and cloud tools that need a Maestro account. An agent can explore a screen with `inspect_screen` and `run`, then save the YAML it wrote into the repo as a regression flow. That matches the rhythm in [section 9](#9-agent-judged-versus-scripted-validation). The MCP server was **not run here**; the flows in this project were run directly with the CLI.

### 8.6 Choosing a driver

| | `adb` + a parser | Maestro | In-process tests (Compose, Espresso, XCUITest) |
|---|---|---|---|
| Install | Nothing beyond the SDK | The CLI and a JVM | Part of your test setup |
| Platforms | One per script | Android and iOS (simulators), web | One per framework |
| Speed | Fast | Slower: a process per call | Fastest |
| Waiting | You write it | Built in | Built in |
| Readability | Code | YAML that a non-developer can review | Code |
| Best for | Zero-dependency checks, full control | One journey on both platforms, agent-written flows | Screens and components, the bulk of the test suite |

A split that works well, and the one used here: keep orchestration (starting the backend, resetting data, server checks, the report) in a script, and use the driver only for the screen. Swapping drivers then touches ten functions and nothing else.

---

## 9. Agent-judged versus scripted validation

| | Agent-judged journey (plain-language steps) | Scripted journey (code) |
|---|---|---|
| Written as | "Tap Add, type a title, verify it appears" | Shell, Kotlin or Swift using labels and polling |
| Strength | Cheap to write, adapts to small UI changes, good at spotting oddities a script wouldn't check | Repeatable, fast, exact assertions, runs unattended in CI |
| Weakness | Varies run to run, slower, costs model time, loosely specified assertions | Brittle when the UI changes, costs effort to write |
| Verifies | What the screen shows | The screen **and** the server, exactly |
| Best for | Exploring a new feature, smoke checks, finding what to automate | Regression, release gates, anything you want proven the same way every time |

A practical rhythm: let an agent explore a new screen with a journey, then turn what it found into a scripted check. Keep the scripted ones as the gate.

Maestro flows ([section 8](#8-maestro-one-flow-language-for-both-platforms)) sit in between: plain YAML that a person can review, deterministic like a script, and easy for an agent to write through its MCP server.

Keep most tests low in the stack. A common guideline (also in the `testing-setup` skill) is that end-to-end journeys should be a small share of all tests, around 5%. Unit tests with fakes for the network, and UI tests of individual screens, carry the rest, and they are faster and less flaky.

---

## 10. Checklists

### App readiness

- [ ] Every interactive element has a descriptive label (from its data) and a unique identifier
- [ ] Loading, empty, content and error states are distinct and identifiable
- [ ] Toggles, selections, counters and messages are readable as text or state
- [ ] Every gesture has an accessibility action or a visible alternative
- [ ] If one flow will serve both platforms, labels and identifiers use the same wording on Android and iOS
- [ ] A debug flavor points at a local or mock server; cleartext is allowed only to local hosts
- [ ] The app can start clean: no mandatory onboarding, sign-in or prompts in debug builds
- [ ] Debug-only affordances are absent from release builds
- [ ] Key events and errors are logged with a consistent tag, with no secrets

### Environment readiness

- [ ] A dedicated emulator or simulator with no personal accounts
- [ ] A server you can reset, query and break on demand (or a mock with those switches)
- [ ] Animations off, runtime and SDK versions matching, devices pinned by name or serial
- [ ] One command to run the journey, with an honest exit code
- [ ] Ports checked before starting, and only your own processes stopped

### Every run

- [ ] Start from an empty server and cleared app data
- [ ] Check the screen **and** the server after each step
- [ ] Change something on the server while the app is closed, then check it appears on reopen
- [ ] Kill the process for "close", don't only background it
- [ ] Poll for conditions, no fixed sleeps, no coordinates
- [ ] Capture a screenshot, the server state and the logs for each step
- [ ] Write a report with commit, device, OS and server details
- [ ] Prove the test can fail by breaking an expectation once

---

## Appendix A: a worked example

The practices above were developed while building a small ToDo app (an Android client, an iOS client, a Spring Boot backend and a WireMock mock, all from one OpenAPI contract) and validating it with an agent. This appendix is specific to that project.

**What exists**

- `scripts/e2e/android-journey.sh` drives the real Android app on an emulator through twelve steps (create two todos, complete one, close, reopen, delete one, complete the other, add a third, close, reopen), then an extra phase where the server goes away and comes back. After every step it checks the screen and the server.
- The script owns the backend lifecycle, data reset, server checks and the report. **The screen is driven by one of two interchangeable drivers**: `driver-adb.sh` (with `ui.py`, a small `uiautomator` parser) or `driver-maestro.sh` (eight YAML flows in `scripts/e2e/maestro/` plus the generated "screen matches server" flow). `lib.sh` holds the waiting, assertion and report helpers.
- `make e2e-android` runs it. `E2E_TARGET=memory|postgres|mock` chooses the server, `E2E_DRIVER=adb|maestro` chooses the driver, and `E2E_PUBLISH=1` refreshes the published report (`docs/e2e/android-journey/` for `adb`, `docs/e2e/android-journey-maestro/` for Maestro).
- Both drivers pass against all three servers:

| Driver | In-memory backend | PostgreSQL (backend restarted mid-journey) | WireMock mock |
|---|---|---|---|
| `adb` | 46 checks, 146 s | 48 checks, 148 s | 46 checks, 135 s |
| Maestro | 46 checks, 238 s | 48 checks, 236 s | 46 checks, 222 s |

- A deliberately wrong expectation made the journey fail with exit code 1, a report ending at that step, and a screenshot. For the `adb` driver this was tested before the refactor, with a wrong server expectation. For Maestro it was an expected "open" count that was off by one. Maestro's exact-row check was also confirmed to fail both for an extra row and for a missing row.

**What the practices looked like in practice**

- **Labels versus identifiers.** On Android the checkbox label is built from the todo's title (`"Complete ${todo.title}"`), so every row has a distinct label, and a `testTag` carries the id. On the iOS branch the checkbox label is the same on every row ("Mark as done") and the identifier carries the id, which works for automation but gives a screen reader user the same words on every row. Putting the title in the iOS label would improve both.
- **The label was missing at first.** The Android checkbox had no label, so it couldn't be told apart from its neighbours. Adding one fixed automation and accessibility together.
- **The server-side edit while the app was closed** (steps 6 and 11) is what makes steps 7 and 12 a real test of "state is retrieved from the server".
- **Swipe-to-delete** was the flakiest step for the `adb` driver and needed a retry loop. Maestro's swipe worked on the first attempt in all four passing runs (its driver allows one retry, which was never used). A "Delete" accessibility action is still the recommended fix and has not been added.
- **A port check bug.** The script's first "port in use" check counted the emulator's lingering client connections and refused to start. Checking for listeners only fixed it.
- **The iOS session** found that `xcodebuild` had no destinations until the iOS 26.5 simulator platform was installed. Its unit tests ran on macOS, and the app ran in the Simulator by hand.
- **Maestro versus `adb`.** Same journey, same checks, about the same amount of code: roughly 190 lines for the `adb` driver and parser, and roughly 100 lines of shell and `jq` plus 60 lines of YAML for Maestro. Maestro was slower (238 s against 146 s) because each of its 24 invocations starts a JVM. What it gave was shorter, more readable steps (a flow reads like the user's actions), built-in waiting, and a way to assert an exact row count without parsing the screen dump.
- **Maestro found the checkbox by its label.** The Android label `"Complete <title>"` is what made `tapOn` work. The iOS checkbox says "Mark as done" on every row (the todo's id is only in its identifier), so the same flow could not be reused on iOS without per-platform branches. Aligning the wording is a small app change that has not been made.
- **Not covered:** the iOS app has no scripted journey yet, and Maestro on iOS and its MCP server were not run.

---

## References

- android/skills: <https://github.com/android/skills>
- Android Debug Bridge: <https://developer.android.com/studio/command-line/adb>
- Emulator command line: <https://developer.android.com/studio/run/emulator-commandline>
- Compose testing: <https://developer.android.com/develop/ui/compose/testing>
- Accessibility testing on Android: <https://developer.android.com/guide/topics/ui/accessibility/testing>
- UI Automator: <https://developer.android.com/training/testing/other-components/ui-automator>
- UI tests with XCTest: <https://developer.apple.com/documentation/xctest/user_interface_tests>
- `XCUIApplication`: <https://developer.apple.com/documentation/xctest/xcuiapplication>
- SwiftUI accessibility modifiers: <https://developer.apple.com/documentation/swiftui/view-accessibility>
- Accessibility (Apple): <https://developer.apple.com/documentation/accessibility>
- Running an app in Simulator: <https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device>
- Maestro: <https://github.com/mobile-dev-inc/maestro>
- How Maestro works: <https://docs.maestro.dev/get-started/how-maestro-works>
- Maestro and Jetpack Compose: <https://docs.maestro.dev/get-started/supported-platform/android/jetpack>
- Maestro and SwiftUI: <https://docs.maestro.dev/get-started/supported-platform/ios/swiftui>
- Maestro selectors: <https://docs.maestro.dev/maestro-flows/flow-control-and-logic/how-to-use-selectors>
- Maestro HTTP requests in flows: <https://docs.maestro.dev/maestro-flows/javascript/make-http-requests>
- Maestro MCP server: <https://docs.maestro.dev/get-started/maestro-mcp>
- Maestro CLI commands and options: <https://docs.maestro.dev/maestro-cli/maestro-cli-commands-and-options>
- Maestro known issues: <https://docs.maestro.dev/extra-materials/troubleshooting/known-issues>
- RFC 9457, Problem Details for HTTP APIs: <https://www.rfc-editor.org/rfc/rfc9457>
