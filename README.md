# Nova

> A compounding-agent nervous system for [Claude Code](https://docs.claude.com/en/docs/claude-code).

Nova is a small, **modular** plugin marketplace. Each plugin is one **loop** that turns a coding session into raw material the agent learns from — so it doesn't reset every session, it **compounds**. Honest, git-native, low context-tax. Install only the loops you want.

## The loops

| Loop | Plugin | What it does | Status |
|------|--------|--------------|--------|
| **Rules** | `claude-md` | Idempotent managed CLAUDE.md block — working discipline, verification, adaptive parallel-git workflow | ✅ |
| **Learning** | `claude-md` (`/learn`) | A correction → one durable rule (deduped). Compounding engineering | ✅ |
| **Continuity** | `handoff` | Per-branch, ephemeral, git-tracked handoff (Stop / PreCompact / SessionStart hooks) so the next session continues | ✅ |
| **Verification** | `nova-gate` | Adversarial completion-honesty audit — an independent verifier maps the session's *claims* to *evidence* (did you really do it, run the tests, stay in scope?) | 🚧 |
| **Record** | `worklog` | A synthesized session narrative (`/document`), optional self-contained visual HTML | 🚧 |

## Install

```sh
/plugin marketplace add givepro91/nova
/plugin install claude-md@nova      # rules + learning
/plugin install handoff@nova        # continuity
```

> Keep your active plugin set small — every plugin's metadata is always loaded into context. Install the loops you actually use.

## Supersedes

Nova consolidates and replaces the standalone [`cc-skills`](https://github.com/givepro91/cc-skills) (`claude-md` + `learn`) and [`cc-handoff`](https://github.com/givepro91/cc-handoff) (`handoff`). Those repos point here.

## License

MIT © 2026 Jay (Spacewalk)
