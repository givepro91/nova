#!/usr/bin/env bash
# End-to-end team-rules checks: (A) two independent git clones of the SAME
# approval commit render a byte-identical active-rule projection with no
# proposed/retired leakage and no raw evidence; (B) an isolated-HOME local
# marketplace install runs propose -> promote -> projection with only the
# Claude Code plugin, git, and node -- no company-internal tools or network.
# Exits non-zero on first failure.
set -eu
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
RULES="$NOVA/plugins/nova/scripts/team-rules.mjs"
APPLY="$NOVA/plugins/nova/scripts/apply-block.mjs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# The NOVA:TEAM-RULES projection region (markers inclusive) is the "active rule
# set" a new session auto-applies; two members at the same commit must see it
# byte-for-byte identical.
proj() { awk '/^<!-- NOVA:TEAM-RULES:START -->$/{p=1} p{print} /^<!-- NOVA:TEAM-RULES:END -->$/{p=0}' "$1"; }

empty_block() {
  cat <<'MD'
# Team project

<!-- CC-RULES:START -->
<!-- NOVA:TEAM-RULES:START -->
<!-- NOVA:TEAM-RULES:END -->

## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->
MD
}

echo "== two independent clones of one approval commit share the active rule set =="
W="$T/workrepo"; mkdir -p "$W/.nova"
git init -q "$W"
git -C "$W" config user.name test
git -C "$W" config user.email test@example.com
cp "$NOVA/.nova/.gitignore" "$W/.nova/.gitignore"
empty_block > "$W/CLAUDE.md"

idA=$(printf '{"scope":["src/**"],"source-summary":"제안 A에서 호출부 확인 원칙을 정제했다.","evidence-summary":"호출부 누락의 반복을 막기 위한 근거다.","rule":"공유 함수 변경 전에 모든 호출부를 확인한다."}\n' \
  | node "$RULES" propose "$W/.nova/rules.md" | sed 's/^proposed: //')
idB=$(printf '{"scope":["docs/**"],"source-summary":"제안 B에서 문서 검토 원칙을 정제했다.","evidence-summary":"오래된 문서 규칙의 이력을 남길 근거다.","rule":"문서 변경 전에 현재 계약을 확인한다."}\n' \
  | node "$RULES" propose "$W/.nova/rules.md" | sed 's/^proposed: //')
idC=$(printf '{"scope":["tests/**"],"source-summary":"제안 C에서 검증 범위 원칙을 정제했다.","evidence-summary":"아직 사람의 활성화 승인이 필요하다.","rule":"변경한 동작의 관련 테스트를 실행한다."}\n' \
  | node "$RULES" propose "$W/.nova/rules.md" | sed 's/^proposed: //')
[ -n "$idA" ] && [ -n "$idB" ] && [ -n "$idC" ] || fail "propose did not return stable ids"

printf '{"id":"%s"}\n' "$idA" | node "$RULES" promote "$W/.nova/rules.md" >/dev/null || fail "promote A"
printf '{"id":"%s"}\n' "$idB" | node "$RULES" promote "$W/.nova/rules.md" >/dev/null || fail "promote B"
printf '{"id":"%s","retired-reason":"새 문서 절차로 대체되어 폐기한다."}\n' "$idB" \
  | node "$RULES" retire "$W/.nova/rules.md" >/dev/null || fail "retire B"
# idC stays proposed; only idA should remain active.

# Raw local evidence must never enter the tracked checkout.
printf '{"output":"token=ghp_SECRETSECRETSECRET1234567890"}\n' > "$W/.nova/evidence.jsonl"
git -C "$W" add -A
git -C "$W" commit -qm "approve team rules" >/dev/null
git -C "$W" ls-files --error-unmatch .nova/evidence.jsonl >/dev/null 2>&1 && fail "evidence.jsonl entered the approval commit"

git clone -q "$W" "$T/cloneA"
git clone -q "$W" "$T/cloneB"
[ "$(git -C "$T/cloneA" rev-parse HEAD)" = "$(git -C "$T/cloneB" rev-parse HEAD)" ] || fail "clones are not on the same commit"

projA="$T/projA"; projB="$T/projB"
proj "$T/cloneA/CLAUDE.md" > "$projA"
proj "$T/cloneB/CLAUDE.md" > "$projB"
cmp "$projA" "$projB" >/dev/null || fail "independent clones render different active projections"
grep -Fq "nova-rule:$idA" "$projA" || fail "active rule A missing from the projection"
grep -Fq "nova-rule:$idB" "$projA" && fail "retired rule B leaked into the projection"
grep -Fq "nova-rule:$idC" "$projA" && fail "proposed rule C leaked into the projection"
grep -rFq 'ghp_SECRETSECRETSECRET1234567890' "$T/cloneA" && fail "raw evidence secret leaked into the checkout"

# Re-projecting from the committed rules.md in each clone is deterministic and
# idempotent: no diff against the approval commit, still byte-identical.
node "$APPLY" --sync-team-rules "$T/cloneA/.nova/rules.md" "$T/cloneA/CLAUDE.md" >/dev/null || fail "clone A re-sync"
node "$APPLY" --sync-team-rules "$T/cloneB/.nova/rules.md" "$T/cloneB/CLAUDE.md" >/dev/null || fail "clone B re-sync"
git -C "$T/cloneA" diff --quiet -- CLAUDE.md || fail "clone A re-sync changed the committed projection"
git -C "$T/cloneB" diff --quiet -- CLAUDE.md || fail "clone B re-sync changed the committed projection"
cmp <(proj "$T/cloneA/CLAUDE.md") <(proj "$T/cloneB/CLAUDE.md") >/dev/null || fail "re-synced clones diverge"
echo "  ok"

echo "== isolated-HOME local marketplace install runs propose -> promote -> projection =="
CLAUDE=$(command -v claude || true)
[ -n "$CLAUDE" ] || fail "claude CLI unavailable — marketplace install E2E is required"
IH="$T/inst-home"; mkdir -p "$IH"
HOME="$IH" "$CLAUDE" plugin marketplace add "$NOVA" </dev/null >/dev/null 2>&1 || fail "claude plugin marketplace add"
HOME="$IH" "$CLAUDE" plugin install nova@nova </dev/null >/dev/null 2>&1 || fail "claude plugin install nova@nova"
INSTALLED=$(find "$IH/.claude" -path '*/scripts/team-rules.mjs' -print -quit 2>/dev/null || true)
[ -n "$INSTALLED" ] || fail "installed team-rules.mjs not found under the isolated HOME"
INSTALLED_APPLY="$(dirname "$INSTALLED")/apply-block.mjs"
[ -f "$INSTALLED_APPLY" ] || fail "installed apply-block.mjs not found next to team-rules.mjs"

IR="$T/inst-repo"; mkdir -p "$IR/.nova"
git init -q "$IR"
empty_block > "$IR/CLAUDE.md"
printf '{"scope":["**"],"source-summary":"설치 검증에서 완료 선언 조건을 확인했다.","evidence-summary":"검증 누락이 반복될 수 있어 성공 확인이 필요하다.","rule":"변경 완료를 알리기 전에 관련 검증 명령의 성공을 확인한다."}\n' \
  | node "$INSTALLED" propose "$IR/.nova/rules.md" > "$T/inst-propose.out" || fail "installed CLI propose failed"
grep -Eq '^proposed: rule-[0-9]{8}-[0-9a-f]{8}$' "$T/inst-propose.out" || fail "installed CLI propose printed no stable id"
[ -f "$IR/.nova/rules.md" ] || fail "installed CLI propose did not create rules.md"
iid=$(sed 's/^proposed: //' "$T/inst-propose.out")
grep -Fq 'nova-rule:' "$IR/CLAUDE.md" && fail "installed propose projected before human approval"
printf '{"id":"%s"}\n' "$iid" | node "$INSTALLED" promote "$IR/.nova/rules.md" >/dev/null || fail "installed CLI promote failed"
grep -Fq "nova-rule:$iid" "$IR/CLAUDE.md" || fail "installed CLI promote did not project into CLAUDE.md"
node "$INSTALLED_APPLY" --check-team-rules "$IR/.nova/rules.md" "$IR/CLAUDE.md" >/dev/null || fail "installed CLI projection out of sync"
echo "  ok (marketplace install)"

echo ""
echo "ALL PASS"
