#!/usr/bin/env node
// Append one Self-Learning rule into the CC-RULES block (after <!-- LEARN:ANCHOR -->), with dedup.
// Usage: node append-rule.mjs <file> <rule text...>   (rule may also come from stdin)
//
// - Inserts "- (YYYY-MM-DD) <rule>" right after the anchor (newest first).
// - Skips if a normalized-equal rule already exists (dedup).
// - Preserves the language the rule was written in.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const ANCHOR = '<!-- LEARN:ANCHOR -->';
const END = '<!-- CC-RULES:END -->';

const file = process.argv[2];
let rule = process.argv.slice(3).join(' ').trim();
if (!rule) { try { rule = readFileSync(0, 'utf8').trim(); } catch { /* none */ } }
if (!file || !rule) { console.error('usage: append-rule.mjs <file> <rule text>'); process.exit(2); }
if (!existsSync(file)) { console.error(`${file} not found — run /claude-md first`); process.exit(1); }

let content = readFileSync(file, 'utf8');
const ai = content.indexOf(ANCHOR);
if (ai === -1) { console.error('No CC-RULES Self-Learning anchor — run /claude-md first'); process.exit(1); }

const norm = (s) => s.toLowerCase().replace(/[^a-z0-9가-힣]+/g, ' ').trim();
const stripBullet = (l) => l.replace(/^\s*-\s+(\(\d{4}-\d{2}-\d{2}\)\s*)?/, '');

// existing rule lines live between the anchor and the END marker (whole-line match, consistent with apply-block.mjs)
const endRe = new RegExp('^' + END.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[ \\t]*$', 'm');
const afterAnchor = content.slice(ai + ANCHOR.length);
const endRel = afterAnchor.search(endRe);
if (endRel === -1) { console.error('No CC-RULES:END after the Self-Learning anchor — run /claude-md first'); process.exit(1); }
const region = afterAnchor.slice(0, endRel);
const existingRules = region.split('\n').filter((l) => /^\s*-\s+/.test(l));
const nRule = norm(rule);
if (existingRules.some((l) => norm(stripBullet(l)) === nRule)) {
  console.log('duplicate rule — skipped');
  process.exit(0);
}

const date = new Date().toISOString().slice(0, 10);
const line = `- (${date}) ${rule}`;
const at = ai + ANCHOR.length;
content = content.slice(0, at) + `\n${line}` + content.slice(at);
writeFileSync(file, content);
console.log(`added rule: ${line}`);
process.exit(0);
