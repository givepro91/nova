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
- `/worklog` — **Record** (NEW). Synthesized worklog + deterministic `--visual` HTML.

handoff + gate **share one `hooks/_lib.mjs`** (the monolith removed the cross-plugin barrier → no duplicated lib). All hooks opt-in per project (`docs/handoff/`, `.nova/gate.on`).

## Locked decisions (with why)

1. **Consolidate (A)** — one `nova` marketplace; cc-skills/cc-handoff deprecated with pointers. Personal repo, ~0 external users → consolidation cost ≈ 0; one brand beats three scattered repos.
2. **nova-gate = manual `/gate` by default + optional `type:"agent"` Stop hook for enforcement.** *Why the reversal from "thin full-auto Stop":* verified (official docs) that a Stop hook gets **no `transcript_path` / last message** (only cwd/session_id/stop_hook_active), so a shell hook can't detect a completion *claim*; and an always-on Stop block is the friction/adoption-death that killed old Nova. Manual `/gate` runs **in-session = full context** → a real claim→evidence audit by an **independent (separate-context) verifier** that reads `git diff` + files + test output; **Critical ⇒ ≥2 rounds**. The `type:"agent"` Stop hook (verified to spawn an independent subagent **without** main-model compliance — but **experimental**) is the opt-in never-miss upgrade.
3. **Absorb verbatim (byte-identical), bug-fixes tracked separately (Inc 1.5).** Because gate default is manual (no Stop), handoff is **not** modified for coordination → byte-identical absorption is honest. The code-review bugs below are a separate, individually-verifiable increment.
4. **Dual Stop hook = no fragile precedence.** Verified: matching hooks run **in parallel, non-deterministic order, any-block-wins, 8-block cap, `stop_hook_active` guard**. So a marker-file "precedence" scheme does NOT work. Default gate (manual) has no Stop → no conflict with handoff. Opt-in agent-Stop coexists with handoff's Stop (both may fire; their reasons merge — acceptable; loops bounded by `stop_hook_active` + cap).
5. **worklog**: `--visual` is a **deterministic render of the .md** (no LLM rewrite that drifts/optimizes); **verdict badges only from real gate evidence** (a JSON ledger), never fabricated. `/worklog` is manual (zero tax). Visual = self-contained HTML (inline CSS, no external assets), light theme + Nova violet. **v0.2.4 (사용자 피드백 "AI스럽고 판단 불가"):** two-reader frame — 요약(TL;DR, 남은 결정 포함)+한 일 = 쉬운 한국어 판단층, 결정 이후 = 엔지니어링 기록층; Voice 규칙은 지침이 아니라 **결정론적 프로즈 린트**(`lint-prose.mjs`: 420자+ 문단 / `→`×2+ 체인 / `x·y·z` 나열)로 게이트한다(worklog·handoff 공용). 렌더러: 결정 테이블→스택 카드, 흐름 ol→타임라인, TL;DR 하이라이트, TOC 칩, `*em*`.
6. **No company-internal dependencies** — never depend on `doc-publish`, `swk-wiki`, `secret-manage`, etc. Nova is a public, portable artifact; plugin users don't have those. All output self-contained.
7. **Market differentiation** = a **raw-transcript claim-evidence audit artifact**, not generic "verify before done" (the platform will absorb the generic version).
8. **Single plugin, not 4 (B over A) — v0.2.0.** Started modular (4 plugins) for context-tax avoidance, then verified (official docs) that a monolith has **LESS** always-on cost (1 plugin metadata vs 4) and that all nova hooks are opt-in markers anyway — so the split's justification didn't hold. Nova's loops are also one *designed system* (gate routes to learn/handoff/worklog; worklog reads gate's ledger). So: one `nova` plugin, five skills; `/plugin install nova@nova` = everything (no meta-plugin band-aid). Trade-off: no per-loop uninstall — acceptable (loops are a system; unused ones stay silent via opt-in hooks). Officially-backed alternative considered: `plugin.json` `dependencies` (a meta-plugin auto-installing the 4) — rejected as a band-aid that keeps the unjustified split + adds a 5th metadata entry.

9. **Evidence ledger (v0.2.5) — gate의 "정직"을 프롬프트 규율에서 기록 구조로.** A verifier that reads only the session's narration inherits its optimism, and compaction erases the raw output it needs. So `.nova/gate.on` also activates a PostToolUse:Bash hook (`evidence.mjs`) appending every command + output tail to `.nova/evidence.jsonl` (rotated at 512KB; kill switch `NOVA_GATE_EVIDENCE=0`). The hook drops `.nova/.gitignore` (`*` except `gate.on`) because output tails may contain anything → the ledger is machine-local by construction. Gate verdicts also append to `.nova/gate-history.jsonl`, which `/learn review` (rule gardener: merge/generalize/retire/promote) mines for recurring failure modes. Trade-off: ~40ms node spawn per Bash call in opted-in projects — accepted (opt-in only).
10. **Canonical team memory = tracked `.nova/rules.md`.** 정제된 팀 규칙은 한 Markdown 파일을 원본으로 삼는다. git diff에서 제안과 상태 변경을 함께 검토할 수 있고, 특정 호스팅이나 회사 내부 서비스 없이 이력과 이식성을 얻기 때문이다.
11. **`CLAUDE.md` = active-only projection.** 새 세션에 자동 적용할 내용은 `active` 규칙만 기존 managed block에 안정된 ID 순서로 투영한다. `proposed`와 `retired`를 컨텍스트에서 제외하면서, 같은 승인 커밋을 받은 팀원이 동일한 규칙 집합을 읽게 하기 때문이다.
12. **Human approval is the only activation gate.** `/learn`의 팀 공유 결과는 항상 `proposed`로 시작하며 자동 승인, commit, push를 하지 않는다. 개인 교정이나 에이전트의 추론이 검토 없이 팀 전체의 행동을 바꾸지 못하게 하기 때문이다.
13. **Rule conflicts fail closed.** malformed record, 중복 ID, 끊긴 provenance, 허용되지 않은 상태 전이, git conflict marker가 하나라도 있으면 projection 쓰기를 거부한다. 조용한 last-write-wins가 팀 기억을 덮어쓰거나 기존 `CLAUDE.md`를 손상시키지 않게 하기 때문이다.
14. **Raw evidence stays machine-local.** `.nova/evidence.jsonl`, gate ledger, transcript, 명령 출력 원문은 팀 규칙의 입력 근거가 될 수 있지만 git 추적 아티팩트로 복사하지 않는다. 팀에는 사람이 검토할 수 있게 새로 쓴 출처 요약과 근거 요약만 남겨 비밀과 로컬 실행 정보의 유출 경로를 줄이기 때문이다.

## Team rules storage contract — approval required

### 판단층

**TL;DR.** 위 다섯 결정은 잠겼지만, 아래 레코드 스키마와 `.nova/.gitignore` allowlist는 아직 구현 승인을 받지 않았다. 승인 전에는 `.nova/rules.md`를 만들거나 projection, `/learn`, gardener, hook, script를 변경하지 않는다.

**한 일.** 팀 규칙의 원본과 새 세션용 projection을 분리하고, 사람 승인과 fail-closed 경계를 명시했다. 원본 evidence가 추적 파일로 흘러가지 않도록 저장 경계도 고정했다.

**남은 결정.** 아래 v1 스키마와 allowlist를 그대로 승인할지 사용자가 결정해야 한다. 수정 승인이면 바뀐 항목을 다시 문서화한 뒤 구현하고, 보류면 이 단계에서 멈춘다.

### 엔지니어링 기록층

#### 제안: `.nova/rules.md` v1

파일은 `schema: nova-team-rules/v1` frontmatter와 규칙 섹션으로 구성한다. 각 규칙은 아래 형식을 따르며 필드명과 순서를 고정한다.

```md
---
schema: nova-team-rules/v1
---

# Nova team rules

## `rule-20260713-a1b2c3d4`

- status: `proposed`
- scope: `["**"]`
- source-summary: `사용자 교정에서 확인한 문제를 원문 없이 요약한다.`
- evidence-summary: `반복을 막아야 하는 근거를 명령 출력 없이 요약한다.`
- origin: `propose`
- derived-from: `[]`

### Rule

변경을 완료했다고 말하기 전에 관련 검증 명령의 성공을 확인한다.
```

- ID는 생성 시 한 번만 부여하는 `rule-YYYYMMDD-<8 lowercase hex>` 형식이다. 본문을 고쳐도 ID는 바꾸지 않으며, 중복이면 쓰기를 거부한다.
- `status`는 `proposed`, `active`, `retired`만 허용한다. `retired`에는 `retired-reason` 한 줄이 필수이고, 다른 상태에는 이 필드를 두지 않는다.
- `scope`는 repo-relative glob의 JSON 배열이다. 저장소 전체는 `["**"]`로 표현하며 빈 배열, 절대 경로, 저장소 밖을 가리키는 경로는 거부한다.
- `source-summary`와 `evidence-summary`는 각각 새로 작성한 한 줄 요약이다. evidence나 transcript 원문, 명령 출력, 코드 블록, 비밀 문자열을 넣지 않으며 정제 검사를 통과하지 못하면 쓰지 않는다.
- `origin`은 `propose`, `merge`, `generalize`만 허용한다. `derived-from`은 원본 규칙 ID의 JSON 배열이며, `merge`와 `generalize`에서는 비어 있을 수 없다.
- `Rule` 본문은 projection 가능한 한 줄의 실행 규칙이다. 빈 본문과 unresolved conflict marker가 있는 문서는 전체 쓰기를 거부한다.

`promote`는 같은 ID의 상태만 `proposed`에서 `active`로 바꾼다. `merge`와 `generalize`는 사람 승인 뒤 새 ID의 active 규칙을 만들고 모든 원본 ID를 `derived-from`에 보존한다. 원본 레코드는 대체 규칙 ID를 폐기 사유에 남긴 채 retired로 전환한다. 참조된 원본 레코드가 없거나 provenance chain이 순환하면 아무 파일도 쓰지 않는다.

`retire`는 상태를 retired로 바꾸고 사유를 보존한다. 레코드를 삭제하지 않으므로 출처 요약, 근거 요약, 변환 계보는 git history에만 의존하지 않고 현재 아티팩트에서도 검토할 수 있다.

#### 제안: active-only projection

기존 `CLAUDE.md` managed block 안에 아래 전용 구간을 정확히 한 번 유지한다. active 레코드를 ID의 bytewise 오름차순으로 정렬하고 각 scope와 본문을 한 줄로 렌더링한다.

```md
<!-- NOVA:TEAM-RULES:START -->
- [scope: **] 변경을 완료했다고 말하기 전에 관련 검증 명령의 성공을 확인한다. <!-- nova-rule:rule-20260713-a1b2c3d4 -->
<!-- NOVA:TEAM-RULES:END -->
```

proposed와 retired 레코드는 이 구간에 나타나지 않는다. 입력 문서 검사가 끝나기 전에는 `CLAUDE.md`를 열어 쓰지 않으며, 같은 입력으로 다시 실행했을 때 byte diff가 없어야 한다.

#### 제안: `.nova/.gitignore` allowlist

현재 machine-local 기본값을 유지하면서 팀 아티팩트 하나만 추가로 추적한다.

```gitignore
*
!.gitignore
!gate.on
!rules.md
```

이 allowlist는 `.nova/rules.md`만 새로 공유한다. `evidence.jsonl`, `gate-history.jsonl`, `gate-verdict.json`과 그 밖의 로컬 산출물은 계속 무시한다. hook이 기존 `.gitignore`를 갱신해야 하는 경우에도 이 네 줄을 결정론적으로 보존해야 한다.

#### 승인 게이트

구현 시작 조건은 사용자의 명시적 승인이다. 승인 대상은 `.nova/rules.md` v1 필드와 전이 의미론, projection 형식, `.nova/.gitignore` 네 줄 allowlist다. 승인이 없으면 이 문서 변경만 남기고 구현 단계로 넘어가지 않는다.

10. **`/web-doc` capability — its own skill, not folded into `/design-direction` or `/worklog` (v0.2.x).** A document deserves a style pitched at *what it is*; one look for every doc (or a claude.ai-style landing hero) is the tell that no choice was made. The two adjacent skills don't cover it: `/design-direction` *decides* a subjective look by showing mockups, `/worklog` renders a *session record* in one deterministic Nova-branded template. `/web-doc` is the missing **build** capability — character → style (notion/report/editorial), one self-contained file (inline CSS, system fonts, no CDN, light+dark, a11y — same self-contained rule as #6), routing to `/design-direction` when the look is genuinely subjective. **Model-invocable** (unlike `scout`/`design-direction`, which are explicit-only) so "make this a web page / 페이지로 만들어줘" triggers it — deliberate, because a well-triggered skill replaces an ad-hoc "always use tool X" global rule while keeping the design tool **pluggable** ("frontend-design or better", never hardcoded). Trade-off: one more capability surface on the public plugin — accepted (build sibling of `design-direction`; self-contained per #6, zero deps).

11. **`/explain-diff` capability — the human-understanding counterpart to `/gate` (v0.2.9).** *Source:* Geoffrey Litt's "Understanding is the new bottleneck" (understand to **participate**, not just verify; the quiz as a **speed regulator**). The insight Nova adopts: gate audits the *agent's* claims (is the work real?), but nothing checked the *human's* comprehension — Nova's human+agent thesis under-served the human axis. `/explain-diff` fills it: a fixed pedagogical arc (**background → intuition(toy data + HTML diagrams) → literate code walkthrough → comprehension quiz**) rendered as one self-contained HTML (inline CSS, system fonts, no CDN, light+dark, a11y — same rule as #6). **Not folded into `/web-doc`** (which *chooses* a style per document): here the character is fixed, so it ships one skeleton (`styles/explain-diff.css` = quality floor + reference JS, mirroring web-doc's `styles/*.css`). **Model-invocable** ("이 PR 설명해줘 / explain this diff") like web-doc. Deliberate choices vs the source: **Notion variant dropped** (portability #6, no external deps), **quiz options shuffled at render** (fixes the gist's own "answer guessable by length/position" flaw), and the artifact is written **outside the repo** (a reading file, not a committed doc). The quiz is opt-in/manual — *pass it before you ship* is a norm, not an enforced Stop (same friction-avoidance as gate's default). Trade-off: one more capability surface — accepted (self-contained per #6, zero deps).

12. **`/design-system` capability + `/claude-md` block gains 3 universal rules (v0.2.10).** *Source:* a real project's CLAUDE.md rules (Design System / Comments-why / Lint-max-lines / Naming / Worktree-safety). Two moves: **(a)** the 3 *universal* rules entered `/claude-md`'s managed block — `Comment the why, not the what` + `Name for content, not role` (Working Discipline) and `Stay in the worktree you were given` (Parallel Git: don't follow a subagent's main-repo absolute path back — on Nova's multi-agent thesis). The 2 *project-specific* ones (Design System, lint-config) were **rejected from the block** — they're exactly what `/learn` accumulates per project; the block stays lean (#8, SKILL Notes now names the boundary). **(b)** The rejected "Design System" rule presupposes a STYLEGUIDE + tokens exist — so `/design-system` is the **build capability that creates that structure**, making such a project-specific rule meaningful. It owns *structure* (roles, scales, resolution order, canonical tokens, a binding rule wired via `/claude-md`'s free area — **not** the managed block) and **delegates the subjective look** to `/design-direction`/`frontend-design` (pluggable per #10). Deliberate scoping vs the source's React+shadcn example: **stack-adaptive & installs nothing** (portability #6 — rejected the "wire into codebase / scaffold components" option), framework-neutral CSS-custom-property tokens by default, ships two editable skeletons (`assets/STYLEGUIDE.template.md`, `assets/tokens.css`, mirroring web-doc's `styles/*`). **Model-invocable** ("디자인 시스템 잡아줘") like web-doc, but **confirm before writing** (blast radius = new files + a governing rule) and **idempotent** (re-run audits/extends, never clobbers). Trade-off: one more capability surface — accepted (self-contained per #6, zero deps; closes the loop with #8's lean-block boundary).

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
