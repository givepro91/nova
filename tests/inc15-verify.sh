#!/usr/bin/env bash
# Regression guard for the absorbed-code bug fixes (Inc 1.5). Exits non-zero on first failure.
# Run: bash tests/inc15-verify.sh
set -u
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$NOVA/plugins/handoff/hooks/_lib.mjs"
APPEND="$NOVA/plugins/claude-md/scripts/append-rule.mjs"
APPLY="$NOVA/plugins/claude-md/scripts/apply-block.mjs"
T=$(mktemp -d)
fail() { echo "FAIL: $1"; exit 1; }

echo "== node --check =="
for f in "$NOVA"/plugins/handoff/hooks/*.mjs "$NOVA"/plugins/claude-md/scripts/*.mjs; do
  node --check "$f" || fail "syntax $f"; done
echo "  ok"

echo "== Fix: parseFrontMatter tolerates CRLF =="
node -e "
import('file://$LIB').then(m => {
  const crlf='---\r\nbranch: feat/x\r\nstatus: closed\r\n---\r\n# body\r\n';
  const r=m.parseFrontMatter(crlf);
  if(r.data.status!=='closed'){console.error('status='+JSON.stringify(r.data.status));process.exit(1);}
  if(/\r/.test(JSON.stringify(r.data))){console.error('CR leaked');process.exit(1);}
  if(!r.body.includes('# body')){console.error('body wrong');process.exit(1);}
  console.log('  CRLF status:', r.data.status);
});" || fail "CRLF front-matter"

echo "== Fix: changedFiles returns non-ASCII (Korean) paths literally =="
G=$(mktemp -d); git -C "$G" init -q; git -C "$G" config user.email t@t.t; git -C "$G" config user.name t
printf x > "$G/한글파일.md"
node -e "
import('file://$LIB').then(m => {
  const f=m.changedFiles('$G');
  if(!f||!f.includes('한글파일.md')){console.error('got '+JSON.stringify(f));process.exit(1);}
  console.log('  ',JSON.stringify(f));
});" || { rm -rf "$G"; fail "Korean path"; }
rm -rf "$G"

echo "== Fix: append-rule inserts within block, whole-line END =="
F="$T/ok.md"
printf '%s\n' '<!-- CC-RULES:START -->' '## Self-Learning Rules' '<!-- LEARN:ANCHOR -->' '<!-- CC-RULES:END -->' > "$F"
node "$APPEND" "$F" "always grep call sites" >/dev/null || fail "append exit"
node -e "const t=require('fs').readFileSync('$F','utf8');const a=t.indexOf('LEARN:ANCHOR'),e=t.indexOf('CC-RULES:END'),r=t.indexOf('always grep');process.exit(a<r&&r<e?0:1);" || fail "rule placement"
echo "  ok"

echo "== Fix: append-rule errors on missing END =="
F2="$T/noend.md"; printf '%s\n' '<!-- CC-RULES:START -->' '<!-- LEARN:ANCHOR -->' > "$F2"
if node "$APPEND" "$F2" "x" 2>/dev/null; then fail "missing-END must exit nonzero"; fi
echo "  ok"

echo "== Fix: apply-block preserves learned rule on normal upsert =="
F3="$T/blk.md"
printf '%s\n' '<!-- CC-RULES:START -->' '<!-- note -->' '' '## X' '<!-- LEARN:ANCHOR -->' '- (2026-01-01) keep me' '<!-- CC-RULES:END -->' > "$F3"
printf '%s\n' '## Y' '<!-- LEARN:ANCHOR -->' | node "$APPLY" "$F3" >/dev/null || fail "apply exit"
grep -q 'keep me' "$F3" || fail "learned rule lost"; grep -q '## Y' "$F3" || fail "body not applied"
echo "  ok"

echo "== Fix: apply-block refuses (no write) when new body lacks anchor but rules exist =="
F4="$T/blk2.md"
printf '%s\n' '<!-- CC-RULES:START -->' '<!-- note -->' '<!-- LEARN:ANCHOR -->' '- (2026-01-01) precious' '<!-- CC-RULES:END -->' > "$F4"
BEFORE=$(cat "$F4")
if printf '%s\n' '## NoAnchor' | node "$APPLY" "$F4" 2>/dev/null; then fail "must refuse"; fi
[ "$BEFORE" = "$(cat "$F4")" ] || fail "file modified despite refusal"
echo "  ok"

rm -rf "$T"
echo ""; echo "ALL PASS"
