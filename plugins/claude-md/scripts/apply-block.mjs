#!/usr/bin/env node
// Idempotently upsert (or remove) the CC-RULES managed block in a target file.
//   Upsert: node apply-block.mjs <file>            (block body read from stdin)
//   Remove: node apply-block.mjs --remove <file>   (deletes the block; used when moving it
//                                                    to a different canonical file)
//
// Guarantees:
// - Existing file with a CC-RULES block      → replace only that block (user area preserved).
// - Existing file without a CC-RULES block    → append the block (existing content preserved).
// - Missing file                              → create it with the block.
// - Re-running is idempotent (no duplicate blocks).
// - Self-Learning rules accumulated after <!-- LEARN:ANCHOR --> are PRESERVED across regen.
// - Markers are matched ONLY as standalone lines, so prose that merely *mentions* a marker
//   (e.g. inside backticks in the preamble) is never mistaken for the real block.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const START = '<!-- CC-RULES:START -->';
const END = '<!-- CC-RULES:END -->';
const ANCHOR = '<!-- LEARN:ANCHOR -->';
const NOTE = '<!-- Managed by /claude-md. Edits inside this block are overwritten on regen; put custom rules outside it. -->';

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const lineRe = (marker) => new RegExp(`^${esc(marker)}[ \\t]*$`, 'm'); // whole-line match only

const argv = process.argv.slice(2);
const remove = argv[0] === '--remove';
const file = remove ? argv[1] : argv[0];
if (!file) { console.error('usage: apply-block.mjs [--remove] <file>  (block body on stdin for upsert)'); process.exit(2); }

// ---------- remove mode ----------
if (remove) {
  if (!existsSync(file)) { console.log(`${file} not found — nothing to remove`); process.exit(0); }
  const text = readFileSync(file, 'utf8');
  const sm = lineRe(START).exec(text);
  const em = lineRe(END).exec(text);
  if (!(sm && em && em.index > sm.index)) { console.log(`no CC-RULES block in ${file}`); process.exit(0); }
  const before = text.slice(0, sm.index).replace(/\s+$/, '');
  const after = text.slice(em.index + em[0].length).replace(/^\s+/, '');
  const joined = before && after ? `${before}\n\n${after}\n` : before ? `${before}\n` : after ? `${after}\n` : '';
  writeFileSync(file, joined);
  console.log(`removed CC-RULES block from ${file}`);
  process.exit(0);
}

// ---------- upsert mode ----------
let body = '';
try { body = readFileSync(0, 'utf8'); } catch { /* empty */ }
body = body.replace(/^\n+|\n+$/g, '');
if (!body) { console.error('error: empty block body on stdin'); process.exit(2); }

let block = `${START}\n${NOTE}\n\n${body}\n${END}`;
const existing = existsSync(file) ? readFileSync(file, 'utf8') : null;

if (existing == null) {
  writeFileSync(file, block + '\n');
  console.log(`created ${file} with CC-RULES block`);
  process.exit(0);
}

const sm = lineRe(START).exec(existing);
const em = lineRe(END).exec(existing);
if (sm && em && em.index > sm.index) {
  const blockStart = sm.index;
  const blockEnd = em.index + em[0].length;
  const oldBlock = existing.slice(blockStart, blockEnd);
  // preserve previously-learned rules (text between old anchor and old END line)
  const oai = oldBlock.indexOf(ANCHOR);
  if (oai !== -1) {
    const endInOld = oldBlock.search(lineRe(END));
    const learned = oldBlock.slice(oai + ANCHOR.length, endInOld).replace(/\s+$/, '');
    const nai = block.indexOf(ANCHOR);
    if (nai !== -1 && learned.trim()) {
      block = block.slice(0, nai + ANCHOR.length) + learned + block.slice(nai + ANCHOR.length);
    }
  }
  writeFileSync(file, existing.slice(0, blockStart) + block + existing.slice(blockEnd));
  console.log(`updated CC-RULES block in ${file} (learned rules preserved)`);
} else {
  const sep = existing.endsWith('\n') ? '\n' : '\n\n';
  writeFileSync(file, existing + sep + block + '\n');
  console.log(`appended CC-RULES block to ${file}`);
}
process.exit(0);
