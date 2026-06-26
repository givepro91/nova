# Nova — dev instructions

Nova is a **compounding-agent nervous system** for Claude Code, shipped as a modular plugin marketplace. Each plugin is one *loop* over a coding session (rules · learning · continuity · verification · record). It replaces the standalone `cc-skills` + `cc-handoff` repos (consolidated here; those are deprecated and point here).

> User-facing language: respond to the user in **Korean**.

## Design thesis

The session is raw material. Honest, git-native, low-context-tax loops let the agent compound across sessions instead of resetting. Nova is a **keeper** (state/rules/records around the agent), not a **doer** (orchestration) — orchestration is owned by the platform + omc; Nova lives in the layer they don't.

## The 5 loops → 4 plugins

- `claude-md` — **Rules** (`/claude-md`, idempotent managed block) + **Learning** (`/learn`, correction→rule). Absorbed from cc-skills.
- `handoff` — **Continuity**. Per-branch ephemeral handoff + 3 hooks (Stop/PreCompact/SessionStart). Absorbed from cc-handoff.
- `nova-gate` — **Verification** (NEW). See decisions below.
- `worklog` — **Record** (NEW). See decisions below.

Plugins are **independently installable** — no cross-plugin imports. Reason: context tax (a plugin's metadata is always loaded). Don't monolith.

## Locked decisions (with why)

1. **Consolidate (A)** — one `nova` marketplace; cc-skills/cc-handoff deprecated with pointers. Personal repo, ~0 external users → consolidation cost ≈ 0; one brand beats three scattered repos.
2. **nova-gate = manual `/gate` by default + optional `type:"agent"` Stop hook for enforcement.** *Why the reversal from "thin full-auto Stop":* verified (official docs) that a Stop hook gets **no `transcript_path` / last message** (only cwd/session_id/stop_hook_active), so a shell hook can't detect a completion *claim*; and an always-on Stop block is the friction/adoption-death that killed old Nova. Manual `/gate` runs **in-session = full context** → a real claim→evidence audit by an **independent (separate-context) verifier** that reads `git diff` + files + test output; **Critical ⇒ ≥2 rounds**. The `type:"agent"` Stop hook (verified to spawn an independent subagent **without** main-model compliance — but **experimental**) is the opt-in never-miss upgrade.
3. **Absorb verbatim (byte-identical), bug-fixes tracked separately (Inc 1.5).** Because gate default is manual (no Stop), handoff is **not** modified for coordination → byte-identical absorption is honest. The code-review bugs below are a separate, individually-verifiable increment.
4. **Dual Stop hook = no fragile precedence.** Verified: matching hooks run **in parallel, non-deterministic order, any-block-wins, 8-block cap, `stop_hook_active` guard**. So a marker-file "precedence" scheme does NOT work. Default gate (manual) has no Stop → no conflict with handoff. Opt-in agent-Stop coexists with handoff's Stop (both may fire; their reasons merge — acceptable; loops bounded by `stop_hook_active` + cap).
5. **worklog**: `--visual` is a **deterministic render of the .md** (no LLM rewrite that drifts/optimizes); **verdict badges only from real gate evidence** (a JSON ledger), never fabricated. `/document` is manual (zero tax). Visual = self-contained HTML (inline CSS, no external assets), light theme + Nova violet.
6. **No company-internal dependencies** — never depend on `doc-publish`, `swk-wiki`, `secret-manage`, etc. Nova is a public, portable artifact; plugin users don't have those. All output self-contained.
7. **Market differentiation** = a **raw-transcript claim-evidence audit artifact**, not generic "verify before done" (the platform will absorb the generic version).

## Brand

Violet: `#7c3aed` (primary) · `#a855f7` (light) · `#6d28d9` (deep). Light theme, system font stack (Korean: Apple SD Gothic / Pretendard). No webfont CDN (CSP).

## Inc 1.5 — absorbed-code bug fixes (from /code-review)

Fixes live in each plugin's own files (no cross-plugin shared lib — independent-install rule). nova-gate will copy the hardened patterns. **Verified by `tests/inc15-verify.sh` (ALL PASS).**

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
node --check plugins/**/*.mjs                 # syntax
# install locally to test:  /plugin marketplace add /Users/jay/develop/givepro91/nova
```

## Git

Commit identity = givepro91 (this dir's .gitconfig). Don't commit/push without explicit approval. Convention: `feat:`/`fix:`/`update:`/`docs:`/`refactor:`/`chore:`.
