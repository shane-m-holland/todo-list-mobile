#!/usr/bin/env bash
# Reset the mock's state and load a few sample todos.
set -euo pipefail

MOCK_URL="${MOCK_URL:-http://localhost:8080}"
API="$MOCK_URL/api/v1"

curl -fsS -X DELETE "$MOCK_URL/__admin/state-extension/contexts" >/dev/null
curl -fsS -X POST "$MOCK_URL/__admin/scenarios/reset" >/dev/null

create() {
  curl -fsS -X POST "$API/todos" -H 'Content-Type: application/json' -d "$1" | jq -r .id
}

create '{"title":"Buy groceries","notes":"Milk, eggs, coffee"}' >/dev/null
create '{"title":"Book dentist appointment"}' >/dev/null
done_id=$(create '{"title":"Renew passport","notes":"Photos are in the desk drawer"}')
curl -fsS -X PATCH "$API/todos/$done_id" -H 'Content-Type: application/json' \
  -d '{"completed":true}' >/dev/null

echo "Seeded $(curl -fsS "$API/todos" | jq length) todos at $API/todos"
