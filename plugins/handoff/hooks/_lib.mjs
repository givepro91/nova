// 공유 헬퍼 — handoff 플러그인 hook 들이 import.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { execSync } from 'node:child_process';

/** stdin(JSON) 파싱. 실패해도 {} 반환. */
export function readInput() {
  let raw = '';
  try { raw = readFileSync(0, 'utf8'); } catch { /* no stdin */ }
  try { return JSON.parse(raw || '{}'); } catch { return {}; }
}

/** 프로젝트 루트: CLAUDE_PROJECT_DIR > hook input.cwd > process.cwd(). */
export function projectDir(input) {
  return process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();
}

export function handoffDir(dir) { return join(dir, 'docs', 'handoff'); }

/** v1 단일 파일(legacy). v2 는 브랜치별 파일을 쓰지만 마이그레이션·폴백에 필요. */
export function legacyHandoffFile(dir) { return join(handoffDir(dir), 'HANDOFF.md'); }

/** v2: 브랜치별 핸드오프 파일 docs/handoff/<slug>.md */
export function branchHandoffFile(dir, slug) { return join(handoffDir(dir), `${slug}.md`); }

/** back-compat alias (= legacy 단일 파일). */
export function handoffFile(dir) { return legacyHandoffFile(dir); }

/** 프로젝트별 opt-in: docs/handoff/ 가 있어야 hook 활성. */
export function isOptedIn(dir) { return existsSync(handoffDir(dir)); }

/** git 명령 실행. 실패 시 null. */
export function git(dir, args) {
  try {
    return execSync(`git ${args}`, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { return null; }
}

export function isGitRepo(dir) { return git(dir, 'rev-parse --is-inside-work-tree') === 'true'; }

/** 현재 브랜치명. detached HEAD 는 detached-<shortsha>. 비-git 은 null. */
export function currentBranch(dir) {
  const b = git(dir, 'rev-parse --abbrev-ref HEAD');
  if (!b) return null;
  if (b === 'HEAD') {                                   // detached
    const sha = git(dir, 'rev-parse --short HEAD') || 'detached';
    return `detached-${sha}`;
  }
  return b;
}

/** 브랜치명 → 파일 안전 slug. feat/login → feat-login. */
export function branchSlug(branch) {
  return (branch || 'detached')
    .replace(/[^A-Za-z0-9._-]+/g, '-')                 // '/' 등 → '-'
    .replace(/-+/g, '-')
    .replace(/^[-.]+|[-.]+$/g, '')
    || 'detached';
}

export function nowISO() { return new Date().toISOString(); }

/** git status --porcelain → 변경 파일 경로 배열(rename 은 대상 경로). */
export function changedFiles(dir) {
  const out = git(dir, 'status --porcelain');
  if (out == null) return null;
  return out.split('\n')
    .filter((l) => l.length > 3)               // "XY path"
    .map((l) => l.slice(3))                     // 상태 2자 + 공백 제거
    .map((p) => p.split(' -> ').pop());         // rename: orig -> new
}

/** 아주 단순한 front-matter 파서. { data, body } 반환. front-matter 없으면 data={}. */
export function parseFrontMatter(content) {
  const m = /^---\n([\s\S]*?)\n---\n?/.exec(content);
  if (!m) return { data: {}, body: content };
  const data = {};
  for (const line of m[1].split('\n')) {
    const mm = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (mm) data[mm[1]] = mm[2].trim();
  }
  return { data, body: content.slice(m[0].length) };
}

/** front-matter 직렬화 (정해진 키 순서, 빈 값은 생략). */
export function buildFrontMatter(data) {
  const lines = ['---'];
  for (const k of ['branch', 'status', 'updated', 'issue', 'pr']) {
    const v = data[k];
    if (v !== undefined && v !== null && v !== '') lines.push(`${k}: ${v}`);
  }
  lines.push('---');
  return lines.join('\n') + '\n';
}

/**
 * 현재 브랜치의 핸드오프 경로를 해석한다.
 * - 비-git: legacy 단일 파일 모드.
 * - 브랜치 파일 있으면 그걸 사용.
 * - 없고 legacy 만 있으면: migrate=true 시 legacy → 브랜치 파일로 1회 복사(무손실, legacy 보존),
 *   migrate=false 시 legacy 를 읽기용으로 폴백(migrationPending).
 */
export function resolveHandoff(dir, { migrate = false } = {}) {
  const legacy = legacyHandoffFile(dir);
  const branch = currentBranch(dir);
  if (!branch) {                                        // 비-git → 단일 파일 모드
    return { file: legacy, branch: null, slug: null, isLegacy: true, exists: existsSync(legacy) };
  }
  const slug = branchSlug(branch);
  const bf = branchHandoffFile(dir, slug);
  if (existsSync(bf)) return { file: bf, branch, slug, isLegacy: false, exists: true };

  if (existsSync(legacy)) {
    if (migrate) {
      try {
        const raw = readFileSync(legacy, 'utf8');
        const { data, body } = parseFrontMatter(raw);
        const fm = buildFrontMatter({
          branch,
          status: data.status || 'active',
          updated: nowISO(),
          issue: data.issue,
          pr: data.pr,
        });
        writeFileSync(bf, fm + body.replace(/^\n+/, ''));
        return { file: bf, branch, slug, isLegacy: false, exists: true, migratedFrom: legacy };
      } catch { /* 실패 시 legacy 읽기로 폴백 */ }
    }
    return { file: legacy, branch, slug, isLegacy: true, exists: true, migrationPending: true };
  }
  return { file: bf, branch, slug, isLegacy: false, exists: false };
}

export function output(obj) { process.stdout.write(JSON.stringify(obj)); }
