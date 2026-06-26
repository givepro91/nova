---
name: handoff
description: Record the current session's decisions, reasoning, open work, and next steps into the current branch's handoff (docs/handoff/<branch>.md) so the next session — or another machine — can continue. Use when wrapping up a session, pausing work, or before context is compacted/cleared.
when_to_use: When the user runs /handoff, when finishing a session, when work will continue on another machine, or when context is about to be compacted/reset.
argument-hint: "[quick|blocked|status|resolve|prune]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Bash(git status*), Bash(git log*), Bash(git diff --stat*), Bash(git rev-parse*), Bash(git branch*), Bash(git remote*), Bash(git fetch*), Bash(git rm*), Bash(mkdir -p*), Bash(rm -f docs/handoff/*)
---

# /handoff — write a session handoff (branch-aware, ephemeral)

Record the current session's state into **`docs/handoff/<branch>.md`** (one handoff per branch) so the next session — even on another machine — continues without losing context.

## Mental model (read once)

A handoff is an **ephemeral continuity note for OPEN work** — not a record of what was done. The durable record lives in **git log / commit bodies / roadmap / self-learning rules**. So:

- **Open work → a handoff file exists.** When the work is done, the handoff is **deleted** (its purpose is spent; history keeps it). A missing handoff means "no open continuity note here".
- **One file per branch** (`docs/handoff/<branch>.md`, slug-sanitized, e.g. `feat/login` → `feat-login.md`). Each worktree only writes its own file → **no disk or merge conflict**.
- **The overview is derived** — `/handoff status` scans the files; there is **no committed index** (that would conflict on merge).

## Status

Front-matter `status` has exactly two live values:

| status | SessionStart | meaning |
|--------|--------------|---------|
| `active` (default) | injected | open work in progress |
| `blocked` | injected **prominently** | open but stuck; needs attention/escalation |

There is **no `closed` on disk** — terminal = the file is deleted (`/handoff resolve` / `/handoff prune`).

## Principles

- **Data lives in the repo (git).** The branch handoff is committed and pushed, so it travels to other machines. Auto memory and transcripts live only on this machine — do not rely on them.
- **Detailed *why* goes in commit messages; open work and next steps go in the handoff.** Don't duplicate — "Decisions" should point at `git log` hashes.
- **Honesty.** No guessing. Record only what was actually done/verified; mark unverified items "unverified".

## Arguments

- *(none)* / `quick` → write/update this branch's handoff (`quick` = only "Restore in 30s" + "Next steps").
- `blocked` → write/update and set `status: blocked`.
- `status` → render the board (read-only) + list prunable orphans.
- `resolve` → the work is done: **delete this branch's handoff file** (terminal).
- `prune` → clean up orphaned handoffs whose branches are gone/merged (default `--dry-run`; `--apply` to delete).

## Procedure — write (default / `quick` / `blocked`)

1. **Root & branch**: `git rev-parse --show-toplevel`; `git rev-parse --abbrev-ref HEAD`. Slug = replace `/` and unsafe chars with `-`.
2. **Ensure opt-in**: if `docs/handoff/` is missing, `mkdir -p docs/handoff`.
3. **Migrate legacy if needed**: if `docs/handoff/<slug>.md` is absent but a legacy `docs/handoff/HANDOFF.md` exists, base the new file on it (the SessionStart hook usually does this automatically).
4. **Gather facts**: `git status --porcelain`, `git diff --stat`, `git log --oneline -5`; capture the linked issue/PR when known.
5. **Write `docs/handoff/<slug>.md`** with the template below. Keep the YAML front-matter at the top, set `status` (`active`, or `blocked` for the `blocked` arg), refresh `updated`.
6. Offer to commit (don't commit without approval).

## Template

```markdown
---
branch: <branch name>
status: active            # active | blocked
updated: <ISO-8601 timestamp>
issue: <number>           # optional
pr: <number>              # optional
---

# Handoff — <task> · <YYYY-MM-DD> · <machine>

## Restore in 30s
What you were doing / where you got to / what you just finished.

## Next steps
- [ ] Concrete next action — down to files & commands
- [ ] Blocker / sticking point + what was already tried
- [ ] Parked item + why

## Touch points
- `path/to/file:line` — what / why
- verify: `command` → expected result

## Decisions
- <key decision in one line> → detailed why in commit `<hash>`
```

## Procedure — `status` (read-only board)

1. `Glob` `docs/handoff/*.md` (exclude legacy `HANDOFF.md` if a branch file already covers it).
2. Read each file's front-matter; render, marking the current branch, sorted by `updated`:

```
🟢 feat-login   (current)  2h ago   #42
⛔ fix-cache    BLOCKED     1d ago   #51
```

(🟢 active · ⛔ blocked). This view is **derived** — never write an index file.
3. **Orphan check** (prunable): `git fetch --prune` (if a remote exists), then for each handoff whose `<slug>` maps to no existing local/remote branch, or whose branch is already merged into the default branch (`git branch --merged <default>`), list it under "prunable" and suggest `/handoff prune`.

## Procedure — `resolve` (work done → delete)

1. The current branch's work is complete (e.g. merged or abandoned). **Delete** `docs/handoff/<slug>.md` (`git rm docs/handoff/<slug>.md` if tracked, else `rm -f`).
2. The closure record is the commit message, not a lingering file — suggest a message like `chore(handoff): resolve <slug> (merged in #42)`.
3. Offer to commit (don't commit without approval). Do **not** delete any other branch's file here.

## Procedure — `prune` (clean up orphans)

Conservative, cross-machine-safe cleanup of handoffs whose branches no longer warrant a note.

1. `git fetch --prune` if a remote exists.
2. Determine the default branch (e.g. `main`).
3. A handoff `docs/handoff/<slug>.md` is **prunable** if ALL hold:
   - it is **not** the current branch's file, and
   - no existing local or remote branch maps to `<slug>`, **or** that branch is already merged into the default branch.
4. **`--dry-run` (default)**: list prunable files and why. Do not delete.
5. **`--apply`**: delete the prunable files in a **deletion-only commit** (e.g. `chore(handoff): prune N merged/orphaned handoffs`). Offer to commit; never auto-commit without approval.
6. Never prune a file whose branch still exists and is unmerged (it may be active on another machine).

## Relationship to the hooks

- `SessionStart` injects **the current branch's** handoff (blocked ones prominently; terminal/deleted ones not at all) and auto-migrates a legacy `HANDOFF.md` on first run.
- `Stop` blocks once and instructs a write when "3+ files changed but the branch handoff is stale" (never-miss).
- `PreCompact` leaves a lossless per-branch transcript backup in `docs/handoff/.snapshots/` (git-ignored).
