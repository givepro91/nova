#!/usr/bin/env node
// nova-gate evidence recorder (PostToolUse:Bash, opt-in via .nova/gate.on).
// Appends what ACTUALLY ran — command + output tail — to .nova/evidence.jsonl,
// so /gate can verify claims against a deterministic ledger instead of the
// session's own narration (which compaction erases and optimism bends).
// Silent + fail-open: never blocks, never prints, exits 0 no matter what.
// Kill switch: NOVA_GATE_EVIDENCE=0.
import { existsSync, readFileSync, writeFileSync, appendFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { readInput, projectDir, nowISO } from './_lib.mjs';

const MAX_TAIL = 1500;         // chars kept per stream — the END (test summaries print last)
const MAX_BYTES = 512 * 1024;  // ledger rotation threshold
const KEEP_LINES = 400;

const tail = (v) => { const s = String(v ?? ''); return s.length > MAX_TAIL ? '…' + s.slice(-MAX_TAIL) : s; };

try {
  if (process.env.NOVA_GATE_EVIDENCE !== '0') {
    const input = readInput();
    const nova = join(projectDir(input), '.nova');
    const cmd = input.tool_input?.command;
    if (cmd && existsSync(join(nova, 'gate.on'))) {               // opt-in only
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
      if (!existsSync(gi)) writeFileSync(gi, '*\n!.gitignore\n!gate.on\n');

      const ledger = join(nova, 'evidence.jsonl');
      const entry = { ts: nowISO(), session: input.session_id ?? null, cmd: tail(cmd), code, out: tail(out), err: tail(err) };
      appendFileSync(ledger, JSON.stringify(entry) + '\n');

      if (statSync(ledger).size > MAX_BYTES) {
        const lines = readFileSync(ledger, 'utf8').split('\n').filter(Boolean);
        writeFileSync(ledger, lines.slice(-KEEP_LINES).join('\n') + '\n');
      }
    }
  }
} catch { /* fail-open */ }
process.exit(0);
