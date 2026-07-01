---
title: Nova /scout — 에이전트 적합지 발굴 + 설계 스킬
status: SHIP (critic 재검토 SHIP · 구현 착수 가능)
date: 2026-07-01
author: Jay (givepro91)
revision: 3 (재검토 SHIP + N1~N5 미세 흡수)
---

# Nova `/scout` — 에이전트 적합지 발굴 + 설계 스킬 (설계 스펙)

## 1. 한 줄 정의

아무 프로젝트에 들어가서, **"AI가 안전하게 *행동*해도 되는 자리"**(= 사람이 반복하는 운영 판단)를
*프로젝트 이해 + 짧은 인터뷰*로 찾아 **적합도순으로 랭킹**하고, 선택된 후보를
**AI가 그대로 만들 수 있는 설계 스펙**으로 떨궈주는 Nova 스킬.

박제하는 것은 하나의 설계 사고다 — *생성/검증 분리 · 승인 게이트(HITL) · 운영을 내부 제품으로*.
도구의 목적은 **그 프로젝트에 가장 맞는 자동화를 설계**하는 것이지, 특정 이력/JD 역량을 찍는 게 아니다.
(그 설계를 잘 하면 "agentic 제품" 역량이 증명되는 것은 *부수효과*일 뿐, 필드 선택의 동기가 아니다.)

## 2. 배경 & Nova 안에서의 위치

- Nova는 "내(Jay) 개발을 세션을 가로질러 복리로 돕는 플러그인"이고, mission은 "keeping(상태 보존)"에
  갇히지 않는다 (CLAUDE.md thesis 2026-07-01 개정 반영). `/scout`는 **세션 5-loop이 아니라 capability**다.
  - **loops (세션 위 5개):** rules(`/claude-md`) · learning(`/learn`) · continuity(`/handoff`) ·
    verification(`/gate`) · record(`/document`↔worklog).
  - **capabilities (loop이 아닌 스킬):** `design-direction`(기존, 현재 README 미기재) · **`scout`(신규)**.
  - ⇒ README/CLAUDE의 "5 loops" 프레이밍은 이미 낡음. §7에서 loops/capabilities를 분리해 정정한다.
- **바이브코딩 시대 전제:** 코드는 점점 AI가 양산한다 → (a) 깔끔한 코드 *패턴*보다 **의도**
  (README·docs·커밋·사람 머릿속)가 후보의 진실이고, (b) 산출물은 *"AI가 그대로 만들 수 있는 설계 스펙"*
  이 정답이다.
- 이식성 최우선: 특정 스택·언어·프레임워크 비종속. 어떤 레포에서도 동작.

## 3. 스킬이 박제하는 패턴 — canonical "safe-action-agent" shape

`/scout`는 이 형태를 **후보 생성 렌즈이자 설계 골격**으로 쓴다:

1. 사람이 반복하는 **운영 판단** 1개를 대상으로.
2. 에이전트가 여러 시스템에서 **맥락 조사**(tool use) → **행동안 + 확신도/위험도** 제시.
3. **승인 게이트(HITL):** 저위험 자동 / 고위험 사람 승인.
4. 실행 + **자기검증**.
5. **eval + observability.** — 단, 이 5요소는 **상한(ceiling) 체크리스트지 전부 필수가 아니다.**
   후보의 위험도·규모에 맞춰 **티어링**한다(§6). 작은 read-only 자동화에 엔터프라이즈급 eval/obs를
   강제하지 않는다(도구 자신의 YAGNI를 후보 산출 스펙에도 적용).

## 4. 워크플로우 (스킬 호출 시)

### Phase A — 프로젝트 이해 (comprehension, *not* grep)
얕은 신호 스캔이 아니라 **프로젝트가 무엇을 하는지 이해**한다. 입력: README·docs·매니페스트 /
도메인 모델(schema·types) / surfaces·workflows(라우트·잡·CLI·외부연동) / **git 히스토리·커밋**.
- 큰 레포는 **Explore 서브에이전트로 위임**(메인 컨텍스트 보존, 깊이 적응형).
- **Explore 반환 계약(고정 구조):** `{ 프로젝트 정체(도메인·사용자), 도메인 엔티티, surfaces/workflows 목록,
  git 마찰 영역(파일·재방문빈도·메시지 신호), 후보 seed 힌트 }`. 이 구조로 받아 Phase C에 먹인다.

### Phase B — 짧은 인터뷰 (3문, tacit knowledge)
1. 사람이 **반복해서 손으로 판단/처리하는 일**은?
2. **틀리면 비싼**(오류비용) 결정은? *(→ S3 자동화 가치의 오류비용 성분; 빈도·수작업 성분은 Q1·Q3)*
3. 지금 **누가 어떤 도구로** 하나?
- **Fallback:** 도메인을 아는 사람이 없어 인터뷰가 비면, **comprehension-only로 진행**하되 모든 후보를
  *추정(unverified)* 으로 표기.

### Phase C — 후보 *생성* (§3을 generation lens로) + dedup
방법을 명문화한다(암묵 즉흥생성 금지):
1. **seed 나열:** 인터뷰 답 + git-마찰 영역 + surfaces/workflows를 후보 seed로 모은다.
2. **투영:** 각 seed를 §3의 5요소 형태에 투영해 *"safe-action-agent로 성립하는가"* 판정.
   (기존 코드에 없어도 됨 — *있어야 할* 워크플로우도 seed가 될 수 있다.)
3. **등록:** 성립분만 후보로 등록.
4. **dedup:** 같은 운영 판단이 입도만 다르게 여러 후보로 잡히면, **행동 가능한 입도의 것 하나로 병합**
   (나머지는 sub-scope로 각주).

### Phase D — 적합도 점수 → 랭킹 (정량)
각 후보를 §5 루브릭으로 **점수화**하고 **점수 근거와 함께** 랭킹한다(§6 랭킹 포맷).
- **0-후보 정직 반환:** 채점 가능한 후보(G2·G3 통과)가 하나도 없으면 **억지 Top-1을 만들지 말고**
  *"적합 후보 없음 + 이유(평가불가/무통제/수단없음)"* 반환. **보류(HOLD)만 남은 경우**는 "없음"이 아니라
  *"eval 셋 확보 시 유망 — 보류 후보 N건"* 으로 구분 반환한다.

### Phase E — 선택 후보 → 설계 스펙
Top-1(또는 사용자가 고른 후보)을 §6 설계 스펙 문서로 출력.

## 5. 적합도 루브릭 (= "적합한 걸 찾기"의 알맹이)

**게이트 축 (pass/fail — 하나라도 fail이면 탈락 또는 '보류' 표기):**
- **G1 평가 가능** — 신뢰성 측정용 ground truth(과거 사례/정답)를 만들 수 있는가? (전무 → 보류)
- **G2 안전 통제** — 되돌릴 수 있거나 승인 게이트로 통제 가능한가? (비가역·무통제 → 탈락)
- **G3 행동 수단 존재 가능** — 최소한 상상 가능한 도구/API가 있는가? (전무 → 탈락)
- **보류(G1 fail) 처리:** G2·G3는 통과했는데 G1만 fail이면 **탈락이 아니라 보류** — 채점·랭킹에 포함하되
  스코어카드에 `HOLD(ground-truth 부재)` 플래그, Top-1로 선택되면 **'eval 셋 확보'를 선결 리스크로 강제.**

**점수 축 (G2·G3 통과 후보 채점 · G1-fail은 HOLD로 채점 · 각 2/1/0 · 점수마다 이유 1줄 강제):**
| 축 | 2 | 1 | 0 |
|---|---|---|---|
| S1 반복성·빈도 | 자주 | 가끔 | 드묾 |
| S2 판단 밀도 | 재량·맥락 필요 | 일부 | 순수 기계작업(→스크립트) |
| S3 자동화 가치 (건당 절약 또는 회피 오류비용)×빈도 | 큼 | 중 | 미미 |
| S4 행동수단 성숙도 | 현존 API/시스템 | 구축 필요(+비용을 리스크로) | — (0은 G3서 탈락) |
| S5 입출력 명확성 | MVP로 떨어짐 | 다소 모호 | 경계 불명 |

- **집계:** `sum(S1..S5)` 내림차순 랭킹. **동점 타이브레이크:** ① 자동화 가치(S3) → ② 가역성(되돌리기 쉬움) 정도.
- *양면성 각주:* '고위험·비가역'은 S3(가치)를 올리면서 G2/타이브레이크(안전)를 낮춘다 — 의도된 상반 신호.
- 원칙: **판단 없는 반복 = 스크립트**, **평가 불가 = 보류**, **행동 수단 없음 = 탈락**.

## 6. 출력 (2종 + ledger)

### (a) 랭킹 스코어카드 (사용자에게 표시)
후보별 한 줄: `후보 slug | G1·G2·G3 pass/fail | S1..S5 점수 | 합계 | 한 줄 이유`. 내림차순.

### (b) 설계 스펙 문서 `docs/specs/<slug>-agent-design.md`
필드: **컨텍스트**(Phase A 이해 요약) / **문제·대상 사용자** / **에이전트 책임 vs 사람 책임(HITL 경계)** /
**도구 목록**(read·write·위험도) / **state·플로우** / **승인 게이트 규칙** /
**eval 셋**(아래 티어링) / **observability 지표**(아래 티어링) / **MVP 스코프 + 비-목표(YAGNI)** /
**미검증 가정·리스크**.

- **eval/obs 티어링 규칙 (M4):**
  - *저위험 read-only/조회형:* 작은 golden set + 정확도/승인율. (regression·LLM-judge·prod feedback는 **N/A 명시** 또는 필요 시)
  - *중위험 write·가역:* + regression + LLM-judge + trace·cost·latency.
  - *고위험/비가역 근접:* 전체 5요소 + human eval + production feedback loop.
  - §3 5요소는 상한 — 후보가 요구하지 않는 항목은 **"N/A + 이유"** 로 정직하게 비운다.

### (c) ledger `.nova/scout-candidates.json` (compounding)
랭킹·선택·기각 후보를 `[{slug, 점수, gate판정, 선택여부, ts}, ...]` 로 기록.
재실행 시 **이전 ledger 로드 → diff**("신규 후보 N / 점수 오른 후보 / 기각 유지")를 보여줘
프로젝트가 진화할수록 발굴이 복리가 되게. (ts는 스킬 실행 시점 주입.)
- **slug는 canonical 규칙**(대상 시스템 + 동작 동사 — 예: `orders-refund`, `onboarding-grant`)으로 생성 —
  LLM 재명명으로 같은 판단이 '가짜 신규 후보'로 뜨는 것을 막는다. diff는 canonical slug + 의미 매칭.

## 7. Nova 통합 (구조 · 컨벤션)

- 위치: `plugins/nova/skills/scout/SKILL.md` — **SKILL.md만**(결정적 grep 스크립트 없음).
  스캔/이해는 내장 검색도구 + Explore 서브에이전트로.
- frontmatter(Nova 컨벤션): `name: scout` / `description` / `when_to_use` / `argument-hint` /
  `disable-model-invocation` / `allowed-tools`
  = **Read, Glob, Grep, Bash(git*), Bash(mkdir -p*), Task, Write**. (`mkdir -p` = `docs/specs/`·`.nova/` 생성용.)
- 호출: `/scout` · 사용자 응답 **한국어** · 브랜드 violet.
- **산출물 정책:** 설계 스펙 = `docs/specs/<slug>-agent-design.md`(경로 고정) · **파일 생성만, commit은 사용자에게**
  (Jay CLAUDE.md의 자동 commit 금지 준수). ledger = `.nova/scout-candidates.json`.
- **문서 갱신(m2):** README/CLAUDE에서 **loops(5)와 capabilities를 분리**하는 섹션 신설 —
  `scout` + 기존 `design-direction`을 capability로 등재, "5 loops" 표현 정정. (scout 구현에 딸린 최소 정정.)
- **`.gitignore`:** `.nova/`의 **머신 상태 산출물만** 무시(`.nova/*.json` — `scout-candidates.json`·`gate-verdict.json` 등).
  `.nova/gate.on` 같은 **opt-in 마커는 팀 공유를 위해 커밋 가능해야 하므로 통짜 무시하지 않는다.**

## 8. 비-목표 (YAGNI)

- ❌ 에이전트 **실행/오케스트레이션**(런타임) — 산출은 *설계 문서*까지.
- ❌ **스캐폴드 코드 생성**(LangGraph 등) — 스택 종속 회피, 이식성 우선.
- ❌ eval **자동 실행** — eval *셋 설계*까지.
- ❌ 결정적 신호-스캔 스크립트(초기 불필요).
- ❌ 특정 이력/JD 역량을 찍는 것을 필드 선택 동기로 삼기(§1).

## 9. 미검증 가정 · 리스크

- 큰/모노레포 comprehension 비용 → Explore 위임 + 적응형 깊이로 완화(검증 필요).
- AI-양산 코드라 도메인 모델이 흐릴 수 있음 → 인터뷰·커밋 히스토리로 보완.
- **AI 자동 커밋 환경에선 "manual/hotfix" 류 메시지 신호가 약함(m6)** → **파일 변경 빈도·재방문**,
  PR/이슈 본문, 인터뷰로 보강.
- "있어야 할 워크플로우" 제안이 과한 추론이 될 위험 → 스펙 §미검증 가정 섹션 + 후보 *추정* 표기 필수.
- 루브릭 점수의 주관성 → 게이트/점수 축 분리(§5) + 점수마다 이유 강제로 완화(완전 제거는 불가; Phase E HITL이 최종 방어).

## 10. 검증 계획

- SKILL.md frontmatter/구조가 Nova 기존 스킬(gate 등)과 정합(스모크).
- 실제 레포 1~2곳(Spacewalk 제품 / Nova 자신)에 `/scout` 돌려 후보·랭킹·스펙 품질 육안 검증.
- 산출 스펙을 Nova `/gate`로 점검 — 미검증 가정이 정직하게 표기됐는지.
- ledger diff가 재실행에서 실제로 동작하는지(2회 실행) 확인.
