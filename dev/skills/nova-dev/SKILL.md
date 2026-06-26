---
name: nova-dev
description: "Develop/evolve the Nova plugin (givepro91/nova) itself — scan only the Claude Code changes Nova actually depends on, make a surgical plugin change, verify with the repo's own tests + dogfood /gate, then ship. Deliberately lean: NO ledger/cron/gate-chain/trend-scanner machinery. MUST TRIGGER: 'evolve nova', '/nova-dev', updating nova for a new Claude Code feature, or adding/changing a nova skill/hook/script."
description_en: "Lean dev loop for the Nova plugin: light signal scan -> surgical change -> tests + /gate -> ship."
user-invocable: true
---

# Nova Dev — evolve the plugin, lean

One lightweight loop for keeping the `nova` plugin healthy and current. Nova is small and deliberately lean (five skills + shared hooks, one plugin) — so this tool is too. The whole point: a person + agent run this in one sitting.

**Repo:** `~/develop/givepro91/nova` · skills: claude-md, learn, handoff, gate, document · `plugins/nova/{skills,scripts,hooks}`.

## When to run

- A Claude Code change touches what Nova depends on: `plugin.json` / `marketplace.json` / `hooks.json` schema, hook **types**, or the skill format.
- You have a concrete improvement to a nova skill / hook / script.
- **Don't run it to "find something to do."** Evolve on a real signal, not a schedule.

## The loop

1. **Signal (light scan).** Only when relevant. Check the *authoritative* source for the specific thing you're acting on — don't guess from memory (Claude Code moves fast):
   - Claude Code plugin/hooks docs + `anthropics/claude-code` CHANGELOG — schema / hook-type / skill-format changes.
   - *(optional)* one ecosystem pattern worth absorbing — but require a real, fetched source; no blog/abstract-only claims.

2. **Propose (small).** Write the change as a short list: `file → what → one-line why + source`. If it isn't surgical, it's too big for this loop — split it.

3. **Implement.** Surgical edit, match the repo's style, new code on by default (no flags/abstractions for single use). Touch only what the change needs.

4. **Verify (non-negotiable).** All three suites green + syntax:
   ```sh
   bash tests/inc15-verify.sh && bash tests/gate-verify.sh && bash tests/worklog-verify.sh
   node --check plugins/nova/hooks/*.mjs plugins/nova/scripts/*.mjs
   ```
   Then **dogfood Nova's own gate**: run `/gate` on this dev session — an independent verifier maps your "done" claims to evidence. Nova must clear its own honesty bar. Changed the renderer or a hook? Extend a test, don't eyeball.

5. **Ship (explicit approval only).** Bump `plugins/nova/.claude-plugin/plugin.json` (patch: fix/docs · minor: new/changed skill or hook). Commit (`feat:`/`fix:`/`update:`/`docs:`/`chore:`). Push + `gh release` only on the user's word (givepro91 account — switch active, push, restore jay-swk).

## Validate by dogfooding (lightweight)

The real field test is **using Nova on actual work and noticing friction** — no worktree/subagent machinery. When a command annoys you or misses, that's the signal: feed it to the next loop's *Propose*, or `/learn` it on the spot.

## Anti-scope — what this is deliberately NOT

No `_ABSORBED.md` ledger · no baseline-fallback · no 8-query trend scanner · no cron auto-apply · no gate-chain rollback. Those fit a sprawling framework; Nova is five skills. If a "dev tool" starts growing those, it has stopped being lean — that's the same over-engineering the monolith decision rejected. Keep this a one-sitting checklist. And **never ship dev tooling inside the plugin** — this skill lives in `dev/`, never `plugins/nova/`.
