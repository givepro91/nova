#!/usr/bin/env bash
# Regression guard for the deterministic worklog renderer. Exits non-zero on first failure.
# Run: bash tests/worklog-verify.sh
set -u
NOVA="$(cd "$(dirname "$0")/.." && pwd)"
R="$NOVA/plugins/nova/scripts/render.mjs"
T=$(mktemp -d)
fail() { echo "FAIL: $1"; exit 1; }
has() { grep -qF "$1" "$2" || fail "missing: $1"; }
hasnot() { grep -qF "$1" "$2" && fail "must NOT contain: $1"; return 0; }

echo "== node --check =="
node --check "$R" || fail "syntax"; echo "  ok"

cat > "$T/wl.md" <<'MD'
# Worklog — 테스트 세션

## 한 일
**중요** 작업과 `code` 그리고 [링크](https://example.com).

- 항목 1
- 항목 2

## 결정과 왜
| 결정 | 왜 |
|------|----|
| A 채택 | 이유 |

> 핵심: 이건 callout.

위험한 입력 <script>alert(1)</script> 는 이스케이프돼야 한다.
MD

cat > "$T/verdict.json" <<'JSON'
{"verdict":"ISSUES","timestamp":"2026-06-26","claims":[{"status":"confirmed"},{"status":"unverified"},{"status":"unverified"},{"status":"false"}]}
JSON

echo "== render with verdict =="
node "$R" "$T/wl.md" "$T/verdict.json" > "$T/out.html" || fail "render exit"

echo "== standalone doc validity =="
has '<!DOCTYPE html>' "$T/out.html"
has '<html lang="ko">' "$T/out.html"
has 'meta charset="utf-8"' "$T/out.html"
has '<title>Worklog — 테스트 세션</title>' "$T/out.html"
echo "  lang/charset/title ok"

echo "== markdown rendered =="
has '<h1>' "$T/out.html"; has '<h2>' "$T/out.html"
has '<strong>중요</strong>' "$T/out.html"
has '<code>code</code>' "$T/out.html"
has '<a href="https://example.com">링크</a>' "$T/out.html"
has '<table>' "$T/out.html"; has '<li>항목 1</li>' "$T/out.html"
has '<blockquote>' "$T/out.html"
echo "  headings/bold/code/link/table/list/callout ok"

echo "== HTML escaping (no injected tag) =="
has '&lt;script&gt;alert(1)&lt;/script&gt;' "$T/out.html"
hasnot '<script' "$T/out.html"        # also doubles as: no inline/external script anywhere
echo "  script escaped + no <script in doc"

echo "== self-contained (no external assets) =="
hasnot '<link ' "$T/out.html"
hasnot '@import' "$T/out.html"
hasnot 'url(' "$T/out.html"
hasnot 'src=' "$T/out.html"
echo "  no link/@import/url()/src"

echo "== verdict panel from ledger =="
has 'gate verdict' "$T/out.html"
has 'ISSUES' "$T/out.html"
has 'confirmed 1' "$T/out.html"
has 'unverified 2' "$T/out.html"
has 'false 1' "$T/out.html"
echo "  verdict rendered from real ledger"

echo "== no ledger → no verdict panel (no fabrication) =="
node "$R" "$T/wl.md" "$T/does-not-exist.json" > "$T/out2.html" || fail "render exit (no ledger)"
hasnot 'gate verdict' "$T/out2.html"
echo "  absent verdict → no panel"

rm -rf "$T"
echo ""; echo "ALL PASS"
