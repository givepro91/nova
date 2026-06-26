#!/usr/bin/env node
// PreCompact hook — leaves a deterministic snapshot right before compaction, to guard
// against loss: (1) a lossless backup of the raw transcript, (2) a git breadcrumb.
// Does not block compaction. Snapshots go to docs/handoff/.snapshots/ (auto git-ignored).
import { existsSync, mkdirSync, copyFileSync, appendFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { readInput, projectDir, handoffDir, isOptedIn, git, currentBranch, branchSlug } from './_lib.mjs';

const input = readInput();
const dir = projectDir(input);
if (!isOptedIn(dir)) process.exit(0);

const hd = handoffDir(dir);
const snapDir = join(hd, '.snapshots');
try { mkdirSync(snapDir, { recursive: true }); } catch { /* ignore */ }

// ensure .snapshots/ is git-ignored
const giPath = join(hd, '.gitignore');
try {
  const gi = existsSync(giPath) ? readFileSync(giPath, 'utf8') : '';
  if (!gi.split('\n').some((l) => l.trim() === '.snapshots/')) {
    appendFileSync(giPath, (gi && !gi.endsWith('\n') ? '\n' : '') + '.snapshots/\n');
  }
} catch { /* ignore */ }

// lossless transcript backup (overwrite latest, per-branch so worktrees don't clobber each other)
const branch = currentBranch(dir) || '?';
const slug = branchSlug(branch);
if (input.transcript_path && existsSync(input.transcript_path)) {
  try { copyFileSync(input.transcript_path, join(snapDir, `last-precompact-${slug}.jsonl`)); } catch { /* ignore */ }
}

// breadcrumb
const ts = new Date().toISOString();
const status = git(dir, 'status --porcelain') || '';
const changed = status ? status.split('\n').filter(Boolean).length : 0;
const log = git(dir, 'log --oneline -3') || '(no commits)';
const entry = [
  `## ${ts} (${input.trigger || 'compact'})`,
  `- branch: ${branch} · ${changed} file(s) changed`,
  `- recent commits:`,
  log.split('\n').map((l) => `  - ${l}`).join('\n'),
  '',
].join('\n');
try { appendFileSync(join(snapDir, 'precompact-log.md'), entry + '\n'); } catch { /* ignore */ }

process.exit(0);
