# Nova

> A compounding-agent nervous system for [Claude Code](https://docs.claude.com/en/docs/claude-code) — for both you and your coding agent.

Nova is a single Claude Code **plugin** — five **loops** that turn each coding session into raw material both sides compound on: the agent stops resetting session to session (rules · learning · continuity), and you get honesty and a record you can actually judge (gate · document). Honest, git-native, low context-tax. One install; every hook is opt-in per project.

## The loops

| Loop | Command | What it does |
|------|---------|--------------|
| **Rules** | `/claude-md` | Idempotent managed CLAUDE.md block — working discipline, verification, adaptive parallel-git workflow |
| **Learning** | `/learn` | A correction → one durable rule (deduped). Compounding engineering |
| **Continuity** | `/handoff` | Per-branch, ephemeral, git-tracked handoff (SessionStart / PreCompact / Stop hooks) so the next session continues |
| **Verification** | `/gate` | Adversarial completion-honesty audit — an independent verifier maps the session's *claims* to *evidence* (did you really do it, run the tests, stay in scope?). Opt-in hook records every Bash run to a machine-local evidence ledger the verifier audits against |
| **Record** | `/worklog` | A synthesized session narrative (two-layer: plain-Korean TL;DR first, engineering record after) with a deterministic prose lint, optional self-contained Nova-branded HTML |

## Capabilities (loop이 아닌 스킬)

| Capability | Command | What it does |
|------------|---------|---------------|
| **Discovery & Design** | `/scout` | 아무 프로젝트에서 "AI가 안전하게 *행동*할 자리"를 발굴·적합도 랭킹하고, 선택 후보를 safe-action-agent 설계 스펙으로 출력. 랭킹은 `.nova/` ledger로 compounding |
| **Design Direction** | `/design-direction` | Settle vague aesthetic asks ("modern", "sleek") by rendering 2–4 real mockups and narrowing from the user's reactions, instead of guessing from adjectives |
| **Design System** | `/design-system` | Set up a portable design-system *contract* agents obey — `docs/STYLEGUIDE.md` (roles + a resolution order) + one canonical token source + a binding rule wired in via `/claude-md` — so UI work uses documented tokens, not invented values. Stack-adaptive, installs nothing; routes the subjective look to `/design-direction` |
| **Web Doc** | `/web-doc` | Turn content into ONE self-contained HTML document (inline CSS, system fonts, no CDN, light+dark, a11y) in a style that fits its character — notion (reading), report (analysis/RCA), editorial (showcase); routes to `/design-direction` when the look is subjective |
| **Change Explainer** | `/explain-diff` | Turn a diff / commit / branch / PR into ONE self-contained HTML explainer — background → intuition (toy data + HTML diagrams) → literate code walkthrough → a comprehension quiz. The human-understanding counterpart to `/gate`: *understand to participate, not just approve* |

> Nova = "세션을 가로질러 개발을 복리로 돕는" 플러그인. 위 5 loops는 *세션* 위에서 돌고, capabilities는 loop이 아닌 도구다.

## Install

```sh
/plugin marketplace add givepro91/nova
/plugin install nova@nova       # one install — everything
```

> One plugin: five loop skills + capability skills. Every hook is **opt-in per project** — `docs/handoff/` activates handoff, `.nova/gate.on` activates the gate nudge + evidence recorder. Nothing fires until you opt in, so it stays low-tax.

## 팀 공유 규칙 사용법

### 판단층

**TL;DR.** `.nova/rules.md`가 git에 추적되는 팀 규칙의 원본이다. `/learn team`은 규칙을 `proposed`로만 제안하며, 사람이 diff와 정확한 대상을 검토한 뒤에만 활성화한다. `active` 규칙만 canonical `CLAUDE.md` 또는 `AGENTS.md`에 동일한 순서로 반영된다.

**한 일.** 제안, diff 검토, 승인 연산, sync, check를 git과 Nova 플러그인 안에서 완료한다. 회사 내부 도구, 호스팅 API, 네트워크는 필요하지 않다.

**남은 결정.** 팀은 각 제안을 활성화할지와 변환 결과를 사람이 결정해야 한다. Nova는 commit, push, 배포를 자동으로 수행하지 않으며, 이 기능을 포함한 실제 배포도 별도의 사용자 승인 전까지 보류한다.

### 엔지니어링 기록층

1. 공유할 규칙을 제안한다. Nova가 stable ID를 부여하고 `.nova/rules.md`에 `proposed`로 저장하며, 이 단계에서 `CLAUDE.md`는 바뀌지 않는다.

   ```text
   /learn team 공유 함수의 시그니처를 바꾸기 전에 모든 호출부를 확인한다.
   ```

2. 변경 상태와 추적 파일의 diff를 검토한다. 첫 제안에서 새 파일은 untracked이므로 `git add -N`으로 intent-to-add만 표시한다. 이 명령은 파일 내용을 stage하지 않는다. diff에서 규칙 본문, `scope`, 정제된 출처와 근거 요약, `status`를 확인한다.

   ```sh
   git status --short
   git add -N .nova/rules.md .nova/.gitignore
   git diff -- .nova/rules.md .nova/.gitignore CLAUDE.md AGENTS.md
   ```

3. 사람이 정확한 ID와 결과를 승인한 뒤 필요한 연산을 요청한다. `promote`는 제안을 그대로 활성화하고, `retire`는 사유와 이력을 남기고 비활성화한다. `merge`는 겹치는 제안을 하나로 합치며, `generalize`는 여러 제안을 더 넓지만 실행 가능한 규칙으로 바꾼다.

   ```text
   /learn team promote rule-20260713-a1b2c3d4
   /learn team retire rule-20260713-a1b2c3d4 사유: 보호하던 절차가 사라졌다.
   /learn team merge rule-20260713-a1b2c3d4 rule-20260713-b2c3d4e5; scope: ["src/**","tests/**"]; 출처 요약: 두 제안이 같은 변경 경계를 다룬다.; 근거 요약: 하나의 규칙이 반복 누락을 막는다.; 최종 규칙: 공유 동작을 바꾸기 전에 호출부와 관련 테스트를 확인한다.
   /learn team generalize rule-20260713-a1b2c3d4 rule-20260713-b2c3d4e5; scope: ["**"]; 출처 요약: 두 제안이 공유 변경의 검토 원칙을 다룬다.; 근거 요약: 파급 범위 누락의 재발을 막아야 한다.; 최종 규칙: 공유 동작을 바꾸기 전에 영향받는 코드와 검증을 확인한다.
   ```

   `merge`와 `generalize`는 모든 원본 ID, 결과 `scope`, 정제된 요약, 최종 규칙을 명시해야 한다. 내용이 충돌하면 Nova는 임의로 한쪽을 선택하지 않고 다시 승인을 요청한다.

4. 승인 연산은 `active` 규칙을 canonical `CLAUDE.md` 또는 `AGENTS.md`의 managed block에 반영한다. `/claude-md`를 다시 실행해도 canonical 파일을 찾아 sync한 뒤 read-only check를 멱등적으로 수행한다.

   ```text
   /claude-md
   ```

   저수준 `--sync-team-rules`와 `--check-team-rules`는 Nova가 플러그인 내부 경로와 canonical 파일을 확인한 뒤 실행한다. 공개 설치자는 환경변수나 파일 위치를 직접 지정하지 말고 `/claude-md`를 사용한다. check는 파일을 바꾸지 않고 projection이 다르면 non-zero로 종료한다.

malformed record, 중복 ID, 끊긴 provenance, 허용되지 않은 상태 전이, git conflict marker가 있으면 쓰기를 거부한다. `.nova/evidence.jsonl`, `.nova/gate-history.jsonl`, `.nova/gate-verdict.json`과 다른 로컬 ledger는 `.nova/.gitignore`에 의해 machine-local에 남는다. transcript와 명령 출력 원문은 추적 아티팩트로 복사하지 않는다. `.nova/rules.md`에는 비밀과 원문 대신 사람이 검토할 수 있게 새로 쓴 요약만 저장한다.

## Supersedes

Nova consolidates and replaces the standalone [`cc-skills`](https://github.com/givepro91/cc-skills) (`claude-md` + `learn`) and [`cc-handoff`](https://github.com/givepro91/cc-handoff) (`handoff`). Those repos point here.

## Related

More AI-workflow tooling by [@givepro91](https://github.com/givepro91):

- **[markwand](https://github.com/givepro91/markwand)** — a desktop curator for the markdown docs your AI-driven projects leave scattered everywhere: discover, read, and re-enter them (Electron).
- **[my-wiki-template](https://github.com/givepro91/my-wiki-template)** — a template for an evidence-based personal wiki you and your AI agents maintain together (MCP-ready).

## License

MIT © 2026 Jay (Spacewalk)
