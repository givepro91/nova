#!/usr/bin/env bash
# Storage-contract checks for canonical .nova/rules.md. Exits non-zero on first failure.
set -eu
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$NOVA/plugins/nova/scripts/team-rules.mjs"
APPLY="$NOVA/plugins/nova/scripts/apply-block.mjs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

echo "== syntax + empty canonical store =="
node --check "$RULES" || fail "syntax"
node "$RULES" validate "$NOVA/.nova/rules.md" >/dev/null || fail "empty store"
echo "  ok"

valid_doc() {
  cat <<'MD'
---
schema: nova-team-rules/v1
---

# Nova team rules

## `rule-20260713-a1b2c3d4`

- status: `proposed`
- scope: `["**","src/**"]`
- source-summary: `사용자 교정에서 완료 선언 조건을 확인했다.`
- evidence-summary: `검증 누락이 반복될 수 있어 성공 확인이 필요하다.`
- origin: `propose`
- derived-from: `[]`

### Rule

변경 완료를 알리기 전에 관련 검증 명령의 성공을 확인한다.
MD
}

echo "== valid record + CRLF =="
valid_doc > "$T/valid.md"
node "$RULES" validate "$T/valid.md" >/dev/null || fail "valid record"
sed 's/$/\r/' "$T/valid.md" > "$T/crlf.md"
node "$RULES" validate "$T/crlf.md" >/dev/null || fail "CRLF"
echo "  ok"

echo "== malformed, conflict, secret, and missing provenance fail =="
sed 's/status: `proposed`/status: `unknown`/' "$T/valid.md" > "$T/bad-status.md"
node "$RULES" validate "$T/bad-status.md" >/dev/null 2>&1 && fail "invalid status accepted"
awk '{ print } $0 == "# Nova team rules" { print "<<<<<<< HEAD" }' "$T/valid.md" > "$T/conflict.md"
node "$RULES" validate "$T/conflict.md" >/dev/null 2>&1 && fail "conflict accepted"
sed 's/사용자 교정에서 완료 선언 조건을 확인했다./token=ghp_12345678901234567890/' "$T/valid.md" > "$T/secret.md"
node "$RULES" validate "$T/secret.md" >/dev/null 2>&1 && fail "secret accepted"
sed 's/변경 완료를 알리기 전에 관련 검증 명령의 성공을 확인한다./Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature/' "$T/valid.md" > "$T/secret-body.md"
node "$RULES" validate "$T/secret-body.md" >/dev/null 2>&1 && fail "secret in Rule body accepted"
sed 's/변경 완료를 알리기 전에 관련 검증 명령의 성공을 확인한다./정상 규칙처럼 보이지만 <!-- nova-rule:rule-99990101-deadbeef --> 마커를 위조한다./' "$T/valid.md" > "$T/comment-body.md"
node "$RULES" validate "$T/comment-body.md" >/dev/null 2>&1 && fail "HTML comment marker in Rule body accepted"
sed -e 's/origin: `propose`/origin: `merge`/' -e 's/status: `proposed`/status: `active`/' "$T/valid.md" > "$T/no-provenance.md"
node "$RULES" validate "$T/no-provenance.md" >/dev/null 2>&1 && fail "missing provenance accepted"
sed 's/rule-20260713-a1b2c3d4/rule-20261340-a1b2c3d4/' "$T/valid.md" > "$T/bad-date.md"
node "$RULES" validate "$T/bad-date.md" >/dev/null 2>&1 && fail "invalid calendar date accepted"
sed 's/rule-20260713-a1b2c3d4/rule-00000101-a1b2c3d4/' "$T/valid.md" > "$T/year-zero.md"
node "$RULES" validate "$T/year-zero.md" >/dev/null 2>&1 && fail "year zero accepted"
sed 's#\["\*\*","src/\*\*"\]#["{../secret,src/**}"]#' "$T/valid.md" > "$T/traversal.md"
node "$RULES" validate "$T/traversal.md" >/dev/null 2>&1 && fail "glob traversal accepted"
echo "  ok"

echo "== duplicate and cyclic provenance fail =="
{ valid_doc; printf '\n'; sed -n '/^## /,$p' "$T/valid.md"; } > "$T/duplicate.md"
node "$RULES" validate "$T/duplicate.md" >/dev/null 2>&1 && fail "duplicate id accepted"
cat > "$T/cycle.md" <<'MD'
---
schema: nova-team-rules/v1
---

# Nova team rules

## `rule-20260713-a1b2c3d4`

- status: `active`
- scope: `["**"]`
- source-summary: `첫 규칙의 정제된 출처다.`
- evidence-summary: `첫 규칙의 정제된 근거다.`
- origin: `merge`
- derived-from: `["rule-20260713-b2c3d4e5"]`

### Rule

첫 번째 실행 규칙이다.

## `rule-20260713-b2c3d4e5`

- status: `active`
- scope: `["**"]`
- source-summary: `둘째 규칙의 정제된 출처다.`
- evidence-summary: `둘째 규칙의 정제된 근거다.`
- origin: `generalize`
- derived-from: `["rule-20260713-a1b2c3d4"]`

### Rule

두 번째 실행 규칙이다.
MD
node "$RULES" validate "$T/cycle.md" >/dev/null 2>&1 && fail "provenance cycle accepted"
echo "  ok"

echo "== rejected write leaves existing file byte-identical =="
cp "$T/valid.md" "$T/write.md"
before=$(git hash-object "$T/write.md")
node "$RULES" write "$T/write.md" < "$T/bad-status.md" >/dev/null 2>&1 && fail "bad write succeeded"
[ "$before" = "$(git hash-object "$T/write.md")" ] || fail "bad write modified file"
echo "  ok"

echo "== approved allowlist tracks rules only =="
G="$T/repo"; git -C "$T" init -q repo; mkdir -p "$G/.nova"
cp "$NOVA/.nova/.gitignore" "$G/.nova/.gitignore"
touch "$G/.nova/gate.on" "$G/.nova/rules.md" "$G/.nova/evidence.jsonl" "$G/.nova/gate-history.jsonl" "$G/.nova/gate-verdict.json" "$G/.nova/transcript.txt"
git -C "$G" check-ignore -q .nova/evidence.jsonl || fail "evidence tracked"
git -C "$G" check-ignore -q .nova/gate-history.jsonl || fail "history tracked"
git -C "$G" check-ignore -q .nova/gate-verdict.json || fail "verdict tracked"
git -C "$G" check-ignore -q .nova/transcript.txt || fail "raw output tracked"
git -C "$G" check-ignore -q .nova/rules.md && fail "rules ignored"
git -C "$G" check-ignore -q .nova/gate.on && fail "gate marker ignored"
echo "  ok"

echo "== explicit team proposal is proposed-only and isolated =="
P="$T/proposal-repo"; git -C "$T" init -q proposal-repo; mkdir -p "$P/.nova"
git -C "$P" config user.name test
git -C "$P" config user.email test@example.com
cat > "$P/CLAUDE.md" <<'MD'
# Project instructions

<!-- CC-RULES:START -->
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
echo baseline > "$P/README.md"
git -C "$P" add CLAUDE.md README.md
git -C "$P" commit -qm baseline
claude_before=$(git hash-object "$P/CLAUDE.md")
head_before=$(git -C "$P" rev-parse HEAD)
cat > "$T/proposal.json" <<'JSON'
{
  "scope": ["src/**"],
  "source-summary": "사용자 교정에서 호출부 검토 원칙을 확인했다.",
  "evidence-summary": "호출부 누락의 반복을 막기 위해 팀 검토가 필요하다.",
  "rule": "공유 함수 시그니처를 바꾸기 전에 모든 호출부를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/proposal.json" > "$T/proposal.out" || fail "team proposal"
node "$RULES" validate "$P/.nova/rules.md" >/dev/null || fail "proposed store validation"
grep -Eq '^proposed: rule-[0-9]{8}-[0-9a-f]{8}$' "$T/proposal.out" || fail "proposal id output"
grep -Eq '^## `rule-[0-9]{8}-[0-9a-f]{8}`$' "$P/.nova/rules.md" || fail "stable id record"
grep -Fq -- '- status: `proposed`' "$P/.nova/rules.md" || fail "proposal status"
grep -Fq -- '- origin: `propose`' "$P/.nova/rules.md" || fail "proposal origin"
grep -Fq -- '- derived-from: `[]`' "$P/.nova/rules.md" || fail "proposal provenance"
grep -Fq -- '- scope: `["src/**"]`' "$P/.nova/rules.md" || fail "proposal scope"
grep -Fq -- '- source-summary: `사용자 교정에서 호출부 검토 원칙을 확인했다.`' "$P/.nova/rules.md" || fail "source summary"
grep -Fq -- '- evidence-summary: `호출부 누락의 반복을 막기 위해 팀 검토가 필요하다.`' "$P/.nova/rules.md" || fail "evidence summary"
grep -Fq '공유 함수 시그니처를 바꾸기 전에 모든 호출부를 확인한다.' "$P/.nova/rules.md" || fail "rule body"
grep -Fq -- '- status: `active`' "$P/.nova/rules.md" && fail "proposal activated itself"
[ "$claude_before" = "$(git hash-object "$P/CLAUDE.md")" ] || fail "proposal modified CLAUDE.md"
[ "$head_before" = "$(git -C "$P" rev-parse HEAD)" ] || fail "proposal created a commit"
cmp "$P/.nova/.gitignore" "$NOVA/.nova/.gitignore" >/dev/null || fail "proposal allowlist"
echo "  ok"

echo "== valid dollar scope and technical prose are accepted =="
cat > "$T/edge-proposal.json" <<'JSON'
{
  "scope": ["$root.tsx"],
  "source-summary": "사용자 교정에서 at /api 경계의 적용 원칙을 확인했다.",
  "evidence-summary": "검토 결과는 at version 2:3 및 issue 123:4 기준에 맞았다.",
  "rule": "API 경계 변경 전에 관련 규칙의 적용 범위를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/edge-proposal.json" >/dev/null || fail "valid edge proposal"
node "$RULES" validate "$P/.nova/rules.md" >/dev/null || fail "valid edge store"
grep -Fq -- '- scope: `["$root.tsx"]`' "$P/.nova/rules.md" || fail "dollar scope"
grep -Fq -- '- source-summary: `사용자 교정에서 at /api 경계의 적용 원칙을 확인했다.`' "$P/.nova/rules.md" || fail "technical prose"
echo "  ok"

echo "== proposal rejects raw, secret, and extra fields without writes =="
rules_before=$(git hash-object "$P/.nova/rules.md")
ignore_before=$(git hash-object "$P/.nova/.gitignore")
cat > "$T/secret-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "token=ghp_12345678901234567890",
  "evidence-summary": "재발 방지를 위해 팀 검토가 필요하다.",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/secret-proposal.json" >/dev/null 2>&1 && fail "secret proposal accepted"
cat > "$T/secret-scope-proposal.json" <<'JSON'
{
  "scope": ["token=ghp_12345678901234567890"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "재발 방지를 위해 팀 검토가 필요하다.",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/secret-scope-proposal.json" >/dev/null 2>&1 && fail "secret scope accepted"
cat > "$T/raw-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "근거 요약 뒤에 stdout: npm test passed",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/raw-proposal.json" >/dev/null 2>&1 && fail "raw output proposal accepted"
cat > "$T/stack-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "오류 위치 at run (file:///tmp/check.mjs:1:2)",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/stack-proposal.json" >/dev/null 2>&1 && fail "stack output proposal accepted"
cat > "$T/relative-stack-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "오류 위치 at run (src/check.mjs:1:2)",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/relative-stack-proposal.json" >/dev/null 2>&1 && fail "relative stack output accepted"
cat > "$T/punctuated-stack-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "오류 위치 at run (src/check.mjs:1:2), 재발 방지가 필요하다.",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/punctuated-stack-proposal.json" >/dev/null 2>&1 && fail "punctuated stack output accepted"
cat > "$T/suffixed-stack-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "오류 위치 at run (src/check.mjs:1:2)에서 누락을 확인했다.",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/suffixed-stack-proposal.json" >/dev/null 2>&1 && fail "suffixed stack output accepted"
for raw_output in \
  '오류 위치 at Object.run [as handle] (src/check.mjs:1:2)' \
  '오류 위치 at <anonymous>:1:2' \
  'Error: validation failed at runtime' \
  'npm ERR! code ELIFECYCLE' \
  'Traceback (most recent call last):' \
  'File "/tmp/check.py", line 3, in run' \
  'PASS tests/auth.test.js (5.3 s) Tests: 12 passed, 12 total' \
  'FAIL src/user.spec.ts' \
  'Tests: 3 failed, 9 passed, 12 total' \
  '2 passing, 1 failing' \
  'not ok 4 - user login' \
  'Ran 12 tests in 0.123s' \
  'ok   example.com/project/pkg 0.123s' \
  '12 examples, 0 failures' \
  'Passed! - Failed: 0, Passed: 12, Skipped: 0, Total: 12' \
  '** TEST SUCCEEDED **' \
  '--- PASS: TestLogin (0.00s)' \
  'test auth::login ... ok' \
  '12 runs, 24 assertions, 0 failures, 0 errors, 0 skips' \
  'Tests run: 12, Failures: 0, Errors: 0, Skipped: 0' \
  'OK (12 tests, 24 assertions)' \
  'FAIL   example.com/project/pkg 0.123s' \
  'ok   example.com/project/pkg (cached)' \
  '?    example.com/project/pkg [no test files]' \
  'FAIL example.com/project/pkg [build failed]' \
  'FAIL example.com/project/pkg [setup failed]' \
  'FAIL'
do
  RAW_OUTPUT="$raw_output" node -e 'process.stdout.write(JSON.stringify({scope:["**"],"source-summary":"사용자 교정에서 검증 원칙을 확인했다.","evidence-summary":process.env.RAW_OUTPUT,rule:"검증 결과를 확인한다."}))' > "$T/raw-variant-proposal.json"
  node "$RULES" propose "$P/.nova/rules.md" < "$T/raw-variant-proposal.json" >/dev/null 2>&1 && fail "raw output variant accepted: $raw_output"
done
for credential in \
  'https://alice:s3cr3t@example.com/log' \
  'postgres://user:pw@db.internal:5432/app' \
  'ftp://admin:hunter2@files.example.org'
do
  CRED="검토 출처는 $credential 이다." node -e 'process.stdout.write(JSON.stringify({scope:["**"],"source-summary":process.env.CRED,"evidence-summary":"재발 방지를 위해 팀 검토가 필요하다.",rule:"검증 결과를 확인한다."}))' > "$T/cred-proposal.json"
  node "$RULES" propose "$P/.nova/rules.md" < "$T/cred-proposal.json" >/dev/null 2>&1 && fail "credential URL accepted: $credential"
done
cat > "$T/extra-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "재발 방지를 위해 팀 검토가 필요하다.",
  "rule": "검증 결과를 확인한다.",
  "raw-evidence": "do not retain this field"
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/extra-proposal.json" >/dev/null 2>&1 && fail "extra proposal field accepted"
[ "$rules_before" = "$(git hash-object "$P/.nova/rules.md")" ] || fail "rejected proposal modified rules"
[ "$ignore_before" = "$(git hash-object "$P/.nova/.gitignore")" ] || fail "rejected proposal modified allowlist"
[ "$claude_before" = "$(git hash-object "$P/CLAUDE.md")" ] || fail "rejected proposal modified CLAUDE.md"
echo "  ok"

echo "== raw local evidence stays out of the tracked proposal diff =="
printf '%s\n' '{"output":"token=ghp_12345678901234567890"}' > "$P/.nova/evidence.jsonl"
git -C "$P" check-ignore -q .nova/evidence.jsonl || fail "proposal evidence tracked"
git -C "$P" add .nova/.gitignore .nova/rules.md
git -C "$P" diff --cached -- .nova > "$T/proposal.diff"
grep -Fq 'ghp_12345678901234567890' "$T/proposal.diff" && fail "raw secret copied into tracked diff"
git -C "$P" ls-files --error-unmatch .nova/evidence.jsonl >/dev/null 2>&1 && fail "raw evidence entered index"
echo "  ok"

echo "== symlinked .gitignore is refused, victim file and symlink untouched =="
S="$T/symlink-repo"; mkdir -p "$S/.nova"
cp "$NOVA/.nova/rules.md" "$S/.nova/rules.md"
printf 'ORIGINAL USER DATA\n' > "$T/victim.txt"
ln -s ../victim.txt "$S/.nova/.gitignore"
cat > "$T/symlink-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "검증 누락의 재발을 막기 위한 근거다.",
  "rule": "완료 전에 관련 검증을 실행한다."
}
JSON
node "$RULES" propose "$S/.nova/rules.md" < "$T/symlink-proposal.json" >/dev/null 2>&1 && fail "symlinked gitignore write accepted"
[ -L "$S/.nova/.gitignore" ] || fail "symlink was replaced"
[ "$(cat "$T/victim.txt")" = "ORIGINAL USER DATA" ] || fail "victim file was overwritten through symlink"
echo "  ok"

echo "== bare Bearer/JWT secret is rejected, rules.md byte-identical =="
rules_before=$(git hash-object "$P/.nova/rules.md")
cat > "$T/jwt-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 인증 원칙을 확인했다.",
  "evidence-summary": "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
  "rule": "인증 변경 전에 검증한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/jwt-proposal.json" >/dev/null 2>&1 && fail "bare Bearer/JWT accepted"
grep -Fq 'eyJhbGciOiJIUzI1NiJ9' "$P/.nova/rules.md" && fail "JWT leaked into rules.md"
[ "$rules_before" = "$(git hash-object "$P/.nova/rules.md")" ] || fail "rejected JWT proposal modified rules"
echo "  ok"

echo "== concurrent proposals: success count matches final new-record count =="
C="$T/concurrent-repo"; mkdir -p "$C/.nova"
cp "$NOVA/.nova/rules.md" "$C/.nova/rules.md"
N=20
for i in $(seq 1 "$N"); do
  printf '{"scope":["src/**"],"source-summary":"동시 제안 %s의 정제된 출처다.","evidence-summary":"동시 누락 %s의 재발을 막기 위한 근거다.","rule":"동시 작업 %s 전에 범위를 확인한다."}\n' "$i" "$i" "$i" > "$T/cp$i.json"
  node "$RULES" propose "$C/.nova/rules.md" < "$T/cp$i.json" > "$T/co$i" 2> "$T/ce$i" &
done
wait
succ=$(grep -l '^proposed:' "$T"/co* 2>/dev/null | wc -l | tr -d ' ')
recs=$(grep -c '^## `rule-' "$C/.nova/rules.md")
[ "$succ" = "$recs" ] || fail "success count ($succ) != final record count ($recs)"
node "$RULES" validate "$C/.nova/rules.md" >/dev/null || fail "concurrent store invalid"
echo "  ok"

echo "== a writer slower than the lock timeout never has its success silently lost =="
SL="$T/slow-repo"; mkdir -p "$SL/.nova"
cp "$NOVA/.nova/rules.md" "$SL/.nova/rules.md"
cat > "$T/slow-p1.json" <<'JSON'
{"scope":["src/**"],"source-summary":"느린 첫 제안의 정제된 출처다.","evidence-summary":"느린 첫 누락의 재발을 막는 근거다.","rule":"느린 첫 작업 전에 범위를 확인한다."}
JSON
cat > "$T/slow-p2.json" <<'JSON'
{"scope":["src/**"],"source-summary":"빠른 둘째 제안의 정제된 출처다.","evidence-summary":"빠른 둘째 누락의 재발을 막는 근거다.","rule":"빠른 둘째 작업 전에 범위를 확인한다."}
JSON
FILE="$SL/.nova/rules.md" RULES_URL="file://$RULES" P1="$(cat "$T/slow-p1.json")" node --input-type=module -e '
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const read = fs.readFileSync;
let count = 0;
fs.readFileSync = (path, ...args) => {
  const result = read(path, ...args);
  if (String(path) === process.env.FILE && ++count === 2) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 11000);
  }
  return result;
};
syncBuiltinESMExports();
const { proposeTeamRule } = await import(process.env.RULES_URL + "?slow=" + Date.now());
const r = proposeTeamRule(process.env.FILE, process.env.P1);
console.log("FIRST_SUCCESS=" + r.id);
' > "$T/slow-first.out" 2> "$T/slow-first.err" &
first_pid=$!
while [ ! -e "$SL/.nova/.rules.lock" ]; do sleep 0.01; done
if node "$RULES" propose "$SL/.nova/rules.md" < "$T/slow-p2.json" > "$T/slow-second.out" 2> "$T/slow-second.err"; then
  second_exit=0
else
  second_exit=$?
fi
if wait "$first_pid"; then first_exit=0; else first_exit=$?; fi
[ "$first_exit" = 0 ] || fail "slow first writer (holding the lock past timeout) unexpectedly failed"
grep -q '^FIRST_SUCCESS=' "$T/slow-first.out" || fail "slow first writer did not report success"
records=$(grep -c '^## `rule-' "$SL/.nova/rules.md" || true)
first_present=$(grep -c '느린 첫 작업' "$SL/.nova/rules.md" || true)
second_present=$(grep -c '빠른 둘째 작업' "$SL/.nova/rules.md" || true)
[ "$first_present" = 1 ] || fail "slow first writer's successful record was lost (lock was stolen)"
if [ "$second_exit" = 0 ]; then
  { [ "$records" = 2 ] && [ "$second_present" = 1 ]; } || fail "second writer reported success but its record is missing"
else
  { [ "$records" = 1 ] && [ "$second_present" = 0 ]; } || fail "second writer failed but left a partial or duplicate record"
fi
node "$RULES" validate "$SL/.nova/rules.md" >/dev/null || fail "slow-writer store invalid"
echo "  ok"

gardener_doc() {
  cat <<'MD'
---
schema: nova-team-rules/v1
---

# Nova team rules

## `rule-20260713-11111111`

- status: `proposed`
- scope: `["src/**"]`
- source-summary: `첫 제안에서 호출부 확인 원칙을 정제했다.`
- evidence-summary: `호출부 누락의 반복을 막기 위한 근거다.`
- origin: `propose`
- derived-from: `[]`

### Rule

공유 함수 변경 전에 호출부를 확인한다.

## `rule-20260713-22222222`

- status: `proposed`
- scope: `["tests/**"]`
- source-summary: `둘째 제안에서 검증 범위 원칙을 정제했다.`
- evidence-summary: `관련 검증 누락의 반복을 막기 위한 근거다.`
- origin: `propose`
- derived-from: `[]`

### Rule

변경한 동작의 관련 테스트를 실행한다.

## `rule-20260713-33333333`

- status: `active`
- scope: `["docs/**"]`
- source-summary: `문서 변경에서 검토 원칙을 정제했다.`
- evidence-summary: `오래된 문서 규칙의 이력을 남길 근거다.`
- origin: `propose`
- derived-from: `[]`

### Rule

문서 변경 전에 현재 계약을 확인한다.
MD
}

echo "== gardener promote and retire preserve identity and history =="
D="$T/gardener-direct"; mkdir -p "$D/.nova"; gardener_doc > "$D/.nova/rules.md"
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$D/.nova/rules.md" > "$T/promote.out" || fail "promote"
grep -Fq 'promote: rule-20260713-11111111' "$T/promote.out" || fail "promote output"
awk '/rule-20260713-11111111/{found=1} found && /status: `active`/{ok=1; exit} END{exit !ok}' "$D/.nova/rules.md" || fail "promote status"
promoted=$(git hash-object "$D/.nova/rules.md")
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$D/.nova/rules.md" >/dev/null 2>&1 && fail "double promote accepted"
[ "$promoted" = "$(git hash-object "$D/.nova/rules.md")" ] || fail "rejected promote modified rules"
printf '{"id":"rule-20260713-33333333","retired-reason":"문서 계약이 새 절차로 대체되어 폐기한다."}\n' | node "$RULES" retire "$D/.nova/rules.md" >/dev/null || fail "retire"
grep -Fq -- '- retired-reason: `문서 계약이 새 절차로 대체되어 폐기한다.`' "$D/.nova/rules.md" || fail "retire reason"
grep -Fq '문서 변경 전에 현재 계약을 확인한다.' "$D/.nova/rules.md" || fail "retire history"
node "$RULES" validate "$D/.nova/rules.md" >/dev/null || fail "direct gardener store"
echo "  ok"

echo "== merge and generalize require explicit result and preserve all sources =="
M="$T/gardener-merge"; mkdir -p "$M/.nova"; gardener_doc > "$M/.nova/rules.md"
cat > "$T/merge.json" <<'JSON'
{
  "derived-from": ["rule-20260713-11111111", "rule-20260713-22222222"],
  "scope": ["src/**", "tests/**"],
  "source-summary": "두 제안의 호출부와 검증 범위를 함께 정제했다.",
  "evidence-summary": "변경 영향과 관련 검증을 함께 확인해야 재발을 막을 수 있다.",
  "rule": "공유 동작을 바꿀 때 호출부와 관련 테스트를 함께 확인한다."
}
JSON
node "$RULES" merge "$M/.nova/rules.md" < "$T/merge.json" > "$T/merge.out" || fail "merge"
merge_id=$(sed -n 's/^merge: //p' "$T/merge.out")
echo "$merge_id" | grep -Eq '^rule-[0-9]{8}-[0-9a-f]{8}$' || fail "merge id"
grep -Fq -- '- derived-from: `["rule-20260713-11111111","rule-20260713-22222222"]`' "$M/.nova/rules.md" || fail "merge provenance"
grep -Fq -- '- scope: `["src/**","tests/**"]`' "$M/.nova/rules.md" || fail "merge scope"
grep -Fq -- '- origin: `merge`' "$M/.nova/rules.md" || fail "merge origin"
[ "$(grep -Fc -- "- retired-reason: \`Replaced by $merge_id\`" "$M/.nova/rules.md")" = 2 ] || fail "merge source retirement"
node "$RULES" validate "$M/.nova/rules.md" >/dev/null || fail "merged store"
merged=$(git hash-object "$M/.nova/rules.md")
node "$RULES" merge "$M/.nova/rules.md" < "$T/merge.json" >/dev/null 2>&1 && fail "retired merge sources accepted"
[ "$merged" = "$(git hash-object "$M/.nova/rules.md")" ] || fail "rejected merge modified rules"

GZ="$T/gardener-generalize"; mkdir -p "$GZ/.nova"; gardener_doc > "$GZ/.nova/rules.md"
sed 's/"scope": \["src\/\*\*", "tests\/\*\*"\]/"scope": ["**"]/' "$T/merge.json" |
  sed 's/"rule": ".*"/"rule": "행동을 변경할 때 영향 범위와 검증 범위를 먼저 확인한다."/' > "$T/generalize.json"
node "$RULES" generalize "$GZ/.nova/rules.md" < "$T/generalize.json" >/dev/null || fail "generalize"
grep -Fq -- '- origin: `generalize`' "$GZ/.nova/rules.md" || fail "generalize origin"
grep -Fq -- '- scope: `["**"]`' "$GZ/.nova/rules.md" || fail "generalize explicit scope"
grep -Fq '행동을 변경할 때 영향 범위와 검증 범위를 먼저 확인한다.' "$GZ/.nova/rules.md" || fail "generalize body"
node "$RULES" validate "$GZ/.nova/rules.md" >/dev/null || fail "generalized store"
echo "  ok"

echo "== promote/retire project active rules into an existing canonical block =="
GP="$T/gardener-project"; mkdir -p "$GP/.nova"; gardener_doc > "$GP/.nova/rules.md"
cat > "$GP/CLAUDE.md" <<'MD'
# Existing project instructions

keep-before

<!-- CC-RULES:START -->
<!-- Managed by /claude-md. -->

## Working Discipline
- Keep this section.

## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->

keep-after
MD
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GP/.nova/rules.md" >/dev/null || fail "promote for projection"
grep -Fq 'nova-rule:rule-20260713-11111111' "$GP/CLAUDE.md" || fail "promote did not project into CLAUDE.md"
grep -Fq 'keep-before' "$GP/CLAUDE.md" || fail "promote changed preamble"
grep -Fq 'keep-after' "$GP/CLAUDE.md" || fail "promote changed trailing content"
node "$APPLY" --check-team-rules "$GP/.nova/rules.md" "$GP/CLAUDE.md" >/dev/null || fail "promote projection out of sync"
printf '{"id":"rule-20260713-33333333","retired-reason":"더 이상 필요하지 않아 폐기한다."}\n' | node "$RULES" retire "$GP/.nova/rules.md" >/dev/null || fail "retire for projection"
grep -Fq 'nova-rule:rule-20260713-33333333' "$GP/CLAUDE.md" && fail "retired rule stayed projected"
grep -Fq 'nova-rule:rule-20260713-11111111' "$GP/CLAUDE.md" || fail "unrelated retire dropped an active projection"
node "$APPLY" --check-team-rules "$GP/.nova/rules.md" "$GP/CLAUDE.md" >/dev/null || fail "post-retire projection out of sync"
echo "  ok"

echo "== merge/generalize project the replacement rule and drop retired sources =="
GM="$T/gardener-project-merge"; mkdir -p "$GM/.nova"; gardener_doc > "$GM/.nova/rules.md"
cat > "$GM/CLAUDE.md" <<'MD'
<!-- CC-RULES:START -->
## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GM/.nova/rules.md" >/dev/null || fail "promote before merge (1)"
printf '{"id":"rule-20260713-22222222"}\n' | node "$RULES" promote "$GM/.nova/rules.md" >/dev/null || fail "promote before merge (2)"
node "$RULES" merge "$GM/.nova/rules.md" < "$T/merge.json" > "$T/project-merge.out" || fail "merge for projection"
merge_id=$(sed -n 's/^merge: //p' "$T/project-merge.out")
grep -Fq "nova-rule:$merge_id" "$GM/CLAUDE.md" || fail "merge result not projected"
grep -Fq 'nova-rule:rule-20260713-11111111' "$GM/CLAUDE.md" && fail "merged source 1 still projected"
grep -Fq 'nova-rule:rule-20260713-22222222' "$GM/CLAUDE.md" && fail "merged source 2 still projected"
node "$APPLY" --check-team-rules "$GM/.nova/rules.md" "$GM/CLAUDE.md" >/dev/null || fail "post-merge projection out of sync"

GZP="$T/gardener-project-generalize"; mkdir -p "$GZP/.nova"; gardener_doc > "$GZP/.nova/rules.md"
cat > "$GZP/CLAUDE.md" <<'MD'
<!-- CC-RULES:START -->
## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GZP/.nova/rules.md" >/dev/null || fail "promote before generalize (1)"
printf '{"id":"rule-20260713-22222222"}\n' | node "$RULES" promote "$GZP/.nova/rules.md" >/dev/null || fail "promote before generalize (2)"
node "$RULES" generalize "$GZP/.nova/rules.md" < "$T/generalize.json" > "$T/project-generalize.out" || fail "generalize for projection"
generalize_id=$(sed -n 's/^generalize: //p' "$T/project-generalize.out")
grep -Fq "nova-rule:$generalize_id" "$GZP/CLAUDE.md" || fail "generalize result not projected"
grep -Fq 'nova-rule:rule-20260713-11111111' "$GZP/CLAUDE.md" && fail "generalized source 1 still projected"
grep -Fq 'nova-rule:rule-20260713-22222222' "$GZP/CLAUDE.md" && fail "generalized source 2 still projected"
node "$APPLY" --check-team-rules "$GZP/.nova/rules.md" "$GZP/CLAUDE.md" >/dev/null || fail "post-generalize projection out of sync"
echo "  ok"

echo "== gardener without a canonical file still succeeds; rules.md stays the source of truth =="
GN="$T/gardener-no-canonical"; mkdir -p "$GN/.nova"; gardener_doc > "$GN/.nova/rules.md"
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GN/.nova/rules.md" >/dev/null || fail "promote without canonical file"
[ -e "$GN/CLAUDE.md" ] && fail "promote created a canonical file that never existed"
echo "  ok"

echo "== gardener bootstraps a missing CC-RULES block before projecting =="
GB="$T/gardener-bootstrap"; mkdir -p "$GB/.nova"; gardener_doc > "$GB/.nova/rules.md"
printf '%s\n' '# Plain project doc' '' 'no managed block here yet' > "$GB/CLAUDE.md"
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GB/.nova/rules.md" >/dev/null || fail "promote with no CC-RULES block yet"
grep -Fq 'no managed block here yet' "$GB/CLAUDE.md" || fail "bootstrap dropped prior content"
grep -Fq 'nova-rule:rule-20260713-11111111' "$GB/CLAUDE.md" || fail "bootstrap did not project the promoted rule"
node "$APPLY" --check-team-rules "$GB/.nova/rules.md" "$GB/CLAUDE.md" >/dev/null || fail "post-bootstrap projection out of sync"
echo "  ok"

echo "== gardener resolves AGENTS.md as canonical when CLAUDE.md imports it =="
GA="$T/gardener-agents"; mkdir -p "$GA/.nova"; gardener_doc > "$GA/.nova/rules.md"
printf '%s\n' '@AGENTS.md' > "$GA/CLAUDE.md"
cat > "$GA/AGENTS.md" <<'MD'
<!-- CC-RULES:START -->
## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GA/.nova/rules.md" >/dev/null || fail "promote with AGENTS.md canonical"
grep -Fq 'nova-rule:rule-20260713-11111111' "$GA/AGENTS.md" || fail "AGENTS.md did not receive the projection"
grep -Fq 'nova-rule' "$GA/CLAUDE.md" && fail "CLAUDE.md received a projection though AGENTS.md is canonical"
echo "  ok"

echo "== gardener preflight fails closed on a broken canonical block without mutating rules.md =="
GF="$T/gardener-preflight-fail"; mkdir -p "$GF/.nova"; gardener_doc > "$GF/.nova/rules.md"
cat > "$GF/CLAUDE.md" <<'MD'
<!-- CC-RULES:START -->
## Self-Learning Rules
<!-- LEARN:ANCHOR -->
MD
rules_before=$(git hash-object "$GF/.nova/rules.md")
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$GF/.nova/rules.md" >/dev/null 2>&1 && fail "promote accepted despite a broken canonical block"
[ "$rules_before" = "$(git hash-object "$GF/.nova/rules.md")" ] || fail "preflight failure still mutated rules.md"
echo "  ok"

echo "== gardener conflicts fail closed without partial writes =="
F="$T/gardener-fail"; mkdir -p "$F/.nova"; gardener_doc > "$F/.nova/rules.md"
before=$(git hash-object "$F/.nova/rules.md")
printf '{"derived-from":["rule-20260713-11111111","rule-20260713-22222222"],"source-summary":"정제된 출처다.","evidence-summary":"정제된 근거다.","rule":"결과 규칙이다."}\n' |
  node "$RULES" merge "$F/.nova/rules.md" >/dev/null 2>&1 && fail "merge without explicit scope accepted"
printf '{"derived-from":["rule-20260713-11111111","rule-20260713-22222222"],"scope":["**"],"source-summary":"정제된 출처다.","evidence-summary":"정제된 근거다."}\n' |
  node "$RULES" generalize "$F/.nova/rules.md" >/dev/null 2>&1 && fail "generalize without explicit body accepted"
printf '{"derived-from":["rule-20260713-11111111","rule-20260713-11111111"],"scope":["**"],"source-summary":"정제된 출처다.","evidence-summary":"정제된 근거다.","rule":"결과 규칙이다."}\n' |
  node "$RULES" merge "$F/.nova/rules.md" >/dev/null 2>&1 && fail "duplicate source accepted"
[ "$before" = "$(git hash-object "$F/.nova/rules.md")" ] || fail "rejected gardener input modified rules"

FILE="$F/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const read = fs.readFileSync;
let count = 0;
fs.readFileSync = (path, ...args) => {
  if (String(path) === process.env.FILE && ++count === 2) {
    const external = read(path, "utf8").replace("# Nova team rules\n", "# Nova team rules\n\n## `rule-20260713-44444444`\n\n- status: `proposed`\n- scope: `[\"**\"]`\n- source-summary: `동시 편집에서 추가된 정제 출처다.`\n- evidence-summary: `승인 중 변경을 감지할 필요가 있다는 근거다.`\n- origin: `propose`\n- derived-from: `[]`\n\n### Rule\n\n승인 전에 최신 규칙 문서를 다시 확인한다.\n");
    fs.writeFileSync(path, external);
  }
  return read(path, ...args);
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?concurrent=" + Date.now());
try {
  applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
  process.exitCode = 2;
} catch (error) {
  if (!/(?:records must be retired, not deleted|concurrent edit detected)/.test(error.message)) throw error;
}
' || fail "concurrent edit was not rejected"
grep -Fq 'rule-20260713-44444444' "$F/.nova/rules.md" || fail "concurrent external edit was lost"
awk '/rule-20260713-11111111/{found=1} found && /status: `proposed`/{ok=1; exit} END{exit !ok}' "$F/.nova/rules.md" || fail "failed concurrent promote partially applied"
node "$RULES" validate "$F/.nova/rules.md" >/dev/null || fail "concurrent edit store invalid"
echo "  ok"

echo "== canonical file edited between preflight and sync fails closed, both files preserved =="
CE="$T/canonical-edit"; mkdir -p "$CE/.nova"; gardener_doc > "$CE/.nova/rules.md"
cat > "$CE/CLAUDE.md" <<'MD'
# Existing project instructions

<!-- CC-RULES:START -->
<!-- NOVA:TEAM-RULES:START -->
<!-- NOVA:TEAM-RULES:END -->

## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
rules_before=$(git hash-object "$CE/.nova/rules.md")
# Wrap execFileSync so an external editor injects into the canonical projection
# region in the instant right before the projection sync exec runs — the exact
# preflight->sync window a comparison in the parent process cannot close.
FILE="$CE/.nova/rules.md" CANON="$CE/CLAUDE.md" RULES_URL="file://$RULES" node --input-type=module -e '
import cp from "node:child_process";
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const real = cp.execFileSync;
let injected = false;
cp.execFileSync = (command, args, options) => {
  if (!injected && Array.isArray(args) && args.includes("--sync-team-rules")) {
    injected = true;
    const edited = fs.readFileSync(process.env.CANON, "utf8").replace("<!-- NOVA:TEAM-RULES:START -->", "<!-- NOVA:TEAM-RULES:START -->\n- EXTERNAL-CONCURRENT-EDIT");
    fs.writeFileSync(process.env.CANON, edited);
  }
  return real(command, args, options);
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?canonical-edit=" + Date.now());
try {
  applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
  process.exitCode = 2;
} catch (error) {
  if (!/concurrent edit detected/.test(error.message)) throw error;
}
if (!injected) process.exitCode = 3;
' || fail "concurrent canonical edit during projection was not rejected"
grep -Fq 'EXTERNAL-CONCURRENT-EDIT' "$CE/CLAUDE.md" || fail "concurrent canonical edit was overwritten (last-write-wins)"
grep -Fq 'nova-rule:rule-20260713-11111111' "$CE/CLAUDE.md" && fail "failed projection still wrote the active rule"
[ "$rules_before" = "$(git hash-object "$CE/.nova/rules.md")" ] || fail "failed projection left rules.md mutated instead of restored"
awk '/rule-20260713-11111111/{found=1} found && /status: `proposed`/{ok=1; exit} END{exit !ok}' "$CE/.nova/rules.md" || fail "rules.md was not restored to its pre-approval proposed state"
node "$RULES" validate "$CE/.nova/rules.md" >/dev/null || fail "restored store invalid"
echo "  ok"

echo "== pre-capture external atomic-save fails closed and preserves the external record =="
PC="$T/pre-capture-window"; mkdir -p "$PC/.nova"; gardener_doc > "$PC/.nova/rules.md"
FILE="$PC/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import path from "node:path";
import { syncBuiltinESMExports } from "node:module";
const rename = fs.renameSync;
const dir = path.dirname(process.env.FILE);
const externalTmp = path.join(dir, ".external-editor.tmp");
const external = fs.readFileSync(process.env.FILE, "utf8").replace("# Nova team rules\n", "# Nova team rules\n\n## `rule-20260713-66666666`\n\n- status: `proposed`\n- scope: `[\"**\"]`\n- source-summary: `외부 편집기 atomic rename의 정제 출처다.`\n- evidence-summary: `사전 교체 경쟁을 탐지해야 한다는 근거다.`\n- origin: `propose`\n- derived-from: `[]`\n\n### Rule\n\n외부 atomic rename 직후에도 승인 결과를 재확인한다.\n");
let injected = false;
fs.renameSync = (from, to) => {
  if (!injected && String(from) === process.env.FILE) {
    injected = true;
    // Simulate an external editor atomic-saving a brand-new inode onto the
    // canonical path in the instant right before our own capture-rename —
    // the exact window a pre-swap identity check cannot close.
    fs.writeFileSync(externalTmp, external);
    rename(externalTmp, process.env.FILE);
  }
  return rename(from, to);
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?pre-capture-window=" + Date.now());
try {
  applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
  process.exitCode = 2;
} catch (error) {
  if (!/concurrent edit detected/.test(error.message)) throw error;
}
' || fail "pre-capture external atomic-save was not rejected"
grep -Fq 'rule-20260713-66666666' "$PC/.nova/rules.md" || fail "pre-capture external atomic-save was lost"
awk '/rule-20260713-11111111/{found=1} found && /status: `proposed`/{ok=1; exit} END{exit !ok}' "$PC/.nova/rules.md" || fail "pre-capture race returned a partial promote"
node "$RULES" validate "$PC/.nova/rules.md" >/dev/null || fail "pre-capture window store invalid"
echo "  ok"

echo "== post-install diagnostic read failure keeps the completed commit =="
VR="$T/verification-read"; mkdir -p "$VR/.nova"; gardener_doc > "$VR/.nova/rules.md"
FILE="$VR/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const link = fs.linkSync;
const read = fs.readFileSync;
let installed = false;
let injected = false;
fs.linkSync = (from, to) => {
  const result = link(from, to);
  if (String(to) === process.env.FILE) installed = true;
  return result;
};
fs.readFileSync = (path, ...args) => {
  if (installed && !injected && String(path) === process.env.FILE) {
    injected = true;
    const error = new Error("injected post-install read EIO");
    error.code = "EIO";
    throw error;
  }
  return read(path, ...args);
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?verification-read=" + Date.now());
applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
if (!injected) process.exitCode = 2;
' || fail "post-install verification read failure injection"
awk '/rule-20260713-11111111/{found=1} found && /status: `active`/{ok=1; exit} END{exit !ok}' "$VR/.nova/rules.md" || fail "diagnostic read failure lost the completed promote"
[ "$(find "$VR/.nova" -name '.rules.md.*.backup' | wc -l | tr -d ' ')" = 0 ] || fail "completed commit left a backup"
[ "$(find "$VR/.nova" -name '.rules.md.*.recovered' | wc -l | tr -d ' ')" = 1 ] || fail "completed commit did not retire its captured backup to a recovery path"
echo "  ok"

echo "== a delayed write to the captured backup after install fails closed and is not discarded =="
BW="$T/backup-delayed-write"; mkdir -p "$BW/.nova"; gardener_doc > "$BW/.nova/rules.md"
FILE="$BW/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import path from "node:path";
import { syncBuiltinESMExports } from "node:module";
const read = fs.readFileSync;
const write = fs.writeFileSync;
const dir = path.dirname(process.env.FILE);
const base = path.basename(process.env.FILE);
const backupRe = new RegExp("^\\." + base.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\.[^.]+\\.backup$");
const external = read(process.env.FILE, "utf8").replace("# Nova team rules\n", "# Nova team rules\n\n## `rule-20260713-77777777`\n\n- status: `proposed`\n- scope: `[\"**\"]`\n- source-summary: `지연 쓰기 경쟁에서 추가된 정제 출처다.`\n- evidence-summary: `캡처된 backup 삭제가 지연 쓰기를 지울 수 있다는 근거다.`\n- origin: `propose`\n- derived-from: `[]`\n\n### Rule\n\n캡처된 backup을 재확인 없이 삭제하지 않는다.\n");
let injected = false;
fs.readFileSync = (p, ...args) => {
  const result = read(p, ...args);
  if (!injected && path.dirname(String(p)) === dir && backupRe.test(path.basename(String(p)))) {
    // Simulate a file descriptor an external editor opened on the
    // canonical path before our own capture-rename: right after our first
    // read of the relocated inode (now named `backup`) returns its
    // pre-image, that same editor delivers a delayed write into it.
    injected = true;
    write(p, external);
  }
  return result;
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?backup-delayed-write=" + Date.now());
try {
  applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
  process.exitCode = 2;
} catch (error) {
  if (!/concurrent edit detected in the captured backup/.test(error.message)) throw error;
}
if (!injected) process.exitCode = 2;
' || fail "delayed write to captured backup was not rejected"
[ "$(find "$BW/.nova" -name '.rules.md.*.backup' | wc -l | tr -d ' ')" = 1 ] || fail "delayed backup write did not preserve the backup file"
grep -rFq 'rule-20260713-77777777' "$BW/.nova" || fail "delayed write to captured backup was lost"
awk '/rule-20260713-11111111/{found=1} found && /status: `active`/{ok=1; exit} END{exit !ok}' "$BW/.nova/rules.md" || fail "delayed backup write reverted the already-installed promote"
node "$RULES" validate "$BW/.nova/rules.md" >/dev/null || fail "delayed backup write store invalid"
echo "  ok"

echo "== post-install in-place edit fails closed and crash keeps canonical path =="
RW="$T/rename-window"; mkdir -p "$RW/.nova"; gardener_doc > "$RW/.nova/rules.md"
FILE="$RW/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const link = fs.linkSync;
const write = fs.writeFileSync;
const external = fs.readFileSync(process.env.FILE, "utf8").replace("# Nova team rules\n", "# Nova team rules\n\n## `rule-20260713-55555555`\n\n- status: `proposed`\n- scope: `[\"**\"]`\n- source-summary: `교체 직후 외부 편집의 정제 출처다.`\n- evidence-summary: `성공 오판을 막기 위해 결과 확인이 필요하다.`\n- origin: `propose`\n- derived-from: `[]`\n\n### Rule\n\n저장 결과를 반환하기 전에 실제 파일을 확인한다.\n");
let injected = false;
fs.linkSync = (from, to) => {
  const result = link(from, to);
  if (!injected && String(to) === process.env.FILE) {
    injected = true;
    write(process.env.FILE, external);
  }
  return result;
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?rename-window=" + Date.now());
try {
  applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
  process.exitCode = 2;
} catch (error) {
  if (!/concurrent edit detected/.test(error.message)) throw error;
}
' || fail "post-install edit was not rejected"
grep -Fq 'rule-20260713-55555555' "$RW/.nova/rules.md" || fail "post-install external edit was lost"
awk '/rule-20260713-11111111/{found=1} found && /status: `proposed`/{ok=1; exit} END{exit !ok}' "$RW/.nova/rules.md" || fail "post-install edit returned a partial promote"
node "$RULES" validate "$RW/.nova/rules.md" >/dev/null || fail "post-install edit store invalid"
[ "$(find "$RW/.nova" -name '.rules.md.*.backup' | wc -l | tr -d ' ')" = 1 ] || fail "post-install edit did not preserve the original backup"
[ "$(find "$RW/.nova" -name '.rules.md.*.conflict' | wc -l | tr -d ' ')" = 0 ] || fail "post-install edit created an unnecessary conflict file"

CR="$T/crash-window"; mkdir -p "$CR/.nova"; gardener_doc > "$CR/.nova/rules.md"
if FILE="$CR/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const rename = fs.renameSync;
fs.renameSync = (from, to) => {
  const result = rename(from, to);
  if (String(from) === process.env.FILE) process.exit(91);
  return result;
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?crash-window=" + Date.now());
applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
'; then
  fail "crash injection unexpectedly succeeded"
fi
[ -f "$CR/.nova/rules.md" ] || fail "crash removed canonical rules path"
node "$RULES" validate "$CR/.nova/rules.md" >/dev/null || fail "crash left invalid canonical rules"
rm -f "$CR/.nova/.rules.lock"
echo "  ok"

echo "== a hard kill mid-swap (no exit handler) leaves a recoverable backup; next writer fails closed =="
SK="$T/sigkill-window"; mkdir -p "$SK/.nova"; gardener_doc > "$SK/.nova/rules.md"
# Simulate the on-disk state right after a SIGKILL lands between the
# capture-rename and the exclusive re-link, bypassing the process.exit()
# safety net entirely: `path` is relocated to a `.backup` sibling and never
# re-linked.
mv "$SK/.nova/rules.md" "$SK/.nova/.rules.md.deadbeef.backup"
cat > "$T/sigkill-proposal.json" <<'JSON'
{
  "scope": ["**"],
  "source-summary": "사용자 교정에서 검증 원칙을 확인했다.",
  "evidence-summary": "재발 방지를 위해 팀 검토가 필요하다.",
  "rule": "검증 결과를 확인한다."
}
JSON
node "$RULES" propose "$SK/.nova/rules.md" < "$T/sigkill-proposal.json" >/dev/null 2>&1 && fail "propose silently created a fresh store over an orphaned backup"
[ -f "$SK/.nova/rules.md" ] && fail "propose created a fresh rules.md instead of failing closed"
[ -f "$SK/.nova/.rules.md.deadbeef.backup" ] || fail "orphaned backup was deleted instead of preserved"
grep -Fq '공유 함수 변경 전에 호출부를 확인한다.' "$SK/.nova/.rules.md.deadbeef.backup" || fail "orphaned backup lost its content"
printf '{"id":"rule-20260713-11111111"}\n' | node "$RULES" promote "$SK/.nova/rules.md" >/dev/null 2>&1 && fail "promote silently created a fresh store over an orphaned backup"
[ -f "$SK/.nova/rules.md" ] && fail "promote created a fresh rules.md instead of failing closed"
echo "  ok"

echo "== allowlist write failure leaves canonical rules unchanged =="
IO="$T/gitignore-io"; mkdir -p "$IO/.nova"; gardener_doc > "$IO/.nova/rules.md"
io_before=$(git hash-object "$IO/.nova/rules.md")
FILE="$IO/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module -e '
import fs from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const rename = fs.renameSync;
fs.renameSync = (from, to) => {
  if (String(to).endsWith("/.gitignore")) {
    const error = new Error("injected allowlist failure");
    error.code = "EIO";
    throw error;
  }
  return rename(from, to);
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + "?gitignore-io=" + Date.now());
try {
  applyGardenerOperation(process.env.FILE, "promote", JSON.stringify({id:"rule-20260713-11111111"}));
  process.exitCode = 2;
} catch (error) {
  if (error.code !== "EIO") throw error;
}
' || fail "allowlist failure injection"
[ "$io_before" = "$(git hash-object "$IO/.nova/rules.md")" ] || fail "allowlist failure partially changed rules"
[ "$(find "$IO/.nova" -name '.gitignore.*.tmp' | wc -l | tr -d ' ')" = 0 ] || fail "allowlist failure left temp residue"
echo "  ok"

echo ""
echo "ALL PASS"
