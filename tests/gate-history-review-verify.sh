#!/usr/bin/env bash
# Regression guard for the gate-history aggregator (`/learn review`) and the
# machine-local `.nova/.gitignore` fix for manual `/gate`. Exits non-zero on first failure.
# Run: bash tests/gate-history-review-verify.sh
set -u
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$NOVA/plugins/nova/scripts/gate-history-review.mjs"
GITIGNORE="$NOVA/plugins/nova/scripts/ensure-nova-gitignore.mjs"
APPEND="$NOVA/plugins/nova/scripts/append-rule.mjs"
T=$(mktemp -d)
fail() { echo "FAIL: $1"; exit 1; }
hash_of() { python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }

echo "== node --check =="
node --check "$REVIEW" || fail "syntax gate-history-review"
node --check "$GITIGNORE" || fail "syntax ensure-nova-gitignore"
echo "  ok"

# ---------------------------------------------------------------------------
# Aggregator: threshold, dedup, legacy inference, malformed lines, read-only
# ---------------------------------------------------------------------------

record() { # record <status> <failure_mode-or-empty> <head>
  python3 -c "
import json, sys
status, mode, head = sys.argv[1], sys.argv[2], sys.argv[3]
claim = {'claim': 'x', 'status': status, 'evidence': 'e', 'severity': 'High'}
if mode:
    claim['failure_mode'] = mode
rec = {'intent': 'i', 'head': head, 'timestamp': 't', 'verdict': 'ISSUES', 'claims': [claim]}
print(json.dumps(rec))
" "$1" "$2" "$3"
}

echo "== 2 occurrences of one mode → observation only, no candidate =="
F="$T/two.jsonl"
{ record unverified verification-evidence-missing h1; record false verification-evidence-missing h2; } > "$F"
node "$REVIEW" "$F" > "$T/two.json" || fail "aggregator failed on 2-record fixture"
python3 -c "
import json
d = json.load(open('$T/two.json'))
assert d['candidates'] == [], d['candidates']
obs = [o for o in d['observations'] if o['failure_mode'] == 'verification-evidence-missing']
assert len(obs) == 1 and obs[0]['occurrences'] == 2, obs
" || fail "2-record boundary wrong"
echo "  ok"

echo "== 3 occurrences of one mode → exactly one candidate with occurrences=3 =="
F="$T/three.jsonl"
{ record unverified verification-evidence-missing h1; record false verification-evidence-missing h2; record unverified verification-evidence-missing h3; } > "$F"
node "$REVIEW" "$F" > "$T/three.json" || fail "aggregator failed on 3-record fixture"
python3 -c "
import json
d = json.load(open('$T/three.json'))
cands = [c for c in d['candidates'] if c['failure_mode'] == 'verification-evidence-missing']
assert len(cands) == 1, d['candidates']
c = cands[0]
assert c['occurrences'] == 3, c
assert c['id'] == 'gate:verification-evidence-missing', c
assert c['proposal'] == '완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.', c
assert len(c['records']) == 3, c
" || fail "3-record threshold/candidate shape wrong"
echo "  ok"

echo "== semantically-identical legacy wording (no failure_mode) merges into one mode =="
F="$T/legacy.jsonl"
python3 -c "
import json
def rec(head, text):
    claim = {'claim': text, 'status': 'unverified', 'evidence': 'e', 'severity': 'High'}
    return json.dumps({'intent': 'i', 'head': head, 'timestamp': 't', 'verdict': 'ISSUES', 'claims': [claim]})
print(rec('h1', 'The required verification was not run; run the exact check and retain its passing output.'))
print(rec('h2', 'No execution evidence exists; capture the passing output after executing the command.'))
print(rec('h3', '검증 명령의 통과 출력이 누락됐다. 명령을 실행하고 통과 출력을 확인한다.'))
" > "$F"
node "$REVIEW" "$F" > "$T/legacy.json" || fail "aggregator failed on legacy fixture"
python3 -c "
import json
d = json.load(open('$T/legacy.json'))
cands = d['candidates']
assert len(cands) == 1, cands
c = cands[0]
assert c['failure_mode'] == 'verification-evidence-missing', c
assert c['occurrences'] == 3, c
assert c['records'] == [
    {'line': 1, 'head': 'h1', 'timestamp': 't', 'claim_indices': [1]},
    {'line': 2, 'head': 'h2', 'timestamp': 't', 'claim_indices': [1]},
    {'line': 3, 'head': 'h3', 'timestamp': 't', 'claim_indices': [1]},
], c['records']
" || fail "legacy wording produced duplicate candidates for one mode"
echo "  ok"

echo "== different causes do NOT merge (each stays its own mode/bucket) =="
F="$T/distinct.jsonl"
{ record unverified verification-evidence-missing h1; record unverified requested-scope-omitted h2; } > "$F"
node "$REVIEW" "$F" > "$T/distinct.json" || fail "aggregator failed on distinct-mode fixture"
python3 -c "
import json
d = json.load(open('$T/distinct.json'))
modes = {o['failure_mode'] for o in d['observations']}
assert modes == {'verification-evidence-missing', 'requested-scope-omitted'}, modes
assert d['candidates'] == [], d['candidates']
" || fail "distinct causes incorrectly merged"
echo "  ok"

echo "== duplicate claims for the same mode within ONE record count as one occurrence =="
F="$T/dup-in-record.jsonl"
python3 -c "
import json
claims = [
    {'claim': 'a', 'status': 'unverified', 'evidence': 'e', 'severity': 'High', 'failure_mode': 'reference-not-found'},
    {'claim': 'b', 'status': 'false', 'evidence': 'e', 'severity': 'High', 'failure_mode': 'reference-not-found'},
]
rec = {'intent': 'i', 'head': 'h1', 'timestamp': 't', 'verdict': 'ISSUES', 'claims': claims}
print(json.dumps(rec))
" > "$F"
node "$REVIEW" "$F" > "$T/dup.json" || fail "aggregator failed on dup-claim fixture"
python3 -c "
import json
d = json.load(open('$T/dup.json'))
obs = [o for o in d['observations'] if o['failure_mode'] == 'reference-not-found']
assert len(obs) == 1 and obs[0]['occurrences'] == 1, obs
assert obs[0]['records'][0]['claim_indices'] == [1, 2], obs[0]['records']
" || fail "same-record duplicate claims not deduplicated to one occurrence"
echo "  ok"

echo "== unclassified never produces a candidate even at ≥3 occurrences =="
F="$T/unclassified.jsonl"
{ record unverified '' h1; record false '' h2; record unverified '' h3; } > "$F"
node "$REVIEW" "$F" > "$T/unclassified.json" || fail "aggregator failed on unclassified fixture"
python3 -c "
import json
d = json.load(open('$T/unclassified.json'))
assert not any(c['failure_mode'] == 'unclassified' for c in d['candidates']), d['candidates']
obs = [o for o in d['observations'] if o['failure_mode'] == 'unclassified']
assert len(obs) == 1 and obs[0]['occurrences'] == 3, obs
" || fail "unclassified incorrectly promoted to a candidate"
echo "  ok"

echo "== blank/malformed/invalid lines are reported and ignored; valid lines still aggregate =="
F="$T/mixed.jsonl"
{
  record unverified verification-evidence-missing h1
  echo ""
  echo "{not json"
  echo '{"intent":"","verdict":"ISSUES","claims":[]}'
  record false verification-evidence-missing h2
  record unverified verification-evidence-missing h3
} > "$F"
node "$REVIEW" "$F" > "$T/mixed.json" || fail "aggregator failed on mixed fixture"
python3 -c "
import json
d = json.load(open('$T/mixed.json'))
reasons = {(i['line'], i['reason']) for i in d['ignored_lines']}
assert (2, 'blank') in reasons, d['ignored_lines']
assert (3, 'malformed') in reasons, d['ignored_lines']
assert (4, 'invalid-record') in reasons, d['ignored_lines']
assert d['valid_records'] == 3, d
cands = [c for c in d['candidates'] if c['failure_mode'] == 'verification-evidence-missing']
assert len(cands) == 1 and cands[0]['occurrences'] == 3, cands
" || fail "malformed/blank/invalid lines not reported or aggregation broke"
echo "  ok"

echo "== read-only: aggregator never modifies its input file =="
F="$T/three.jsonl"
BEFORE=$(hash_of "$F")
node "$REVIEW" "$F" > /dev/null || fail "aggregator run failed"
AFTER=$(hash_of "$F")
[ "$BEFORE" = "$AFTER" ] || fail "aggregator modified the ledger it read"
echo "  ok"

echo "== CLI usage errors on missing/extra args =="
node "$REVIEW" >/dev/null 2>&1 && fail "should fail with no args"
node "$REVIEW" a b >/dev/null 2>&1 && fail "should fail with extra args"
echo "  ok"

# ---------------------------------------------------------------------------
# Approval integration: only the approved candidate reaches the rules file,
# unapproved candidates never do, and re-running is duplicate-safe.
# ---------------------------------------------------------------------------

echo "== approval flow: only the approved candidate is appended; no duplicate on re-run =="
RULES="$T/CLAUDE.md"
cat > "$RULES" <<'EOF'
# Rules

## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
EOF
BEFORE_HASH=$(hash_of "$RULES")
# candidate is proposed (read-only review) — file must stay untouched
node "$REVIEW" "$T/three.jsonl" > /dev/null
AFTER_REVIEW_HASH=$(hash_of "$RULES")
[ "$BEFORE_HASH" = "$AFTER_REVIEW_HASH" ] || fail "unapproved review modified the rules file"

APPROVED_PROPOSAL='완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.'
OTHER_PROPOSAL='요청 범위 밖의 변경이 필요하면 구현하기 전에 사용자 승인을 받는다.'

# Minimal executable completion harness: when the approved rule is in force it
# runs the required check and retains the passing output. Without the rule, the
# original failure condition (no execution evidence) remains reproducible.
EXPECTED="$T/expected.txt"
ACTUAL="$T/actual.txt"
EVIDENCE="$T/verification.out"
printf 'expected result\n' > "$EXPECTED"
printf 'expected result\n' > "$ACTUAL"
exercise_completion() {
  rm -f "$EVIDENCE"
  if grep -qF "$APPROVED_PROPOSAL" "$RULES"; then
    cmp "$EXPECTED" "$ACTUAL" > "$EVIDENCE" 2>&1 && printf 'PASS: cmp expected actual\n' >> "$EVIDENCE"
  fi
  test -s "$EVIDENCE" && grep -qF 'PASS: cmp expected actual' "$EVIDENCE"
}
exercise_completion && fail "unapproved rule unexpectedly produced verification evidence"

node "$APPEND" "$RULES" "$APPROVED_PROPOSAL" > /dev/null || fail "append of approved candidate failed"
grep -qF "$APPROVED_PROPOSAL" "$RULES" || fail "approved candidate not present after apply"
grep -qF "$OTHER_PROPOSAL" "$RULES" && fail "unapproved candidate leaked into rules file"
exercise_completion || fail "approved rule did not run the required check and retain passing output"

# re-run review + re-approve same candidate → append-rule dedups, no duplicate line
node "$APPEND" "$RULES" "$APPROVED_PROPOSAL" > /dev/null || fail "re-append of approved candidate failed"
COUNT=$(grep -cF "$APPROVED_PROPOSAL" "$RULES")
[ "$COUNT" -eq 1 ] || fail "duplicate rule line after re-approval ($COUNT occurrences)"
echo "  ok"

# ---------------------------------------------------------------------------
# Regression: the representative failure mode fixture is prevented once its
# candidate is approved and appended.
# ---------------------------------------------------------------------------

echo "== regression: approval flips missing evidence to executed passing evidence =="
python3 -c "
import json
d = json.load(open('$T/three.json'))
c = [c for c in d['candidates'] if c['failure_mode'] == 'verification-evidence-missing'][0]
assert c['preventive_action'] == 'Run the exact check and retain its passing output', c
assert c['proposal'] == '완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.', c
"
grep -qF 'PASS: cmp expected actual' "$EVIDENCE" || fail "passing verification output was not retained"
echo "  ok (unapproved: no evidence; approved: required check executed with passing evidence)"

rm -rf "$T"

# ---------------------------------------------------------------------------
# Critical fix: manual /gate must not leak ledger files into a fresh consumer
# repo that never opted into the evidence hook (no pre-existing .nova/.gitignore).
# ---------------------------------------------------------------------------

echo "== fresh consumer repo: all gate ledgers ignored, gate.on stays trackable =="
G=$(mktemp -d)
git -C "$G" init -q
git -C "$G" config user.email t@t.t
git -C "$G" config user.name t
mkdir -p "$G/.nova"
node "$GITIGNORE" "$G/.nova" > /dev/null || fail "ensure-nova-gitignore run failed"
touch "$G/.nova/gate.on"
printf '%s\n' '{"intent":"x","verdict":"ISSUES","claims":[{"evidence":"SECRET_OUTPUT"}]}' > "$G/.nova/gate-history.jsonl"
printf '%s\n' '{"intent":"x","verdict":"ISSUES","claims":[]}' > "$G/.nova/gate-verdict.json"
printf '%s\n' '{"command":"printf SECRET_OUTPUT"}' > "$G/.nova/evidence.jsonl"
git -C "$G" check-ignore -q "$G/.nova/gate-history.jsonl" || fail "gate-history.jsonl not ignored in fresh repo"
git -C "$G" check-ignore -q "$G/.nova/gate-verdict.json" || fail "gate-verdict.json not ignored in fresh repo"
git -C "$G" check-ignore -q "$G/.nova/evidence.jsonl" || fail "evidence.jsonl not ignored in fresh repo"
git -C "$G" check-ignore -q "$G/.nova/gate.on" && fail "gate.on must stay trackable (not ignored)"
UNTRACKED=$(git -C "$G" status --short --untracked-files=all -- .nova)
echo "$UNTRACKED" | grep -q 'gate-history.jsonl' && fail "gate-history.jsonl visible in git status"
echo "$UNTRACKED" | grep -q 'gate-verdict.json' && fail "gate-verdict.json visible in git status"
echo "$UNTRACKED" | grep -q 'evidence.jsonl' && fail "evidence.jsonl visible in git status"
echo "$UNTRACKED" | grep -q 'gate.on' || fail "gate.on missing from git status (should be untracked+trackable)"
rm -rf "$G"
echo "  ok"

echo "== conflicting trailing unignore is overridden by the final managed block =="
G=$(mktemp -d)
git -C "$G" init -q
mkdir -p "$G/.nova"
printf '*\n!.gitignore\n!gate.on\n!gate-history.jsonl\n' > "$G/.nova/.gitignore"
node "$GITIGNORE" "$G/.nova" > /dev/null || fail "ensure-nova-gitignore failed on trailing unignore"
for required in '*' '!.gitignore' '!gate.on'; do
  COUNT=$(grep -cFx "$required" "$G/.nova/.gitignore")
  [ "$COUNT" -eq 1 ] || fail "legacy managed line was not moved cleanly: $required ($COUNT occurrences)"
done
touch "$G/.nova/gate.on" "$G/.nova/gate-verdict.json" "$G/.nova/evidence.jsonl"
printf 'SECRET_OUTPUT\n' > "$G/.nova/gate-history.jsonl"
for ledger in gate-history.jsonl gate-verdict.json evidence.jsonl; do
  git -C "$G" check-ignore -q ".nova/$ledger" || fail "$ledger exposed by trailing unignore"
done
git -C "$G" check-ignore -q .nova/gate.on && fail "gate.on ignored after managed suffix repair"
UNTRACKED=$(git -C "$G" status --short --untracked-files=all -- .nova)
echo "$UNTRACKED" | grep -q 'gate-history.jsonl' && fail "gate-history.jsonl visible after managed suffix repair"
echo "$UNTRACKED" | grep -q 'gate.on' || fail "gate.on not trackable after managed suffix repair"

# A custom rule added after an existing managed block must be preserved while
# the managed block moves back to the final position on the next run.
printf '!evidence.jsonl\n' >> "$G/.nova/.gitignore"
node "$GITIGNORE" "$G/.nova" > /dev/null || fail "ensure-nova-gitignore failed to move existing managed block"
grep -qFx '!evidence.jsonl' "$G/.nova/.gitignore" || fail "custom trailing rule was not preserved"
git -C "$G" check-ignore -q .nova/evidence.jsonl || fail "custom trailing unignore overrode moved managed suffix"
rm -rf "$G"
echo "  ok"

echo "== reversed required lines are repaired by the final managed block =="
G=$(mktemp -d)
git -C "$G" init -q
mkdir -p "$G/.nova"
printf '!gate.on\n!.gitignore\n*\n' > "$G/.nova/.gitignore"
node "$GITIGNORE" "$G/.nova" > /dev/null || fail "ensure-nova-gitignore failed on reversed lines"
touch "$G/.nova/gate.on" "$G/.nova/gate-history.jsonl" "$G/.nova/gate-verdict.json" "$G/.nova/evidence.jsonl"
for ledger in gate-history.jsonl gate-verdict.json evidence.jsonl; do
  git -C "$G" check-ignore -q ".nova/$ledger" || fail "$ledger not ignored after reversed-line repair"
done
git -C "$G" check-ignore -q .nova/gate.on && fail "gate.on ignored after reversed-line repair"
rm -rf "$G"
echo "  ok"

echo "== existing custom .nova/.gitignore content is preserved, not destroyed =="
G=$(mktemp -d)
mkdir -p "$G/.nova"
printf 'my-custom-note.txt\n' > "$G/.nova/.gitignore"
node "$GITIGNORE" "$G/.nova" > /dev/null || fail "ensure-nova-gitignore run failed on existing file"
grep -qF 'my-custom-note.txt' "$G/.nova/.gitignore" || fail "pre-existing gitignore content destroyed"
grep -qF '!gate.on' "$G/.nova/.gitignore" || fail "required lines not augmented into existing gitignore"
rm -rf "$G"
echo "  ok"

echo "== corrupted unterminated managed marker: refuses to modify, preserves file byte-for-byte across repeated runs =="
G=$(mktemp -d)
mkdir -p "$G/.nova"
printf '%s\n' 'keep-before' '# >>> nova: managed gate ledger ignore >>>' 'keep-after-unterminated' '!custom.jsonl' > "$G/.nova/.gitignore"
BEFORE=$(hash_of "$G/.nova/.gitignore")
node "$GITIGNORE" "$G/.nova" > /dev/null 2>/dev/null && fail "ensure-nova-gitignore should have failed on unterminated managed marker"
AFTER=$(hash_of "$G/.nova/.gitignore")
[ "$BEFORE" = "$AFTER" ] || fail "file was modified despite corrupted unterminated marker (data loss)"
node "$GITIGNORE" "$G/.nova" > /dev/null 2>/dev/null && fail "ensure-nova-gitignore should keep failing on unterminated managed marker (run 2)"
AFTER2=$(hash_of "$G/.nova/.gitignore")
[ "$BEFORE" = "$AFTER2" ] || fail "file was modified on second run despite corrupted unterminated marker (data loss)"
grep -qF 'keep-after-unterminated' "$G/.nova/.gitignore" || fail "content after unterminated marker was destroyed"
grep -qF '!custom.jsonl' "$G/.nova/.gitignore" || fail "custom rule after unterminated marker was destroyed"
rm -rf "$G"
echo "  ok"

echo "== idempotent: second run produces byte-identical managed suffix =="
G=$(mktemp -d)
mkdir -p "$G/.nova"
node "$GITIGNORE" "$G/.nova" > /dev/null
BEFORE=$(hash_of "$G/.nova/.gitignore")
node "$GITIGNORE" "$G/.nova" > /dev/null
AFTER=$(hash_of "$G/.nova/.gitignore")
[ "$BEFORE" = "$AFTER" ] || fail "gitignore changed on second run"
COUNT=$(grep -c '^!gate\.on$' "$G/.nova/.gitignore")
[ "$COUNT" -eq 1 ] || fail "gitignore line duplicated across runs ($COUNT occurrences)"
rm -rf "$G"
echo "  ok"

echo
echo "ALL PASS: gate-history-review-verify.sh"
