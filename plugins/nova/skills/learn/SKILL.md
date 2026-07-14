---
name: learn
description: Capture a lesson from a mistake into personal Self-Learning Rules, or explicitly propose and human-review sanitized team rules in `.nova/rules.md`. Distills the most recent correction into ONE concise, reusable rule. `/learn review` gardens personal rules; `/learn team` creates proposed-only records; `/learn team <promote|merge|generalize|retire>` applies an explicitly approved team operation.
when_to_use: When the user runs /learn, or right after a correction ("no, don't…", "again", "that's wrong", "always/never do X") that should become a durable rule. Use /learn team only when the user explicitly chooses to share or review a lesson with the team. /learn review when the personal rule list has grown stale or long.
argument-hint: "[rule text | team [rule text | promote|merge|generalize|retire] | review]"
disable-model-invocation: true
allowed-tools: Read, Edit, Bash(git rev-parse*), Bash(git diff*), Bash(node*), Bash(readlink*), Bash(grep*)
---

# /learn — keep a rule from a mistake

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
6. **Offer team sharing as a separate choice.** Do not create a team proposal unless the user explicitly accepts or invoked `/learn team`.

## Procedure — `team` (explicit team proposal)

`/learn team [rule text]` is a proposal-only path. It writes `.nova/rules.md`; it does not append to the personal Self-Learning Rules, project `CLAUDE.md`, or `AGENTS.md`. If the user chooses team sharing after a normal `/learn`, the personal write has already happened, but this team step must not modify those files further.

1. **Require an explicit choice.** Enter this path only for `/learn team` or a clear yes to the separate team-sharing offer. A correction by itself is not consent to share it.
2. **Distill one rule** using the same imperative, one-line, language-preserving rules above.
3. **Prepare only reviewed metadata:**
   - `scope`: a non-empty JSON array of repo-relative globs. Use `["**"]` only when the rule truly applies to the whole repository; ask when the intended scope is ambiguous.
   - `source-summary`: one newly written line describing the kind of reviewed source, without quoting the correction or transcript.
   - `evidence-summary`: one newly written line explaining why the rule prevents recurrence, without command text or output.
   - `rule`: the one-line executable rule.
   Never copy raw transcript, `.nova/evidence.jsonl`, command output, stack traces, credentials, or secret-looking strings into any field. Do not read machine-local evidence merely to populate this proposal.
4. **Append the proposal through the validator** (replace the example values with the reviewed metadata):
   ```sh
   node "${CLAUDE_PLUGIN_ROOT}/scripts/team-rules.mjs" propose "<project root>/.nova/rules.md" <<'JSON'
   {
     "scope": ["**"],
     "source-summary": "사용자 교정에서 반복 가능한 작업 원칙을 확인했다.",
     "evidence-summary": "같은 누락의 재발을 막기 위해 팀 검토가 필요하다.",
     "rule": "변경을 완료했다고 말하기 전에 관련 검증 명령의 성공을 확인한다."
   }
   JSON
   ```
   The helper assigns the stable ID and fixes `status: proposed`, `origin: propose`, and `derived-from: []`; never hand-author or override those fields. If validation rejects a field, rewrite the summary safely or ask the user—never weaken or bypass the validator.
5. **Report the proposal ID and review boundary.** State that the rule is not active and `CLAUDE.md` was not changed by this step. Show the user the `.nova/rules.md` diff for review, but do not approve, commit, or push it.

## Procedure — `team promote|merge|generalize|retire` (human-approved gardener)

Run a team gardener operation only after the user explicitly approves the exact IDs and result. Read and validate the current `.nova/rules.md`, show the planned status/provenance change, and do not infer approval from an earlier correction or proposal.

- **Promote** changes one existing `proposed` record to `active` without changing its ID or content:
  ```sh
  printf '%s\n' '{"id":"rule-20260713-a1b2c3d4"}' |
    node "${CLAUDE_PLUGIN_ROOT}/scripts/team-rules.mjs" promote "<project root>/.nova/rules.md"
  ```
- **Retire** changes one non-retired record to `retired` and requires a newly written one-line reason:
  ```sh
  printf '%s\n' '{"id":"rule-20260713-a1b2c3d4","retired-reason":"The guarded workflow no longer exists."}' |
    node "${CLAUDE_PLUGIN_ROOT}/scripts/team-rules.mjs" retire "<project root>/.nova/rules.md"
  ```
- **Merge/generalize** require every reviewed source ID plus the explicit result scope, sanitized summaries, and final one-line rule. They create one new `active` record, preserve the source IDs in `derived-from`, and retire each source with the replacement ID:
  ```sh
  node "${CLAUDE_PLUGIN_ROOT}/scripts/team-rules.mjs" merge "<project root>/.nova/rules.md" <<'JSON'
  {
    "derived-from": ["rule-20260713-a1b2c3d4", "rule-20260713-b2c3d4e5"],
    "scope": ["src/**", "tests/**"],
    "source-summary": "Two reviewed proposals describe the same change boundary.",
    "evidence-summary": "One shared rule prevents both recurring omissions.",
    "rule": "Before changing shared behavior, inspect its callers and related tests."
  }
  JSON
  ```
  Use `generalize` instead of `merge` only when the approved result is a broader but still actionable principle. Never choose one source's scope or body automatically when sources differ; the user must approve the explicit result fields.

If the file changed since review, a source is missing/already retired, IDs are duplicated, or any field fails sanitization/schema validation, stop on the non-zero result and show the fresh diff. Never bypass the validator, edit statuses by hand, activate another proposal, commit, or push. On success, the command itself resolves the repo's canonical agent file (CLAUDE.md, or AGENTS.md when canonical — same rules as `/claude-md`) and projects the now-`active` rules into its `CC-RULES` managed block, removing any rule that just became `retired`; a repo with no canonical file yet is not an error (`.nova/rules.md` stays the source of truth and can be synced later). This operation changes only `.nova/rules.md`, the approved `.nova/.gitignore` allowlist, and that projected region of the canonical file — never commit or push it.

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
