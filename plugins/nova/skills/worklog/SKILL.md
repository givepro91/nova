---
name: worklog
description: Synthesize the current session into a durable worklog — a cross-session narrative of what was accomplished, the decisions and WHY (over which alternatives), what was learned, and what's left open. NOT a git-log dump. Writes docs/worklog/<date>-<slug>.md. Optional --visual also renders a self-contained Nova-branded HTML.
when_to_use: When the user runs /worklog, at the end of a meaningful session, or when a durable "what we did and why" record is worth keeping beyond commit messages.
argument-hint: "[--visual]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git*), Bash(mkdir -p*), Bash(node*), Write
---

# /worklog — synthesize a session worklog

Record what this session actually accomplished as a **durable narrative**, so the *why* survives where git log can't carry it.

## Boundary (read first — don't duplicate)

- **handoff** = OPEN work, forward-looking, ephemeral (deleted when done).
- **git log / commit bodies** = the per-commit *what*.
- **worklog** = COMPLETED work, backward-looking, **durable narrative**: the cross-commit story — what was done, *why this over the alternatives*, what was learned, what's left.

Do NOT copy handoff content or list commits. If a fact already lives in a commit body, reference it — don't restate it. The worklog earns its place only by **synthesis**: the connective reasoning no single commit holds.

## Procedure

1. **Gather** (don't interpret yet): `git log --oneline` for this session's commits, `git diff --stat`, the branch, and — if it exists — `.nova/gate-verdict.json` (the honest "what was actually done vs claimed" from `/gate`).
2. **Honesty.** Record only what was actually done/verified. If `.nova/gate-verdict.json` exists, let it govern claims — never write "done" for anything the gate marked `unverified`/`false`. Mark unverified work "unverified".
3. **Write** `docs/worklog/<YYYY-MM-DD>-<slug>.md` (slug from the session theme) using the structure below. Synthesize — narrative over enumeration — and follow **Voice** (below): the reader wasn't in the session.
4. **Lint the prose** (always, even without `--visual`):
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/render.mjs" --lint docs/worklog/<file>.md
   ```
   It deterministically flags the session shorthand a reader actually feels — mega-paragraphs, `→` chains, `·` runs. Revise and re-run until `LINT: clean`; don't rationalize warnings away.
5. **`--visual`** (optional) — also render a self-contained HTML beside it:
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/render.mjs" docs/worklog/<file>.md .nova/gate-verdict.json > docs/worklog/<file>.html
   ```
   The renderer is **deterministic** (a markdown-subset → Nova-violet HTML transform — no LLM rewrite, no fabrication). Verdict badges appear only when the ledger exists. The 요약 section renders as a highlighted TL;DR card, the 결정 table as stacked decision cards, and a numbered list in 세션 흐름 as a timeline.
6. Offer to commit (don't commit without approval).

## Structure (template)

```markdown
# Worklog — <한 줄 주제> · <YYYY-MM-DD>

## 요약 (TL;DR)
- **문제**: why this session happened — plain Korean, zero jargon. A non-engineer must understand this line.
- **한 일**: what was done, one sentence.
- **지금**: what changed for the project + how it was verified (or "unverified").
- **남은 결정**: what the reader must decide or accept next ("없음" if nothing).

## 한 일 (What we did)
The story in 2–4 short paragraphs — not a commit list, and never one mega-paragraph.

## 결정과 왜 (Decisions & why)
| 결정 | 버린 대안 | 왜 |
|------|----------|----|
| … | … | (the reasoning git log doesn't hold — full sentences, not shorthand) |

## 배운 것 (Learned)
- Generalizable lessons (candidates for /learn).

## 세션 흐름 (How it moved)
1. Ordered milestones as a numbered list (renders as a timeline), when the path itself is informative.

## 남긴 것 (Left open)
- Unfinished / blocked / parked + why (candidates for /handoff blocked).

## 결과·검증 (Outcome)
- What shipped + how it was verified. If /gate ran, cite its verdict in prose — don't hand-write badges; the HTML reads them from the ledger.
```

## Voice — write for a reader who wasn't there

A worklog serves **two readers in one document**, in this order:

1. **판단하는 독자** (30 seconds) — reads 요약 + 한 일. Plain Korean; must be able to judge *what happened, whether it worked, and what they're being asked to decide* without opening the code.
2. **엔지니어 독자** (future-you / a teammate, 5 minutes) — reads 결정과 왜 onward. Identifiers and evidence welcome — but still full sentences, never session shorthand.

Session shorthand that only the session's engineer can parse defeats the whole point of a durable record. Rules (the mechanical ones are enforced by `--lint`):

- **요약 is jargon-free.** No code identifiers, no internal codenames, no tool names. If a product manager can't follow the three bullets, rewrite them.
- **One idea per sentence; 2–4 sentences per paragraph.** Never compress the whole session into one paragraph. A paragraph over ~4 lines gets split.
- **No arrow chains or `·`-joined runs in prose.** `A → B → C 발견 → scope 축소` and `pytest·ruff·mypy clean` are session shorthand, not writing. Unroll into sentences or a bulleted list. (`→` is fine inside a table cell for a version bump like `v63→64`.)
- **Gloss jargon on first use.** Every internal name, table, flag, or term of art gets a short plain-Korean gloss in parentheses the first time it appears: `savings_suppressions`(절감 계산에서 걸러낸 항목을 기록하는 테이블).
- **Numbers carry their meaning.** Not "1903→1932" but "테스트 29개를 새로 더해 전체 1932개가 통과한다".
- **Bold is for the one load-bearing fact per section** — 1–2 uses, not a highlight pen.
- **Parentheses are a smell.** More than one per sentence means the sentence should be split.
- Korean prose; code identifiers stay in backticks. Don't force-translate error messages or tool names.

## Notes

- **Manual only** — no hooks, zero context tax. Run it when a session is worth remembering.
- `docs/worklog/` is excluded from other tools' "meaningful work" signal (nova-gate already ignores it).
- The `.md` is the source of truth; the HTML is for reading/sharing.
