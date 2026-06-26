// nova-gate shared helpers — self-contained (no cross-plugin import). Hardened per Inc 1.5.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { execSync } from 'node:child_process';

/** stdin(JSON) → object, never throws. */
export function readInput() {
  let raw = '';
  try { raw = readFileSync(0, 'utf8'); } catch { /* no stdin */ }
  try { return JSON.parse(raw || '{}'); } catch { return {}; }
}

/** project root: CLAUDE_PROJECT_DIR > input.cwd > process.cwd(). */
export function projectDir(input) {
  return process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
}

export function git(dir, args) {
  try {
    return execSync(`git ${args}`, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { return null; }
}

export function isGitRepo(dir) { return git(dir, 'rev-parse --is-inside-work-tree') === 'true'; }

/** changed file paths. core.quotepath=false → non-ASCII (Korean) paths returned literally. */
export function changedFiles(dir) {
  const out = git(dir, '-c core.quotepath=false status --porcelain');
  if (out == null) return null;
  return out.split('\n')
    .filter((l) => l.length > 3)
    .map((l) => l.slice(3))
    .map((p) => p.split(' -> ').pop());   // rename: orig -> new
}

/** Stop-nudge opt-in: enabled only when .nova/gate.on exists and not globally disabled. */
export function enforceOn(dir) {
  if (process.env.NOVA_GATE_ENFORCE === '0') return false;
  return existsSync(join(dir, '.nova', 'gate.on'));
}

export function output(obj) { process.stdout.write(JSON.stringify(obj)); }
