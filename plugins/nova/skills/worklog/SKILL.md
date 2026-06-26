---
name: document
description: Synthesize the current session into a durable worklog — a cross-session narrative of what was accomplished, the decisions and WHY (over which alternatives), what was learned, and what's left open. NOT a git-log dump. Writes docs/worklog/<date>-<slug>.md. Optional --visual also renders a self-contained Nova-branded HTML.
when_to_use: When the user runs /document, at the end of a meaningful session, or when a durable "what we did and why" record is worth keeping beyond commit messages.
argument-hint: "[--visual]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git*), Bash(mkdir -p*), Bash(node*), Write
---

# /document — synthesize a session worklog

Record what this session actually accomplished as a **durable narrative**, so the *why* survives where git log can't carry it.

## Boundary (read first — don't duplicate)

- **handoff** = OPEN work, forward-looking, ephemeral (deleted when done).
- **git log / commit bodies** = the per-commit *what*.
- **worklog** = COMPLETED work, backward-looking, **durable narrative**: the cross-commit story — what was done, *why this over the alternatives*, what was learned, what's left.

Do NOT copy handoff content or list commits. If a fact already lives in a commit body, reference it — don't restate it. The worklog earns its place only by **synthesis**: the connective reasoning no single commit holds.

## Procedure

1. **Gather** (don't interpret yet): `git log --oneline` for this session's commits, `git diff --stat`, the branch, and — if it exists — `.nova/gate-verdict.json` (the honest "what was actually done vs claimed" from `/gate`).
2. **Honesty.** Record only what was actually done/verified. If `.nova/gate-verdict.json` exists, let it govern claims — never write "done" for anything the gate marked `unverified`/`false`. Mark unverified work "unverified".
3. **Write** `docs/worklog/<YYYY-MM-DD>-<slug>.md` (slug from the session theme) using the structure below. Synthesize — narrative over enumeration.
4. **`--visual`** (optional) — also render a self-contained HTML beside it:
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/render.mjs" docs/worklog/<file>.md .nova/gate-verdict.json > docs/worklog/<file>.html
   ```
   The renderer is **deterministic** (a markdown-subset → Nova-violet HTML transform — no LLM rewrite, no fabrication). Verdict badges appear only when the ledger exists.
5. Offer to commit (don't commit without approval).

## Structure (template)

```markdown
# Worklog — <한 줄 주제> · <YYYY-MM-DD>

## 한 일 (What we did)
The arc in a few sentences — not a commit list.

## 결정과 왜 (Decisions & why)
| 결정 | 버린 대안 | 왜 |
|------|----------|----|
| … | … | (the reasoning git log doesn't hold) |

## 배운 것 (Learned)
- Generalizable lessons (candidates for /learn).

## 세션 흐름 (How it moved)
- Ordered milestones, when the path itself is informative.

## 남긴 것 (Left open)
- Unfinished / blocked / parked + why (candidates for /handoff blocked).

## 결과·검증 (Outcome)
- What shipped + how it was verified. If /gate ran, cite its verdict in prose — don't hand-write badges; the HTML reads them from the ledger.
```

## Notes

- **Manual only** — no hooks, zero context tax. Run it when a session is worth remembering.
- `docs/worklog/` is excluded from other tools' "meaningful work" signal (nova-gate already ignores it).
- The `.md` is the source of truth; the HTML is for reading/sharing.
