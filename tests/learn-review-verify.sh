#!/usr/bin/env bash
# Deterministic `/learn review` regression tests using persistent gate-history fixtures.
# Run: bash tests/learn-review-verify.sh
set -eu

NOVA="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$NOVA/plugins/nova/scripts/gate-history-review.mjs"
APPEND="$NOVA/plugins/nova/scripts/append-rule.mjs"
GATE_SKILL="$NOVA/plugins/nova/skills/gate/SKILL.md"
FIXTURES="$NOVA/tests/fixtures/gate-history"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM

fail() {
  echo "FAIL: $1"
  exit 1
}

echo "== syntax =="
node --check "$REVIEW" || fail "gate-history-review.mjs syntax"
node --check "$APPEND" || fail "append-rule.mjs syntax"
echo "  ok"

echo "== 2 occurrences stay observational; 3 occurrences become one candidate =="
node "$REVIEW" "$FIXTURES/threshold-2.jsonl" > "$T/threshold-2.json" || fail "2-occurrence review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (result.candidates.length !== 0) throw new Error("2 occurrences produced a candidate");
const item = result.observations.find(({ failure_mode }) => failure_mode === "verification-evidence-missing");
if (!item || item.occurrences !== 2) throw new Error("2-occurrence observation is missing");
' "$T/threshold-2.json" || fail "2-occurrence boundary"

node "$REVIEW" "$FIXTURES/corrupted.jsonl" > "$T/threshold-3.json" || fail "3-occurrence review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const items = result.candidates.filter(({ failure_mode }) => failure_mode === "verification-evidence-missing");
if (items.length !== 1 || items[0].occurrences !== 3) throw new Error("3 occurrences did not produce exactly one candidate");
' "$T/threshold-3.json" || fail "3-occurrence boundary"
echo "  ok"

echo "== equivalent legacy wording merges; a distinct cause remains separate =="
node "$REVIEW" "$FIXTURES/recurring-modes.jsonl" > "$T/recurring.json" || fail "recurring-mode review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (result.valid_records !== 6) throw new Error(`expected 6 valid records, got ${result.valid_records}`);
if (result.candidates.length !== 2) throw new Error(`expected 2 candidates, got ${result.candidates.length}`);
const verification = result.candidates.find(({ id }) => id === "gate:verification-evidence-missing");
const scope = result.candidates.find(({ id }) => id === "gate:requested-scope-omitted");
if (!verification || verification.occurrences !== 3) throw new Error("equivalent verification failures were not merged");
if (!scope || scope.occurrences !== 3) throw new Error("distinct scope failures were not kept separate");
if (verification.preventive_action !== "Run the exact check and retain its passing output") {
  throw new Error("verification prevention contract changed");
}
if (verification.proposal !== "완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.") {
  throw new Error("verification rule proposal changed");
}
const expected = [
  { line: 1, head: "verify-a", timestamp: "2026-07-13T00:01:01Z", claim_indices: [1] },
  { line: 2, head: "verify-b", timestamp: "2026-07-13T00:01:02Z", claim_indices: [1] },
  { line: 3, head: "verify-c", timestamp: "2026-07-13T00:01:03Z", claim_indices: [1] },
];
if (JSON.stringify(verification.records) !== JSON.stringify(expected)) throw new Error("evidence record identifiers changed");
' "$T/recurring.json" || fail "mode grouping or evidence identifiers"
echo "  ok"

echo "== empty ledger stays empty and read-only =="
EMPTY="$T/empty.jsonl"
: > "$EMPTY"
EMPTY_BEFORE=$(git hash-object "$EMPTY")
node "$REVIEW" "$EMPTY" > "$T/empty.json" || fail "empty ledger review"
[ "$EMPTY_BEFORE" = "$(git hash-object "$EMPTY")" ] || fail "empty ledger changed during review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (result.valid_records !== 0) throw new Error("empty ledger has valid records");
if (result.ignored_lines.length !== 0) throw new Error("empty ledger reported phantom ignored lines");
if (result.candidates.length !== 0 || result.observations.length !== 0) throw new Error("empty ledger produced findings");
' "$T/empty.json" || fail "empty ledger boundary"
echo "  ok"

echo "== damaged claim schema is reported and cannot become candidate evidence =="
node "$REVIEW" "$FIXTURES/damaged-claims.jsonl" > "$T/damaged-claims.json" || fail "damaged claim review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (result.valid_records !== 1) throw new Error(`expected 1 valid record, got ${result.valid_records}`);
const expected = JSON.stringify([
  { line: 1, reason: "invalid-record" },
  { line: 2, reason: "invalid-record" },
  { line: 3, reason: "invalid-record" },
  { line: 4, reason: "invalid-record" },
  { line: 5, reason: "invalid-record" },
  { line: 6, reason: "invalid-record" },
  { line: 7, reason: "invalid-record" },
  { line: 8, reason: "invalid-record" },
  { line: 9, reason: "invalid-record" },
  { line: 10, reason: "invalid-record" },
]);
if (JSON.stringify(result.ignored_lines) !== expected) throw new Error("damaged claims were not identified as invalid records");
if (result.candidates.length !== 0) throw new Error("damaged claims contributed to a candidate");
const observation = result.observations.find(({ failure_mode }) => failure_mode === "verification-evidence-missing");
if (!observation || observation.occurrences !== 1 || observation.records[0].line !== 11) {
  throw new Error("valid record after damaged claims did not continue aggregating");
}
' "$T/damaged-claims.json" || fail "damaged claim schema guard"
echo "  ok"

echo "== cause-only legacy wording has no prevention evidence → no unsupported merge =="
node "$REVIEW" "$FIXTURES/unsupported-legacy-merge.jsonl" > "$T/unsupported-merge.json" || fail "unsupported legacy merge review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (result.valid_records !== 3) throw new Error(`expected 3 valid records, got ${result.valid_records}`);
if (result.candidates.length !== 0) throw new Error("cause-only wording produced a candidate without prevention evidence");
const unclassified = result.observations.find(({ failure_mode }) => failure_mode === "unclassified");
if (!unclassified || unclassified.occurrences !== 3) throw new Error("cause-only records were not kept observable as unclassified");
if (result.observations.some(({ failure_mode }) => failure_mode === "verification-evidence-missing")) {
  throw new Error("cause-only records were merged into verification-evidence-missing");
}
' "$T/unsupported-merge.json" || fail "unsupported semantic merge guard"
echo "  ok"

echo "== negated legacy action is contradictory evidence → no candidate =="
node "$REVIEW" "$FIXTURES/negated-legacy-action.jsonl" > "$T/negated-action.json" || fail "negated legacy action review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (result.valid_records !== 21) throw new Error(`expected 21 valid records, got ${result.valid_records}`);
if (result.candidates.length !== 0) throw new Error("negated preventive action produced a candidate");
const unclassified = result.observations.find(({ failure_mode }) => failure_mode === "unclassified");
if (!unclassified || unclassified.occurrences !== 21) throw new Error("negated actions were not kept observable as unclassified");
' "$T/negated-action.json" || fail "negated prevention guard"
echo "  ok"

echo "== double-negation legacy action still expresses positive prevention =="
node "$REVIEW" "$FIXTURES/double-negation-positive.jsonl" > "$T/double-negation.json" || fail "double-negation review"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const candidates = result.candidates.filter(({ failure_mode }) => failure_mode === "verification-evidence-missing");
if (candidates.length !== 1 || candidates[0].occurrences !== 6) {
  throw new Error("positive double-negation records did not merge into one candidate");
}
if (result.observations.length !== 0) throw new Error("positive double-negation records became observations");
' "$T/double-negation.json" || fail "double-negation positive prevention"
echo "  ok"

echo "== malformed JSONL is reported, valid records continue, review is read-only =="
mkdir -p "$T/project/.nova"
cp "$FIXTURES/corrupted.jsonl" "$T/project/.nova/gate-history.jsonl"
cp "$FIXTURES/rules.md" "$T/project/CLAUDE.md"
printf '%s\n' '# untouched secondary rules' > "$T/project/AGENTS.md"
RULES="$T/project/CLAUDE.md"
TREE_BEFORE=$(find "$T/project" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
(cd "$T/project" && node "$REVIEW" .nova/gate-history.jsonl > "$T/mixed-first.json") || fail "mixed review first run"
(cd "$T/project" && node "$REVIEW" .nova/gate-history.jsonl > "$T/mixed-second.json") || fail "mixed review second run"
TREE_AFTER=$(find "$T/project" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)
[ "$TREE_BEFORE" = "$TREE_AFTER" ] || fail "unapproved review changed a project file or created a side effect"
cmp "$T/mixed-first.json" "$T/mixed-second.json" >/dev/null || fail "repeated review output is not deterministic"
node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const ignored = JSON.stringify(result.ignored_lines);
const expected = JSON.stringify([
  { line: 2, reason: "blank" },
  { line: 3, reason: "malformed" },
  { line: 4, reason: "invalid-record" },
]);
if (result.valid_records !== 3) throw new Error(`expected 3 valid records, got ${result.valid_records}`);
if (ignored !== expected) throw new Error(`ignored-line report changed: ${ignored}`);
const candidate = result.candidates.find(({ id }) => id === "gate:verification-evidence-missing");
if (!candidate || candidate.occurrences !== 3) throw new Error("valid records did not continue aggregating");
if (candidate.records.map(({ line }) => line).join(",") !== "1,5,6") throw new Error("physical evidence line identifiers changed");
' "$T/mixed-first.json" || fail "damaged JSONL handling"
echo "  ok"

echo "== gate schema remains additive and legacy records stay valid =="
LEGACY_BEFORE=$(git hash-object "$FIXTURES/legacy-schema.jsonl")
node "$REVIEW" "$FIXTURES/legacy-schema.jsonl" > "$T/legacy-schema.json" || fail "legacy gate schema review"
[ "$LEGACY_BEFORE" = "$(git hash-object "$FIXTURES/legacy-schema.jsonl")" ] || fail "legacy ledger changed during review"
node -e '
const fs = require("node:fs");
const result = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const contract = fs.readFileSync(process.argv[2], "utf8");
if (result.valid_records !== 2 || result.ignored_lines.length !== 0) throw new Error("legacy gate records became invalid");
if (result.candidates.length !== 0) throw new Error("legacy schema fixture unexpectedly produced a candidate");
const unclassified = result.observations.find(({ failure_mode }) => failure_mode === "unclassified");
if (!unclassified || unclassified.occurrences !== 1) throw new Error("legacy issue was not retained as an observation");
const baseSchema = "{ intent, head, timestamp, verdict, claims: [{ claim, status, evidence, severity, failure_mode? }] }";
if (!contract.includes(baseSchema)) throw new Error("gate ledger base schema contract changed");
if (!contract.includes("This additive field does not change the meaning of existing fields; older ledger lines remain valid.")) {
  throw new Error("gate failure_mode additive compatibility contract is missing");
}
' "$T/legacy-schema.json" "$GATE_SKILL" || fail "gate schema compatibility"
echo "  ok"

echo "== explicit approval appends only the selected candidate once =="
APPROVED_PROPOSAL=$(node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const item = result.candidates.find(({ id }) => id === "gate:verification-evidence-missing");
if (!item) process.exit(1);
process.stdout.write(item.proposal);
' "$T/recurring.json") || fail "approved candidate lookup"
OTHER_PROPOSAL=$(node -e '
const result = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const item = result.candidates.find(({ id }) => id === "gate:requested-scope-omitted");
if (!item) process.exit(1);
process.stdout.write(item.proposal);
' "$T/recurring.json") || fail "unapproved candidate lookup"

EXPECTED="$T/expected.txt"
ACTUAL="$T/actual.txt"
EVIDENCE="$T/verification.out"
printf 'expected result\n' > "$EXPECTED"
printf 'expected result\n' > "$ACTUAL"
exercise_completion() {
  rm -f "$EVIDENCE"
  if grep -qF "$APPROVED_PROPOSAL" "$RULES"; then
    cmp "$EXPECTED" "$ACTUAL" > "$EVIDENCE" 2>&1 && printf 'PASS: required comparison\n' >> "$EVIDENCE"
  fi
  test -s "$EVIDENCE" && grep -qF 'PASS: required comparison' "$EVIDENCE"
}

if exercise_completion; then
  fail "representative missing-evidence failure passed before approval"
fi

node "$APPEND" "$RULES" "$APPROVED_PROPOSAL" >/dev/null || fail "approved candidate append"
grep -qF "$APPROVED_PROPOSAL" "$RULES" || fail "approved proposal was not appended"
if grep -qF "$OTHER_PROPOSAL" "$RULES"; then
  fail "unapproved proposal was appended"
fi
exercise_completion || fail "approved prevention did not execute and retain passing evidence"

RULES_AFTER_FIRST=$(git hash-object "$RULES")
node "$APPEND" "$RULES" "$APPROVED_PROPOSAL" >/dev/null || fail "approved candidate duplicate re-run"
[ "$RULES_AFTER_FIRST" = "$(git hash-object "$RULES")" ] || fail "duplicate approval changed the rules file"
COUNT=$(grep -cF "$APPROVED_PROPOSAL" "$RULES")
[ "$COUNT" -eq 1 ] || fail "approved proposal appears $COUNT times"
echo "  ok (before approval: no evidence; after approval: passing evidence retained)"

echo
echo "ALL PASS: learn-review-verify.sh"
