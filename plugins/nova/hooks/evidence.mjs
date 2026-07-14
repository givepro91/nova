#!/usr/bin/env node
// nova-gate evidence recorder (PostToolUse:Bash, opt-in via .nova/gate.on).
// Appends what ACTUALLY ran — command + output tail — to .nova/evidence.jsonl,
// so /gate can verify claims against a deterministic ledger instead of the
// session's own narration (which compaction erases and optimism bends).
// Silent + fail-open: never blocks, never prints, exits 0 no matter what.
// Kill switch: NOVA_GATE_EVIDENCE=0.
import { existsSync, readFileSync, writeFileSync, appendFileSync, renameSync, statSync, lstatSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { randomBytes } from 'node:crypto';
import { readInput, projectDir, nowISO } from './_lib.mjs';

const MAX_TAIL = 1500;         // chars kept per stream — the END (test summaries print last)
const MAX_BYTES = 512 * 1024;  // ledger rotation threshold
const KEEP_LINES = 400;
const NOVA_GITIGNORE = '*\n!.gitignore\n!gate.on\n!rules.md\n';

const tail = (v) => { const s = String(v ?? ''); return s.length > MAX_TAIL ? '…' + s.slice(-MAX_TAIL) : s; };

// lstat (never follows symlinks) — true for a real directory only.
const isRealDir = (path) => { try { return lstatSync(path).isDirectory(); } catch { return false; } };
// true if the path is absent (safe to create) or is already a plain regular file
// (never a symlink, device, etc.) — the write target a symlink attack would swap in.
const isFileOrMissing = (path) => {
  try { return lstatSync(path).isFile(); } catch (err) { return err.code === 'ENOENT'; }
};
// Symlink-safe replace: write a fresh temp file in the same dir, then rename over the
// target. Skips (fail-open, no write) if the target exists and isn't a regular file.
const safeReplaceFile = (path, content) => {
  if (!isFileOrMissing(path)) return false;
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}-${randomBytes(6).toString('hex')}.tmp`);
  writeFileSync(tmp, content);
  renameSync(tmp, path);
  return true;
};
// Symlink-safe append: refuses to append through a symlink or into a non-regular file.
const safeAppendFile = (path, content) => {
  if (!isFileOrMissing(path)) return false;
  appendFileSync(path, content);
  return true;
};

try {
  if (process.env.NOVA_GATE_EVIDENCE !== '0') {
    const input = readInput();
    const nova = join(projectDir(input), '.nova');
    const cmd = input.tool_input?.command;
    if (cmd && isRealDir(nova) && existsSync(join(nova, 'gate.on'))) {   // opt-in only, .nova must be a real dir
      // tool_response shape is version-dependent — extract defensively
      const tr = input.tool_response;
      let out = '', err = '', code = null;
      if (tr && typeof tr === 'object' && !Array.isArray(tr)) {
        out = tr.stdout ?? tr.output ?? '';
        err = tr.stderr ?? '';
        code = tr.exitCode ?? tr.exit_code ?? null;
      } else if (Array.isArray(tr)) out = tr.map((b) => b?.text ?? '').join('\n');
      else if (tr != null) out = String(tr);

      // output tails can contain anything — force the ledger to stay machine-local
      const gi = join(nova, '.gitignore');
      if (!existsSync(gi) || readFileSync(gi, 'utf8') !== NOVA_GITIGNORE) safeReplaceFile(gi, NOVA_GITIGNORE);

      const ledger = join(nova, 'evidence.jsonl');
      const entry = { ts: nowISO(), session: input.session_id ?? null, cmd: tail(cmd), code, out: tail(out), err: tail(err) };
      const appended = safeAppendFile(ledger, JSON.stringify(entry) + '\n');

      if (appended && statSync(ledger).size > MAX_BYTES) {
        const lines = readFileSync(ledger, 'utf8').split('\n').filter(Boolean);
        safeReplaceFile(ledger, lines.slice(-KEEP_LINES).join('\n') + '\n');
      }
    }
  }
} catch { /* fail-open */ }
process.exit(0);
