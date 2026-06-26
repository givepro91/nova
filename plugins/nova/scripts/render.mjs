#!/usr/bin/env node
// Deterministic worklog renderer: a worklog .md -> a self-contained Nova-violet HTML page.
// NO LLM (a pure markdown-subset transform), NO external assets (inline CSS, system fonts).
// Verdict badges are rendered ONLY from a real gate-verdict ledger — never fabricated.
//
// Usage: node render.mjs <worklog.md> [gate-verdict.json]  > out.html
//   (verdict path defaults to .nova/gate-verdict.json; omitted entirely if it doesn't exist)
import { readFileSync, existsSync } from 'node:fs';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// inline: escape first, then apply markdown inline markers on the escaped text
function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
}

const splitRow = (line) => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());

// markdown subset -> HTML (headings, bold, code, links, lists, GFM tables, blockquote, hr, paragraphs)
function render(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const out = [];
  const para = [];
  const flushP = () => { if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>`); para.length = 0; } };
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (i === 0 && line.trim() === '---') {                       // YAML front-matter at very top
      let j = i + 1; while (j < lines.length && lines[j].trim() !== '---') j++; i = j + 1; continue;
    }
    if (/^\s*$/.test(line)) { flushP(); i++; continue; }
    const h = /^(#{1,3})\s+(.*)$/.exec(line);
    if (h) { flushP(); out.push(`<h${h[1].length}>${inline(h[2].trim())}</h${h[1].length}>`); i++; continue; }
    if (/^---+\s*$/.test(line)) { flushP(); out.push('<hr>'); i++; continue; }
    if (/^>\s?/.test(line)) {                                     // blockquote -> callout
      flushP(); const buf = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) { buf.push(lines[i].replace(/^>\s?/, '')); i++; }
      out.push(`<blockquote>${render(buf.join('\n'))}</blockquote>`); continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
      flushP();
      const head = splitRow(line); i += 2;                        // header + separator
      let t = '<div class="tbl"><table><thead><tr>' + head.map((c) => `<th>${inline(c)}</th>`).join('') + '</tr></thead><tbody>';
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
        t += '<tr>' + splitRow(lines[i]).map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>'; i++;
      }
      out.push(t + '</tbody></table></div>'); continue;
    }
    if (/^\s*([-*]|\d+\.)\s+/.test(line)) {                       // list
      flushP(); const ordered = /^\s*\d+\.\s+/.test(line); const items = [];
      while (i < lines.length && /^\s*([-*]|\d+\.)\s+/.test(lines[i])) { items.push(lines[i].replace(/^\s*([-*]|\d+\.)\s+/, '')); i++; }
      out.push(`<${ordered ? 'ol' : 'ul'}>` + items.map((it) => `<li>${inline(it)}</li>`).join('') + `</${ordered ? 'ol' : 'ul'}>`);
      continue;
    }
    para.push(line.trim()); i++;
  }
  flushP();
  return out.join('\n');
}

// verdict panel — rendered ONLY from a real ledger; returns '' if absent/unreadable
function verdictPanel(vpath) {
  if (!vpath || !existsSync(vpath)) return '';
  let v; try { v = JSON.parse(readFileSync(vpath, 'utf8')); } catch { return ''; }
  const claims = Array.isArray(v.claims) ? v.claims : [];
  const n = (s) => claims.filter((c) => c && c.status === s).length;
  const pass = String(v.verdict || '').toUpperCase() === 'PASS';
  const chip = (cls, txt) => `<span class="vchip ${cls}">${esc(txt)}</span>`;
  return `<aside class="verdict" aria-label="gate verdict">
  <span class="vlabel">gate verdict${v.timestamp ? ` · ${esc(v.timestamp)}` : ''}</span>
  ${chip(pass ? 'v-good' : 'v-crit', pass ? 'PASS' : 'ISSUES')}
  ${chip('v-good', `confirmed ${n('confirmed')}`)}
  ${chip('v-warn', `unverified ${n('unverified')}`)}
  ${chip('v-crit', `false ${n('false')}`)}
</aside>`;
}

const CSS = `
:root{--paper:#fff;--bg:#f6f5fb;--ink:#1b1a22;--ink-2:#54516a;--muted:#5f5c72;
--line:#e9e6f2;--line-2:#f0eef7;--violet:#7c3aed;--violet-deep:#6d28d9;--wash:#f3effd;--card:#faf9fe;
--good:#15803d;--warn:#b45309;--crit:#dc2626}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR","Segoe UI",system-ui,sans-serif;
font-size:15.5px;line-height:1.72;-webkit-font-smoothing:antialiased;padding:clamp(16px,4vw,52px) 14px}
.sheet{max-width:860px;margin:0 auto;background:var(--paper);border:1px solid var(--line);border-radius:14px;
padding:clamp(26px,5.5vw,60px);box-shadow:0 1px 2px rgba(27,26,34,.04),0 18px 50px -28px rgba(124,58,237,.18)}
h1{font-size:clamp(1.7rem,4.6vw,2.3rem);font-weight:800;letter-spacing:-.02em;line-height:1.15;margin:0 0 .5em;text-wrap:balance}
h2{font-size:clamp(1.25rem,3.2vw,1.5rem);font-weight:800;margin:1.7em 0 .1em;padding-bottom:.28em;position:relative}
h2::after{content:"";position:absolute;left:0;bottom:0;width:38px;height:3px;background:var(--violet);border-radius:2px}
h3{font-size:1.05rem;font-weight:700;margin:1.3em 0 .2em}
p{margin:.7em 0}
strong{font-weight:700}
a{color:var(--violet-deep);text-decoration:underline;text-underline-offset:2px}
a:focus-visible{outline:2px solid var(--violet);outline-offset:2px;border-radius:2px}
code{background:var(--wash);border:1px solid var(--line);border-radius:5px;padding:.08em .35em;font-size:.88em;
font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
ul,ol{margin:.6em 0;padding-left:1.4em}
li{margin:.28em 0}
li::marker{color:var(--violet)}
hr{border:0;border-top:1px solid var(--line);margin:2em 0}
blockquote{margin:1em 0;padding:.6em 1em;background:var(--wash);border:1px solid #e5dcfb;
border-left:4px solid var(--violet);border-radius:0 10px 10px 0;color:var(--ink-2)}
blockquote p:first-child{margin-top:0}blockquote p:last-child{margin-bottom:0}
.tbl{overflow-x:auto;border:1px solid var(--line);border-radius:10px;margin:1em 0}
table{border-collapse:collapse;width:100%;font-size:.92em;min-width:480px}
thead th{background:var(--wash);color:var(--violet-deep);text-align:left;font-weight:700;font-size:.85em;
letter-spacing:.03em;text-transform:uppercase;padding:10px 14px;border-bottom:1px solid #e5dcfb}
tbody td{padding:11px 14px;border-bottom:1px solid var(--line-2);vertical-align:top;color:#37353f}
tbody tr:last-child td{border-bottom:0}
tbody td:first-child{font-weight:600;color:var(--ink)}
.verdict{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:0 0 1.4em;padding:13px 16px;
background:var(--card);border:1px solid var(--line);border-radius:11px}
.vlabel{font-weight:700;font-size:.82em;color:var(--muted);margin-right:4px}
.vchip{font-size:.78em;font-weight:700;padding:4px 10px;border-radius:999px;color:#fff}
.v-good{background:var(--good)}.v-warn{background:var(--warn)}.v-crit{background:var(--crit)}
footer,.muted{color:var(--muted)}
@media(max-width:520px){body{font-size:15px}}
`;

function page(title, body, verdict) {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>${CSS}</style>
</head>
<body>
<main class="sheet">
${verdict}
${body}
</main>
</body>
</html>
`;
}

// ---- CLI ----
const mdPath = process.argv[2];
if (!mdPath) { console.error('usage: render.mjs <worklog.md> [gate-verdict.json]'); process.exit(2); }
const md = readFileSync(mdPath, 'utf8');
const vpath = process.argv[3] || '.nova/gate-verdict.json';
const titleM = /^#\s+(.+)$/m.exec(md);
const title = titleM ? titleM[1].trim() : (mdPath.split('/').pop() || 'worklog').replace(/\.md$/, '');
process.stdout.write(page(title, render(md), verdictPanel(vpath)));
