#!/usr/bin/env bash
# Screen driver: plain adb for input, `uiautomator dump` (via ui.py) for reading the screen.
# No installs beyond the Android SDK. Sourced by android-journey.sh after lib.sh.
#
# Every driver implements the same functions (the journey only calls these):
#   driver_check, drv_launch_empty, drv_launch_with <title>, drv_close, drv_add_todo <title>,
#   drv_complete_todo <title>, drv_delete_todo <title>, drv_refresh_expect_message <prefix> <description>,
#   drv_assert_row_count <n> <description>, drv_recover_screen <label>, drv_assert_screen <label>

DRIVER_NAME="adb + uiautomator (\`scripts/e2e/ui.py\`)"
DRIVER_SLUG="adb"
UI=(python3 -I "$E2E_DIR/ui.py")

driver_check() {
  command -v python3 > /dev/null || die "python3 is required for the adb driver"
}

# ---- low-level screen access ------------------------------------------------------------------------
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

ui_rows() { "${UI[@]}" rows | normalize_todos; }
ui_matches_server() { [[ "$(ui_rows)" == "$(server_rows)" ]]; }

# ---- the driver interface --------------------------------------------------------------------------------
drv_launch_empty() {
  app_start
  wait_for 30 ui_exists --desc "Add todo" || fail "the app did not reach its main screen"
  wait_for 10 ui_exists --text-re "Nothing to do yet" || fail "the empty-state hint never appeared"
  pass "The app is running and shows its empty state"
}

drv_launch_with() { # drv_launch_with <title that must load from the server>
  app_start
  wait_for 30 ui_exists --desc "Complete $1" || fail "the todos did not load after reopening"
}

drv_close() {
  app_stop
  wait_for 5 app_gone || fail "the app process is still alive"
  pass "The app process is gone"
}

drv_add_todo() { # drv_add_todo <title>
  ui_tap --desc "Add todo" || fail "no \"Add todo\" button on screen"
  wait_for 10 ui_exists --text "New todo" || fail "the editor sheet did not open"
  wait_for 10 ui_exists --cls android.widget.EditText --focused true || fail "the title field never got focus"
  ui_type "$1"
  wait_for 5 ui_exists --text "$1" || fail "typed text \"$1\" did not appear in the field"
  ui_tap --text Save || fail "no Save button"
  wait_for 10 ui_gone --text "New todo" || fail "the editor sheet did not close"
  wait_for 10 ui_exists --desc "Complete $1" || fail "\"$1\" did not appear in the list"
}

drv_complete_todo() { # drv_complete_todo <title>
  ui_tap --desc "Complete $1" || fail "no checkbox for \"$1\""
  wait_for 10 ui_exists --desc "Complete $1" --checked true || fail "checkbox for \"$1\" did not become checked"
}

drv_delete_todo() { # drv_delete_todo <title>: swipe the row away
  local attempt
  for attempt in 1 2 3; do
    ui_swipe_left_on --text "$1" || fail "\"$1\" is not on screen"
    if wait_for 6 ui_gone --desc "Complete $1"; then return 0; fi
  done
  fail "swiping \"$1\" away never removed it"
}

drv_refresh_expect_message() { # drv_refresh_expect_message <message prefix> <description>
  ui_pull_to_refresh
  if wait_for 20 ui_exists --text-re "^$(re_escape "$1")"; then pass "$2"; else fail "no \"$1\" message after pulling to refresh"; fi
}

drv_assert_row_count() { # drv_assert_row_count <n> <description>
  expect_eq "$2" "$1" "$("${UI[@]}" rows | jq length)"
}

drv_recover_screen() { # pull to refresh until the screen matches the server again
  local attempt
  for attempt in 1 2 3; do
    ui_pull_to_refresh
    if wait_for 15 ui_matches_server; then pass "$1: after pulling to refresh the screen matches the server again"; return 0; fi
  done
  fail "$1: the app never recovered after the server came back"
}

drv_assert_screen() { # drv_assert_screen <label>: rows, notes, checked state and the "N open" counter all match the server
  if wait_for 15 ui_matches_server; then
    pass "$1: the screen shows exactly what the server has ($(server_rows))"
  else
    fail "$1: screen and server disagree. Screen: $(ui_rows). Server: $(server_rows)"
  fi
  local want; want=$(server_open)
  if wait_for 10 test "$("${UI[@]}" open-count)" = "$want"; then
    pass "Top bar says \"$want open\""
  else
    fail "Top bar should say \"$want open\" but says \"$("${UI[@]}" open-count) open\""
  fi
}
