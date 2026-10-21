#!/usr/bin/env bash
# Shared helpers for the end-to-end journeys. Sourced by the journey scripts, never run directly.
# Written for macOS's bash 3.2: no associative arrays, mapfile or ${var,,}.

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$E2E_DIR/../.." && pwd)"

ANDROID_SDK="${ANDROID_SDK:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
export ADB="${ADB:-$ANDROID_SDK/platform-tools/adb}"
EMULATOR="${EMULATOR:-$ANDROID_SDK/emulator/emulator}"
JDK21_HOME="${JDK21_HOME:-/opt/homebrew/opt/openjdk@21}"
CONTAINER="${CONTAINER:-podman}"
UI=(python3 -I "$E2E_DIR/ui.py")

# ---- run state -----------------------------------------------------------------------------------
FAILED_AT=""
STEP_NO=0
SHOT_NO=0
CHECKS=0
START_SECONDS=$SECONDS

log() { printf '%s\n' "$*" >&2; }
die() { # a setup problem: record the reason in the report, then stop
  log "error: $*"
  FAILED_AT="$*"
  if [[ -n "${BODY:-}" ]]; then md "- ❌ **$***"; fi
  exit 1
}

# ---- the report ------------------------------------------------------------------------------------
# Steps append Markdown to $BODY as they go; the EXIT trap puts a header on top. That way a failed
# run still produces a report that ends where it failed.

md() { printf '%s\n' "$@" >> "$BODY"; }

section() { # section <title> [description]
  log ""; log "== $1"
  md "" "## $1" ""
  if [[ -n "${2:-}" ]]; then md "$2" ""; fi
}

step() { # step <n> <title> [what the script does]
  STEP_NO=$1
  log ""; log "Step $1: $2"
  md "" "## Step $1 — $2" ""
  if [[ -n "${3:-}" ]]; then md "_${3}_" ""; fi
}

pass() { CHECKS=$((CHECKS + 1)); md "- ✅ $1"; log "  ok   $1"; }

fail() {
  md "- ❌ **$1**"; log "  FAIL $1"
  FAILED_AT="Step $STEP_NO: $1"
  shot failure "Screen at the moment of failure" 2>/dev/null || true
  "$ADB" logcat -d -t 80 > "$OUT/logcat-tail.txt" 2>/dev/null || true
  exit 1
}

expect_eq() { # expect_eq <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected \`$2\`, got \`$3\`)"; fi
}

# ---- waiting -----------------------------------------------------------------------------------------
wait_for() { # wait_for <seconds> <command...>: poll until the command succeeds
  local deadline=$((SECONDS + $1)); shift
  until "$@"; do
    if (( SECONDS >= deadline )); then return 1; fi
    sleep 0.5
  done
}

# ---- driving the app ---------------------------------------------------------------------------------
ui_exists() { "${UI[@]}" exists "$@"; }
ui_gone() { ! "${UI[@]}" exists "$@"; }

ui_tap() { # ui_tap <matchers...>
  local xy; xy=$("${UI[@]}" center "$@") || return 1
  # shellcheck disable=SC2086
  "$ADB" shell input tap $xy
}

ui_type() { "$ADB" shell input text "${1// /%s}"; }

ui_swipe_left_on() { # swipe the row containing the matched node to the left: a swipe-to-delete
  local xy w h y; xy=$("${UI[@]}" center "$@") || return 1
  read -r w h <<< "$("${UI[@]}" size)"
  y=${xy#* }
  "$ADB" shell input swipe $((w * 92 / 100)) "$y" $((w * 8 / 100)) "$y" 300
}

ui_pull_to_refresh() {
  local w h; read -r w h <<< "$("${UI[@]}" size)"
  "$ADB" shell input swipe $((w / 2)) $((h * 25 / 100)) $((w / 2)) $((h * 65 / 100)) 400
}

app_start() { "$ADB" shell am start -n "$APP_ID/com.example.todo.MainActivity" > /dev/null; }
app_stop() { "$ADB" shell am force-stop "$APP_ID"; }
app_running() { [[ -n "$("$ADB" shell pidof "$APP_ID" | tr -d '\r')" ]]; }
app_gone() { ! app_running; }

shot() { # shot <slug> <alt text>: screenshot into the report
  local name; name=$(printf '%02d-%s' "$SHOT_NO" "$1"); SHOT_NO=$((SHOT_NO + 1))
  "$ADB" exec-out screencap -p > "$OUT/raw/$name.png"
  sips -Z 900 "$OUT/raw/$name.png" --out "$OUT/img/$name.png" > /dev/null
  md "" "<img src=\"img/$name.png\" width=\"270\" alt=\"${2:-$1}\">" ""
}

# ---- the server (source of truth) ----------------------------------------------------------------------
server_json() { curl -fsS "$API/todos"; }
server_titles() { server_json | jq -r '[.[].title] | join(", ")'; }
server_count() { server_json | jq length; }
server_open() { server_json | jq '[.[] | select(.completed | not)] | length'; }
server_field() { # server_field <title> <jq field>
  server_json | jq -r --arg t "$1" ".[] | select(.title == \$t) | .$2"
}
server_id() { server_field "$1" id; }

normalize_todos() { jq -c 'map({title, completed, notes: (.notes // null)})'; }
server_rows() { server_json | normalize_todos; }
ui_rows() { "${UI[@]}" rows | normalize_todos; }
ui_matches_server() { [[ "$(ui_rows)" == "$(server_rows)" ]]; }

snapshot_md() { # the backend's list, as a table in the report
  md "" "Backend (\`GET /todos\`):" "" "| Todo | Done | Notes |" "|---|---|---|"
  if [[ "$(server_count)" == "0" ]]; then
    md "| _(empty)_ | | |"
  else
    server_json | jq -r '.[] | "| \(.title) | \(if .completed then "✅" else "⬜" end) | \(.notes // "") |"' >> "$BODY"
  fi
  md ""
}

assert_ui_matches_server() { # assert_ui_matches_server <what>
  if wait_for 15 ui_matches_server; then
    pass "$1: the screen shows exactly what the server has ($(server_rows))"
  else
    fail "$1: screen and server disagree. Screen: $(ui_rows). Server: $(server_rows)"
  fi
}

assert_open_count() { # the "N open" counter in the top bar
  local want; want=$(server_open)
  if wait_for 10 test "$("${UI[@]}" open-count)" = "$want"; then
    pass "Top bar says \"$want open\""
  else
    fail "Top bar should say \"$want open\" but says \"$("${UI[@]}" open-count) open\""
  fi
}

# ---- user actions the journey repeats ------------------------------------------------------------------
add_todo() { # add_todo <title>
  ui_tap --desc "Add todo" || fail "no \"Add todo\" button on screen"
  wait_for 10 ui_exists --text "New todo" || fail "the editor sheet did not open"
  wait_for 10 ui_exists --cls android.widget.EditText --focused true || fail "the title field never got focus"
  ui_type "$1"
  wait_for 5 ui_exists --text "$1" || fail "typed text \"$1\" did not appear in the field"
  ui_tap --text Save || fail "no Save button"
  wait_for 10 ui_gone --text "New todo" || fail "the editor sheet did not close"
  wait_for 10 ui_exists --desc "Complete $1" || fail "\"$1\" did not appear in the list"
}

complete_todo() { # complete_todo <title>
  ui_tap --desc "Complete $1" || fail "no checkbox for \"$1\""
  wait_for 10 ui_exists --desc "Complete $1" --checked true || fail "checkbox for \"$1\" did not become checked"
}

delete_todo() { # delete_todo <title>: swipe the row away
  local attempt
  for attempt in 1 2 3; do
    ui_swipe_left_on --text "$1" || fail "\"$1\" is not on screen"
    if wait_for 6 ui_gone --desc "Complete $1"; then return 0; fi
  done
  fail "swiping \"$1\" away never removed it"
}
