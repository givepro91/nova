#!/usr/bin/env node
// nova-gate Stop NUDGE — OPT-IN (create .nova/gate.on). When meaningful work happened and
// the session hasn't been audited, block ONCE to remind running /gate before ending.
//
// This is only a nudge — NOT the audit. A Stop hook gets no transcript/last-message, so the
// real claim→evidence audit must run in-session via /gate (full context). The hook just
// reminds. (For mechanism-level enforcement see the experimental type:"agent" hook in README.)
//
// Loop guard:   stop_hook_active=true → pass.
// Opt-in:       .nova/gate.on must exist.   Disable: NOVA_GATE_ENFORCE=0.
// Threshold:    NOVA_GATE_MIN_CHANGED_FILES (default 3).
// Already audited: skip if .nova/gate-verdict.json is newer than the newest changed file.
import { existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { readInput, projectDir, isGitRepo, changedFiles, enforceOn, output } from './_lib.mjs';

const input = readInput();
if (input.stop_hook_active === true) process.exit(0);   // mid force-continue → avoid loop
const dir = projectDir(input);
if (!enforceOn(dir)) process.exit(0);                   // opt-in only
if (!isGitRepo(dir)) process.exit(0);

const all = changedFiles(dir);
if (!all) process.exit(0);
// exclude tool state files — Nova/handoff/worklog artifacts aren't "work" to audit
const files = all.filter((f) => !/^(\.nova\/|docs\/handoff\/|docs\/worklog\/)/.test(f));
if (!files.length) process.exit(0);

let threshold = parseInt(process.env.NOVA_GATE_MIN_CHANGED_FILES || '3', 10);
if (!Number.isFinite(threshold) || threshold < 1) threshold = 3;
if (files.length < threshold) process.exit(0);          // ignore trivial work

// already audited after the latest change? then don't nag.
const verdict = join(dir, '.nova', 'gate-verdict.json');
if (existsSync(verdict)) {
  const vmt = statSync(verdict).mtimeMs;
  let newest = 0;
  for (const f of files) { try { const m = statSync(join(dir, f)).mtimeMs; if (m > newest) newest = m; } catch { /* deleted */ } }
  if (vmt >= newest) process.exit(0);
}

output({
  decision: 'block',
  reason: [
    `Run /gate before ending — ${files.length} file(s) changed and this session hasn't been audited for completion honesty.`,
    `/gate spawns an independent verifier that maps your completion claims to evidence:`,
    `did the tests actually run? was scope kept? is anything unverified being presented as done?`,
    ``,
    `Already audited, or this doesn't need it? Remove .nova/gate.on or set NOVA_GATE_ENFORCE=0.`,
  ].join('\n'),
});
process.exit(0);
