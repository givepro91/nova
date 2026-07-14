#!/usr/bin/env bash
# End-to-end fixtures for the human-approved team-rule lifecycle.
set -eu

NOVA="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$NOVA/plugins/nova/scripts/team-rules.mjs"
APPLY="$NOVA/plugins/nova/scripts/apply-block.mjs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
hash_file() { git hash-object "$1"; }

init_repo() {
  repo=$1
  git init -q "$repo"
  git -C "$repo" config user.name fixture
  git -C "$repo" config user.email fixture@example.com
  cat > "$repo/CLAUDE.md" <<'MD'
# Fixture project

<!-- CC-RULES:START -->
## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
  printf '%s\n' fixture > "$repo/README.md"
  git -C "$repo" add CLAUDE.md README.md
  git -C "$repo" commit -qm baseline
}

seed_rules() {
  cat <<'MD'
---
schema: nova-team-rules/v1
---

# Nova team rules

## `rule-20260714-11111111`

- status: `proposed`
- scope: `["src/**"]`
- source-summary: `첫 제안에서 호출부 확인 원칙을 정제했다.`
- evidence-summary: `호출부 누락의 반복을 막기 위한 근거다.`
- origin: `propose`
- derived-from: `[]`

### Rule

공유 함수 변경 전에 호출부를 확인한다.

## `rule-20260714-22222222`

- status: `proposed`
- scope: `["tests/**"]`
- source-summary: `둘째 제안에서 검증 범위 원칙을 정제했다.`
- evidence-summary: `관련 검증 누락의 반복을 막기 위한 근거다.`
- origin: `propose`
- derived-from: `[]`

### Rule

변경한 동작의 관련 테스트를 실행한다.
MD
}

echo "== propose is unprojected; local evidence stays ignored =="
P="$T/propose"
init_repo "$P"
mkdir -p "$P/.nova"
printf '%s\n' '{"output":"token=ghp_12345678901234567890","stderr":"raw command output"}' > "$P/.nova/evidence.jsonl"
claude_before=$(hash_file "$P/CLAUDE.md")
head_before=$(git -C "$P" rev-parse HEAD)
cat > "$T/proposal.json" <<'JSON'
{
  "scope": ["src/**"],
  "source-summary": "사용자 교정에서 호출부 검토 원칙을 확인했다.",
  "evidence-summary": "호출부 누락의 반복을 막기 위해 팀 검토가 필요하다.",
  "rule": "공유 함수 시그니처를 바꾸기 전에 모든 호출부를 확인한다."
}
JSON
node "$RULES" propose "$P/.nova/rules.md" < "$T/proposal.json" > "$T/propose.out" || fail "propose"
proposal_id=$(sed -n 's/^proposed: //p' "$T/propose.out")
[ -n "$proposal_id" ] || fail "propose did not return an id"
[ "$claude_before" = "$(hash_file "$P/CLAUDE.md")" ] || fail "propose changed CLAUDE.md"
[ "$head_before" = "$(git -C "$P" rev-parse HEAD)" ] || fail "propose created a commit"

RULES_URL="file://$RULES" RULES_FILE="$P/.nova/rules.md" RULE_ID="$proposal_id" node --input-type=module <<'JS' || fail "proposed record assertion"
import fs from 'node:fs';
import assert from 'node:assert/strict';
const { parseTeamRules } = await import(process.env.RULES_URL);
const records = parseTeamRules(fs.readFileSync(process.env.RULES_FILE, 'utf8')).records;
assert.equal(records.length, 1);
assert.deepEqual(records[0], {
  id: process.env.RULE_ID,
  status: 'proposed',
  scope: ['src/**'],
  sourceSummary: '사용자 교정에서 호출부 검토 원칙을 확인했다.',
  evidenceSummary: '호출부 누락의 반복을 막기 위해 팀 검토가 필요하다.',
  origin: 'propose',
  derivedFrom: [],
  retiredReason: undefined,
  body: '공유 함수 시그니처를 바꾸기 전에 모든 호출부를 확인한다.',
});
JS

git -C "$P" check-ignore -v .nova/evidence.jsonl > "$T/check-ignore.out" || fail "evidence is not ignored"
grep -Eq '^\.nova/\.gitignore:1:\*[[:space:]]+\.nova/evidence\.jsonl$' "$T/check-ignore.out" || fail "unexpected git check-ignore -v result"
git -C "$P" status --porcelain --untracked-files=all > "$T/status.out"
printf '%s\n' '?? .nova/.gitignore' '?? .nova/rules.md' > "$T/status.expected"
cmp "$T/status.expected" "$T/status.out" >/dev/null || fail "unexpected git status --porcelain result"
grep -Fq 'ghp_12345678901234567890' "$P/.nova/rules.md" && fail "secret copied into tracked rules"
echo "  check-ignore: $(cat "$T/check-ignore.out")"
echo "  status: $(tr '\n' ';' < "$T/status.out")"
echo "  ok"

echo "== promote projects once and repeated sync has zero diff =="
printf '{"id":"%s"}\n' "$proposal_id" | node "$RULES" promote "$P/.nova/rules.md" >/dev/null || fail "promote"
[ "$(grep -Fc "nova-rule:$proposal_id" "$P/CLAUDE.md")" -eq 1 ] || fail "promoted rule projection count"
git -C "$P" add CLAUDE.md .nova/.gitignore .nova/rules.md
git -C "$P" commit -qm promoted
node "$APPLY" --sync-team-rules "$P/.nova/rules.md" "$P/CLAUDE.md" >/dev/null || fail "repeat projection sync"
git -C "$P" diff --exit-code >/dev/null || fail "repeat sync produced a diff"
echo "  ok"

echo "== retire preserves history and removes the projection =="
printf '{"id":"%s","retired-reason":"새 절차로 대체되어 더 이상 적용하지 않는다."}\n' "$proposal_id" |
  node "$RULES" retire "$P/.nova/rules.md" >/dev/null || fail "retire"
grep -Fq -- '- retired-reason: `새 절차로 대체되어 더 이상 적용하지 않는다.`' "$P/.nova/rules.md" || fail "retire reason missing"
grep -Fq '공유 함수 시그니처를 바꾸기 전에 모든 호출부를 확인한다.' "$P/.nova/rules.md" || fail "retired rule history missing"
grep -Fq "nova-rule:$proposal_id" "$P/CLAUDE.md" && fail "retired rule remained projected"
echo "  ok"

assert_replacement() {
  repo=$1
  operation=$2
  result_id=$3
  expected_scope=$4
  RULES_URL="file://$RULES" RULES_FILE="$repo/.nova/rules.md" RESULT_ID="$result_id" OPERATION="$operation" EXPECTED_SCOPE="$expected_scope" node --input-type=module <<'JS'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const { parseTeamRules } = await import(process.env.RULES_URL);
const records = parseTeamRules(fs.readFileSync(process.env.RULES_FILE, 'utf8')).records;
const result = records.find((record) => record.id === process.env.RESULT_ID);
assert.ok(result, 'replacement record missing');
assert.equal(result.status, 'active');
assert.equal(result.origin, process.env.OPERATION);
assert.deepEqual(result.derivedFrom, ['rule-20260714-11111111', 'rule-20260714-22222222']);
assert.deepEqual(result.scope, JSON.parse(process.env.EXPECTED_SCOPE));
for (const id of result.derivedFrom) {
  const source = records.find((record) => record.id === id);
  assert.equal(source.status, 'retired');
  assert.match(source.retiredReason, new RegExp(process.env.RESULT_ID));
}
JS
}

prepare_gardener_repo() {
  repo=$1
  init_repo "$repo"
  mkdir -p "$repo/.nova"
  seed_rules > "$repo/.nova/rules.md"
}

cat > "$T/merge.json" <<'JSON'
{
  "derived-from": ["rule-20260714-11111111", "rule-20260714-22222222"],
  "scope": ["src/**", "tests/**"],
  "source-summary": "두 제안의 호출부와 검증 범위를 함께 정제했다.",
  "evidence-summary": "변경 영향과 관련 검증을 함께 확인해야 재발을 막을 수 있다.",
  "rule": "공유 동작을 바꿀 때 호출부와 관련 테스트를 함께 확인한다."
}
JSON

echo "== merge preserves provenance and explicit scope =="
M="$T/merge"
prepare_gardener_repo "$M"
node "$RULES" merge "$M/.nova/rules.md" < "$T/merge.json" > "$T/merge.out" || fail "merge"
merge_id=$(sed -n 's/^merge: //p' "$T/merge.out")
assert_replacement "$M" merge "$merge_id" '["src/**","tests/**"]' || fail "merge assertions"
[ "$(grep -Fc "nova-rule:$merge_id" "$M/CLAUDE.md")" -eq 1 ] || fail "merge replacement projection"
grep -Fq 'nova-rule:rule-20260714-11111111' "$M/CLAUDE.md" && fail "merge source remained projected"
echo "  ok"

echo "== generalize preserves provenance and widened scope =="
G="$T/generalize"
prepare_gardener_repo "$G"
sed -e 's/"scope": \["src\/\*\*", "tests\/\*\*"\]/"scope": ["**"]/' \
  -e 's/공유 동작을 바꿀 때 호출부와 관련 테스트를 함께 확인한다./행동을 변경할 때 영향 범위와 검증 범위를 먼저 확인한다./' \
  "$T/merge.json" > "$T/generalize.json"
node "$RULES" generalize "$G/.nova/rules.md" < "$T/generalize.json" > "$T/generalize.out" || fail "generalize"
generalize_id=$(sed -n 's/^generalize: //p' "$T/generalize.out")
assert_replacement "$G" generalize "$generalize_id" '["**"]' || fail "generalize assertions"
[ "$(grep -Fc "nova-rule:$generalize_id" "$G/CLAUDE.md")" -eq 1 ] || fail "generalize replacement projection"
echo "  ok"

echo "== malformed and merge-conflicted stores fail closed =="
claude_before=$(hash_file "$M/CLAUDE.md")
sed 's/schema: nova-team-rules\/v1/schema: nova-team-rules\/v2/' "$M/.nova/rules.md" > "$T/malformed.md"
node "$APPLY" --sync-team-rules "$T/malformed.md" "$M/CLAUDE.md" >/dev/null 2>&1 && fail "malformed store synced"
[ "$claude_before" = "$(hash_file "$M/CLAUDE.md")" ] || fail "malformed sync changed CLAUDE.md"
c1='<<<<<<< HEAD'; c2='======='; c3='>>>>>>> concurrent-edit'
awk -v c1="$c1" -v c2="$c2" -v c3="$c3" '
  $0 == "# Nova team rules" { print; print c1; print "left"; print c2; print "right"; print c3; next }
  { print }
' "$M/.nova/rules.md" > "$T/conflicted.md"
node "$APPLY" --sync-team-rules "$T/conflicted.md" "$M/CLAUDE.md" >/dev/null 2>&1 && fail "conflicted store synced"
[ "$claude_before" = "$(hash_file "$M/CLAUDE.md")" ] || fail "conflicted sync changed CLAUDE.md"
echo "  ok"

echo "== concurrent gardener edit fails closed; CLAUDE.md is byte-identical =="
C="$T/concurrent"
prepare_gardener_repo "$C"
claude_before=$(hash_file "$C/CLAUDE.md")
FILE="$C/.nova/rules.md" RULES_URL="file://$RULES" node --input-type=module <<'JS' || fail "concurrent edit fixture"
import fs from 'node:fs';
import { syncBuiltinESMExports } from 'node:module';
const originalRead = fs.readFileSync;
let reads = 0;
fs.readFileSync = (path, ...args) => {
  if (String(path) === process.env.FILE && ++reads === 2) {
    const external = originalRead(path, 'utf8').replace(
      '# Nova team rules\n',
      '# Nova team rules\n\n## `rule-20260714-33333333`\n\n- status: `proposed`\n- scope: `["**"]`\n- source-summary: `동시 편집에서 추가된 정제 출처다.`\n- evidence-summary: `승인 중 변경을 감지해야 한다는 근거다.`\n- origin: `propose`\n- derived-from: `[]`\n\n### Rule\n\n승인 전에 최신 규칙 문서를 다시 확인한다.\n',
    );
    fs.writeFileSync(path, external);
  }
  return originalRead(path, ...args);
};
syncBuiltinESMExports();
const { applyGardenerOperation } = await import(process.env.RULES_URL + '?fixture=' + Date.now());
try {
  applyGardenerOperation(process.env.FILE, 'promote', JSON.stringify({ id: 'rule-20260714-11111111' }));
  process.exitCode = 2;
} catch (error) {
  if (!/concurrent edit detected/.test(error.message)) throw error;
}
JS
[ "$claude_before" = "$(hash_file "$C/CLAUDE.md")" ] || fail "concurrent failure changed CLAUDE.md"
grep -Fq 'rule-20260714-33333333' "$C/.nova/rules.md" || fail "concurrent external edit was lost"
RULES_URL="file://$RULES" RULES_FILE="$C/.nova/rules.md" node --input-type=module <<'JS' || fail "concurrent result assertion"
import fs from 'node:fs';
import assert from 'node:assert/strict';
const { parseTeamRules } = await import(process.env.RULES_URL);
const records = parseTeamRules(fs.readFileSync(process.env.RULES_FILE, 'utf8')).records;
assert.equal(records.find((record) => record.id === 'rule-20260714-11111111').status, 'proposed');
assert.equal(records.find((record) => record.id === 'rule-20260714-33333333').status, 'proposed');
JS
echo "  ok"

echo ""
echo "ALL PASS"
