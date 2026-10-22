# Turns the server's todo list (GET /todos) into the assertions that describe the screen it should produce:
#   the "N open" counter, one row per todo with its checked state, its notes, and no further rows.
# `text` selectors are regular expressions, so literal text is escaped first.
def re: gsub("(?<c>[\\\\.*+?^${}()|\\[\\]])"; "\\" + .c);
([.[] | select(.completed | not)] | length) as $open
| length as $n
| "appId: ${APP_ID}",
  "---",
  "- assertVisible: \("\($open) open" | @json)",
  (if $n == 0 then "- assertVisible: \("(?s)Nothing to do yet.*" | @json)" else empty end),
  (.[] | "- assertVisible: {text: \("Complete " + (.title | re) | @json), checked: \(.completed)}",
         (if .notes then "- assertVisible: \(.notes | re | @json)" else empty end)),
  "- assertNotVisible: {text: \("Complete .*" | @json), index: \($n)}"
