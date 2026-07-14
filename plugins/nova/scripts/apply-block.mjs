#!/usr/bin/env node
// Idempotently upsert (or remove) the CC-RULES managed block in a target file.
//   Upsert: node apply-block.mjs <file>            (block body read from stdin)
//   Remove: node apply-block.mjs --remove <file>   (deletes the block; used when moving it
//                                                    to a different canonical file)
//   Sync:   node apply-block.mjs --sync-team-rules <rules-file> <file>
//   Check:  node apply-block.mjs --check-team-rules <rules-file> <file>
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
import { parseTeamRules } from './team-rules.mjs';

const START = '<!-- CC-RULES:START -->';
const END = '<!-- CC-RULES:END -->';
const ANCHOR = '<!-- LEARN:ANCHOR -->';
const TEAM_START = '<!-- NOVA:TEAM-RULES:START -->';
const TEAM_END = '<!-- NOVA:TEAM-RULES:END -->';
const SELF_LEARNING_HEADING = '## Self-Learning Rules';
const NOTE = '<!-- Managed by /claude-md. Edits inside this block are overwritten on regen; put custom rules outside it. -->';
const CONFLICT_RE = /^(?:<<<<<<<|=======|>>>>>>>)(?:[ \t].*)?$/m;

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const lineRe = (marker, flags = 'm') => new RegExp(`^${esc(marker)}[ \\t]*\\r?$`, flags); // whole-line match only
const lineMatches = (text, marker) => [...text.matchAll(lineRe(marker, 'gm'))];

function oneManagedBlock(text) {
  const starts = lineMatches(text, START);
  const ends = lineMatches(text, END);
  if (starts.length !== 1 || ends.length !== 1 || ends[0].index <= starts[0].index) {
    throw new Error('target must contain exactly one well-formed CC-RULES managed block');
  }
  return {
    start: starts[0].index,
    end: ends[0].index + ends[0][0].length,
  };
}

// `range`, when given, restricts the marker search to that slice of `text`
// (e.g. the CC-RULES managed block) so a marker string that merely appears
// as prose/example content elsewhere in the file (outside the block) is
// never mistaken for the real projection.
function currentTeamProjection(text, range) {
  const scope = range ? text.slice(range.start, range.end) : text;
  const offset = range ? range.start : 0;
  const starts = lineMatches(scope, TEAM_START);
  const ends = lineMatches(scope, TEAM_END);
  if (starts.length === 0 && ends.length === 0) return null;
  if (starts.length !== 1 || ends.length !== 1 || ends[0].index <= starts[0].index) {
    throw new Error('target must contain at most one well-formed team-rules projection');
  }
  return {
    start: starts[0].index + offset,
    end: ends[0].index + ends[0][0].length + offset,
    text: scope.slice(starts[0].index, ends[0].index + ends[0][0].length),
  };
}

function projectTeamRules(records) {
  const active = records
    .filter((record) => record.status === 'active')
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const lines = active.map((record) => (
    `- [scope: ${record.scope.join(', ')}] ${record.body} <!-- nova-rule:${record.id} -->`
  ));
  return [TEAM_START, ...lines, TEAM_END].join('\n');
}

function replaceTeamProjection(text, projection) {
  const managed = oneManagedBlock(text);
  const anchors = lineMatches(text, ANCHOR).filter((match) => (
    match.index > managed.start && match.index < managed.end
  ));
  if (anchors.length !== 1) throw new Error(`CC-RULES block must contain exactly one ${ANCHOR}`);

  const existing = currentTeamProjection(text, managed);
  if (existing) {
    if (existing.start < managed.start || existing.end > managed.end) {
      throw new Error('team-rules projection must be inside the CC-RULES managed block');
    }
    if (existing.end >= anchors[0].index) {
      throw new Error(`team-rules projection must be before ${ANCHOR}`);
    }
    return text.slice(0, existing.start) + projection + text.slice(existing.end);
  }

  const headings = lineMatches(text, SELF_LEARNING_HEADING).filter((match) => (
    match.index > managed.start && match.index < anchors[0].index
  ));
  const at = headings.length === 1 ? headings[0].index : anchors[0].index;
  return text.slice(0, at) + `${projection}\n\n` + text.slice(at);
}

function syncTeamRules(rulesFile, file, checkOnly, expected) {
  const rules = parseTeamRules(readFileSync(rulesFile, 'utf8'));
  if (!existsSync(file)) throw new Error(`target not found: ${file}`);
  const existing = readFileSync(file, 'utf8');
  // Compare-and-swap: the caller captured `expected` before mutating its own
  // source of truth. This read happens in the same process, immediately before
  // the write below, so a concurrent external edit that landed in the gap is
  // caught here and the write is refused (fail closed, no last-write-wins).
  if (expected !== undefined && existing !== expected) {
    throw new Error(`concurrent edit detected: ${file}`);
  }
  if (CONFLICT_RE.test(existing)) throw new Error(`unresolved git conflict marker in ${file}`);
  const updated = replaceTeamProjection(existing, projectTeamRules(rules.records));
  if (updated === existing) {
    console.log(`team rules are in sync: ${file}`);
    return;
  }
  if (checkOnly) throw new Error(`team rules are out of sync: ${file}`);
  writeFileSync(file, updated);
  console.log(`synced active team rules to ${file}`);
}

const argv = process.argv.slice(2);
const remove = argv[0] === '--remove';
const sync = argv[0] === '--sync-team-rules';
const check = argv[0] === '--check-team-rules';
// Optional 4th arg for sync only: read the caller's captured pre-edit content
// from stdin and compare-and-swap against it before writing (fail closed on a
// concurrent external edit). `extra`/any other 4th arg stays rejected.
const expectStdin = sync && argv[3] === '--expect-stdin';
const file = remove ? argv[1] : sync || check ? argv[2] : argv[0];
const badSync = sync && (!argv[1] || !(argv.length === 3 || (argv.length === 4 && expectStdin)));
const badCheck = check && (!argv[1] || argv.length !== 3);
if (!file || badSync || badCheck) {
  console.error('usage: apply-block.mjs [--remove] <file> | --sync-team-rules <rules-file> <file> [--expect-stdin] | --check-team-rules <rules-file> <file>  (block body on stdin for upsert; expected canonical content on stdin with --expect-stdin)');
  process.exit(2);
}

// ---------- team-rules sync/check mode ----------
if (sync || check) {
  let expected;
  if (expectStdin) {
    try { expected = readFileSync(0, 'utf8'); } catch { expected = ''; }
  }
  try {
    syncTeamRules(argv[1], file, check, expected);
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exit(1);
  }
  process.exit(0);
}

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
  // Preserve the independently-synced active team-rule projection across
  // ordinary /claude-md regeneration, including regeneration by an older
  // block body that does not yet contain the projection markers.
  let oldProjection;
  try { oldProjection = currentTeamProjection(oldBlock); } catch (error) {
    console.error(`refusing to write ${file}: ${error.message}`);
    process.exit(1);
  }
  if (oldProjection) {
    const oldAnchors = lineMatches(oldBlock, ANCHOR);
    if (oldAnchors.length !== 1 || oldProjection.end >= oldAnchors[0].index) {
      console.error(`refusing to write ${file}: team-rules projection must be before ${ANCHOR}`);
      process.exit(1);
    }
    try { block = replaceTeamProjection(block, oldProjection.text); } catch (error) {
      console.error(`refusing to write ${file}: ${error.message}`);
      process.exit(1);
    }
  }
  // preserve previously-learned rules (text between old anchor and old END line)
  const oai = oldBlock.indexOf(ANCHOR);
  if (oai !== -1) {
    const endInOld = oldBlock.search(lineRe(END));
    const learned = oldBlock.slice(oai + ANCHOR.length, endInOld).replace(/\s+$/, '');
    const nai = block.indexOf(ANCHOR);
    if (learned.trim() && nai === -1) {                  // would silently drop accumulated rules
      console.error(`refusing to write ${file}: new block body has no ${ANCHOR} — that would drop accumulated Self-Learning rules`);
      process.exit(1);
    }
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
