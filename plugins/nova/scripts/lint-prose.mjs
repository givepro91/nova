#!/usr/bin/env node
// Prose lint shared by Nova's text outputs (worklog, handoff): deterministic
// anti-shorthand checks — the Voice rules a reader actually feels.
// Checks prose units (paragraphs / list items); skips front-matter, headings,
// tables; code spans are collapsed first so identifiers don't count.
//
// Module: import { lint } — returns [{line, msg}].
// CLI:    node lint-prose.mjs <file.md>   → prints warnings, exit 1 if any.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function lint(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const units = [];                                               // {start, text}
  let cur = null, i = 0;
  if (lines[0] && lines[0].trim() === '---') {                    // YAML front-matter
    let j = 1; while (j < lines.length && lines[j].trim() !== '---') j++; i = j + 1;
  }
  const flush = () => { if (cur) { units.push(cur); cur = null; } };
  for (; i < lines.length; i++) {
    const t = lines[i].trim();
    if (!t || /^#{1,6}\s/.test(t) || /^\|/.test(t) || /^---+$/.test(t)) { flush(); continue; }
    const text = t.replace(/^>\s?/, '').replace(/^([-*]|\d+\.)\s+/, '');
    if (/^([-*]|\d+\.)\s+/.test(t)) { flush(); units.push({ start: i + 1, text }); continue; }  // a list item is its own unit
    if (cur) cur.text += ' ' + text; else cur = { start: i + 1, text };
  }
  flush();
  const warns = [];
  for (const u of units) {
    const p = u.text.replace(/`[^`]*`/g, '`…`');
    const arrows = (p.match(/→/g) || []).length;
    if (p.length > 420) warns.push({ line: u.start, msg: `문단이 너무 깁니다(${p.length}자) — 하나의 생각 단위로 나누세요` });
    if (arrows >= 2) warns.push({ line: u.start, msg: `화살표 체인(→ ×${arrows}) — 세션 속기입니다. 문장이나 목록으로 푸세요` });
    if (/\S+·\S+·\S+/.test(p)) warns.push({ line: u.start, msg: `'·' 나열 — 쉼표나 목록으로 푸세요` });
  }
  return warns;
}

// ---- CLI (only when run directly) ----
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const p = process.argv[2];
  if (!p) { console.error('usage: lint-prose.mjs <file.md>'); process.exit(2); }
  const warns = lint(readFileSync(p, 'utf8'));
  for (const w of warns) console.error(`lint ${p}:${w.line} ${w.msg}`);
  console.error(warns.length ? `LINT: ${warns.length} warning(s)` : 'LINT: clean');
  process.exit(warns.length ? 1 : 0);
}
