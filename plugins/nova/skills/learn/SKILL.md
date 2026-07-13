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

1. **Find the canonical agent file** (the one holding the `CC-RULES` block). Project root = `git rev-parse --show-toplevel` (fallback: cwd). Resolve the same way `/claude-md` does:
   - Follow a `CLAUDE.md` symlink to its target.
   - Use `AGENTS.md` when `CLAUDE.md` imports `@AGENTS.md`, when `AGENTS.md` is canonical, or when only `AGENTS.md` exists.
   - Otherwise use `CLAUDE.md`.

   In practice, pick whichever file actually contains `<!-- LEARN:ANCHOR -->`. If neither has it, tell the user to run `/claude-md` first (don't hand-edit).
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
   (`<target file>` = the canonical file resolved in step 1.) It inserts `- (YYYY-MM-DD) <rule>` after the anchor (newest first) and skips normalized exact duplicates.
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
rule: "Don't make mistakes." — too vague, not actionable.
rule: "I broke the login test at 3pm." — a story, not a reusable rule.
</bad>

## Procedure — `review` (the gardener)

A rule list that only grows becomes noise: every session pays its context tax, and stale or contradictory rules erode trust in all of them. `/learn review` prunes so the list stays worth loading.

1. **Read the rules** under `<!-- LEARN:ANCHOR -->` in the canonical file (resolve as in step 1 above). If `.nova/gate-history.jsonl` exists, run the deterministic aggregator instead of parsing the JSONL yourself:
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/gate-history-review.mjs" .nova/gate-history.jsonl
   ```

   It is read-only (never modifies the ledger) and returns JSON with `valid_records`, `ignored_lines` (1-based line number + `blank`/`malformed`/`invalid-record` reason), `candidates` (modes with ≥3 distinct valid gate records), and `observations` (modes with 1–2 records, or `unclassified`). Use this output directly in steps 2–3 below — do not re-derive counts, dedup, or mode classification by hand.

   The table documents the fixed mode, cause, preventive action, and Korean proposal mapping the script applies (reference only):

   | Mode | Fixed cause → preventive action | Exact Korean rule proposal |
   |---|---|---|
   | `verification-evidence-missing` | Required verification was not run or lacks execution evidence → run the exact check and retain passing output | `완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.` |
   | `verification-failure-unresolved` | A failed check has no passing rerun → fix and rerun the same check to passing | `검증 명령이 실패하면 원인을 수정하고 같은 명령의 통과 재실행을 확인한 후에만 완료로 보고한다.` |
   | `requested-scope-omitted` | A requested item was left incomplete → map every requested item to implementation and evidence | `완료를 보고하기 전에 모든 요청 항목을 구현 결과와 검증 근거에 대응시켜 누락을 확인한다.` |
   | `unrequested-scope-added` | Work exceeded the requested scope → stay within scope and ask before expansion | `요청 범위 밖의 변경이 필요하면 구현하기 전에 사용자 승인을 받는다.` |
   | `reference-not-found` | A referenced artifact does not exist → resolve and inspect the real reference first | `파일·심볼·명령·플래그·경로를 사용하거나 보고하기 전에 실제 존재와 내용을 확인한다.` |
   | `ambiguity-not-raised` | A material ambiguity was silently assumed away → surface it and get direction | `결과를 바꿀 수 있는 모호함은 임의로 결정하지 말고 사용자에게 알려 방향을 확인한다.` |
   | `completion-overstated` | Partial, skipped, or blocked work was overstated → report the exact incomplete state | `부분 완료·미수행·차단 상태를 완료로 표현하지 말고 남은 작업과 검증 공백을 정확히 보고한다.` |
   | `unclassified` | Cause or prevention is not established → observation only | — |

   The mode key is the deduplication key. Different wording with the same cause and preventive action maps to one mode; similar wording with different causes does not. Within one gate record, the aggregator counts a mode at most once even if several claims have it, and preserves all matching claim indices as evidence.
2. **Propose a gardening plan** (propose first — apply nothing yet):
   - **Merge** near-duplicates into the sharper phrasing (keep the older date).
   - **Generalize** 2–3 rules that are instances of one principle into that principle — only when the general form is still actionable, not a platitude.
   - **Retire** rules that are obsolete (the tool/file/workflow they guard no longer exists — verify with grep, don't guess) or subsumed by a merged/general rule.
   - **Promote** rules that aren't project-specific to the user's global CLAUDE.md — list them as suggestions; never write outside the repo yourself.
   - **Missing rules** from gate history: use the aggregator's `candidates` array as-is. Each entry already represents ≥3 distinct valid gate records for one fixed failure mode, deduplicated by mode key.
   - **Near-duplicate guard:** Before proposing a candidate, compare its trigger and required preventive action with the existing rules under the anchor.
   - If an existing rule already requires the same preventive behavior for the same failure situation, report the candidate as `기존 규칙으로 커버` and exclude it from approval and append. Wording or date differences do not make it a new rule. The append helper's normalization remains the final exact-duplicate guard.
3. **Show a two-layer Korean review, then get explicit approval.** Keep the first layer easy to judge and the second layer evidence-rich:
   - **판단 요약:** State the valid record count, ignored line count, candidate count, and observation count in Korean. Show only uncovered entries from `candidates` in this exact table shape:

     | 후보 ID | 발생 횟수 | 제안 규칙 | 원인 | 예방 행동 |
     |---|---:|---|---|---|
     | `gate:<failure_mode>` | `<occurrences>회` | `<exact proposal>` | `<cause를 한국어로 충실히 표현>` | `<preventive_action을 한국어로 충실히 표현>` |

     Entries with fewer than 3 occurrences remain observations and must not appear in this candidate table. If there are no uncovered candidates, say `승인할 팀 규칙 후보가 없습니다.`
   - **근거 기록:** Under each candidate ID, show every entry in `records` as `[line N] head=<head> timestamp=<timestamp> claim=<claim_indices>`; the script already fills `missing` for an absent `head` or `timestamp`. Report `observations` separately as non-candidates and `ignored_lines` with their line number and reason. Never expose the raw claim evidence or command output from the machine-local ledger.

   End with `승인하려면 후보 ID를 지정해 주세요. 예: gate:verification-evidence-missing 승인`. A generic response such as "승인", "좋아", or "전부 적용" is not candidate-specific approval; ask the user to name each intended ID. Do not write the canonical rules file, `.nova/gate-history.jsonl`, or any other file during review. Re-running an unapproved review must have no filesystem side effects.
4. **Apply only after explicit, candidate-specific approval.** For an approved recurring-failure candidate, pass only its exact proposal to the existing normal append path:
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/append-rule.mjs" <target file> "<approved exact Korean proposal>"
   ```

   Re-check the approved ID against the candidate set from the current review and repeat the near-duplicate check immediately before calling the helper. The helper's existing normalization is the final exact-duplicate guard. Apply only the named IDs, one helper call per candidate; never infer approval for another candidate or auto-approve any candidate.

   Other approved gardening actions may edit only between the anchor and the block end; never touch anything outside the Self-Learning Rules region. Keep `- (YYYY-MM-DD) ` line format; retired rules are deleted (git history keeps them), not commented out.
5. **Report** the before/after count and offer to commit (don't commit without approval).

## Why a separate section + skill (not full automation)

Auto-detecting "mistakes" from chat is noisy and unreliable. `/learn` keeps a human in the loop (you decide a correction is worth a rule), while the helper makes the write deterministic and dedup-safe. The rules live in `CLAUDE.md` so they load every session and travel with the repo.
