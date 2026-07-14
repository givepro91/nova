---
name: claude-md
description: Generate or refresh a project's agent rules — a tailored preamble plus an idempotent managed block (working discipline, verification, adaptive parallel-git workflow, self-learning rules). Writes to the repo's canonical agent file (CLAUDE.md by default, or AGENTS.md when it is canonical, e.g. CLAUDE.md imports @AGENTS.md). Works on new and existing projects; only ever rewrites its own managed block. Use when setting up a repo, standardizing AI working rules, or adopting the parallel-git + self-learning workflow.
when_to_use: When the user runs /claude-md, sets up a new repo, wants consistent agent working rules, or asks to add the parallel-git / self-learning workflow to a project.
argument-hint: "[--ko] [--solo|--team]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git status*), Bash(git rev-parse*), Bash(git remote*), Bash(git branch*), Bash(gh repo view*), Bash(gh auth status*), Bash(node*), Bash(ls*), Bash(cat*), Bash(readlink*)
---

# /claude-md — generate & maintain agent rules

Write a high-quality agent-rules file using a **hybrid** model and an **idempotent managed block**, so it works on new *and* existing projects and is safe to re-run.

## Design (read first)

```
<canonical agent file>          ← CLAUDE.md (default) OR AGENTS.md (when canonical)
## Project … (tailored preamble — scan/interview; written once, then user-owned)

<!-- CC-RULES:START -->        ← managed by this skill; regen rewrites ONLY this block
## Working Discipline          (Karpathy)
## Verification                (Anthropic best-practice)
## Parallel Git Workflow       (adaptive: team / solo / none)
## Self-Learning Rules         (grows via /learn; PRESERVED across regen)
<!-- CC-RULES:END -->

… anything below/around the block is the user's free area — never touched
```

- **Idempotent.** The block is upserted between the markers. Re-running replaces only that region; everything else (incl. an OMC `<!-- OMC:START -->` block or hand-written sections) is left byte-identical.
- **Self-learning preserved.** Rules accumulated under `<!-- LEARN:ANCHOR -->` survive regeneration (the helper carries them over).
- **One block, one file.** The block lives in exactly ONE canonical file; never split or duplicated across CLAUDE.md and AGENTS.md.

## Target resolution (which file gets the block)

The rules are tool-agnostic, so they belong in the file every agent on this repo reads. Detect the canonical file:

1. **`CLAUDE.md` is a symlink** (`readlink CLAUDE.md`) → resolve it; the target is the real file (usually `AGENTS.md`). One physical file — done.
2. **`CLAUDE.md` imports `@AGENTS.md`** (a line that is exactly `@AGENTS.md`), or **`AGENTS.md` self-declares canonical** → the repo is multi-tool (e.g. Claude + Codex). **Target = `AGENTS.md`** so Codex/others also get the rules.
3. **Only `AGENTS.md` exists** (no `CLAUDE.md`) → Target = `AGENTS.md`. Do not create a redundant CLAUDE.md.
4. **Otherwise** → Target = `CLAUDE.md` (default, Claude-native).

**Confirm before writing to AGENTS.md.** Whenever the target is `AGENTS.md` (cases 2–3), state it and get a yes first — agent-config has a large blast radius:

> Detected `@AGENTS.md` import → AGENTS.md is the canonical agent file (Codex reads it too). I'll put the managed block in **AGENTS.md** and keep CLAUDE.md as the pointer. OK?

For the plain CLAUDE.md-only case, no confirmation is needed.

> Note: recent Claude Code may read `AGENTS.md` natively. If so, a `@AGENTS.md` import in CLAUDE.md double-loads it — consider a symlink or dropping the import. Mention this; don't change their structure without asking.

## Procedure

1. **Find the project root** (`git rev-parse --show-toplevel`, fallback cwd) and **resolve the target** per the rules above (confirm if AGENTS.md).
2. **Detect environment** for the adaptive git section:
   - git? `git rev-parse --is-inside-work-tree`
   - remote + GitHub? `git remote -v`, `gh repo view` / `gh auth status` (treat failure as "no gh")
   - **team** if a remote exists and `gh` works; **solo** if git but no usable remote/gh; **none** if not a git repo. `--team` / `--solo` flags override.
   - Language = English by default; `--ko` → Korean prose. (Match the target file's existing language when obvious.)
3. **Remove any stale block from the OTHER file.** If the target is AGENTS.md but a `CC-RULES` block already exists in CLAUDE.md (or vice-versa), delete it from the non-canonical file first so the block never lives in two places:
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/apply-block.mjs" --remove <root>/CLAUDE.md
   ```
4. **Tailored preamble (only if the target file does NOT already exist):**
   - Scan for stack & commands: `package.json` scripts, `Makefile`, `pyproject.toml`, `Cargo.toml`, `go.mod`, README, lockfiles, test/build config.
   - Optionally ask 1–2 short questions only for facts you cannot infer. Don't ask what the repo already tells you.
   - `Write` a minimal preamble: a one-line project description + a `## Project` section with **build / test / run** commands.
   - If the target file already exists, **do not** rewrite the preamble — go straight to the block.
5. **Compose the managed block body** from the template below, choosing the matching Parallel Git Workflow variant and translating prose if `--ko`. Keep `<!-- LEARN:ANCHOR -->` exactly as written.
6. **Upsert the block idempotently:**
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/apply-block.mjs" <target file> <<'BLOCK'
   …composed block body…
   BLOCK
   ```
7. **Verify & report:** show the resulting block, confirm pre-existing content is intact, and note that re-running is safe. Offer to commit (don't commit without approval).

## Managed block body — template

> Render this between the markers. Pick ONE Parallel Git Workflow variant. `--ko` translates the prose; keep headings/markers/anchor verbatim.

```markdown
## Working Discipline
- **Think before coding.** State assumptions; if uncertain, ask. Surface tradeoffs and competing interpretations instead of silently picking one.
- **Simplicity first.** Write the minimum code that solves the stated problem. No speculative features, abstractions, or configuration for single-use code.
- **Surgical changes.** Touch only what the task requires. Don't refactor or reformat adjacent code; match the existing style. Remove only what your change made unused.
- **Comment the why, not the what.** When a design doc or a non-obvious constraint drives the code, add a one- or two-line comment for the *reason* (safety constraint, compat shim, design-doc rule). Don't restate what the code does or narrate the mechanism.
- **Name for content, not role.** Name a file/module after the concrete thing it holds. Avoid catch-all names (`utils`, `helpers`, `common`, `misc`, `shared`) — they become dumping grounds; reaching for `helpers` usually means the file has more than one responsibility and should be split.
- **Goal-driven.** Define a concrete success check (test / build / command / screenshot) before coding, then loop until it passes.

## Verification
- Always give yourself a way to verify — a test, a bash command, a curl, a screenshot. A working feedback loop is the single biggest quality lever.
- Report honestly: if a check fails, say so with the output; mark unverified work "unverified". Never present incomplete work as done.

## Parallel Git Workflow
<!-- variant: TEAM (git + remote + gh) -->
- **Never edit, commit, or merge on the default branch (`main`/`master`) without explicit user approval.** Isolation is the default even for a single session. **One task = one ISSUE = one branch.**
- **Create the branch/worktree BEFORE you start editing — not at commit time.** Isolate each task in its own **git worktree** (`git worktree add ../<task> -b <branch>`), or use your agent's native worktree support — **Claude Code provides worktrees** — so parallel sessions never share a checkout and never collide on `main`. Don't touch worktrees you didn't create (another session's, or tool-managed ones).
- **Stay in the worktree you were given.** Read and edit only inside your task's working directory. A subagent's result may report absolute paths into the main checkout — never follow them back to `main`; re-resolve the path inside your own worktree. Following them silently breaks the isolation above.
- **Clean up when the work lands: once the branch is merged, remove its worktree and delete the branch in the same flow** (`git worktree remove <path>` + `git branch -d <branch>`) — never leave stale worktrees/branches behind.
- Open small, surgical PRs that reference the issue (e.g. "Fixes #42"); keep one concern per PR.
- If cc-handoff is installed: **one branch = one handoff** (`docs/handoff/<branch>.md`).

<!-- variant: SOLO (git, no remote/gh) — use instead of TEAM -->
- **Don't edit, commit, or merge on the default branch without explicit user approval** — isolate every task, even solo. **Create the branch/worktree BEFORE editing — not at commit time** (`git worktree add ../<task> -b <task>`, or `git switch -c <task>`; **Claude Code provides native worktrees**). Don't touch worktrees you didn't create, and never follow a subagent's absolute path back into the main checkout — re-resolve it inside your own worktree.
- **After the work merges back, clean up in the same flow: `git worktree remove <path>` + `git branch -d <branch>`** — no stale worktrees/branches.
- Commit in small, focused steps with the *why* in the body. (No PR ceremony needed for a solo repo.)

<!-- variant: NONE (not a git repo) — replace section body with this single line -->
- Not a git repo yet — run `git init` to enable branch/worktree isolation for parallel sessions.

## Self-Learning Rules
<!-- Append one concise rule per correction. `/learn` writes here automatically; newest first. -->
<!-- LEARN:ANCHOR -->
```

## Notes

- The block uses distinct markers (`CC-RULES`), so it never collides with an OMC (`OMC:START`) block in the same file.
- Keep the block lean — it's guidance, not documentation. Project-specific conventions (a design-system / STYLEGUIDE contract, a lint-config policy, a stack-specific rule) do NOT go in the block — they belong in the preamble, the user's free area, or the Self-Learning Rules that `/learn` accumulates per project.
- `/learn` is the companion that grows the Self-Learning Rules; it writes to the same canonical file this skill chose.
