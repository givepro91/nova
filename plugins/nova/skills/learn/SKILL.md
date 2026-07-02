---
name: learn
description: Capture a lesson from a mistake into CLAUDE.md's Self-Learning Rules so the same mistake isn't repeated. Distills the most recent correction into ONE concise, reusable rule and appends it (deduped). `/learn review` is the gardener — consolidates, generalizes, retires, and promotes accumulated rules so the list stays sharp instead of becoming noise. Use right after Claude does something wrong and the user corrects it, or when the user runs /learn.
when_to_use: When the user runs /learn, or right after a correction ("no, don't…", "again", "that's wrong", "always/never do X") that should become a durable rule. /learn review when the rule list has grown stale or long.
argument-hint: "[rule text | review]"
disable-model-invocation: true
allowed-tools: Read, Edit, Bash(git rev-parse*), Bash(node*), Bash(readlink*), Bash(grep*)
---

# /learn — append a rule from a mistake

Turn a correction into a durable rule in the canonical agent file's **Self-Learning Rules**, so the next session doesn't repeat it. This is the "compounding engineering" loop: every mistake makes the rules sharper.

## Procedure

1. **Find the canonical agent file** (the one holding the `CC-RULES` block). Project root = `git rev-parse --show-toplevel` (fallback: cwd). Resolve the same way `/claude-md` does: a `CLAUDE.md` symlink → its target; `CLAUDE.md` importing `@AGENTS.md` (or AGENTS.md canonical) → `AGENTS.md`; only `AGENTS.md` → `AGENTS.md`; else `CLAUDE.md`. In practice: pick whichever of `CLAUDE.md` / `AGENTS.md` actually contains `<!-- LEARN:ANCHOR -->`. If neither has it, tell the user to run `/claude-md` first (don't hand-edit).
2. **Determine the rule:**
   - If the user passed text after `/learn`, use that as the rule (lightly cleaned).
   - Otherwise, look at the **most recent correction** in this conversation — what Claude did wrong and what the user actually wanted — and distill it into **one** rule.
3. **Write the rule well** (this matters more than anything):
   - **Imperative and general**, not a story. ✅ "When editing a shared function, grep all call sites before changing its signature." ❌ "Earlier you broke the build."
   - **One line, one lesson.** Actionable next time. Prefer "always/never/before X do Y" shapes.
   - **Preserve the user's language** (Korean correction → Korean rule).
   - Capture the *generalizable* lesson, not the one-off detail.
4. **Append (deduped)** via the helper:
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/append-rule.mjs" <target file> "<the one-line rule>"
   ```
   (`<target file>` = the canonical file resolved in step 1.) It inserts `- (YYYY-MM-DD) <rule>` after the anchor (newest first) and skips near-duplicates.
5. **Confirm** the added line (or report it was a duplicate). Offer to commit (don't commit without approval).

## Examples

<good>
User: "you changed the API signature but didn't update the callers"
→ rule: "Before changing a function's signature, grep every call site and update them in the same change."
</good>

<good>
User (Korean): "스키마 바꾸기 전에 꼭 물어봐"
→ rule (Korean): "DB 스키마를 변경하기 전에 반드시 사용자 승인을 받는다."
</good>

<bad>
rule: "Don't make mistakes." → too vague, not actionable.
rule: "I broke the login test at 3pm." → a story, not a reusable rule.
</bad>

## Procedure — `review` (the gardener)

A rule list that only grows becomes noise: every session pays its context tax, and stale or contradictory rules erode trust in all of them. `/learn review` prunes so the list stays worth loading.

1. **Read the rules** under `<!-- LEARN:ANCHOR -->` in the canonical file (resolve as in step 1 above). If `.nova/gate-history.jsonl` exists, also read it — recurring gate findings are evidence of a *missing* rule; a finding that stopped recurring is evidence a rule is working.
2. **Propose a gardening plan** (propose first — apply nothing yet):
   - **Merge** near-duplicates into the sharper phrasing (keep the older date).
   - **Generalize** 2–3 rules that are instances of one principle into that principle — only when the general form is still actionable, not a platitude.
   - **Retire** rules that are obsolete (the tool/file/workflow they guard no longer exists — verify with grep, don't guess) or subsumed by a merged/general rule.
   - **Promote** rules that aren't project-specific to the user's global CLAUDE.md — list them as suggestions; never write outside the repo yourself.
   - **Missing rules** from gate history: "N of the last M gates flagged X" → propose a new rule via the normal append flow.
3. **Show the plan as a table** (rule → action → why) and get explicit approval.
4. **Apply** only the approved actions by editing between the anchor and the block end — never touch anything outside the Self-Learning Rules region. Keep `- (YYYY-MM-DD) ` line format; retired rules are deleted (git history keeps them), not commented out.
5. **Report** the before/after count and offer to commit (don't commit without approval).

## Why a separate section + skill (not full automation)

Auto-detecting "mistakes" from chat is noisy and unreliable. `/learn` keeps a human in the loop (you decide a correction is worth a rule), while the helper makes the write deterministic and dedup-safe. The rules live in `CLAUDE.md` so they load every session and travel with the repo.
