# Nova — dev instructions

Nova is a **compounding-agent nervous system** for Claude Code — for both the human and the agent — shipped as a single plugin (`nova`) in a marketplace. Five *loops* over a coding session (rules · learning · continuity · verification · record) as five loop skills + shared hooks. It replaces the standalone `cc-skills` + `cc-handoff` repos (consolidated here; deprecated, pointing here).

> User-facing language: respond to the user in **Korean**.

## Design thesis

The session is raw material. Honest, git-native, low-context-tax loops let the agent compound across sessions instead of resetting. Nova is a **public, portable Claude Code plugin — anyone can install it** — and it stands on its own (no dependency on, or deference to, any orchestration layer such as omc or the platform). Its mission is to **compound a coding session's value across sessions, for both the human and the agent**: the agent stops resetting (rules · learning · continuity), and the human gets honesty and a record they can judge (verification · record). The mission is **not limited to "keeping" state** — capabilities that help build (e.g. discovering & designing where agents safely fit in a project) are equally Nova.

## The 5 loops → 1 plugin (`nova`)

One plugin, five session **loops** + shared hooks (`plugins/nova/{skills/*, scripts/*, hooks/*}`). Capabilities are **not** loops — `skills/*` now also holds capability skills (`scout`, `design-direction`) that help you build but don't run per-session; see README's Capabilities table.
- `/claude-md` — **Rules** (idempotent managed block) + `/learn` — **Learning** (correction→rule). Absorbed from cc-skills.
- `/handoff` — **Continuity**. Per-branch ephemeral handoff + hooks (SessionStart/PreCompact/Stop). Absorbed from cc-handoff.
- `/gate` — **Verification** (NEW). Independent claim→evidence verifier + opt-in Stop nudge.
- `/document` — **Record** (NEW). Synthesized worklog + deterministic `--visual` HTML.

handoff + gate **share one `hooks/_lib.mjs`** (the monolith removed the cross-plugin barrier → no duplicated lib). All hooks opt-in per project (`docs/handoff/`, `.nova/gate.on`).

## Locked decisions (with why)

1. **Consolidate (A)** — one `nova` marketplace; cc-skills/cc-handoff deprecated with pointers. Personal repo, ~0 external users → consolidation cost ≈ 0; one brand beats three scattered repos.
2. **nova-gate = manual `/gate` by default + optional `type:"agent"` Stop hook for enforcement.** *Why the reversal from "thin full-auto Stop":* verified (official docs) that a Stop hook gets **no `transcript_path` / last message** (only cwd/session_id/stop_hook_active), so a shell hook can't detect a completion *claim*; and an always-on Stop block is the friction/adoption-death that killed old Nova. Manual `/gate` runs **in-session = full context** → a real claim→evidence audit by an **independent (separate-context) verifier** that reads `git diff` + files + test output; **Critical ⇒ ≥2 rounds**. The `type:"agent"` Stop hook (verified to spawn an independent subagent **without** main-model compliance — but **experimental**) is the opt-in never-miss upgrade.
3. **Absorb verbatim (byte-identical), bug-fixes tracked separately (Inc 1.5).** Because gate default is manual (no Stop), handoff is **not** modified for coordination → byte-identical absorption is honest. The code-review bugs below are a separate, individually-verifiable increment.
4. **Dual Stop hook = no fragile precedence.** Verified: matching hooks run **in parallel, non-deterministic order, any-block-wins, 8-block cap, `stop_hook_active` guard**. So a marker-file "precedence" scheme does NOT work. Default gate (manual) has no Stop → no conflict with handoff. Opt-in agent-Stop coexists with handoff's Stop (both may fire; their reasons merge — acceptable; loops bounded by `stop_hook_active` + cap).
5. **worklog**: `--visual` is a **deterministic render of the .md** (no LLM rewrite that drifts/optimizes); **verdict badges only from real gate evidence** (a JSON ledger), never fabricated. `/document` is manual (zero tax). Visual = self-contained HTML (inline CSS, no external assets), light theme + Nova violet. **v0.2.4 (사용자 피드백 "AI스럽고 판단 불가"):** two-reader frame — 요약(TL;DR, 남은 결정 포함)+한 일 = 쉬운 한국어 판단층, 결정 이후 = 엔지니어링 기록층; Voice 규칙은 지침이 아니라 **결정론적 프로즈 린트**(`lint-prose.mjs`: 420자+ 문단 / `→`×2+ 체인 / `x·y·z` 나열)로 게이트한다(worklog·handoff 공용). 렌더러: 결정 테이블→스택 카드, 흐름 ol→타임라인, TL;DR 하이라이트, TOC 칩, `*em*`.
6. **No company-internal dependencies** — never depend on `doc-publish`, `swk-wiki`, `secret-manage`, etc. Nova is a public, portable artifact; plugin users don't have those. All output self-contained.
7. **Market differentiation** = a **raw-transcript claim-evidence audit artifact**, not generic "verify before done" (the platform will absorb the generic version).
8. **Single plugin, not 4 (B over A) — v0.2.0.** Started modular (4 plugins) for context-tax avoidance, then verified (official docs) that a monolith has **LESS** always-on cost (1 plugin metadata vs 4) and that all nova hooks are opt-in markers anyway — so the split's justification didn't hold. Nova's loops are also one *designed system* (gate routes to learn/handoff/worklog; worklog reads gate's ledger). So: one `nova` plugin, five skills; `/plugin install nova@nova` = everything (no meta-plugin band-aid). Trade-off: no per-loop uninstall — acceptable (loops are a system; unused ones stay silent via opt-in hooks). Officially-backed alternative considered: `plugin.json` `dependencies` (a meta-plugin auto-installing the 4) — rejected as a band-aid that keeps the unjustified split + adds a 5th metadata entry.

9. **Evidence ledger (v0.2.5) — gate의 "정직"을 프롬프트 규율에서 기록 구조로.** A verifier that reads only the session's narration inherits its optimism, and compaction erases the raw output it needs. So `.nova/gate.on` also activates a PostToolUse:Bash hook (`evidence.mjs`) appending every command + output tail to `.nova/evidence.jsonl` (rotated at 512KB; kill switch `NOVA_GATE_EVIDENCE=0`). The hook drops `.nova/.gitignore` (`*` except `gate.on`) because output tails may contain anything → the ledger is machine-local by construction. Gate verdicts also append to `.nova/gate-history.jsonl`, which `/learn review` (rule gardener: merge/generalize/retire/promote) mines for recurring failure modes. Trade-off: ~40ms node spawn per Bash call in opted-in projects — accepted (opt-in only).

## Brand

Violet: `#7c3aed` (primary) · `#a855f7` (light) · `#6d28d9` (deep). Light theme, system font stack (Korean: Apple SD Gothic / Pretendard). No webfont CDN (CSP).

## Inc 1.5 — absorbed-code bug fixes (from /code-review)

Fixes live in `plugins/nova/{hooks,scripts}`; since v0.2.0 (monolith) handoff + gate share one hardened `hooks/_lib.mjs`. **Verified by `tests/inc15-verify.sh` (ALL PASS).**

**Fixed ✅**
- `handoff/hooks/_lib.mjs` `changedFiles` — non-ASCII (Korean) paths were octal-quoted by `core.quotepath` → now `-c core.quotepath=false`. *(verified: `한글파일.md` returned literally)*
- `_lib.mjs` `parseFrontMatter` — `^---\n` failed / kept `\r` on CRLF → now `\r?\n`-tolerant. *(verified: CRLF `status: closed` parsed)*
- `handoff/hooks/stop.mjs` threshold — `parseInt(malformed)=NaN` → `Number.isFinite` fallback to 3 (no more "block every change").
- `claude-md/scripts/apply-block.mjs` — refuses to write (exit 1, **no data loss**) when the new body lacks `LEARN:ANCHOR` but learned rules exist. *(verified)*
- `claude-md/scripts/append-rule.mjs` — whole-line END match (consistent w/ apply-block); errors if END missing instead of dedup-against-whole-file. *(verified)*

**Deferred (low-likelihood / invasive — documented, not fixed)**
- `_lib.mjs` `branchSlug` — `feat/login` vs `feat-login` collide to one handoff file. Fix changes the filename scheme (touches docs + hooks) → defer.
- `session-start.mjs` `slice(4000)` may split a surrogate pair (cosmetic); `stop.mjs` mtime staleness fooled by checkout/formatter (inherent heuristic).

**worklog a11y — apply when building the Inc 3 `--visual` template:** `--ink-3 #a29fb0` = 2.59:1 (AA fail, widely-used token); standalone HTML needs `<html lang="ko">` + `<meta charset>`; verdict pills sub-AA + color-only (and badges must be evidence-gated regardless).

## Verification trail

This design passed: codex gpt-5.5 ×2 (general + adversarial), claude-code-guide official-docs verification, and built-in `/code-review`. (`/ccg` external advisors — omc/gemini — unavailable on this machine; Gemini lens not obtained.)

## Build & test

```sh
bash tests/inc15-verify.sh && bash tests/gate-verify.sh && bash tests/worklog-verify.sh   # all green
# install locally:  /plugin marketplace add /Users/jay/develop/givepro91/nova  →  /plugin install nova@nova
```

## Git

Commit identity = givepro91 (this dir's .gitconfig). Don't commit/push without explicit approval. Convention: `feat:`/`fix:`/`update:`/`docs:`/`refactor:`/`chore:`.
