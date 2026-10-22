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

# ---- run state -----------------------------------------------------------------------------------
FAILED_AT=""
STEP_LABEL="Setup"
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
  STEP_LABEL="$1"
  log ""; log "== $1"
  md "" "## $1" ""
  if [[ -n "${2:-}" ]]; then md "$2" ""; fi
}

step() { # step <n> <title> [what the script does]
  STEP_NO=$1
  STEP_LABEL="Step $1"
  log ""; log "Step $1: $2"
  md "" "## Step $1 — $2" ""
  if [[ -n "${3:-}" ]]; then md "_${3}_" ""; fi
}

pass() { CHECKS=$((CHECKS + 1)); md "- ✅ $1"; log "  ok   $1"; }

fail() {
  md "- ❌ **$1**"; log "  FAIL $1"
  case "$1" in
    "$STEP_LABEL"*) FAILED_AT="$1" ;;
    *) FAILED_AT="$STEP_LABEL: $1" ;;
  esac
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

# ---- the app process (shared by every driver) -------------------------------------------------------------
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

# Literal text -> regular expression matching exactly that text (Maestro selectors are regexes).
re_escape() { printf '%s' "$1" | jq -Rr 'gsub("(?<c>[\\\\.*+?^${}()|\\[\\]])"; "\\" + .c)'; }

snapshot_md() { # the backend's list, as a table in the report
  md "" "Backend (\`GET /todos\`):" "" "| Todo | Done | Notes |" "|---|---|---|"
  if [[ "$(server_count)" == "0" ]]; then
    md "| _(empty)_ | | |"
  else
    server_json | jq -r '.[] | "| \(.title) | \(if .completed then "✅" else "⬜" end) | \(.notes // "") |"' >> "$BODY"
  fi
  md ""
}
