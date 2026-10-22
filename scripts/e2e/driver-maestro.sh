#!/usr/bin/env bash
# Screen driver: Maestro (https://maestro.dev). Each user action is a small YAML flow in maestro/,
# run with `maestro test`. "Does the screen match the server?" is answered by generating a flow from
# the server's actual state and running it, so the expected screen is never written by hand.
# Sourced by android-journey.sh after lib.sh. Same interface as driver-adb.sh.

DRIVER_SLUG="maestro"
MAESTRO_FLOWS="$E2E_DIR/maestro"
MX_N=0
MX_ERROR=""

driver_check() {
  command -v maestro > /dev/null || die "maestro is not installed (brew install mobile-dev-inc/tap/maestro)"
  DRIVER_NAME="Maestro $(maestro_env maestro --version 2> /dev/null | tail -1)"
}

# Maestro needs Java 17 or 21 (very new JDKs can misbehave), and every run here has analytics, the update
# check and the AI-analysis notice switched off. Set per command: nothing is written to a shell profile.
maestro_env() {
  env JAVA_HOME="$JDK21_HOME" \
    MAESTRO_CLI_NO_ANALYTICS=true MAESTRO_DISABLE_UPDATE_CHECK=true MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true \
    "$@"
}

mx() { # mx <name> <flow file> [KEY=VALUE ...]: run one flow. On failure MX_ERROR holds the first failing line.
  local name=$1 flow=$2; shift 2
  MX_N=$((MX_N + 1))
  local tag; tag=$(printf '%03d-%s' "$MX_N" "$name")
  mkdir -p "$OUT/maestro"
  local args=(-e "APP_ID=$APP_ID") kv
  for kv in "$@"; do args+=(-e "$kv"); done
  if maestro_env maestro test --debug-output "$OUT/maestro/$tag" --flatten-debug-output \
      "${args[@]}" "$flow" > "$OUT/maestro/$tag.log" 2>&1; then
    MX_ERROR=""
    return 0
  fi
  MX_ERROR=$(grep -m1 -E "FAILED|Assertion|Error" "$OUT/maestro/$tag.log" | sed 's/^[[:space:]]*//' || true)
  MX_ERROR="${MX_ERROR:-see maestro/$tag.log}"
  return 1
}

# ---- the driver interface --------------------------------------------------------------------------------
drv_launch_empty() {
  mx launch-fresh "$MAESTRO_FLOWS/launch-fresh.yaml" || fail "the app did not reach its empty main screen: $MX_ERROR"
  pass "The app is running and shows its empty state"
}

drv_launch_with() { # drv_launch_with <title that must load from the server>
  mx launch "$MAESTRO_FLOWS/launch.yaml" "WAIT_RE=$(re_escape "$1")" || fail "the todos did not load after reopening: $MX_ERROR"
}

drv_close() {
  mx stop "$MAESTRO_FLOWS/stop.yaml" || fail "could not stop the app: $MX_ERROR"
  wait_for 5 app_gone || fail "the app process is still alive"
  pass "The app process is gone"
}

drv_add_todo() { # drv_add_todo <title>
  mx add-todo "$MAESTRO_FLOWS/add-todo.yaml" "TITLE=$1" "TITLE_RE=$(re_escape "$1")" || fail "adding \"$1\" failed: $MX_ERROR"
}

drv_complete_todo() { # drv_complete_todo <title>
  mx complete-todo "$MAESTRO_FLOWS/complete-todo.yaml" "TITLE_RE=$(re_escape "$1")" || fail "completing \"$1\" failed: $MX_ERROR"
}

drv_delete_todo() { # drv_delete_todo <title>: swipe the row away
  local attempt
  for attempt in 1 2; do
    if mx delete-todo "$MAESTRO_FLOWS/delete-todo.yaml" "TITLE_RE=$(re_escape "$1")"; then return 0; fi
  done
  fail "swiping \"$1\" away never removed it: $MX_ERROR"
}

drv_refresh_expect_message() { # drv_refresh_expect_message <message prefix> <description>
  if mx refresh-message "$MAESTRO_FLOWS/refresh-expect-message.yaml" "MSG_RE=$(re_escape "$1")"; then
    pass "$2"
  else
    fail "no \"$1\" message after pulling to refresh: $MX_ERROR"
  fi
}

drv_assert_row_count() { # drv_assert_row_count <n> <description>
  local n=$1 flow="$OUT/maestro/row-count-$1.yaml"
  mkdir -p "$OUT/maestro"
  {
    echo 'appId: ${APP_ID}'
    echo '---'
    if (( n > 0 )); then echo "- assertVisible: {text: \"Complete .*\", index: $((n - 1))}"; fi
    echo "- assertNotVisible: {text: \"Complete .*\", index: $n}"
  } > "$flow"
  if mx row-count "$flow"; then pass "$2"; else fail "$2 (expected $n rows): $MX_ERROR"; fi
}

drv_assert_screen() { # drv_assert_screen <label>: rows, notes, checked state and the "N open" counter all match the server
  local flow="$OUT/maestro/screen-$((MX_N + 1)).yaml"
  mkdir -p "$OUT/maestro"
  server_json | jq -r -f "$MAESTRO_FLOWS/screen.jq" > "$flow"
  if mx screen "$flow"; then
    pass "$1: the screen shows exactly what the server has ($(server_rows))"
    pass "Top bar says \"$(server_open) open\""
  else
    fail "$1: screen and server disagree ($MX_ERROR). Server: $(server_rows)"
  fi
}

drv_recover_screen() { # pull to refresh until the screen matches the server again
  local attempt flow="$OUT/maestro/recover-screen.yaml"
  mkdir -p "$OUT/maestro"
  for attempt in 1 2 3; do
    mx refresh "$MAESTRO_FLOWS/refresh.yaml" || true
    server_json | jq -r -f "$MAESTRO_FLOWS/screen.jq" > "$flow"
    if mx screen "$flow"; then pass "$1: after pulling to refresh the screen matches the server again"; return 0; fi
  done
  fail "$1: the app never recovered after the server came back: $MX_ERROR"
}
