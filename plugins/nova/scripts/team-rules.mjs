#!/usr/bin/env node
// Parse, validate, and safely write the canonical .nova/rules.md team-rule store.
import {
  existsSync, mkdirSync, readFileSync, writeFileSync, renameSync, lstatSync,
  openSync, closeSync, writeSync, unlinkSync, linkSync, readdirSync, readlinkSync, realpathSync,
} from 'node:fs';
import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, posix, win32, join, basename, isAbsolute } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const APPLY_BLOCK_SCRIPT = fileURLToPath(new URL('./apply-block.mjs', import.meta.url));
const MANAGED_BLOCK_RE = { start: /^<!-- CC-RULES:START -->[ \t]*\r?$/m, end: /^<!-- CC-RULES:END -->[ \t]*\r?$/m };

export const TEAM_RULES_SCHEMA = 'nova-team-rules/v1';
export const NOVA_GITIGNORE = '*\n!.gitignore\n!gate.on\n!rules.md\n';

const ID_RE = /^rule-\d{8}-[0-9a-f]{8}$/;
const STATUS = new Set(['proposed', 'active', 'retired']);
const ORIGIN = new Set(['propose', 'merge', 'generalize']);
const PREFIX = `---\nschema: ${TEAM_RULES_SCHEMA}\n---\n\n# Nova team rules\n`;
const CONFLICT_RE = /^(?:<<<<<<<|=======|>>>>>>>)(?:[ \t].*)?$/m;
const SECRET_RE = /(?:-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\b(?:sk|gh[pousr])[-_][A-Za-z0-9_-]{16,}\b|\bgithub_pat_[A-Za-z0-9_]{16,}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}\b|\bAIza[A-Za-z0-9_-]{20,}\b|\bBearer\s+[A-Za-z0-9._~+/=-]{8,}\b|\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b|\b(?:api[_-]?key|token|password|secret|authorization)\s*[:=]\s*\S+)/i;
const STACK_FRAME_RE = /(?:^|\s)at\s+(?:async\s+)?(?:[^()\r\n]+\s+\()?(?:file:\/{2,3}[^()\r\n]*|[A-Za-z]:\\[^()\r\n]*|(?:\/|\.{1,2}\/)[^()\r\n]*|[^()\r\n]*[/\\][^()\r\n]*|[^()\s]+\.[A-Za-z0-9]{1,10}|<anonymous>):\d+(?::\d+)?\)?/;
const RAW_OUTPUT_RE = /(?:^|\s)(?:[A-Za-z]*Error:\s|npm ERR!|Traceback \(most recent call last\):|File ["'][^"']+["'], line \d+(?:, in \S+)?)/i;
// Common test-runner / build-tool result lines pasted verbatim from a
// terminal — a refined one-line summary never contains these shapes, so
// their presence means raw command output crossed into a team-visible field.
const COMMAND_OUTPUT_RE = /^(?:PASS|FAIL)$|(?:^|\s)(?:(?:PASS|FAIL)\s+\S+\.(?:[cm]?[jt]sx?|py|rb|go|rs|java|php)\b|---\s+(?:PASS|FAIL):\s+\S+\s+\(\d+(?:\.\d+)?s\)|test\s+\S+\s+\.\.\.\s+(?:ok|FAILED|ignored)\b|(?:ok|FAIL)\s+\S+\s+(?:\d+(?:\.\d+)?s|\(cached\)|\[(?:build|setup) failed\])(?:\s|$)|\?\s+\S+\s+\[no test files\])|\b(?:Test Suites?|Tests?|Snapshots?|Suites?|Assertions?):\s+\d|\bTests run:\s*\d+,\s*Failures:\s*\d+,\s*Errors:\s*\d+|\bRan\s+\d+\s+tests?\s+in\s+\d+(?:\.\d+)?s\b|\b\d+\s+(?:passed|failed|passing|failing|skipped|pending|todo)\b|\b\d+\s+examples?,\s+\d+\s+failures?\b|\b\d+\s+runs?,\s+\d+\s+assertions?(?:,\s+\d+\s+(?:failures?|errors?|skips?))+\b|\bOK\s+\(\d+\s+tests?,\s+\d+\s+assertions?\)|\bPassed!\s*-\s*Failed:\s*\d+,\s*Passed:\s*\d+|\*\*\s*TEST\s+(?:SUCCEEDED|FAILED)\s*\*\*|\b(?:ok|not ok)\s+\d+\b/i;
// A URL carrying inline `user:password@` credentials — the classic secret
// leak that the token-shaped SECRET_RE patterns below do not cover.
const CREDENTIAL_URL_RE = /\b[a-z][a-z0-9+.-]*:\/\/[^\s/:@]+:[^\s/@]+@/i;
// projection embeds Rule bodies verbatim into an HTML comment in CLAUDE.md
// (<!-- nova-rule:id -->) — an unescaped comment delimiter in the body could
// close/open a comment and forge or hide a projection control marker.
const HTML_COMMENT_RE = /<!--|-->/;
const PROPOSAL_FIELDS = ['evidence-summary', 'rule', 'scope', 'source-summary'];
const GARDENER_FIELDS = {
  promote: ['id'],
  retire: ['id', 'retired-reason'],
  merge: ['derived-from', 'evidence-summary', 'rule', 'scope', 'source-summary'],
  generalize: ['derived-from', 'evidence-summary', 'rule', 'scope', 'source-summary'],
};

// --- symlink-safe fs helpers (mirrors hooks/evidence.mjs) ---------------
// lstat (never follows symlinks) — true for a real directory only.
const isRealDir = (path) => { try { return lstatSync(path).isDirectory(); } catch { return false; } };
// true if the path is absent (safe to create) or is already a plain regular
// file (never a symlink, device, etc.) — the write target a symlink attack
// would swap in.
const isFileOrMissing = (path) => {
  try { return lstatSync(path).isFile(); } catch (err) { return err.code === 'ENOENT'; }
};
// Write a fresh temp file in the same directory, then rename over the
// target — never opens/truncates the target path itself.
function atomicWriteFile(path, content) {
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}-${randomBytes(6).toString('hex')}.tmp`);
  writeFileSync(tmp, content);
  try {
    renameSync(tmp, path);
  } finally {
    try { unlinkSync(tmp); } catch { /* renamed or already removed */ }
  }
}

function createFileIfAbsent(path, content) {
  const tmp = join(dirname(path), `.${basename(path)}.${process.pid}-${randomBytes(6).toString('hex')}.tmp`);
  writeFileSync(tmp, content);
  try {
    linkSync(tmp, path);
  } finally {
    try { unlinkSync(tmp); } catch { /* already removed */ }
  }
}

// Atomically replace `path` via a two-step, non-destructive swap: relocate
// whatever currently occupies `path` to `backup` (rename to a fresh,
// never-before-used name can only move data, never overwrite it), then
// install the new content with an EXCLUSIVE link (fails instead of silently
// replacing if another writer re-occupied `path` in the gap since the
// relocation). A "check identity, then separately rename" cannot close this
// window no matter how tightly the check is written — POSIX rename() has no
// compare-and-swap, so it always replaces whatever is at the destination.
// This protocol never calls a replacing rename against `path`, so nothing
// there is ever destroyed unseen; a race lands in `backup` instead, where it
// can be compared against `expected` and restored after the fact. For the
// same reason `backup` itself is never unlinked, even once every check has
// passed: a file descriptor opened on the pre-rename inode can still deliver
// a delayed write to it up to the last possible instant, so on every exit
// path it is renamed to a fresh `recovered` name instead — a move can only
// relocate that data, never destroy it.
function replaceFileIfUnchanged(path, expected, content) {
  const suffix = `${process.pid}-${randomBytes(6).toString('hex')}`;
  const tmp = join(dirname(path), `.${basename(path)}.${suffix}.tmp`);
  const backup = join(dirname(path), `.${basename(path)}.${suffix}.backup`);
  const recovered = join(dirname(path), `.${basename(path)}.${suffix}.recovered`);
  let committed = false;
  let restored = false;
  writeFileSync(tmp, content);
  // Crash safety net for the window below where `path` is briefly absent
  // (relocated to `backup`, not yet re-linked). process.exit() — including
  // one triggered by an uncaught exception — still runs 'exit' listeners
  // synchronously, so this can fire even if the crash lands mid-syscall
  // before the rest of this function resumes. It reads disk state directly
  // rather than in-memory flags, since a crash mid-syscall can leave those
  // stale. A hard kill (SIGKILL) bypasses this entirely; the data is not
  // lost (it is still sitting in `backup`), but assertNoOrphanedBackup()
  // must fail the *next* run closed instead of silently discarding it.
  const restoreOnExit = () => {
    if (!existsSync(path) && existsSync(backup)) {
      try { linkSync(backup, path); } catch { /* leave for manual recovery */ }
    }
  };
  process.on('exit', restoreOnExit);
  try {
    renameSync(path, backup);

    // Validate what the capture-rename actually moved before installing the
    // new inode. If an editor saved between the caller's read and this
    // rename, restore that captured edit with an exclusive link and fail;
    // the new content has never occupied the canonical path.
    let backupContent;
    try {
      backupContent = readFileSync(backup, 'utf8');
    } catch (err) {
      try {
        linkSync(backup, path);
        restored = true;
      } catch (restoreError) {
        const error = new TeamRulesError(`could not safely restore ${path} after capture verification failed; backup preserved at ${backup}: ${restoreError.message}`);
        error.cause = err;
        throw error;
      }
      throw err;
    }
    if (backupContent !== expected) {
      try {
        linkSync(backup, path);
        restored = true;
      } catch (restoreError) {
        const error = new TeamRulesError(`could not safely restore a concurrent edit at ${path}; backup preserved at ${backup}: ${restoreError.message}`);
        throw error;
      }
      fail(`concurrent edit detected: ${path}`);
    }

    try {
      linkSync(tmp, path);
    } catch (err) {
      if (err.code === 'EEXIST') fail(`concurrent edit detected: ${path}`);
      try {
        linkSync(backup, path);
        restored = true;
      } catch (restoreError) {
        const error = new TeamRulesError(`could not safely restore ${path} after install failed; backup preserved at ${backup}: ${restoreError.message}`);
        error.cause = err;
        throw error;
      }
      throw err;
    }

    // The exclusive link above is the commit point: tmp was fully written
    // before the swap and path now names that exact inode; path is not
    // rolled back past this point no matter what the checks below find.

    // A file descriptor an editor opened on `path` before the capture-rename
    // can still deliver a delayed write to that same inode — now reachable
    // only via `backup` — at any instant up to right now. Re-read it and
    // compare against the content captured earlier: a mismatch means that
    // delayed write landed, so `backup` must be left exactly where it is
    // (not retired below) instead of being silently discarded as a spent
    // temp file.
    let postCaptureBackupContent;
    try {
      postCaptureBackupContent = readFileSync(backup, 'utf8');
    } catch (err) {
      const error = new TeamRulesError(`could not verify ${backup} for a delayed write after installing ${path}; the new content is installed, but ${backup} could not be re-read to confirm it is safe to retire — inspect it manually: ${err.message}`);
      throw error;
    }
    if (postCaptureBackupContent !== backupContent) {
      fail(`concurrent edit detected in the captured backup after installing ${path}: ${backup} changed after capture verification; the new content is installed at ${path}, and the delayed write is preserved at ${backup} for manual recovery`);
    }

    // This read is only a best-effort detector for a later non-cooperating
    // editor, so an I/O error cannot turn a completed commit into a failed
    // partial write.
    let installedContent;
    try {
      installedContent = readFileSync(path, 'utf8');
    } catch {
      committed = true;
      return;
    }
    if (installedContent !== content) fail(`concurrent edit detected after replacing: ${path}`);
    committed = true;
  } finally {
    process.removeListener('exit', restoreOnExit);
    try { unlinkSync(tmp); } catch { /* linked or already removed */ }
    if (committed || restored) {
      // Rename rather than unlink: even after every check above passes, a
      // delayed write to this inode from an fd opened before the capture-
      // rename could still land in the instant before this line runs.
      // Renaming can only move that data, never destroy it, so it survives
      // on disk under a unique name for manual recovery either way.
      try { renameSync(backup, recovered); } catch { /* already moved/removed */ }
    }
  }
}

// Refuses to proceed when `path` is missing but a `.backup` sibling exists —
// the signature of a crash landing inside replaceFileIfUnchanged's swap
// window (relocated but never linked back, and the process.exit() safety
// net above never got a chance to run — e.g. SIGKILL). Treating a missing
// `path` as "no prior file" here would create a fresh store and silently
// discard the real history that is still sitting, intact, in the backup.
function assertNoOrphanedBackup(path) {
  if (existsSync(path)) return;
  const dir = dirname(path);
  const prefix = `.${basename(path)}.`;
  let entries;
  try { entries = readdirSync(dir); } catch { return; }
  if (entries.some((name) => name.startsWith(prefix) && name.endsWith('.backup'))) {
    fail(`refusing to write: ${path} is missing but a recoverable .backup sibling exists in ${dir} — restore it manually before retrying`);
  }
}

// Refuses to write rules.md or its sibling .gitignore through a symlink (or
// a symlinked .nova directory) — both paths are checked before either is
// touched, so a bad target leaves both files unchanged.
function assertSafeWriteTargets(file, novaDir) {
  if (existsSync(novaDir) && !isRealDir(novaDir)) fail(`refusing to write: not a real directory: ${novaDir}`);
  if (!isFileOrMissing(file)) fail(`refusing to write through non-regular-file path: ${file}`);
  const gitignoreFile = join(novaDir, '.gitignore');
  if (!isFileOrMissing(gitignoreFile)) fail(`refusing to write through non-regular-file path: ${gitignoreFile}`);
}

// --- per-repo exclusive lock (covers read through the final atomic write) --
const LOCK_TIMEOUT_MS = 10000;
const LOCK_POLL_MS = 20;

function sleepSync(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// Exclusive create (O_EXCL) is atomic and symlink-safe: it fails with EEXIST
// if anything — including a symlink — already occupies the path. There is no
// mtime-based stale takeover: a lock's age says nothing about whether its
// owner is still alive, and a false takeover would let two writers believe
// they both succeeded while one's record is silently lost. So a held lock
// fails closed on timeout instead — a stuck/dead-owner lock requires a human
// to confirm no writer is running and remove .rules.lock manually. The lock
// body carries a random per-holder token so release() only ever unlinks a
// lock this call still owns, never one an unrelated cleanup or process has
// since recreated.
function acquireLock(novaDir) {
  const lockPath = join(novaDir, '.rules.lock');
  const token = randomBytes(16).toString('hex');
  const body = `${process.pid}\n${token}\n`;
  const start = Date.now();
  for (;;) {
    try {
      const fd = openSync(lockPath, 'wx');
      writeSync(fd, body);
      closeSync(fd);
      return () => {
        try { if (readFileSync(lockPath, 'utf8') === body) unlinkSync(lockPath); } catch { /* already released */ }
      };
    } catch (err) {
      if (err.code !== 'EEXIST') fail(`could not acquire team rules lock: ${err.message}`);
      if (Date.now() - start > LOCK_TIMEOUT_MS) {
        fail(`timed out waiting for the .nova/rules.md lock at ${lockPath} (another process may be writing; if it is stale, confirm no writer is running and remove it manually)`);
      }
      sleepSync(LOCK_POLL_MS);
    }
  }
}

export class TeamRulesError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TeamRulesError';
  }
}

const fail = (message) => { throw new TeamRulesError(message); };
const isValidRuleId = (id) => {
  const match = /^rule-(\d{4})(\d{2})(\d{2})-[0-9a-f]{8}$/.exec(id);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= days[month - 1];
};
const normalizeNewlines = (content) => {
  if (typeof content !== 'string') fail('team rules content must be a string');
  if (/\r(?!\n)/.test(content)) fail('lone CR line ending is not allowed');
  return content.replace(/\r\n/g, '\n');
};

function parseJsonArray(raw, field, id) {
  let value;
  try { value = JSON.parse(raw); } catch { fail(`${id}: ${field} must be a JSON array`); }
  if (!Array.isArray(value)) fail(`${id}: ${field} must be a JSON array`);
  return value;
}

function assertNoSecret(value, field, id) {
  if (CREDENTIAL_URL_RE.test(value) || SECRET_RE.test(value)) fail(`${id}: ${field} looks like raw secret material`);
}

// Refuse raw command-output shapes in prose fields and secret-looking material
// in every tracked, team-visible field.
function assertNotRawOrSecret(value, field, id) {
  if (/\x1b\[[0-9;]*m/.test(value)
    || /^\s*\$/i.test(value)
    || /\b(?:stdout|stderr):/i.test(value)
    || RAW_OUTPUT_RE.test(value)
    || COMMAND_OUTPUT_RE.test(value)
    || STACK_FRAME_RE.test(value)) {
    fail(`${id}: ${field} looks like raw command output`);
  }
  assertNoSecret(value, field, id);
}

function validateSummary(value, field, id) {
  if (!value || value !== value.trim()) fail(`${id}: ${field} must be a non-empty trimmed line`);
  if (/[\r\n`]/.test(value) || value.includes('```')) fail(`${id}: ${field} must be a plain one-line summary`);
  assertNotRawOrSecret(value, field, id);
}

function validateScope(scope, id) {
  if (scope.length === 0) fail(`${id}: scope must not be empty`);
  const seen = new Set();
  for (const glob of scope) {
    if (typeof glob !== 'string' || !glob || glob !== glob.trim()) fail(`${id}: scope entries must be non-empty strings`);
    if (glob.includes('\\') || posix.isAbsolute(glob) || win32.isAbsolute(glob)) fail(`${id}: scope must be repo-relative: ${glob}`);
    if (glob.includes('..')) fail(`${id}: scope must not contain a parent traversal: ${glob}`);
    if (/[\0\r\n]/.test(glob)) fail(`${id}: scope contains an invalid character`);
    assertNoSecret(glob, 'scope', id);
    if (seen.has(glob)) fail(`${id}: duplicate scope entry: ${glob}`);
    seen.add(glob);
  }
}

function parseRecord(block) {
  const match = /^## `(rule-\d{8}-[0-9a-f]{8})`\n\n- status: `([^`]+)`\n- scope: `([^`]+)`\n- source-summary: `([^`]+)`\n- evidence-summary: `([^`]+)`\n- origin: `([^`]+)`\n- derived-from: `([^`]+)`(?:\n- retired-reason: `([^`]+)`)?\n\n### Rule\n\n([^\n]+)$/.exec(block);
  if (!match) fail('malformed rule record or field order');

  const [, id, status, scopeRaw, sourceSummary, evidenceSummary, origin, derivedRaw, retiredReason, body] = match;
  const scope = parseJsonArray(scopeRaw, 'scope', id);
  const derivedFrom = parseJsonArray(derivedRaw, 'derived-from', id);
  return { id, status, scope, sourceSummary, evidenceSummary, origin, derivedFrom, retiredReason, body };
}

function validateRecord(record) {
  const { id, status, scope, sourceSummary, evidenceSummary, origin, derivedFrom, retiredReason, body } = record;
  if (!ID_RE.test(id) || !isValidRuleId(id)) fail(`invalid rule id: ${id}`);
  if (!STATUS.has(status)) fail(`${id}: invalid status: ${status}`);
  if (!ORIGIN.has(origin)) fail(`${id}: invalid origin: ${origin}`);
  validateScope(scope, id);
  validateSummary(sourceSummary, 'source-summary', id);
  validateSummary(evidenceSummary, 'evidence-summary', id);
  if (!body || body !== body.trim() || /[\r\n]/.test(body)) fail(`${id}: Rule must be one non-empty trimmed line`);
  if (CONFLICT_RE.test(body)) fail(`${id}: unresolved conflict marker in Rule`);
  if (HTML_COMMENT_RE.test(body)) fail(`${id}: Rule must not contain an HTML comment marker`);
  assertNotRawOrSecret(body, 'Rule', id);

  const seen = new Set();
  for (const sourceId of derivedFrom) {
    if (typeof sourceId !== 'string' || !ID_RE.test(sourceId) || !isValidRuleId(sourceId)) fail(`${id}: invalid derived-from id`);
    if (seen.has(sourceId)) fail(`${id}: duplicate derived-from id: ${sourceId}`);
    seen.add(sourceId);
  }
  if (origin === 'propose' && derivedFrom.length !== 0) fail(`${id}: propose origin must have empty derived-from`);
  if (origin !== 'propose' && derivedFrom.length === 0) fail(`${id}: ${origin} origin requires derived-from provenance`);
  if (status === 'proposed' && origin !== 'propose') fail(`${id}: proposed rules must use propose origin`);
  if (origin !== 'propose' && status !== 'active' && status !== 'retired') fail(`${id}: ${origin} rules must start active`);

  if (status === 'retired') {
    if (!retiredReason) fail(`${id}: retired rules require retired-reason`);
    validateSummary(retiredReason, 'retired-reason', id);
  } else if (retiredReason !== undefined) {
    fail(`${id}: retired-reason is only allowed for retired rules`);
  }
}

function validateProvenance(records) {
  const byId = new Map(records.map((record) => [record.id, record]));
  for (const record of records) {
    for (const sourceId of record.derivedFrom) {
      if (!byId.has(sourceId)) fail(`${record.id}: derived-from record not found: ${sourceId}`);
    }
  }

  const visiting = new Set();
  const visited = new Set();
  const visit = (id) => {
    if (visiting.has(id)) fail(`${id}: provenance cycle detected`);
    if (visited.has(id)) return;
    visiting.add(id);
    for (const sourceId of byId.get(id).derivedFrom) visit(sourceId);
    visiting.delete(id);
    visited.add(id);
  };
  for (const record of records) visit(record.id);
}

export function parseTeamRules(content) {
  const normalized = normalizeNewlines(content);
  if (CONFLICT_RE.test(normalized)) fail('unresolved git conflict marker');
  if (!normalized.startsWith(PREFIX)) fail(`expected schema ${TEAM_RULES_SCHEMA} and canonical heading`);

  const remainder = normalized.slice(PREFIX.length);
  if (remainder === '') return { schema: TEAM_RULES_SCHEMA, records: [], content: normalized };
  if (!remainder.startsWith('\n')) fail('expected a blank line before the first rule');

  let recordsText = remainder.slice(1);
  if (recordsText.endsWith('\n')) recordsText = recordsText.slice(0, -1);
  if (!recordsText) fail('unexpected trailing blank line');
  const blocks = recordsText.split(/\n\n(?=## `)/);
  const records = blocks.map(parseRecord);
  const ids = new Set();
  for (const record of records) {
    if (ids.has(record.id)) fail(`duplicate rule id: ${record.id}`);
    ids.add(record.id);
    validateRecord(record);
  }
  validateProvenance(records);
  return { schema: TEAM_RULES_SCHEMA, records, content: normalized };
}

const comparable = (record) => JSON.stringify(record, Object.keys(record).sort());

export function validateTeamRulesTransition(previous, next) {
  const oldDoc = typeof previous === 'string' ? parseTeamRules(previous) : previous;
  const newDoc = typeof next === 'string' ? parseTeamRules(next) : next;
  const oldById = new Map(oldDoc.records.map((record) => [record.id, record]));
  const newById = new Map(newDoc.records.map((record) => [record.id, record]));

  for (const oldRecord of oldDoc.records) {
    const nextRecord = newById.get(oldRecord.id);
    if (!nextRecord) fail(`${oldRecord.id}: records must be retired, not deleted`);
    const transition = `${oldRecord.status}->${nextRecord.status}`;
    if (!new Set(['proposed->proposed', 'proposed->active', 'proposed->retired', 'active->active', 'active->retired', 'retired->retired']).has(transition)) {
      fail(`${oldRecord.id}: forbidden status transition ${transition}`);
    }
    if (oldRecord.status !== nextRecord.status) {
      const expected = { ...nextRecord, status: oldRecord.status, retiredReason: oldRecord.retiredReason };
      if (comparable(oldRecord) !== comparable(expected)) fail(`${oldRecord.id}: status transition may not change other fields`);
    }
  }

  for (const record of newDoc.records) {
    if (oldById.has(record.id)) continue;
    if (record.origin === 'propose' && record.status !== 'proposed') fail(`${record.id}: new proposals must start proposed`);
    if (record.origin !== 'propose' && record.status !== 'active') fail(`${record.id}: new ${record.origin} rules must start active`);
    if (record.origin !== 'propose') {
      for (const sourceId of record.derivedFrom) {
        const oldSource = oldById.get(sourceId);
        const newSource = newById.get(sourceId);
        if (!oldSource || !newSource) fail(`${record.id}: provenance must reference an existing source record: ${sourceId}`);
        if (oldSource.status === 'retired' || newSource.status !== 'retired') fail(`${record.id}: source record must transition to retired: ${sourceId}`);
        if (!newSource.retiredReason.includes(record.id)) fail(`${sourceId}: retired-reason must name replacement ${record.id}`);
      }
    }
  }
  return newDoc;
}

export function writeTeamRules(file, content, expectedContent) {
  const next = parseTeamRules(content);
  const novaDir = dirname(file);
  if (existsSync(novaDir) && !isRealDir(novaDir)) fail(`refusing to write: not a real directory: ${novaDir}`);
  if (!isFileOrMissing(file)) fail(`refusing to write through non-regular-file path: ${file}`);
  if (existsSync(file)) {
    const currentContent = readFileSync(file, 'utf8');
    if (expectedContent !== undefined && currentContent !== expectedContent) fail(`concurrent edit detected: ${file}`);
    validateTeamRulesTransition(parseTeamRules(currentContent), next);
  } else if (expectedContent !== undefined) {
    fail(`concurrent edit detected: ${file} was removed`);
  }
  mkdirSync(novaDir, { recursive: true });
  const output = next.content.endsWith('\n') ? next.content : `${next.content}\n`;
  if (expectedContent === undefined) atomicWriteFile(file, output);
  else replaceFileIfUnchanged(file, expectedContent, output);
  return next;
}

function formatRecord(record) {
  const retiredReason = record.retiredReason === undefined ? '' : `\n- retired-reason: \`${record.retiredReason}\``;
  return `## \`${record.id}\`\n\n- status: \`${record.status}\`\n- scope: \`${JSON.stringify(record.scope)}\`\n- source-summary: \`${record.sourceSummary}\`\n- evidence-summary: \`${record.evidenceSummary}\`\n- origin: \`${record.origin}\`\n- derived-from: \`${JSON.stringify(record.derivedFrom)}\`${retiredReason}\n\n### Rule\n\n${record.body}`;
}

function formatDocument(records) {
  if (records.length === 0) return PREFIX;
  return `${PREFIX}\n${records.map(formatRecord).join('\n\n')}\n`;
}

function createRuleId(records) {
  const date = new Date().toISOString().slice(0, 10).replaceAll('-', '');
  const existing = new Set(records.map((record) => record.id));
  for (let attempt = 0; attempt < 16; attempt += 1) {
    const id = `rule-${date}-${randomBytes(4).toString('hex')}`;
    if (!existing.has(id)) return id;
  }
  fail('could not generate a unique rule id');
}

function parseProposal(input) {
  let proposal;
  try { proposal = JSON.parse(input); } catch { fail('proposal input must be one JSON object'); }
  if (!proposal || typeof proposal !== 'object' || Array.isArray(proposal)) fail('proposal input must be one JSON object');
  const fields = Object.keys(proposal).sort();
  if (JSON.stringify(fields) !== JSON.stringify(PROPOSAL_FIELDS)) {
    fail(`proposal fields must be exactly: ${PROPOSAL_FIELDS.join(', ')}`);
  }
  return proposal;
}

function parseGardenerInput(operation, input) {
  let value;
  try { value = JSON.parse(input); } catch { fail(`${operation} input must be one JSON object`); }
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${operation} input must be one JSON object`);
  const fields = Object.keys(value).sort();
  if (JSON.stringify(fields) !== JSON.stringify(GARDENER_FIELDS[operation])) {
    fail(`${operation} fields must be exactly: ${GARDENER_FIELDS[operation].join(', ')}`);
  }
  return value;
}

export function proposeTeamRule(file, input) {
  const novaDir = dirname(file);
  mkdirSync(novaDir, { recursive: true });
  assertSafeWriteTargets(file, novaDir);
  const release = acquireLock(novaDir);
  try {
    assertNoOrphanedBackup(file);
    const currentContent = existsSync(file) ? readFileSync(file, 'utf8') : undefined;
    const current = currentContent === undefined ? parseTeamRules(PREFIX) : parseTeamRules(currentContent);
    const proposal = typeof input === 'string' ? parseProposal(input) : input;
    const record = {
      id: createRuleId(current.records),
      status: 'proposed',
      scope: proposal.scope,
      sourceSummary: proposal['source-summary'],
      evidenceSummary: proposal['evidence-summary'],
      origin: 'propose',
      derivedFrom: [],
      body: proposal.rule,
    };
    validateRecord(record);
    const separator = current.content.endsWith('\n') ? '\n' : '\n\n';
    const content = `${current.content}${separator}${formatRecord(record)}\n`;
    if (currentContent === undefined) {
      ensureNovaGitignore(novaDir);
      try { createFileIfAbsent(file, content); } catch (error) {
        if (error.code === 'EEXIST') fail(`concurrent edit detected: ${file} was created`);
        throw error;
      }
    } else {
      ensureNovaGitignore(novaDir);
    }
    const written = currentContent === undefined ? parseTeamRules(content) : writeTeamRules(file, content, currentContent);
    if (!written.records.some((r) => r.id === record.id)) fail(`${record.id}: written document is missing the new record`);
    return record;
  } finally {
    release();
  }
}

// Resolve the repo's canonical agent file the same way /claude-md does:
// a CLAUDE.md symlink wins (its target is the real file); CLAUDE.md
// importing `@AGENTS.md` hands canonical status to AGENTS.md; an AGENTS.md-
// only repo uses AGENTS.md; otherwise CLAUDE.md (default), whether or not it
// exists yet — a missing canonical file is handled by the caller, not here.
function resolveCanonicalAgentFile(root) {
  const claudeMd = join(root, 'CLAUDE.md');
  const agentsMd = join(root, 'AGENTS.md');
  try {
    if (lstatSync(claudeMd).isSymbolicLink()) {
      const target = readlinkSync(claudeMd);
      return isAbsolute(target) ? target : join(dirname(claudeMd), target);
    }
  } catch { /* CLAUDE.md missing or not a symlink */ }
  if (existsSync(claudeMd)) {
    const text = readFileSync(claudeMd, 'utf8');
    return /^@AGENTS\.md[ \t]*\r?$/m.test(text) ? agentsMd : claudeMd;
  }
  return existsSync(agentsMd) ? agentsMd : claudeMd;
}

const hasManagedBlock = (text) => MANAGED_BLOCK_RE.start.test(text) && MANAGED_BLOCK_RE.end.test(text);
const hasManagedBlockMarker = (text) => MANAGED_BLOCK_RE.start.test(text) || MANAGED_BLOCK_RE.end.test(text);

// stdio must be fully piped (not the execFileSync default, which lets a
// failing child's stderr leak straight through to this process's own
// stderr) so an expected "out of sync" preflight result stays silent.
function runApplyBlock(args, input) {
  return execFileSync(process.execPath, [APPLY_BLOCK_SCRIPT, ...args], {
    input: input ?? '', encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'],
  });
}

// Project active rules into the repo's canonical agent file after a
// gardener mutation succeeds (or, with `preflight`, sanity-check it
// beforehand). A canonical file that does not exist yet is not an error —
// the repo may not have run /claude-md — `.nova/rules.md` stays the source
// of truth either way and the projection can be synced later.
// Returns the canonical file's content captured at preflight (or null when it
// does not exist / needs bootstrapping), so the sync pass can compare-and-swap
// against it and refuse a projection that would clobber a concurrent edit.
function projectToCanonicalFile(rulesFile, novaDir, { preflight, expectedBefore }) {
  const canonical = resolveCanonicalAgentFile(dirname(novaDir));
  if (!existsSync(canonical)) return null;
  const text = readFileSync(canonical, 'utf8');

  if (preflight) {
    if (!hasManagedBlockMarker(text)) return text; // nothing to preflight; sync bootstraps it below
    try {
      runApplyBlock(['--check-team-rules', rulesFile, canonical]);
    } catch (error) {
      const message = (error.stderr || error.message).trim();
      if (!/are out of sync:/.test(message)) {
        fail(`refusing gardener operation: ${canonical} is not in a projectable state: ${message}`);
      }
    }
    return text;
  }

  if (!hasManagedBlock(text)) {
    // No managed block existed at preflight, so there is no prior projection a
    // concurrent edit could silently overwrite — bootstrap then sync directly.
    try {
      runApplyBlock([canonical], '<!-- NOVA:TEAM-RULES:START -->\n<!-- NOVA:TEAM-RULES:END -->\n\n## Self-Learning Rules\n<!-- LEARN:ANCHOR -->\n');
    } catch (error) {
      fail(`gardener mutation succeeded, but could not prepare ${canonical} for projection: ${(error.stderr || error.message).trim()}`);
    }
    try {
      runApplyBlock(['--sync-team-rules', rulesFile, canonical]);
      runApplyBlock(['--check-team-rules', rulesFile, canonical]);
    } catch (error) {
      fail(`gardener mutation succeeded, but syncing active rules into ${canonical} failed: ${(error.stderr || error.message).trim()}`);
    }
    return null;
  }

  // A managed block existed at preflight. Hand apply-block the content captured
  // then so it compare-and-swaps: it re-reads the canonical file immediately
  // before writing and refuses if an external edit changed it in between
  // (fail closed, no last-write-wins). `--check` afterward stays read-only.
  try {
    if (expectedBefore != null) {
      runApplyBlock(['--sync-team-rules', rulesFile, canonical, '--expect-stdin'], expectedBefore);
    } else {
      runApplyBlock(['--sync-team-rules', rulesFile, canonical]);
    }
    runApplyBlock(['--check-team-rules', rulesFile, canonical]);
  } catch (error) {
    fail(`gardener mutation succeeded, but syncing active rules into ${canonical} failed: ${(error.stderr || error.message).trim()}`);
  }
  return null;
}

export function applyGardenerOperation(file, operation, input) {
  if (!Object.hasOwn(GARDENER_FIELDS, operation)) fail(`unknown gardener operation: ${operation}`);
  const novaDir = dirname(file);
  mkdirSync(novaDir, { recursive: true });
  assertSafeWriteTargets(file, novaDir);
  const release = acquireLock(novaDir);
  try {
    assertNoOrphanedBackup(file);
    if (!existsSync(file)) fail(`team rules file not found: ${file}`);
    const currentContent = readFileSync(file, 'utf8');
    const current = parseTeamRules(currentContent);
    const canonicalBefore = projectToCanonicalFile(file, novaDir, { preflight: true });
    const request = typeof input === 'string' ? parseGardenerInput(operation, input) : input;
    const byId = new Map(current.records.map((record) => [record.id, record]));
    let resultId;
    let records;

    if (operation === 'promote') {
      const record = byId.get(request.id);
      if (!record) fail(`rule not found: ${request.id}`);
      if (record.status !== 'proposed') fail(`${record.id}: only proposed rules can be promoted`);
      resultId = record.id;
      records = current.records.map((candidate) => (
        candidate.id === record.id ? { ...candidate, status: 'active' } : candidate
      ));
    } else if (operation === 'retire') {
      const record = byId.get(request.id);
      if (!record) fail(`rule not found: ${request.id}`);
      if (record.status === 'retired') fail(`${record.id}: rule is already retired`);
      validateSummary(request['retired-reason'], 'retired-reason', record.id);
      resultId = record.id;
      records = current.records.map((candidate) => (
        candidate.id === record.id
          ? { ...candidate, status: 'retired', retiredReason: request['retired-reason'] }
          : candidate
      ));
    } else {
      const sourceIds = request['derived-from'];
      if (!Array.isArray(sourceIds) || sourceIds.length === 0) fail(`${operation}: derived-from must be a non-empty JSON array`);
      const seen = new Set();
      for (const sourceId of sourceIds) {
        if (typeof sourceId !== 'string' || seen.has(sourceId)) fail(`${operation}: derived-from must contain unique rule ids`);
        seen.add(sourceId);
        const source = byId.get(sourceId);
        if (!source) fail(`${operation}: source rule not found: ${sourceId}`);
        if (source.status === 'retired') fail(`${sourceId}: retired rules cannot be ${operation} sources`);
      }
      resultId = createRuleId(current.records);
      const replacement = {
        id: resultId,
        status: 'active',
        scope: request.scope,
        sourceSummary: request['source-summary'],
        evidenceSummary: request['evidence-summary'],
        origin: operation,
        derivedFrom: sourceIds,
        body: request.rule,
      };
      validateRecord(replacement);
      records = current.records.map((record) => (
        seen.has(record.id)
          ? { ...record, status: 'retired', retiredReason: `Replaced by ${resultId}` }
          : record
      ));
      records.push(replacement);
    }

    const content = formatDocument(records);
    const next = parseTeamRules(content);
    validateTeamRulesTransition(current, next);
    ensureNovaGitignore(novaDir);
    const written = writeTeamRules(file, content, currentContent);
    if (!written.records.some((record) => record.id === resultId)) fail(`${resultId}: written document is missing the operation result`);
    try {
      projectToCanonicalFile(file, novaDir, { preflight: false, expectedBefore: canonicalBefore });
    } catch (error) {
      // rules.md was mutated above, but the projection failed closed (e.g. the
      // canonical file was edited concurrently between preflight and sync).
      // Restore rules.md to its exact pre-approval bytes so the operation
      // leaves BOTH files untouched, then surface the failure non-zero.
      try { atomicWriteFile(file, currentContent); } catch { /* original still recoverable from the error path above */ }
      throw error;
    }
    return { id: resultId, operation };
  } finally {
    release();
  }
}

export function ensureNovaGitignore(novaDir) {
  if (existsSync(novaDir) && !isRealDir(novaDir)) fail(`refusing to write: not a real directory: ${novaDir}`);
  mkdirSync(novaDir, { recursive: true });
  const file = join(novaDir, '.gitignore');
  if (!isFileOrMissing(file)) fail(`refusing to write through non-regular-file path: ${file}`);
  if (!existsSync(file) || readFileSync(file, 'utf8') !== NOVA_GITIGNORE) atomicWriteFile(file, NOVA_GITIGNORE);
}

async function main() {
  const command = process.argv[2];
  const file = process.argv[3] || '.nova/rules.md';
  if (!['propose', 'promote', 'merge', 'generalize', 'retire', 'validate', 'write'].includes(command)) {
    console.error('usage: team-rules.mjs <propose|promote|merge|generalize|retire|validate|write> [file]  (mutations/write read JSON/document from stdin)');
    process.exitCode = 2;
    return;
  }
  try {
    if (command === 'propose') {
      const record = proposeTeamRule(file, readFileSync(0, 'utf8'));
      console.log(`proposed: ${record.id}`);
    } else if (Object.hasOwn(GARDENER_FIELDS, command)) {
      const result = applyGardenerOperation(file, command, readFileSync(0, 'utf8'));
      console.log(`${command}: ${result.id}`);
    } else if (command === 'validate') {
      const document = parseTeamRules(readFileSync(file, 'utf8'));
      console.log(`valid: ${document.records.length} rule(s)`);
    } else {
      assertSafeWriteTargets(file, dirname(file));
      const document = writeTeamRules(file, readFileSync(0, 'utf8'));
      ensureNovaGitignore(dirname(file));
      console.log(`wrote: ${document.records.length} rule(s)`);
    }
  } catch (error) {
    console.error(`error: ${error.message}`);
    process.exitCode = 1;
  }
}

// Run main() only when invoked directly as a CLI. Node resolves an ESM
// entry point's real path (symlinks + platform aliases like macOS
// /var -> /private/var), so import.meta.url can differ byte-for-byte from an
// un-normalized process.argv[1] pointing at the same file — a plain string
// compare then silently skips main() and the CLI becomes an exit-0 no-op.
// Compare both sides after realpath so the aliased and canonical paths agree.
function isMainModule() {
  const argvPath = process.argv[1];
  if (!argvPath) return false;
  const modulePath = fileURLToPath(import.meta.url);
  try {
    return realpathSync(argvPath) === realpathSync(modulePath);
  } catch {
    return pathToFileURL(argvPath).href === import.meta.url;
  }
}
if (isMainModule()) await main();
