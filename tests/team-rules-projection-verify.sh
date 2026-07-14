#!/usr/bin/env bash
# Active-only projection checks for .nova/rules.md -> CC-RULES managed block.
set -eu
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
APPLY="$NOVA/plugins/nova/scripts/apply-block.mjs"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

cat > "$T/rules.md" <<'MD'
---
schema: nova-team-rules/v1
---

# Nova team rules

## `rule-20260714-33333333`

- status: `retired`
- scope: `["legacy/**"]`
- source-summary: `사용자 교정에서 과거 규칙의 범위를 확인했다.`
- evidence-summary: `현재 구조에서는 기존 규칙을 폐기해야 한다.`
- origin: `propose`
- derived-from: `[]`
- retired-reason: `현재 구조에서 더 이상 적용되지 않는다.`

### Rule

과거 규칙은 새 작업에 적용하지 않는다.

## `rule-20260714-22222222`

- status: `active`
- scope: `["src/**","tests/**"]`
- source-summary: `사용자 교정에서 호출부 확인 원칙을 확인했다.`
- evidence-summary: `호출부 누락의 반복을 막아야 한다.`
- origin: `propose`
- derived-from: `[]`

### Rule

공유 함수 변경 전에 모든 호출부를 확인한다.

## `rule-20260714-11111111`

- status: `active`
- scope: `["**"]`
- source-summary: `사용자 교정에서 검증 원칙을 확인했다.`
- evidence-summary: `완료 선언 전에 성공 근거가 필요하다.`
- origin: `propose`
- derived-from: `[]`

### Rule

완료를 알리기 전에 관련 검증의 성공을 확인한다.

## `rule-20260714-44444444`

- status: `proposed`
- scope: `["docs/**"]`
- source-summary: `사용자 교정에서 문서 검토 후보를 확인했다.`
- evidence-summary: `아직 사람의 활성화 승인이 필요하다.`
- origin: `propose`
- derived-from: `[]`

### Rule

문서 변경 전에 링크를 모두 확인한다.
MD

cat > "$T/CLAUDE.md" <<'MD'
# Existing project instructions

keep-before

<!-- CC-RULES:START -->
<!-- Managed by /claude-md. -->

## Working Discipline
- Keep this section.

## Self-Learning Rules
<!-- LEARN:ANCHOR -->
- (2026-07-13) keep learned rule
<!-- CC-RULES:END -->

keep-after
MD

echo "== active-only stable projection + check =="
node "$APPLY" --sync-team-rules "$T/rules.md" "$T/CLAUDE.md" >/dev/null || fail "initial sync"
grep -Fq 'keep-before' "$T/CLAUDE.md" || fail "preamble changed"
grep -Fq 'keep-after' "$T/CLAUDE.md" || fail "trailing content changed"
grep -Fq 'keep learned rule' "$T/CLAUDE.md" || fail "learned rule changed"
[ "$(grep -Fc '<!-- NOVA:TEAM-RULES:START -->' "$T/CLAUDE.md")" -eq 1 ] || fail "START count"
[ "$(grep -Fc '<!-- NOVA:TEAM-RULES:END -->' "$T/CLAUDE.md")" -eq 1 ] || fail "END count"
grep -Fq -- '- [scope: **] 완료를 알리기 전에 관련 검증의 성공을 확인한다. <!-- nova-rule:rule-20260714-11111111 -->' "$T/CLAUDE.md" || fail "first active rule"
grep -Fq -- '- [scope: src/**, tests/**] 공유 함수 변경 전에 모든 호출부를 확인한다. <!-- nova-rule:rule-20260714-22222222 -->' "$T/CLAUDE.md" || fail "second active rule"
first=$(grep -n 'nova-rule:rule-20260714-11111111' "$T/CLAUDE.md" | cut -d: -f1)
second=$(grep -n 'nova-rule:rule-20260714-22222222' "$T/CLAUDE.md" | cut -d: -f1)
[ "$first" -lt "$second" ] || fail "ID ordering"
grep -Fq 'rule-20260714-33333333' "$T/CLAUDE.md" && fail "retired projected"
grep -Fq 'rule-20260714-44444444' "$T/CLAUDE.md" && fail "proposed projected"
node "$APPLY" --check-team-rules "$T/rules.md" "$T/CLAUDE.md" >/dev/null || fail "check after sync"
before=$(git hash-object "$T/CLAUDE.md")
node "$APPLY" --sync-team-rules "$T/rules.md" "$T/CLAUDE.md" >/dev/null || fail "second sync"
[ "$before" = "$(git hash-object "$T/CLAUDE.md")" ] || fail "second sync changed bytes"
echo "  ok"

echo "== projection markers outside the managed block stay user-owned =="
cat > "$T/outside-example.md" <<'MD'
# Schema documentation

```md
<!-- NOVA:TEAM-RULES:START -->
- example only
<!-- NOVA:TEAM-RULES:END -->
```

keep-before

<!-- CC-RULES:START -->
## Self-Learning Rules
<!-- LEARN:ANCHOR -->
<!-- CC-RULES:END -->

keep-after
MD
outside_bytes() {
  awk '
    /^<!-- CC-RULES:START -->$/ { managed = 1; next }
    /^<!-- CC-RULES:END -->$/ { managed = 0; next }
    !managed { print }
  ' "$1"
}
outside_before=$(outside_bytes "$T/outside-example.md" | git hash-object --stdin)
node "$APPLY" --sync-team-rules "$T/rules.md" "$T/outside-example.md" >/dev/null || fail "sync with outside marker example"
node "$APPLY" --check-team-rules "$T/rules.md" "$T/outside-example.md" >/dev/null || fail "check with outside marker example"
[ "$outside_before" = "$(outside_bytes "$T/outside-example.md" | git hash-object --stdin)" ] || fail "sync changed content outside managed block"
[ "$(grep -Fc '<!-- NOVA:TEAM-RULES:START -->' "$T/outside-example.md")" -eq 2 ] || fail "outside START example was consumed"
[ "$(grep -Fc '<!-- NOVA:TEAM-RULES:END -->' "$T/outside-example.md")" -eq 2 ] || fail "outside END example was consumed"
echo "  ok"

echo "== ordinary block regeneration preserves both rule lanes =="
cat > "$T/new-body.md" <<'MD'
## Working Discipline
- Regenerated section.

<!-- NOVA:TEAM-RULES:START -->
<!-- NOVA:TEAM-RULES:END -->

## Self-Learning Rules
<!-- LEARN:ANCHOR -->
MD
node "$APPLY" "$T/CLAUDE.md" < "$T/new-body.md" >/dev/null || fail "ordinary regeneration"
grep -Fq 'nova-rule:rule-20260714-11111111' "$T/CLAUDE.md" || fail "projection lost on regeneration"
grep -Fq 'keep learned rule' "$T/CLAUDE.md" || fail "learned rule lost on regeneration"
node "$APPLY" --check-team-rules "$T/rules.md" "$T/CLAUDE.md" >/dev/null || fail "check after regeneration"
echo "  ok"

echo "== check is read-only when projection is stale =="
sed 's/공유 함수 변경 전에 모든 호출부를 확인한다./공유 함수 변경 전에 호출부와 문서를 확인한다./' "$T/rules.md" > "$T/changed-rules.md"
before=$(git hash-object "$T/CLAUDE.md")
node "$APPLY" --check-team-rules "$T/changed-rules.md" "$T/CLAUDE.md" >/dev/null 2>&1 && fail "stale check passed"
[ "$before" = "$(git hash-object "$T/CLAUDE.md")" ] || fail "check modified target"
echo "  ok"

echo "== invalid inputs and conflicted target fail without writes =="
sed 's/schema: nova-team-rules\/v1/schema: nova-team-rules\/v2/' "$T/rules.md" > "$T/bad-schema.md"
sed 's/derived-from: `\[\]`/derived-from: `["rule-20260714-99999999"]`/' "$T/rules.md" > "$T/missing-provenance.md"
awk '{ print } $0 == "# Nova team rules" { print "<<<<<<< HEAD" }' "$T/rules.md" > "$T/conflicted-rules.md"
for invalid in "$T/bad-schema.md" "$T/missing-provenance.md" "$T/conflicted-rules.md"; do
  before=$(git hash-object "$T/CLAUDE.md")
  node "$APPLY" --sync-team-rules "$invalid" "$T/CLAUDE.md" >/dev/null 2>&1 && fail "invalid rules accepted: $invalid"
  [ "$before" = "$(git hash-object "$T/CLAUDE.md")" ] || fail "invalid rules modified target"
done
cp "$T/CLAUDE.md" "$T/conflicted-CLAUDE.md"
# Assemble the conflict markers from variables (never as a literal line start
# in this script's own source) so this fixture doesn't itself trip `git diff
# --check`'s leftover-conflict-marker scan of the test file.
c1='<<<<<<< HEAD'; c2='======='; c3='>>>>>>> branch'
awk -v c1="$c1" -v c2="$c2" -v c3="$c3" '
  index($0, "keep-after") { print c1; print "conflict"; print c2; print "other"; print c3 }
  { print }
' "$T/conflicted-CLAUDE.md" > "$T/conflicted-CLAUDE.md.new"
mv "$T/conflicted-CLAUDE.md.new" "$T/conflicted-CLAUDE.md"
before=$(git hash-object "$T/conflicted-CLAUDE.md")
node "$APPLY" --sync-team-rules "$T/rules.md" "$T/conflicted-CLAUDE.md" >/dev/null 2>&1 && fail "conflicted target accepted"
[ "$before" = "$(git hash-object "$T/conflicted-CLAUDE.md")" ] || fail "conflicted target modified"
echo "  ok"

echo "== misaligned projection fails closed without learned-rule loss =="
cat > "$T/wrapped-anchor.md" <<'MD'
<!-- CC-RULES:START -->
<!-- NOVA:TEAM-RULES:START -->
<!-- LEARN:ANCHOR -->
- (2026-07-13) precious learned rule
<!-- NOVA:TEAM-RULES:END -->
<!-- CC-RULES:END -->
MD
before=$(git hash-object "$T/wrapped-anchor.md")
node "$APPLY" --sync-team-rules "$T/rules.md" "$T/wrapped-anchor.md" >/dev/null 2>&1 && fail "projection wrapping anchor accepted"
[ "$before" = "$(git hash-object "$T/wrapped-anchor.md")" ] || fail "wrapped anchor target modified"
grep -Fq 'precious learned rule' "$T/wrapped-anchor.md" || fail "wrapped learned rule lost"

cat > "$T/after-anchor.md" <<'MD'
<!-- CC-RULES:START -->
<!-- LEARN:ANCHOR -->
- (2026-07-13) precious learned rule
<!-- NOVA:TEAM-RULES:START -->
<!-- NOVA:TEAM-RULES:END -->
<!-- CC-RULES:END -->
MD
before=$(git hash-object "$T/after-anchor.md")
node "$APPLY" --check-team-rules "$T/rules.md" "$T/after-anchor.md" >/dev/null 2>&1 && fail "check accepted projection after anchor"
[ "$before" = "$(git hash-object "$T/after-anchor.md")" ] || fail "misaligned check modified target"
printf '%s\n' '<!-- NOVA:TEAM-RULES:START -->' '<!-- NOVA:TEAM-RULES:END -->' '<!-- LEARN:ANCHOR -->' \
  | node "$APPLY" "$T/after-anchor.md" >/dev/null 2>&1 && fail "regen accepted projection after anchor"
[ "$before" = "$(git hash-object "$T/after-anchor.md")" ] || fail "misaligned regen modified target"
[ "$(grep -Fc '<!-- NOVA:TEAM-RULES:START -->' "$T/after-anchor.md")" -eq 1 ] || fail "regen duplicated projection markers"
grep -Fq 'precious learned rule' "$T/after-anchor.md" || fail "regen lost learned rule"
echo "  ok"

echo "== sync/check reject extra CLI arguments =="
node "$APPLY" --sync-team-rules "$T/rules.md" "$T/CLAUDE.md" extra >/dev/null 2>&1 && fail "sync accepted extra argument"
node "$APPLY" --check-team-rules "$T/rules.md" "$T/CLAUDE.md" extra >/dev/null 2>&1 && fail "check accepted extra argument"
echo "  ok"

echo "== independent copies render byte-identically =="
cp "$T/CLAUDE.md" "$T/CLAUDE-a.md"
cp "$T/CLAUDE.md" "$T/CLAUDE-b.md"
node "$APPLY" --sync-team-rules "$T/changed-rules.md" "$T/CLAUDE-a.md" >/dev/null || fail "copy a sync"
node "$APPLY" --sync-team-rules "$T/changed-rules.md" "$T/CLAUDE-b.md" >/dev/null || fail "copy b sync"
cmp "$T/CLAUDE-a.md" "$T/CLAUDE-b.md" >/dev/null || fail "independent projections differ"
echo "  ok"

echo ""
echo "ALL PASS"
