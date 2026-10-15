#!/usr/bin/env bash
set -uo pipefail

WORKER_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT=8799
BASE="http://127.0.0.1:$PORT"
STATS_KEY_VALUE=smoketest
KNOWN_SOURCE=com.guitaripod.embr
APP_ID="9$(date +%s)"
FAILURES=0
SERVER_PID=""
SERVER_LOG="$(mktemp "${TMPDIR:-/tmp}/midgar-smoke-server.XXXXXX")"
MIGRATE_LOG="$(mktemp "${TMPDIR:-/tmp}/midgar-smoke-migrate.XXXXXX")"

kill_tree() {
  local pid="$1" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    kill_tree "$child"
  done
  kill "$pid" 2>/dev/null
}

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill_tree "$SERVER_PID"
    wait "$SERVER_PID" 2>/dev/null
  fi
  rm -f "$MIGRATE_LOG"
  wrangler kv key delete catalog --binding MIDGAR --local >/dev/null 2>&1
  if [ "$FAILURES" -eq 0 ]; then
    rm -f "$SERVER_LOG"
  else
    printf 'dev server log kept at %s\n' "$SERVER_LOG" >&2
  fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

status_is() {
  local expected="$1"
  shift
  [ "$(curl -s -o /dev/null -w '%{http_code}' "$@")" = "$expected" ]
}

post_event() {
  status_is "$1" -X POST -H 'content-type: application/json' --data "$2" "$BASE/v1/event"
}

stats_value() {
  curl -s -H "authorization: Bearer $STATS_KEY_VALUE" "$BASE/v1/stats?$1" | node -e '
    let data = "";
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => {
      const totals = JSON.parse(data).totals || {};
      const row = totals[process.argv[1]] || {};
      process.stdout.write(String(row[process.argv[2]] || 0));
    });
  ' "$2" "$3" 2>/dev/null
}

stats_equals() {
  local query="$1" key="$2" event="$3" expected="$4" attempt
  for attempt in $(seq 1 40); do
    if [ "$(stats_value "$query" "$key" "$event")" = "$expected" ]; then return 0; fi
    sleep 0.25
  done
  return 1
}

impression_counts_two() {
  post_event 204 "{\"event\":\"impression\",\"appId\":\"$APP_ID\",\"source\":\"$KNOWN_SOURCE\"}" &&
    stats_equals "by=app" "$APP_ID" impression 2
}

tap_with_source_and_storefront() {
  post_event 204 "{\"event\":\"tap\",\"appId\":\"$APP_ID\",\"source\":\"$KNOWN_SOURCE\",\"storefront\":\"US\"}"
}

catalog_has_apps() {
  status_is 200 "$BASE/v1/catalog" &&
    curl -s "$BASE/v1/catalog" | node -e '
      let data = "";
      process.stdin.on("data", (chunk) => (data += chunk));
      process.stdin.on("end", () => process.exit(Array.isArray(JSON.parse(data).apps) ? 0 : 1));
    '
}

server_ready() {
  local attempt
  for attempt in $(seq 1 120); do
    if curl -fsS "$BASE/health" >/dev/null 2>&1; then return 0; fi
    kill -0 "$SERVER_PID" 2>/dev/null || return 1
    sleep 1
  done
  return 1
}

cd "$WORKER_DIR" || exit 1
printf 'STATS_KEY=%s\n' "$STATS_KEY_VALUE" > .dev.vars

if wrangler d1 migrations apply midgar-events --local >"$MIGRATE_LOG" 2>&1; then
  pass "d1 migrations apply --local"
else
  fail "d1 migrations apply --local"
  cat "$MIGRATE_LOG" >&2
  exit 1
fi

wrangler dev --local --test-scheduled --port "$PORT" >"$SERVER_LOG" 2>&1 </dev/null &
SERVER_PID=$!

if server_ready; then
  pass "GET /health returns 200"
else
  fail "GET /health returns 200"
  tail -n 40 "$SERVER_LOG" >&2
  exit 1
fi

check "valid event returns 204" post_event 204 "{\"event\":\"impression\",\"appId\":\"$APP_ID\",\"source\":\"$KNOWN_SOURCE\"}"
check "invalid event returns 400" post_event 400 "{\"event\":\"bogus\",\"appId\":\"$APP_ID\",\"source\":\"$KNOWN_SOURCE\"}"
check "event without source returns 400" post_event 400 "{\"event\":\"impression\",\"appId\":\"$APP_ID\"}"
check "event from a bundle id not in the catalog returns 400" post_event 400 "{\"event\":\"impression\",\"appId\":\"$APP_ID\",\"source\":\"com.example.host\"}"
check "portal_open with appId 0 returns 204" post_event 204 "{\"event\":\"portal_open\",\"appId\":\"0\",\"source\":\"$KNOWN_SOURCE\"}"
check "two events with same dimensions give n=2 by app" impression_counts_two
check "event with source and storefront returns 204" tap_with_source_and_storefront
check "source dimension shows the tap" stats_equals "by=source&app=$APP_ID" "$KNOWN_SOURCE" tap 1
check "storefront dimension shows lowercase us" stats_equals "by=storefront&app=$APP_ID" us tap 1
check "stats without key returns 401" status_is 401 "$BASE/v1/stats"
check "stats rejects ?key= query with 401" status_is 401 "$BASE/v1/stats?key=$STATS_KEY_VALUE"
check "stats accepts bearer header" status_is 200 -H "authorization: Bearer $STATS_KEY_VALUE" "$BASE/v1/stats"
check "catalog returns 200 with apps array" catalog_has_apps

HELIA=com.guitaripod.helia
SCHEDULED_URL="$BASE/__scheduled?cron=17+*/6+*+*+*"

catalog_override_json() {
  python3 -I - "$1" <<'PY'
import json
import sys

with open("catalog.json") as handle:
    document = json.load(handle)
document["apps"] = [app for app in document["apps"] if app["bundleId"] != "com.guitaripod.helia"]
if sys.argv[1] != "":
    document["hide"] = sys.argv[1].split(",")
print(json.dumps(document))
PY
}

put_catalog_override() {
  wrangler kv key put catalog "$(catalog_override_json "$1")" --binding MIDGAR --local >/dev/null 2>&1
}

trigger_scheduled() {
  curl -fsS "$SCHEDULED_URL" >/dev/null 2>&1
}

catalog_json() {
  curl -s "$BASE/v1/catalog"
}

helia_is_discovered_and_curated_unchanged() {
  catalog_json | node -e '
    let data = "";
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => {
      const apps = JSON.parse(data).apps;
      const curated = JSON.parse(require("fs").readFileSync("catalog.json", "utf8")).apps.filter((a) => a.bundleId !== process.argv[1]);
      const helia = apps.find((a) => a.bundleId === process.argv[1]);
      const unchanged = curated.every((c) => JSON.stringify(apps.find((a) => a.bundleId === c.bundleId)) === JSON.stringify(c));
      process.exit(helia && helia.auto === true && curated.length === 15 && unchanged ? 0 : 1);
    });
  ' "$HELIA"
}

discovered_has_many_apps() {
  curl -s "$BASE/v1/discovered" | node -e '
    let data = "";
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => process.exit(JSON.parse(data).apps.length > 10 ? 0 : 1));
  '
}

helia_is_hidden() {
  catalog_json | node -e '
    let data = "";
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => {
      const apps = JSON.parse(data).apps;
      process.exit(apps.length === 15 && !apps.some((a) => a.bundleId === process.argv[1]) ? 0 : 1);
    });
  ' "$HELIA"
}

check "kv catalog override without helia is written" put_catalog_override ""
check "scheduled handler runs" trigger_scheduled
check "catalog gains helia with auto true and keeps the 15 curated entries" helia_is_discovered_and_curated_unchanged
check "discovered returns more than 10 apps" discovered_has_many_apps
check "kv catalog override with hide is written" put_catalog_override "$HELIA"
check "hide removes the discovered entry" helia_is_hidden

exit $((FAILURES > 0))
