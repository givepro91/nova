# Nova `/scout` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nova에 `/scout` 스킬을 추가한다 — 아무 프로젝트에서 "AI가 안전하게 행동할 자리"를 발굴·랭킹하고, 선택 후보를 safe-action-agent 설계 스펙으로 출력한다.

**Architecture:** SKILL.md 단일 파일이 워크플로우(comprehension → interview → 후보생성 → 점수·랭킹 → 설계스펙)를 구동한다. 스캔은 내장 검색도구 + Explore 서브에이전트(`Task`)로, 산출은 대상 레포의 `docs/specs/<slug>-agent-design.md`(생성만), 상태는 `.nova/scout-candidates.json` ledger로. 결정적 스크립트 없음(이식성).

**Tech Stack:** Claude Code plugin skill (SKILL.md + YAML frontmatter). 산출물은 markdown/JSON. 코드 스택 비종속.

## Global Constraints

(스펙 `docs/specs/2026-07-01-scout-skill-design.md`의 프로젝트 전역 요구 — 모든 task에 암묵 포함)

- 사용자 응답 언어 = **한국어**. 브랜드 색 = violet (`#7c3aed`).
- `allowed-tools` = **`Read, Glob, Grep, Bash(git*), Bash(mkdir -p*), Task, Write`** (gate와 정합).
- 설계 스펙 출력 경로 = **`docs/specs/<slug>-agent-design.md`** (고정) · **파일 생성만, 자동 commit 금지**.
- ledger 경로 = **`.nova/scout-candidates.json`** · slug = canonical(대상 시스템 + 동작 동사).
- `SKILL.md`만 (결정적 grep 스크립트 **없음**). 특정 스택/프레임워크 스캐폴드 **금지**.
- eval/observability는 후보 위험도·규모에 **티어링** (전부 필수 아님, 상한 체크리스트).
- **커밋은 사용자 승인 시에만** — 아래 commit step은 스테이징·메시지 준비까지; 실제 `git commit`은 사용자 요청 시 실행 (사용자/프로젝트 commit 정책).

---

## File Structure

- **Create** `plugins/nova/skills/scout/SKILL.md` — 스킬 본문(전체 워크플로우·루브릭·출력·ledger). 단일 책임.
- **Modify** `.gitignore` — `.nova/*.json`(머신상태) 무시. scout ledger 출력에 딸림 → Task 1.
- **Modify** `README.md` — loops(5) vs capabilities 구분, `scout`·`design-direction` 등재.
- **Modify** `CLAUDE.md` — capability 한 줄 + "5 loops" 프레이밍 정정.

---

## Task 1: `scout/SKILL.md` + ledger gitignore

**Files:**
- Create: `plugins/nova/skills/scout/SKILL.md`
- Modify: `.gitignore` (repo root)

**Interfaces:**
- Consumes: 없음 (스킬은 자족적).
- Produces: `/scout` 명령 · 산출 `docs/specs/<slug>-agent-design.md` · ledger `.nova/scout-candidates.json`. (Task 2/3가 참조.)

- [ ] **Step 1: frontmatter 작성** — 아래를 그대로 파일 상단에 둔다.

```yaml
---
name: scout
description: 아무 프로젝트에서 "AI가 안전하게 행동해도 되는 자리"(사람이 반복하는 운영 판단)를 프로젝트 이해 + 짧은 인터뷰로 발굴해 적합도순으로 랭킹하고, 선택 후보를 "AI가 그대로 만들 수 있는" safe-action-agent 설계 스펙(docs/specs/<slug>-agent-design.md)으로 출력한다. 랭킹·기각 후보는 .nova/scout-candidates.json ledger에 남겨 재실행 시 복리로 발굴한다. 에이전트 실행/오케스트레이션·스택별 스캐폴드 코드는 만들지 않는다(산출은 설계까지).
when_to_use: 사용자가 /scout를 실행할 때, 또는 "여기 어디에 AI 에이전트를 붙이면 좋을지", "안전하게 자동화할 자리 찾아줘", "이 레포에 agentic하게 뭘 만들 수 있을지" 류를 물을 때.
argument-hint: "[대상 경로 또는 후보 slug (선택)]"
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Bash(git*), Bash(mkdir -p*), Task, Write
---
```

- [ ] **Step 2: body 작성** — 스펙 §3~§6을 SKILL.md 본문으로 옮긴다. 아래 섹션 순서·내용 필수:
  1. `# /scout — 에이전트 적합지 발굴 + 설계` + 1줄 목적(스펙 §1) + "도구 목적 = 최적 자동화 설계, 이력/JD 찍기 아님" 원칙(스펙 §1·§8).
  2. **`## 박제 패턴`** — 스펙 §3의 5요소(조사→제안→HITL 게이트→실행→자기검증 + eval/obs). "5요소=상한 체크리스트, 티어링" 명시.
  3. **`## 절차`** — Phase A~E(스펙 §4) 그대로:
     - A 프로젝트 이해: README·docs·매니페스트·도메인 모델·surfaces/workflows·**git 히스토리**. 큰 레포는 `Task`로 Explore 위임 + **반환 계약**(`{정체, 엔티티, workflows, git 마찰영역, seed 힌트}`).
     - B 인터뷰 3문 + **fallback**(무응답 → comprehension-only + 추정 표기).
     - C 후보 **생성** 4단계(seed 나열 → §3 5요소 투영 → 성립분 등록 → dedup).
     - D 점수→랭킹(정량) + **0-후보/HOLD-only 정직 반환**.
     - E 선택 후보 → 설계 스펙.
  4. **`## 루브릭`** — 스펙 §5 그대로: 게이트축 G1~G3(pass/fail, G1=HOLD) + 점수축 S1~S5(2/1/0 표) + `sum` 집계 + 타이브레이크(자동화가치→가역성) + 양면성 각주.
  5. **`## 출력`** — (a) 랭킹 스코어카드 포맷 / (b) 설계 스펙 템플릿 필드 + **eval·obs 티어링(저/중/고위험)** / (c) ledger + canonical slug + 재실행 diff.
  6. **`## 산출물 규칙`** — 경로 고정 `docs/specs/<slug>-agent-design.md`, **생성만·commit은 사용자**, `mkdir -p`로 디렉토리 확보, ledger `.nova/scout-candidates.json`.

- [ ] **Step 3: frontmatter 정합 검증**

Run:
```bash
cd /Users/keunsik/develop/givepro91/nova && node -e "
const fs=require('fs');const t=fs.readFileSync('plugins/nova/skills/scout/SKILL.md','utf8');
const m=t.match(/^---\n([\s\S]*?)\n---/);if(!m){console.error('NO FRONTMATTER');process.exit(1)}
for(const k of ['name:','description:','when_to_use:','argument-hint:','disable-model-invocation:','allowed-tools:']){
  if(!m[1].includes(k)){console.error('MISSING '+k);process.exit(1)}
}
console.log('frontmatter OK');
"
```
Expected: `frontmatter OK`

- [ ] **Step 4: 스펙 커버리지 자기점검** — 스펙 §3,§4(A-E),§5(게이트/점수/집계),§6(a/b/c),§7 산출규칙이 본문에 1:1로 있는지 눈으로 대조. 빠진 섹션 있으면 Step 2로 돌아가 보강.

- [ ] **Step 5: ledger gitignore 추가** — `.gitignore`에 아래 블록 추가(없으면). opt-in 마커는 무시하지 않도록 `*.json`만.

```gitignore
# Nova machine-state artifacts (ledgers/verdicts) — opt-in markers (.nova/*.on) stay committable
.nova/*.json
```

- [ ] **Step 6: gitignore 동작 확인**

Run:
```bash
cd /Users/keunsik/develop/givepro91/nova && mkdir -p .nova && : > .nova/scout-candidates.json && : > .nova/gate.on && \
git check-ignore .nova/scout-candidates.json; echo "---"; git check-ignore .nova/gate.on || echo "gate.on NOT ignored (correct)"; \
rm -f .nova/scout-candidates.json .nova/gate.on
```
Expected: `.nova/scout-candidates.json` 는 출력됨(ignored), `gate.on NOT ignored (correct)` 출력.

- [ ] **Step 7: commit 준비** (실제 commit은 사용자 승인 시)

```bash
cd /Users/keunsik/develop/givepro91/nova && git add plugins/nova/skills/scout/SKILL.md .gitignore && git status
# 메시지: feat(scout): add agent-fit discovery+design skill (+ .nova ledger gitignore)
```

---

## Task 2: Nova 문서 — loops vs capabilities 정정 + scout 등재

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Task 1의 `/scout` 존재.
- Produces: 없음(문서).

- [ ] **Step 1: README 현재 표 확인**

Run: `cd /Users/keunsik/develop/givepro91/nova && sed -n '/## The loops/,/## Install/p' README.md`
Expected: 5행 loop 표(`/worklog`까지) 확인, `design-direction`·`scout` 없음 확인.

- [ ] **Step 2: README에 capabilities 구분 추가** — 기존 "## The loops" 표는 **세션 5-loop**로 유지하고, 표 아래에 아래 섹션을 신설한다.

```markdown
## Capabilities (loop이 아닌 스킬)

| Capability | Command | What it does |
|------------|---------|--------------|
| **Discovery & Design** | `/scout` | 아무 프로젝트에서 "AI가 안전하게 *행동*할 자리"를 발굴·적합도 랭킹하고, 선택 후보를 safe-action-agent 설계 스펙으로 출력. 랭킹은 `.nova/` ledger로 compounding |
| **Design Direction** | `/design-direction` | (기존) |

> Nova = "세션을 가로질러 개발을 복리로 돕는" 플러그인. 위 5 loops는 *세션* 위에서 돌고, capabilities는 loop이 아닌 도구다.
```
(`/design-direction`의 "What it does"는 해당 SKILL.md의 description 1줄로 채운다 — Step 2b.)

- [ ] **Step 2b: design-direction 설명 채우기**

Run: `cd /Users/keunsik/develop/givepro91/nova && sed -n '1,6p' plugins/nova/skills/design-direction/SKILL.md`
그 description을 위 표 `(기존)` 자리에 1줄로 요약해 넣는다.

- [ ] **Step 3: CLAUDE.md 정정** — "## The 5 loops → 1 plugin" 근처에 capabilities가 별도임을 1줄 추가하고, `plugins/nova/{skills/*}`가 이제 loops + capabilities(`scout`·`design-direction`)를 포함함을 반영. (thesis line은 이미 2026-07-01 개정됨 — 재수정 불필요.)

- [ ] **Step 4: 정합 확인**

Run: `cd /Users/keunsik/develop/givepro91/nova && grep -n "scout\|design-direction\|Capabilities" README.md`
Expected: scout·design-direction·Capabilities 모두 등장.

- [ ] **Step 5: commit 준비** (사용자 승인 시)

```bash
cd /Users/keunsik/develop/givepro91/nova && git add README.md CLAUDE.md && git status
# 메시지: docs(nova): split loops vs capabilities, register /scout and /design-direction
```

---

## Task 3: 검증 — frontmatter 스모크 + 실 레포 dry-run + /gate

**Files:** (없음 — 검증)

**Interfaces:**
- Consumes: Task 1·2 산출.
- Produces: 검증 증거(육안 + gate ledger).

- [ ] **Step 1: 스킬 로드 스모크** — Claude Code에서 `/scout`가 인식되는지(플러그인 로컬 설치 상태) 확인. 미설치면 `/plugin marketplace add /Users/keunsik/develop/givepro91/nova` → `/plugin install nova@nova` 후 재확인.

- [ ] **Step 2: dry-run — 실제 레포에 `/scout`** — Spacewalk 제품 레포(또는 Nova 자신)에서 `/scout` 실행. 관찰 체크리스트:
  - Phase A 이해 요약이 실제 프로젝트를 맞게 파악했는가.
  - 후보가 §3 5요소로 성립하는가(억지 후보 아님).
  - 랭킹 스코어카드가 G1~G3 + S1~S5 + 합계 + 이유로 나오는가.
  - 산출이 `docs/specs/<slug>-agent-design.md`에 생성만 되고 자동 commit 안 하는가.
  - ledger `.nova/scout-candidates.json`가 생기는가.

- [ ] **Step 3: 재실행 diff 확인** — 같은 레포에 `/scout` 2회차 실행 → "신규/점수변화/기각유지" diff가 이전 ledger 기준으로 뜨는지. slug canonical로 같은 후보가 '가짜 신규'로 안 뜨는지.

- [ ] **Step 4: 산출물 정직성 — Nova `/gate`** — 생성된 설계 스펙에 대해 `/gate` 실행 → 미검증 가정이 정직히 표기됐는지, eval/obs 티어링이 후보 규모에 맞는지 독립 검증.

- [ ] **Step 5: 결과 기록** — 발견된 N1~N5류 미세 틈(있으면) SKILL.md에 1~2줄 흡수, 필요시 handoff에 기록.

---

## Self-Review (plan vs spec)

- **Spec coverage:** §3→Task1 Step2.2 / §4 A-E→Step2.3 / §5→Step2.4 / §6 a·b·c→Step2.5 / §7 산출·gitignore→Task1 Step5·Task2 / §8 YAGNI→frontmatter+Global Constraints / §9·§10 리스크·검증→Task3. 갭 없음.
- **Placeholder scan:** `(기존)`은 Step 2b에서 실제 description으로 치환하도록 명시 — placeholder 아님. 그 외 TBD/TODO 없음.
- **Type consistency:** 경로·명령 일관 — `docs/specs/<slug>-agent-design.md`, `.nova/scout-candidates.json`, `.nova/*.json`, allowed-tools 6종이 Task 전체에서 동일 문자열.
