#!/usr/bin/env bash
# Regression guard for nova-gate's Stop nudge. Exits non-zero on first failure.
# Run: bash tests/gate-verify.sh
set -u
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
NUDGE="$NOVA/plugins/nova/hooks/nudge.mjs"
fail() { echo "FAIL: $1"; exit 1; }

echo "== node --check =="
node --check "$NOVA/plugins/nova/hooks/_lib.mjs" || fail "syntax _lib"
node --check "$NUDGE" || fail "syntax nudge"
echo "  ok"

mkrepo() { local d; d=$(mktemp -d); git -C "$d" init -q; git -C "$d" config user.email t@t.t; git -C "$d" config user.name t; echo "$d"; }
run() { echo "{\"cwd\":\"$1\"}" | node "$NUDGE"; }   # prints JSON if it blocks, nothing otherwise

echo "== opt-in OFF → silent (no block) =="
G=$(mkrepo); touch "$G/a" "$G/b" "$G/c"
[ -z "$(run "$G")" ] || fail "blocked while not opted in"; rm -rf "$G"; echo "  ok"

echo "== opt-in ON + 3 work files → block =="
G=$(mkrepo); mkdir -p "$G/.nova"; touch "$G/.nova/gate.on" "$G/a" "$G/b" "$G/c"
run "$G" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('decision')=='block' else 1)" || fail "did not block on real work"
echo "  ok"
# and the count must EXCLUDE .nova state (3 work files, not 4)
run "$G" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if '3 file' in d['reason'] else 1)" || fail "state files counted as work"
echo "  state files excluded from count"; rm -rf "$G"

echo "== opt-in ON + only .nova state changed → no block =="
G=$(mkrepo); mkdir -p "$G/.nova"; touch "$G/.nova/gate.on"
[ -z "$(run "$G")" ] || fail "blocked on state-only change"; rm -rf "$G"; echo "  ok"

echo "== opt-in ON + fresh verdict (audited) → no block =="
G=$(mkrepo); mkdir -p "$G/.nova"; touch "$G/.nova/gate.on" "$G/a" "$G/b" "$G/c"
sleep 1; touch "$G/.nova/gate-verdict.json"   # verdict newer than work
[ -z "$(run "$G")" ] || fail "nagged after a fresh audit"; rm -rf "$G"; echo "  ok"

echo ""; echo "ALL PASS"
