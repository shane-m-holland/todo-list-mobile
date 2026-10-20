#!/usr/bin/env bash
# End-to-end CRUD check against any server that implements the contract: the mock or the backend.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080/api/v1}"
pass=0

check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else
    printf '  FAIL %s (expected %q, got %q)\n' "$1" "$2" "$3"; exit 1
  fi
}

# request <method> <path> [json-body] -> sets $status and $body
request() {
  local out
  out=$(curl -sS -X "$1" "$BASE_URL$2" -H 'Content-Type: application/json' \
    ${3:+-d "$3"} -w $'\n%{http_code}')
  status="${out##*$'\n'}"
  body="${out%$'\n'*}"
}

echo "Smoke testing $BASE_URL"

request GET /todos
check "list returns 200" 200 "$status"
before=$(jq length <<<"$body")

request POST /todos '{"title":"Smoke \"test\" & co","notes":"line 1\nline 2"}'
check "create returns 201" 201 "$status"
id=$(jq -r .id <<<"$body")
check "create echoes title (with escaping)" 'Smoke "test" & co' "$(jq -r .title <<<"$body")"
check "create starts not completed" false "$(jq -r .completed <<<"$body")"
check "create sets timestamps" true "$(jq '(.createdAt|type=="string") and (.updatedAt|type=="string")' <<<"$body")"

request GET /todos
check "list grows by one" $((before + 1)) "$(jq length <<<"$body")"
check "list contains new todo" true "$(jq --arg id "$id" 'any(.id == $id)' <<<"$body")"

request GET "/todos/$id"
check "get returns 200" 200 "$status"
check "get returns notes" $'line 1\nline 2' "$(jq -r .notes <<<"$body")"

request PATCH "/todos/$id" '{"completed":true}'
check "patch returns 200" 200 "$status"
check "patch sets completed" true "$(jq -r .completed <<<"$body")"
check "patch keeps title" 'Smoke "test" & co' "$(jq -r .title <<<"$body")"

request PATCH "/todos/$id" '{"title":"Renamed","notes":""}'
check "patch renames" Renamed "$(jq -r .title <<<"$body")"
check "patch with empty notes clears them" false "$(jq 'has("notes")' <<<"$body")"

request GET "/todos/$id"
check "get reflects patches" 'Renamed true' "$(jq -r '"\(.title) \(.completed)"' <<<"$body")"

request POST /todos '{"title":"   "}'
check "create with blank title returns 400" 400 "$status"
check "400 is a problem document" 400 "$(jq -r .status <<<"$body")"

request PATCH "/todos/$id" '{}'
check "patch with empty body returns 400" 400 "$status"

request DELETE "/todos/$id"
check "delete returns 204" 204 "$status"

request GET "/todos/$id"
check "get after delete returns 404" 404 "$status"

request DELETE "/todos/$id"
check "delete unknown returns 404" 404 "$status"

request GET /todos
check "list shrinks back" "$before" "$(jq length <<<"$body")"

echo "All $pass checks passed."
