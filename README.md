# Nova

> A compounding-agent nervous system for [Claude Code](https://docs.claude.com/en/docs/claude-code).

Nova is a single Claude Code **plugin** — five **loops** that turn each coding session into raw material the agent learns from, so it doesn't reset every session, it **compounds**. Honest, git-native, low context-tax. One install; every hook is opt-in per project.

## The loops

| Loop | Command | What it does |
|------|---------|--------------|
| **Rules** | `/claude-md` | Idempotent managed CLAUDE.md block — working discipline, verification, adaptive parallel-git workflow |
| **Learning** | `/learn` | A correction → one durable rule (deduped). Compounding engineering |
| **Continuity** | `/handoff` | Per-branch, ephemeral, git-tracked handoff (SessionStart / PreCompact / Stop hooks) so the next session continues |
| **Verification** | `/gate` | Adversarial completion-honesty audit — an independent verifier maps the session's *claims* to *evidence* (did you really do it, run the tests, stay in scope?) |
| **Record** | `/document` | A synthesized session narrative, optional self-contained Nova-branded HTML |

## Install

```sh
/plugin marketplace add givepro91/nova
/plugin install nova@nova       # one install — all five loops
```

> One plugin, five skills. Every hook is **opt-in per project** — `docs/handoff/` activates handoff, `.nova/gate.on` activates the gate nudge. Nothing fires until you opt in, so it stays low-tax.

## Supersedes

Nova consolidates and replaces the standalone [`cc-skills`](https://github.com/givepro91/cc-skills) (`claude-md` + `learn`) and [`cc-handoff`](https://github.com/givepro91/cc-handoff) (`handoff`). Those repos point here.

## License

MIT © 2026 Jay (Spacewalk)
