#!/usr/bin/env node
// Ensures .nova/.gitignore keeps gate ledgers (gate-history.jsonl, gate-verdict.json,
// evidence.jsonl) machine-local in consumer repos, even when the opt-in evidence hook
// (which writes its own .nova/.gitignore on first Bash call) never fired — e.g. a
// project that only ever runs manual `/gate`. Safe to run repeatedly: creates the file
// if missing, or keeps one managed block at the end so later user patterns cannot
// override it. Content outside the managed block is preserved.
// Usage: node ensure-nova-gitignore.mjs [novaDir=".nova"]
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const MANAGED_BEGIN = '# >>> nova: managed gate ledger ignore >>>';
const MANAGED_END = '# <<< nova: managed gate ledger ignore <<<';
const REQUIRED_LINES = ['*', '!.gitignore', '!gate.on'];
const MANAGED_BLOCK = [MANAGED_BEGIN, ...REQUIRED_LINES, MANAGED_END].join('\n') + '\n';

// Refuses to touch a file whose managed markers are unterminated, orphaned, or
// nested — withoutManagedBlocks() pairs the FIRST begin marker it finds with
// whatever end marker comes after it, so a stray/unterminated begin marker
// left over from a corrupted prior run would otherwise get paired with a
// later, unrelated end marker and silently delete everything in between.
function assertMarkersBalanced(content) {
  const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const beginRe = new RegExp(`^${escape(MANAGED_BEGIN)}\\r?$`, 'gm');
  const endRe = new RegExp(`^${escape(MANAGED_END)}\\r?$`, 'gm');
  const markers = [];
  for (let m; (m = beginRe.exec(content)); ) markers.push({ index: m.index, type: 'begin' });
  for (let m; (m = endRe.exec(content)); ) markers.push({ index: m.index, type: 'end' });
  markers.sort((a, b) => a.index - b.index);

  let open = false;
  for (const marker of markers) {
    if (marker.type === 'begin') {
      if (open) throw new Error('nested managed begin marker (previous one never closed) — refusing to modify, file left untouched');
      open = true;
    } else {
      if (!open) throw new Error('orphan managed end marker with no matching begin — refusing to modify, file left untouched');
      open = false;
    }
  }
  if (open) throw new Error('unterminated managed begin marker (no matching end) — refusing to modify, file left untouched');
}

function withoutManagedBlocks(content) {
  let remaining = content;
  const beginPattern = new RegExp(`^${MANAGED_BEGIN.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\r?$`, 'm');
  const endPattern = new RegExp(`^${MANAGED_END.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\r?$`, 'm');

  while (true) {
    const begin = beginPattern.exec(remaining);
    if (!begin) return remaining;
    const tail = remaining.slice(begin.index + begin[0].length);
    const end = endPattern.exec(tail);
    if (!end) return remaining;

    let blockEnd = begin.index + begin[0].length + end.index + end[0].length;
    if (remaining.startsWith('\r\n', blockEnd)) blockEnd += 2;
    else if (remaining.startsWith('\n', blockEnd)) blockEnd += 1;
    remaining = remaining.slice(0, begin.index) + remaining.slice(blockEnd);
  }
}

function withoutLegacyManagedBlocks(content) {
  return content.replace(
    /(^|\r?\n)\*\r?\n!\.gitignore\r?\n!gate\.on\r?(?=\n|$)\n?/g,
    (_match, prefix) => prefix,
  );
}

export function ensureNovaGitignore(novaDir = '.nova') {
  mkdirSync(novaDir, { recursive: true });
  const giPath = join(novaDir, '.gitignore');
  const existing = existsSync(giPath) ? readFileSync(giPath, 'utf8') : null;

  if (existing === null) {
    writeFileSync(giPath, MANAGED_BLOCK);
    return { path: giPath, action: 'created', added: REQUIRED_LINES };
  }

  assertMarkersBalanced(existing);

  const userContent = withoutLegacyManagedBlocks(withoutManagedBlocks(existing));
  const sep = userContent === '' || userContent.endsWith('\n') ? '' : '\n';
  const desired = userContent + sep + MANAGED_BLOCK;
  if (desired === existing) return { path: giPath, action: 'unchanged', added: [] };

  writeFileSync(giPath, desired);
  return { path: giPath, action: 'updated', added: REQUIRED_LINES };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const novaDir = process.argv[2] || '.nova';
  try {
    process.stdout.write(`${JSON.stringify(ensureNovaGitignore(novaDir))}\n`);
  } catch (error) {
    console.error(`ensure-nova-gitignore: ${error.message}`);
    process.exit(1);
  }
}
