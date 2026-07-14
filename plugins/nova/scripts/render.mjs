#!/usr/bin/env node
// Deterministic worklog renderer: a worklog .md -> a self-contained Nova-violet HTML page.
// NO LLM (a pure markdown-subset transform), NO external assets (inline CSS, system fonts).
// Verdict badges are rendered ONLY from a real gate-verdict ledger — never fabricated.
//
// Layout: the h1 + verdict become a masthead; each `## section` becomes a numbered card,
// so the page reads as discrete chapters instead of one continuous markdown dump.
//
// Usage: node render.mjs <worklog.md> [gate-verdict.json]  > out.html
//   (verdict path defaults to .nova/gate-verdict.json; omitted entirely if it doesn't exist)
import { readFileSync, existsSync } from 'node:fs';
import { lint } from './lint-prose.mjs';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// inline: escape first, then apply markdown inline markers on the escaped text
function inline(s) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2">$1</a>');
}

const splitRow = (line) => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());

// markdown subset -> array of block-level HTML strings
// (headings, bold, code, links, lists, GFM tables, blockquote, hr, paragraphs)
function renderBlocks(md) {
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
      out.push(`<blockquote>${renderBlocks(buf.join('\n')).join('\n')}</blockquote>`); continue;
    }
    if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
      flushP();
      const head = splitRow(line); i += 2;                        // header + separator
      const rows = [];
      while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) { rows.push(splitRow(lines[i])); i++; }
      // the template's decisions table -> stacked cards: three columns of long Korean
      // reasoning get crushed at page width, so each row renders full-width instead
      const col = (re) => head.findIndex((c) => re.test(c));
      const d = { pick: col(/결정/), alt: col(/대안/), why: col(/왜|이유/) };
      if (head.length >= 3 && d.pick >= 0 && d.alt >= 0 && d.why >= 0) {
        out.push('<div class="decisions">' + rows.map((r) =>
          `<article class="decision"><p class="d-pick">${inline(r[d.pick] || '')}</p>` +
          `<p class="d-why">${inline(r[d.why] || '')}</p>` +
          `<p class="d-alt"><span class="d-label">${inline(head[d.alt])}</span>${inline(r[d.alt] || '')}</p></article>`).join('') + '</div>');
        continue;
      }
      let t = '<div class="tbl"><table><thead><tr>' + head.map((c) => `<th>${inline(c)}</th>`).join('') + '</tr></thead><tbody>';
      for (const r of rows) t += '<tr>' + r.map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>';
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
  return out;
}

// peel the redundant "Worklog —" prefix + trailing date off the title for display
// (the .md keeps the full self-describing title; only the masthead is cleaned)
function parseTitle(raw) {
  let t = raw, date = '';
  const dm = t.match(/(\d{4}-\d{2}-\d{2})\s*$/);
  if (dm) { date = dm[1]; t = t.slice(0, dm.index); }
  t = t.replace(/[\s·∙•—–-]+$/u, '');                              // separators left after date removal
  t = t.replace(/^\s*worklog\s*[—–:-]*\s*/i, '');                  // drop the common "Worklog —" prefix
  return { display: t.trim() || raw, date };
}

// group the flat block stream into a masthead (brand + title + verdict + intro) and numbered section cards
function assemble(blocks, verdictHtml, display, date) {
  // mark the first paragraph (the opening line) as a visual lead
  for (const b of blocks) { if (b.startsWith('<p>')) { blocks[blocks.indexOf(b)] = '<p class="lead">' + b.slice(3); break; } }

  let i = 0;
  const intro = [];
  while (i < blocks.length && !/^<h2>/.test(blocks[i])) {         // everything before the first ## heading
    if (!/^<h1>/.test(blocks[i])) intro.push(blocks[i]);          // drop the raw h1; the title is rebuilt cleaned
    i++;
  }

  const sections = [];
  const toc = [];
  let n = 0;
  while (i < blocks.length) {
    const head = blocks[i]; i++;                                  // an <h2> block
    const body = [];
    while (i < blocks.length && !/^<h2>/.test(blocks[i])) { body.push(blocks[i]); i++; }
    const no = String(++n).padStart(2, '0');
    let cls = 'sec';
    if (/요약|TL;?DR/i.test(head)) cls += ' sec-sum';              // the TL;DR card reads first — set it apart
    if (/흐름|How it moved/i.test(head)) cls += ' sec-flow';       // the flow section's <ol> renders as a timeline
    const label = head.replace(/<[^>]+>/g, '').replace(/\s*\([^)]*\)\s*$/, '').trim(); // chip text: heading minus the English gloss
    toc.push(`<a href="#sec-${no}"><span class="no">${no}</span>${esc(label)}</a>`);
    sections.push(`<section class="${cls}" id="sec-${no}"><div class="kicker">${no}</div>${head}<div class="sec-body">${body.join('\n')}</div></section>`);
  }

  const dateChip = date ? `<span class="sep">·</span><span class="bdate">${esc(date)}</span>` : '';
  const brand = `<div class="brand"><span class="mark"></span>nova<span class="sep">·</span>worklog${dateChip}</div>`;
  const h1 = `<h1>${inline(display)}</h1>`;
  const masthead = `<header class="masthead">${brand}\n${h1}\n${verdictHtml}\n${intro.join('\n')}</header>\n<div class="rule"></div>`;
  const nav = toc.length > 1 ? `<nav class="toc" aria-label="sections">${toc.join('')}</nav>` : '';
  return `${masthead}\n${nav}\n${sections.join('\n')}\n<footer class="foot">nova · worklog · /worklog</footer>`;
}

// prose lint lives in ./lint-prose.mjs (shared with handoff) — imported above.

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
:root{--bg:#f4f2fb;--paper:#fff;--ink:#1b1a22;--ink-2:#46435a;--muted:#615d76;
--line:#e9e6f2;--line-2:#f1eff8;--violet:#7c3aed;--violet-light:#a855f7;--violet-deep:#6d28d9;
--wash:#f3effd;--good:#15803d;--warn:#b45309;--crit:#dc2626;
--mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
*{box-sizing:border-box}
body{margin:0;color:var(--ink);background:linear-gradient(180deg,#ece5fb 0%,var(--bg) 300px);
font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR","Segoe UI",system-ui,sans-serif;
font-size:16px;line-height:1.78;-webkit-font-smoothing:antialiased;padding:clamp(20px,5vw,64px) 16px;
word-break:keep-all;overflow-wrap:break-word}
.wrap{max-width:820px;margin:0 auto}

/* masthead */
.masthead{margin:0 0 2px;padding:0 6px}
.brand{display:inline-flex;align-items:center;gap:8px;font-weight:700;font-size:.82rem;
letter-spacing:.03em;color:var(--violet-deep);margin-bottom:16px}
.brand .mark{width:20px;height:20px;border-radius:6px;
background:linear-gradient(135deg,var(--violet-light),var(--violet-deep));box-shadow:0 3px 10px rgba(124,58,237,.35)}
.brand .sep{color:#d4cdea;font-weight:400}
.brand .bdate{font-family:var(--mono);font-weight:600;color:var(--muted);letter-spacing:0}
h1{font-size:clamp(1.4rem,3.2vw,1.8rem);font-weight:800;letter-spacing:-.018em;line-height:1.32;
margin:0;text-wrap:balance;color:var(--ink)}
.rule{height:3px;border-radius:3px;margin:18px 0 22px;
background:linear-gradient(90deg,var(--violet) 0%,var(--violet-light) 48%,transparent 100%)}

/* section chip nav */
.toc{display:flex;flex-wrap:wrap;gap:8px;margin:0 6px 6px}
.toc a{display:inline-flex;gap:7px;align-items:center;font-size:.8rem;font-weight:600;color:var(--violet-deep);
text-decoration:none;background:var(--paper);border:1px solid var(--line);border-radius:999px;padding:5px 13px}
.toc a:hover{border-color:var(--violet-light);background:var(--wash)}
.toc a:focus-visible{outline:2px solid var(--violet);outline-offset:2px}
.toc .no{font-family:var(--mono);font-size:.72em;font-weight:700;color:var(--violet)}

/* verdict strip */
.verdict{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:18px 0 0}
.vlabel{font-weight:700;font-size:.78rem;color:var(--muted);letter-spacing:.02em;margin-right:2px}
.vchip{font-size:.76rem;font-weight:700;padding:4px 11px;border-radius:999px;color:#fff;letter-spacing:.01em}
.v-good{background:var(--good)}.v-warn{background:var(--warn)}.v-crit{background:var(--crit)}

/* section cards */
.sec{background:var(--paper);border:1px solid var(--line);border-radius:16px;
padding:clamp(22px,4vw,38px);margin:16px 0;
box-shadow:0 1px 2px rgba(27,26,34,.03),0 16px 44px -32px rgba(124,58,237,.28)}
.kicker{font-family:var(--mono);font-size:.74rem;font-weight:700;letter-spacing:.1em;
color:var(--violet);opacity:.8;margin-bottom:7px}
.sec h2{font-size:clamp(1.22rem,3vw,1.52rem);font-weight:800;letter-spacing:-.012em;color:var(--ink);
margin:0 0 .85em;padding-bottom:.5em;border-bottom:1px solid var(--line-2)}
.sec-body>:first-child{margin-top:0}.sec-body>:last-child{margin-bottom:0}

/* TL;DR card — the plain-language entry point */
.sec-sum{background:linear-gradient(180deg,#f8f5ff,#fff);border-color:#e3d9f9}
.sec-sum ul{list-style:none;padding-left:0;margin:.2em 0}
.sec-sum li{margin:.6em 0;padding:.72em 1em;background:var(--paper);border:1px solid var(--line);border-radius:10px}
.sec-sum li strong{color:var(--violet-deep)}

/* flow section — the <ol> becomes a timeline */
.sec-flow ol{list-style:none;padding-left:0;margin:.2em 0;counter-reset:step}
.sec-flow ol>li{counter-increment:step;position:relative;margin:0;padding:0 0 1.15em 44px}
.sec-flow ol>li::before{content:counter(step);position:absolute;left:0;top:0;width:26px;height:26px;
display:flex;align-items:center;justify-content:center;border-radius:999px;
background:var(--wash);border:1.5px solid var(--violet-light);color:var(--violet-deep);
font-family:var(--mono);font-size:.76rem;font-weight:700}
.sec-flow ol>li::after{content:"";position:absolute;left:12.5px;top:30px;bottom:4px;width:1.5px;background:var(--line)}
.sec-flow ol>li:last-child{padding-bottom:0}
.sec-flow ol>li:last-child::after{display:none}

/* prose */
p{margin:.85em 0;text-wrap:pretty}
.lead{font-size:1.1em;line-height:1.74;color:var(--ink-2)}
h3{font-size:1.02rem;font-weight:700;color:var(--ink);margin:1.5em 0 .3em}
strong{font-weight:700;color:var(--ink)}
a{color:var(--violet-deep);text-decoration:underline;text-underline-offset:2px;text-decoration-thickness:1px}
a:focus-visible{outline:2px solid var(--violet);outline-offset:2px;border-radius:2px}
code{background:var(--wash);border:1px solid var(--line);border-radius:5px;padding:.08em .36em;font-size:.88em;font-family:var(--mono)}
ul,ol{margin:.7em 0;padding-left:1.45em}
li{margin:.4em 0;text-wrap:pretty}
li::marker{color:var(--violet);font-weight:700}
em{font-style:italic}
hr{border:0;border-top:1px solid var(--line);margin:1.6em 0}
blockquote{margin:1.1em 0;padding:.7em 1.1em;background:var(--wash);border:1px solid #e7ddfb;
border-left:4px solid var(--violet);border-radius:0 12px 12px 0;color:var(--ink-2)}
blockquote p:first-child{margin-top:0}blockquote p:last-child{margin-bottom:0}

/* tables */
.tbl{overflow-x:auto;border:1px solid var(--line);border-radius:11px;margin:1.1em 0}
table{border-collapse:collapse;width:100%;font-size:.92em;min-width:480px}
thead th{background:var(--wash);color:var(--violet-deep);text-align:left;font-weight:700;font-size:.78em;
letter-spacing:.04em;text-transform:uppercase;padding:11px 15px;border-bottom:1px solid #e5dcfb}
tbody td{padding:11px 15px;border-bottom:1px solid var(--line-2);vertical-align:top;color:#37353f}
tbody tr:last-child td{border-bottom:0}
tbody td:first-child{font-weight:600;color:var(--ink)}

/* decision cards (rendered from the 결정/버린 대안/왜 table) */
.decisions{margin:1.1em 0;display:flex;flex-direction:column;gap:12px}
.decision{background:#fdfcff;border:1px solid var(--line);border-left:4px solid var(--violet);
border-radius:0 12px 12px 0;padding:16px 20px}
.d-pick{margin:0;font-weight:700;color:var(--ink)}
.d-why{margin:.5em 0 0;color:var(--ink-2)}
.d-alt{margin:.75em 0 0;font-size:.9em;color:var(--muted)}
.d-label{display:inline-block;font-size:.82em;font-weight:700;letter-spacing:.03em;color:var(--violet-deep);
background:var(--wash);border:1px solid #e5dcfb;border-radius:999px;padding:2px 10px;margin-right:8px}

.foot{margin:26px 6px 0;font-size:.78rem;color:var(--muted);text-align:center;letter-spacing:.02em}
@media(max-width:560px){body{font-size:15.5px;padding:18px 12px}.sec{padding:22px 18px}}
@media print{body{background:#fff;padding:0}.sec{box-shadow:none;break-inside:avoid}.toc{display:none}}
html{scroll-behavior:smooth}
`;

function page(title, body) {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<style>${CSS}</style>
</head>
<body>
<main class="wrap">
${body}
</main>
</body>
</html>
`;
}

// ---- CLI ----
const argv = process.argv.slice(2);
const lintOnly = argv[0] === '--lint';
if (lintOnly) argv.shift();
const mdPath = argv[0];
if (!mdPath) { console.error('usage: render.mjs [--lint] <worklog.md> [gate-verdict.json]'); process.exit(2); }
const md = readFileSync(mdPath, 'utf8');
const warns = lint(md);
for (const w of warns) console.error(`lint ${mdPath}:${w.line} ${w.msg}`);   // stderr: advisory in render mode, verdict in --lint mode
if (lintOnly) { console.error(warns.length ? `LINT: ${warns.length} warning(s)` : 'LINT: clean'); process.exit(warns.length ? 1 : 0); }
const vpath = argv[1] || '.nova/gate-verdict.json';
const titleM = /^#\s+(.+)$/m.exec(md);
const rawTitle = titleM ? titleM[1].trim() : (mdPath.split('/').pop() || 'worklog').replace(/\.md$/, '');
const { display, date } = parseTitle(rawTitle);
process.stdout.write(page(rawTitle, assemble(renderBlocks(md), verdictPanel(vpath), display, date)));
