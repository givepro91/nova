#!/usr/bin/env bash
# Regression guard for nova-gate's Stop nudge. Exits non-zero on first failure.
# Run: bash tests/gate-verify.sh
set -u
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
NUDGE="$NOVA/plugins/nova/hooks/nudge.mjs"
EVID="$NOVA/plugins/nova/hooks/evidence.mjs"
fail() { echo "FAIL: $1"; exit 1; }

echo "== node --check =="
node --check "$NOVA/plugins/nova/hooks/_lib.mjs" || fail "syntax _lib"
node --check "$NUDGE" || fail "syntax nudge"
node --check "$EVID" || fail "syntax evidence"
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

rec() { CLAUDE_PROJECT_DIR= node "$EVID" <<EOF
{"cwd":"$1","session_id":"s1","tool_name":"Bash","tool_input":{"command":"$2"},"tool_response":{"stdout":"$3","stderr":""}}
EOF
}

echo "== evidence: opt-in OFF → no ledger =="
G=$(mkrepo); rec "$G" "pytest -q" "1932 passed"
[ ! -e "$G/.nova/evidence.jsonl" ] || fail "wrote ledger while not opted in"; rm -rf "$G"; echo "  ok"

echo "== evidence: opt-in ON → entry + self-gitignore =="
G=$(mkrepo); mkdir -p "$G/.nova"; touch "$G/.nova/gate.on"
rec "$G" "pytest -q" "1932 passed"
[ -e "$G/.nova/evidence.jsonl" ] || fail "no ledger written"
python3 -c "
import json,sys
e=json.loads(open('$G/.nova/evidence.jsonl').readline())
assert e['cmd']=='pytest -q', e
assert '1932 passed' in e['out'], e
assert e['session']=='s1', e
" || fail "ledger entry malformed"
grep -q '^!gate.on$' "$G/.nova/.gitignore" || fail "self-gitignore missing/wrong"
git -C "$G" add -A -n 2>/dev/null | grep -q 'evidence.jsonl' && fail "ledger not gitignored"
echo "  entry recorded, ledger gitignored, gate.on still committable"

echo "== evidence: kill switch =="
NOVA_GATE_EVIDENCE=0 CLAUDE_PROJECT_DIR= node "$EVID" <<EOF
{"cwd":"$G","tool_input":{"command":"echo x"},"tool_response":{"stdout":"x"}}
EOF
[ "$(wc -l < "$G/.nova/evidence.jsonl")" -eq 1 ] || fail "kill switch ignored"; echo "  ok"

echo "== evidence: rotation caps the ledger =="
python3 -c "
line='{\"ts\":\"t\",\"cmd\":\"c\",\"out\":\"'+('x'*1000)+'\"}'
open('$G/.nova/evidence.jsonl','w').write((line+'\n')*600)   # ~600KB > 512KB threshold
"
rec "$G" "echo rotate" "done"
L=$(wc -l < "$G/.nova/evidence.jsonl")
[ "$L" -le 401 ] || fail "rotation did not cap ($L lines)"
tail -1 "$G/.nova/evidence.jsonl" | grep -q 'echo rotate' || fail "newest entry lost in rotation"
rm -rf "$G"; echo "  ok"

echo ""; echo "ALL PASS"
