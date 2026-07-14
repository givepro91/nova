---
title: Nova 공유 팀 규칙 실행 스펙
status: design-locked-rollout-unapproved
date: 2026-07-13
schema_proposal: nova.team-rules/v1
---

# 공유 팀 규칙 실행 스펙

## 판단층

### TL;DR

승인된 팀 규칙의 canonical 경로는 `.nova/team-rules.md`로 잠근다. 파일에는 `active`와 `retired` 규칙만 남기고, 제안과 충돌은 승인 전에 공유 파일을 바꾸지 않는다. 원본 gate ledger와 명령 출력은 machine-local로 유지하며, 팀에는 비식별 요약과 allowlist 형식의 참조만 공유한다.

이 문서는 아티팩트 경계, 상태 전이, 결정성, 프라이버시 불변조건을 하나의 실행 스펙으로 통합한다. 현재 상태는 설계 확정이며, `.nova/.gitignore`의 allowlist 변경, 스킬 연결, 스키마 배포는 별도 사용자 승인 전에 실행하지 않는다.

### 한 일

- 팀 추적 파일과 machine-local 파일의 경계를 경로 단위로 정했다.
- 최소 필드, 안정적 ID, 문자열 정규화, 정렬, tie-break 규칙을 고정했다.
- `merge`, `generalize`, `retire`, `promote`, `conflict`의 전제조건과 허용 전이를 표로 정리했다.
- 중복, 충돌, 범위 변경을 승인 전에는 적용하지 않는 fail-closed 절차를 정했다.
- raw ledger의 ignore와 index 비추적을 별도로 검사하고, 승인 입력을 전이 ID 하나에 결박했다.

### 남은 결정

- `.nova/team-rules.md`를 Git 추적 allowlist에 추가하는 스키마 도입을 승인할지 결정해야 한다.
- 기존 Self-Learning Rules를 새 아티팩트로 옮길지, 신규 승인분부터 사용할지 배포 시점에 고르셔야 한다.
- 승인자로 기록할 비식별 공개 alias의 배정표는 아티팩트 밖에서 팀이 관리해야 한다.

## 엔지니어링 기록층

### 범위와 비목표

이 설계는 Git을 사용하는 임의의 공개 저장소에서 작동할 팀 규칙 아티팩트만 다룬다. 구현 코드, 자동 commit, push, 배포, 중앙 서버, 회사 내부 서비스는 범위에 포함하지 않는다. 기존 개인 `/learn` 동작도 이 스펙에서 바꾸지 않는다.

이 스펙은 승인 후 구현자가 따를 규범 계약이다. 문서 현재 상태에서는 아티팩트나 fixture를 생성하지 않으며, hook, script, skill, ignore 로직을 변경하지 않는다. 승인 후에도 개별 규칙 전이는 Locked decision 9의 승인과 별개로 자동 commit, push, 배포를 허용하지 않는다.

### Locked decision 1. canonical 경로는 하나다

- 승인된 공유 아티팩트는 저장소 루트의 `.nova/team-rules.md`다.
- 동일 내용을 `CLAUDE.md`, `AGENTS.md`, 다른 `.nova/` 파일에 복제하지 않는다.
- 미승인 제안과 충돌 보고는 세션 응답과 process memory에서만 다룬다. 저장소 내 임시 파일이나 canonical 파일에 쓰지 않는다.
- 아티팩트는 팀이 명시적으로 opt-in한 저장소에서만 만든다. 미사용 프로젝트에는 파일 생성이나 세션 context tax가 없다.

canonical 파일이 없으면 읽기 단계에서만 `revision: 0`, count 0개, 규칙과 전이 0개인 virtual empty state로 해석한다. 이 상태는 파일로 쓰지 않는다. 첫 전이가 승인되면 `.nova/team-rules.md`를 revision 1의 완전한 template로 한 번에 생성한다. 파일이 이미 있지만 schema나 필수 필드가 잘못되었으면 empty state로 대체하지 않고 fail-closed 처리한다.

### Locked decision 2. 공유 파일은 Markdown 외피와 canonical JSON 레코드를 쓴다

Markdown는 판단층과 리뷰 편의를 담당한다. fenced JSON 레코드는 구현체가 재해석하지 않도록 필드와 키 순서를 고정한다. 임의의 Markdown 문장은 상태 판정의 입력으로 쓰지 않는다.

파일은 아래 literal template의 공백, 빈 줄, heading, fence, 표 구분행을 그대로 쓴다.

````markdown
---
schema: nova.team-rules/v1
revision: <revision>
active_count: <active_count>
retired_count: <retired_count>
---

# 팀 규칙

## 판단층

### TL;DR

현재 revision은 <revision>이며 active 규칙은 <active_count>개, retired 규칙은 <retired_count>개다.

### 한 일

| ID | 범위 | 규칙 | 예외 |
|---|---|---|---|
<active-summary-rows>

### 남은 결정

없음. 미승인 제안과 conflict는 이 파일에 기록하지 않는다.

## 엔지니어링 기록층

### Active

<active-rule-blocks>
### Retired

<retired-rule-blocks>
### Transition ledger

<transition-blocks>
````

summary row는 `| <escaped-id> | <escaped-compact-scope-json> | <escaped-statement> | <escaped-compact-exceptions-json> |`를 쓴다. ID 순으로 정렬하고 row 사이에 빈 줄을 두지 않는다. active 규칙이 없으면 `<active-summary-rows>`를 `| — | — | 현재 active 규칙이 없다. | [] |`로 바꾼다. 네 cell은 모두 같은 `escape-cell` 함수를 거친다. 입력 문자열의 backslash를 `\\`로 먼저 바꾼 뒤 `|`를 `\|`로 바꾼며, JSON cell은 compact JSON으로 직렬화한 결과에 이 함수를 적용한다. 이렇게 모든 cell을 같이 처리해야 scope path나 exception의 `|`가 표 열을 바꾸거나 backslash 표현이 실행자마다 달라지지 않는다.

각 rule block은 다음 literal block을 쓴다. `<rule-json>`은 공백 2개로 들여쓴 canonical rule object로 바꾼다.

````markdown
#### <rule-id>

```json
<rule-json>
```

````

transition block도 같은 형태에서 heading을 `#### <transition-id>`로, 내용을 canonical transition object로 바꾼다. block은 ID 순으로 정렬한다. 빈 block placeholder는 빈 문자열로 바꾸어 섹션 heading 사이에 템플릿의 빈 줄 하나만 남긴다. 문서 끝에는 LF 하나만 남긴다.

`revision`은 승인된 원자적 전이 한 번당 1씩 증가한다. count 필드는 레코드에서 결정적으로 도출하며, 수동 수정으로 건너뛰거나 줄이지 않는다.

제안은 파일에 저장하지 않지만 결정적 처리를 위한 `nova.team-rule-proposal/v1` envelope를 쓴다. 키 순서는 `schema`, `state`, `id`, `base_revision`, `base_state_hash`, `operation`, `candidates`, `requests`, `targets`, `inputs`, `outputs`, `before`, `after`, `scope_impact`, `reason`, `evidence_refs`, `options`다. `state`는 `proposed`, `conflict`, `approved`, `rejected` 중 하나고 `scope_impact`는 `none`, `expand`, `narrow`, `mixed` 중 하나다.

proposed, approved, rejected 제안의 `id`는 `tx-sha256-` ID고 `operation`은 허용된 전이다. 이 경우 `options`는 `[]`다. conflict 제안의 `id`는 `cf-sha256-` + 64자 소문자 hex고 `operation`은 `null`이다. conflict ID는 `schema`, `envelope` 순서의 wrapper에 `schema: "nova.team-rule-conflict.identity/v1"`과 `id`를 제외한 canonical envelope를 담아 compact JSON으로 직렬화한 SHA-256이다. envelope의 `state`는 항상 `conflict`고 option ID까지 계산한 뒤 conflict ID를 계산한다.

`targets`는 영향받는 기존 `tr-` ID만 담는 정렬된 배열이다. promote처럼 기존 규칙이 없으면 `[]`다. proposed envelope의 `inputs`, `outputs`, `before`, `after`는 전이 레코드에 쓸 값과 같다. conflict envelope의 `inputs`는 candidate, request, target ID의 정렬된 합집합이고 `before`는 target 규칙 snapshot을 ID로 정렬한 배열이며, `outputs`와 `after`는 `[]`다. 선택지별 영향은 `options`에만 둔다.

`candidates`에는 전체 batch가 아니라 해당 proposal group이나 conflict component의 candidate 레코드만 넣고 ID로 정렬한다. promote는 신규 후보 1개, merge는 active 입력 투영 N개, generalize는 active 입력 투영 N개와 신규 후보 1개를 넣는다. retire와 rephrase는 target 투영 1개, replace-scope는 target 투영과 신규 후보를 넣는다. conflict는 component에 속한 candidate를 전부 넣는다.

`requests`에는 해당 group이나 conflict component에 속한 명시적 수명주기 요청만 넣고 request ID로 정렬한다. 요청이 없으면 `[]`다. 요청 레코드의 키 순서는 `id`, `operation`, `targets`, `requested_scope`, `requested_statement`, `source_dispositions`, `replaced_by`, `reason`, `evidence_refs`다. 해당 없는 값은 `null`이나 `[]`로 남겨 입력 생략 방식이 해시를 바꾸지 못하게 한다.

conflict option은 canonical 전이를 직접 만들지 않는다. option 레코드의 키 순서는 `id`, `decision`, `members`, `impact`다. `members`는 conflict component의 candidate, request, target ID를 합집합해 정렬한 배열이다. `decision`은 `keep-existing` 또는 `revise-input`만 허용한다.

option ID는 `schema`, `option` 순서의 wrapper에 `schema: "nova.team-rule-conflict-option.identity/v1"`과 `id`를 제외한 option을 담아 compact JSON으로 직렬화한 SHA-256 앞에 `to-sha256-`를 붙인 값이다. conflict마다 두 option을 모두 생성하고 option ID로 정렬한다. `impact`는 각각 `기존 active 규칙을 유지하고 이 conflict 후보를 적용하지 않음`, `기존 active 규칙을 유지하고 보완된 입력으로 새 제안을 생성함`이라는 literal을 쓴다. 어느 option도 canonical diff나 transition ID를 만들지 않는다.

후보 레코드의 키 순서는 `id`, `origins`, `scope`, `trigger_key`, `action_key`, `effect`, `statement`, `exceptions`, `evidence_refs`, `equivalent_to`, `conflicts_with`, `generalizes`, `source_dispositions`다. `origins`는 `gate`, `personal`, `active-rule` 중 하나 이상을 이 literal 순서로 정렬한 배열이고 관계 필드는 ID 배열이다.

생성 정보의 digest가 canonical active 규칙과 일치하면 후보 투영은 기존 `tr-sha256-` ID를 유지한다. 일치하는 active 규칙이 없을 때만 신규 후보에 `tc-sha256-` prefix를 쓴다. 같은 digest의 retired 규칙이 있으면 재활성화 금지 conflict다. 신규 후보가 승인되면 같은 digest의 `tr-sha256-` ID를 사용한다.

`equivalent_to`는 생성 정보가 다른 두 규칙이 같은 행동 의미를 가진다는 명시적 판단만 담는다. `source_dispositions` 항목의 키 순서는 `id`, `status`이며 status는 `active` 또는 `retired`다. 항목은 `id`의 UTF-8 byte 오름차순으로 정렬하고 동일한 `(id,status)`는 하나로 접는다. 같은 `id`에 서로 다른 `status`가 있으면 어느 항목도 소거하지 않고 두 변형을 canonical compact JSON byte 순으로 conflict envelope에 보존한 뒤 `source-disposition-invalid`로 보낸다. generalize 후보에서는 `generalizes`의 모든 원본 ID를 정확히 한 번씩 포함해야 한다. 누락, 중복, 관계 모순은 conflict다. 이 순서를 고정해야 원본 처분 입력 순서가 candidate byte와 제안 ID를 바꾸지 않는다.

같은 신규 후보 ID의 `origins`, 근거, 관계는 합집한다. 신규 후보끼리 정규화된 `statement`가 서로 다르면 lexical 최소값으로 소거하지 않고, 모든 변형을 canonical compact JSON byte 순으로 보존한 `id-collision` conflict로 보낸다. `statement`가 모두 같을 때만 하나로 접는다. canonical active 투영과 같은 ID인 후보는 명시적 `rephrase` request가 없으면 active의 `statement`를 유지하고 후보의 다른 문장으로 canonical을 바꾸지 않는다. 같은 target에 대한 `source_dispositions`의 status가 다르면 합집하지 않고 `source-disposition-invalid` conflict로 보낸다. `gate`와 `personal` 적격성은 각 origin의 근거만으로 따로 계산하고 둘 중 하나가 기준을 통과할 때만 promote 후보로 유지한다.

canonical active 규칙의 candidate 투영은 `origins: ["active-rule"]`와 해당 규칙의 생성 정보, `statement`, `evidence_refs`를 쓴다. proposal 판정용 `equivalent_to`, `conflicts_with`, `generalizes`, `source_dispositions`는 모두 `[]`에서 시작해 normalized batch에 명시된 값만 투영한다. canonical 이력인 `relations`를 proposal 관계로 되살리지 않는다.

관계 필드는 위 ID 투영을 마친 뒤의 `tr-` 또는 `tc-` ID만 참조한다. 후보의 `generalizes`에 `tc-` ID가 있으면 승인된 규칙에서 같은 digest의 `tr-` ID로 바꾼다. `equivalent_to`와 `conflicts_with`는 제안 판정에만 쓰고 canonical rule relation에 복사하지 않는다. 사람이 승인하기 전에는 어느 신규 후보도 공유 규칙으로 간주하지 않는다.

### Locked decision 3. 규칙과 전이의 최소 필드를 고정한다

규칙 레코드의 키는 다음 순서를 쓴다. 이 필드 집합이 `nova.team-rules/v1`의 최소 계약이다.

| 필드 | 제약 | 의미 |
|---|---|---|
| `id` | `tr-sha256-` + 64자 소문자 hex | 생성 후 불변 ID |
| `status` | `active` 또는 `retired` | 공유 규칙의 수명주기 |
| `scope` | 정렬된 비어 있지 않은 배열 | 규칙이 적용되는 저장소 범위 |
| `trigger_key` | 소문자 ASCII dotted key | 규칙을 적용할 상황 |
| `action_key` | 소문자 ASCII dotted key | 요구하거나 금지할 행동 |
| `effect` | `require` 또는 `forbid` | 행동에 대한 방향 |
| `statement` | 정규화된 한 줄 문장 | 사람이 읽는 canonical 규칙 |
| `exceptions` | 정렬된 문자열 배열 | 적용 예외, 없으면 `[]` |
| `evidence_refs` | 정렬된 참조 배열 | 정제된 근거 참조 |
| `transition_refs` | 정렬된 전이 ID 배열 | 규칙에 영향을 준 승인 이력 |
| `relations` | 고정 키를 갖는 object | 병합, 일반화, 대체 관계 |
| `retirement` | object 또는 `null` | 폐기 사유와 대체 규칙 |

`relations`의 키 순서는 `merged_from`, `generalizes`, `specializes`다. 각 값은 정렬된 ID 배열이다. `retirement`는 active일 때 `null`이다. retired일 때는 `reason`, `replaced_by`를 두며 `replaced_by`는 ID 또는 `null`이다.

전이 레코드의 키 순서는 다음과 같다.

| 필드 | 제약 | 의미 |
|---|---|---|
| `id` | `tx-sha256-` + 64자 소문자 hex | 전이 내용의 안정적 ID |
| `operation` | `promote`, `merge`, `generalize`, `retire`, `replace-scope`, `rephrase` | 수명주기 작업 |
| `base_revision` | 0 이상 정수 | 제안이 읽은 기준 버전 |
| `base_state_hash` | `sha256-` + 64자 소문자 hex | 제안이 읽은 full canonical state |
| `inputs` | 정렬된 `tr-` 또는 `tc-` ID 배열 | 전이 이전 규칙이나 후보 |
| `outputs` | 정렬된 ID 배열 | 전이 이후 규칙 |
| `before` | ID 순으로 정렬된 snapshot 배열 | 승인 직전 상태와 내용 |
| `after` | ID 순으로 정렬된 snapshot 배열 | 승인 직후 상태와 내용 |
| `reason` | 정규화된 한 줄 문장 | 전이를 선택한 사유 |
| `evidence_refs` | 정렬된 참조 배열 | 정제된 근거 |
| `approval` | 고정 형식 object | 사람 승인과 공개 안전성 확인 |

snapshot의 키 순서는 `id`, `status`, `scope`, `content_hash`다. `content_hash`는 규칙 레코드의 `scope`, `trigger_key`, `action_key`, `effect`, `statement`, `exceptions`, `evidence_refs`, `relations`, `retirement`을 canonical compact JSON으로 직렬화한 SHA-256다. 표현은 `sha256-` + 64자 소문자 hex다. `transition_refs`는 자기 참조 순환을 막기 위해 content hash에서 제외한다.

`inputs`, `outputs`, `before`, `after`는 전체 아티팩트가 아니라 해당 전이가 영향을 주는 규칙과 후보만 담는다. operation별 cardinality는 다음과 같다.

| operation | `inputs` | `outputs` | `before` | `after` |
|---|---|---|---|---|
| `promote` | `tc` 1개 | 새 `tr` 1개 | `[]` | 새 `tr` snapshot 1개 |
| `merge` | active `tr` N개, N≥2 | 같은 `tr` N개 | 입력 snapshot N개 | canonical active 1개와 retired N-1개 |
| `generalize` | active `tr` N개와 새 `tc` 1개, N≥2 | 원본 `tr` N개와 새 `tr` 1개 | 원본 snapshot N개 | 원본과 새 규칙 snapshot N+1개 |
| `retire` | active `tr` 1개 | 같은 `tr` 1개 | active snapshot 1개 | retired snapshot 1개 |
| `replace-scope` | active `tr` 1개과 새 `tc` 1개 | 기존 `tr` 1개과 새 `tr` 1개 | 기존 active snapshot 1개 | 기존 retired와 새 active snapshot 2개 |
| `rephrase` | active `tr` 1개 | 같은 `tr` 1개 | 기존 statement snapshot 1개 | 새 statement snapshot 1개 |

`targets`는 `before`에 든 기존 `tr` ID와 같다. `outputs`는 `after`에 든 규칙 ID와 같다. 이 두 불변조건을 어기는 제안은 malformed로 거부한다.

`approval`의 키 순서는 `actor`, `decision_ref`, `privacy_reviewed`다. `actor`는 승인자가 직접 제공한 비식별 공개 alias며 `^[a-z0-9][a-z0-9._-]{0,63}$`를 따른다. 이메일, 실명, 계정 ID는 기록하지 않고 alias와 개인의 대응표도 아티팩트에 두지 않는다. `decision_ref`는 같은 공개 저장소에서 검증 가능한 `git` 또는 `doc` evidence ref 문자열 하나로 한정하며 없으면 `null`을 쓴다. issue, PR, 회의록을 참조하려면 그 결정을 먼저 공개 Git commit이나 doc blob으로 정제한다. `privacy_reviewed`는 승인자가 최종 after byte preview의 SHA-256을 지정해 raw evidence와 식별 정보가 없음을 확인한 뒤에만 기록하는 literal `true`다. 누락, `false`, 다른 type은 승인 부재로 처리한다.

timestamp, 서명, 이메일, 자유 서술 comment는 최소 승인 기록에 넣지 않는다. 전이 레코드 자체가 승인 대상 `id`를 포함하므로 approval object에 ID를 중복하지 않는다. commit author와 승인자가 다르더라도 파일의 alias가 승인자 표기로 남는다.

### Locked decision 4. 범위 문법은 겹침을 결정적으로 계산할 수 있어야 한다

`scope`는 다음 세 선택자만 허용한다.

- `repo`: 저장소 전체
- `path:<path>`: 정규화된 정확한 파일 하나
- `tree:<directory>`: 정규화된 디렉터리와 그 하위

중복 slash를 하나로 줄인 후 절대 경로, 빈 경로, 끝 slash, `..`, `.` 세그먼트, 역슬래시, wildcard는 거부한다. 경로는 symlink를 풀거나 파일시스템에 문의하지 않고 NFC 정규화된 repo-relative POSIX 문자열을 case-sensitive UTF-8 byte로 비교한다. `repo`는 모든 범위와 겹친다. 동일 path는 서로 겹치며, path가 tree 하위에 있으면 겹친다. 두 tree는 한쪽이 다른 쪽의 디렉터리 세그먼트 prefix인 경우에만 겹친다.

scope 정규화는 경로 범위가 같은 중복 선택자를 제거한다. `repo`가 있으면 다른 선택자를 모두 제거한다. 부모 tree가 있으면 하위 tree와 하위 path를 제거한다. 결과가 빈 배열이면 schema error로 거부한다.

선택자 포함은 다음과 같다. `repo`는 모든 선택자를 포함하고, tree는 같은 디렉터리나 하위 tree와 path를 포함하고, path는 동일한 path만 포함한다. 정규화 scope 집합 `X`가 `Y`의 부분집합인지는 `X`의 모든 선택자를 포함하는 `Y` 선택자가 각각 하나 이상 있는지로 판정한다. 이 검사는 실제 파일 목록을 열거하지 않는다.

범위 확대는 기존 선택자 집합보다 더 많은 경로를 포함하는 변경이다. 범위 축소는 기존 집합의 진부분집합으로 변경하는 경우다. 두 경우 모두 사람 승인이 필요하다.

proposal의 `scope_impact`는 해당 전이에 관여하는 active `before` snapshot의 scope coverage 합집 `B`와 active `after` snapshot의 scope coverage 합집 `A`로 계산한다. retired snapshot은 합집에서 제외하며 빈 쪽은 공집합이다. 각 쪽의 모든 selector를 한 번 합친 뒤 scope 정규화의 중복·부모 selector 제거를 다시 적용한다. `A = B`는 배열 byte 동일성이 아니라 `A ⊆ B`와 `B ⊆ A`가 모두 참인 coverage 동등을 뜻한다. 진부분집합은 한 방향 포함만 참일 때다. 이렇게 coverage로 비교해야 여러 규칙에 나뉘어 표현된 부모·하위 scope가 의미상 같은 변경을 `mixed`로 잘못 분류하지 않는다.

- `A = B`면 `none`
- `B`가 `A`의 진부분집합이면 `expand`
- `A`가 `B`의 진부분집합이면 `narrow`
- 어느 쪽도 다른 쪽의 부분집합이 아니면 `mixed`

따라서 promote는 `expand`, retire는 `narrow`, 같은 scope의 merge와 rephrase는 `none`이다. replace-scope와 generalize는 위 집합 비교 결과를 쓴다. canonical 결과가 없는 conflict envelope는 기존 active 규칙을 유지하므로 `none`이다.

### Locked decision 5. 정규화와 직렬화를 바이트 단위로 고정한다

입력 byte는 fatal UTF-8로 decode하며 잘못된 byte sequence는 schema error로 거부한다. 파일 맨 앞의 BOM 1개만 제거하고 CRLF와 단독 CR은 LF로 바꾼 뒤 `String.prototype.normalize("NFC")`를 적용한다. `statement`, `reason`, `exceptions` 항목과 허용된 `summary`는 앞뒤 공백을 제거하고 내부의 연속된 ASCII space와 tab을 ASCII space 하나로 바꾼다. 자연어의 대소문자와 문장부호는 바꾸지 않는다.

앞뒤 공백 제거 집합은 `U+0009..U+000D`, `U+0020`, `U+0085`, `U+00A0`, `U+1680`, `U+2000..U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, `U+3000`으로 고정한다. runtime의 locale나 확장 공백 판정을 사용하지 않는다.

정규화 후 모든 문자열 scalar를 UTF-16 code unit 단위로 검사해 unpaired high surrogate `U+D800..U+DBFF`와 unpaired low surrogate `U+DC00..U+DFFF`를 schema error `unpaired-surrogate`로 거부한다. 올바른 surrogate pair는 하나의 Unicode scalar로 허용한다. 이 검사는 JSON parse 후, NFC와 해시 직렬화 전에 object의 모든 key와 string value에 재귀적으로 적용한다. Node.js `JSON.stringify` 가 lone surrogate를 escape하는 방식에 결과 byte를 의존하지 않아야 runtime 차이가 ID로 흐르지 않는다.

이 검사를 통과한 문자열 scalar에 LF, NUL, C0 control이 남으면 거부한다. ID, enum, key, ref는 대소문자를 바꾸거나 빈값을 보충하지 않고 각 필드의 literal이나 정규식에 정확히 맞아야 한다. 정수는 `0`과 `Number.MAX_SAFE_INTEGER` 사이의 JSON number만 허용하며 `-0`, 소수, 지수 표기, NaN, Infinity는 거부한다. schema에 없는 키, 누락된 키, 허용 위치가 아닌 `null`도 묵시하지 않고 거부한다.

`trigger_key`와 `action_key`는 `^[a-z0-9]+(?:[.-][a-z0-9]+)*$`를 따른다. 경로는 POSIX separator를 쓰고 중복 slash를 하나로 줄인다. 문자열과 ID 배열은 정규화한 후 중복을 제거하고 UTF-8 byte 오름차순으로 정렬한다. 비교는 locale와 환경에 영향받는 `localeCompare`를 쓰지 않고 `Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"))`의 부호를 쓴다. tuple은 첫 번째로 다른 성분에 같은 비교를 적용한다.

`evidence_refs`는 `(kind, ref, summary)` 튜플을 각 성분의 UTF-8 byte 순서로 비교해 정렬한다. 세 성분이 같은 항목만 중복으로 제거한다. 같은 `kind`와 `ref`에 다른 `summary`가 있으면 하나 이상이 kind별 literal 계약을 어긴 것이므로 conflict가 아니라 schema error로 거부한다. snapshot은 `id`로, relation은 relation key 안의 ID로 정렬한다.

JSON은 RFC 8259를 따르며 key 순서를 스키마에 적힌 순서로 고정한다. canonical 파일의 레코드는 `JSON.stringify(value, null, 2)`, compact JSON과 해시 입력은 `JSON.stringify(value)`의 출력을 쓴다. proposal envelope의 표준 출력 byte는 `JSON.stringify(envelope, null, 2) + "\n"`이다. Markdown 아티팩트의 문서 끝은 LF 하나고 trailing space는 없다. Markdown heading의 규칙 순서는 ID의 UTF-8 byte 오름차순이다. Active, Retired, Transition ledger 각 섹션 내부에서 같은 정렬을 적용한다.

해시 입력은 Node.js `JSON.stringify(value)`의 compact 출력을 UTF-8로 인코딩한 byte다. replacer와 space 인자를 쓰지 않고 끝에 LF를 붙이지 않는다. object는 스키마의 key 순서로 새로 생성한 뒤 직렬화하며, 입력 object의 원래 key 순서를 신뢰하지 않는다.

결정성의 입력 경계는 `base_revision`의 full canonical state, 그 state에서 만든 active 규칙 투영, 신규 후보 레코드, 명시적 수명주기 요청을 합친 normalized batch다. full canonical state는 schema, revision, active 규칙, retired 규칙, transition ledger의 canonical 레코드를 모두 포함한다.

state hash 입력 object의 키 순서는 `schema`, `revision`, `active`, `retired`, `transitions`다. 각 배열은 canonical 레코드를 ID 순으로 담고 compact JSON으로 직렬화한다. `base_state_hash`는 이 UTF-8 byte의 SHA-256이다. 파일이 없는 virtual revision 0은 같은 object에 빈 배열 세 개를 넣어 계산한다.

수명주기 요청은 정규화 후 위에 적은 request 레코드로 투영한다. 해시 object의 키 순서는 `schema`, `operation`, `targets`, `requested_scope`, `requested_statement`, `source_dispositions`, `replaced_by`, `reason`, `evidence_refs`고 schema는 `nova.team-rule-request.identity/v1`이다. 이 object의 compact JSON SHA-256을 `rq-sha256-` 뒤에 붙여 request ID를 만든다. 내용이 같은 요청만 접고, 같은 target에 대한 다른 request ID는 `multiple-requests` conflict의 독립 member로 유지한다. 이 스펙에서 같은 기준 버전은 revision 정수와 full canonical state byte가 모두 같다는 뜻이다. 둘 중 하나라도 다르면 다른 입력이다.

`retire` 요청의 `replaced_by`는 canonical에 존재하는 다른 active 규칙 ID 또는 `null`이어야 한다. 다른 operation에서는 `null`이다. 승인 후 retirement object는 이 값과 요청의 normalized reason을 그대로 사용한다.

후보와 요청은 각각 ID를 1차 키로, canonical compact JSON byte를 2차 키로 정렬한다. 같은 candidate ID의 `origins`, 근거, 관계 차이는 합집합 규칙으로 접지만, 신규 후보끼리 `statement`가 다르거나 생성 정보가 다르면 `id-collision`이다. 같은 target의 `source_dispositions` status나 신규 후보 `statement`가 다른 candidate 변형은 conflict envelope의 `candidates`에서만 둘 다 유지해 ID 뒤 compact JSON byte로 정렬한다. 같은 request ID의 compact JSON이 다르면 `id-collision`이다. 관계, 원본 처분, retire 사유처럼 사람 판단이 필요한 값이 빠지면 gardener가 채우지 않고 conflict를 출력한다. 이 판단 값이 다르면 같은 normalized batch가 아니다.

전이 `reason`은 다음 계약으로만 만든다. `<...-json>`은 이미 정렬된 값을 canonical compact JSON으로 직렬화한 결과다.

| operation | `reason` literal |
|---|---|
| `promote` | `후보 <inputs-json>를 팀 규칙 <outputs-json>로 승격함` |
| `merge` | `동일 의미와 scope의 규칙 <inputs-json>를 canonical 규칙 <canonical-id>로 병합함` |
| `generalize` | `규칙 <active-inputs-json>의 공통 원칙을 <new-rule-id>로 일반화함` |
| `retire` | normalized lifecycle request의 `reason` 그대로 |
| `replace-scope` | `규칙 <target-id>의 scope를 <before-scope-json>에서 <after-scope-json>로 변경함` |
| `rephrase` | `규칙 <target-id>의 의미를 유지하며 statement를 변경함` |

conflict envelope의 `reason`은 `충돌 <code>: <member-ids-json>` literal을 쓴다. 여러 조건이 맞으면 아래 rank에서 가장 작은 code 하나만 쓴다.

| rank | code | 정확한 조건 |
|---:|---|---|
| 1 | `id-collision` | 같은 digest 또는 ID에 다른 생성 정보가 연결되거나, 같은 신규 후보 ID에 서로 다른 정규화 `statement`가 연결됨 |
| 2 | `retired-id-reuse` | 신규 후보 digest가 canonical retired 규칙과 일치함 |
| 3 | `source-disposition-invalid` | generalize 원본 처분이 누락, 중복, 불일치함 |
| 4 | `judgment-required` | 필요한 관계, 원본 처분, request 값, 수명주기 사유가 입력에 없음 |
| 5 | `declared-conflict` | 관계 preflight가 모순을 발견하거나 `conflicts_with`가 겹치는 scope에 선언됨 |
| 6 | `equivalence-constraint-mismatch` | equivalent component의 scope, effect, exceptions가 일치하지 않음 |
| 7 | `opposite-effect` | 같은 trigger와 action, 겹치는 scope에서 effect가 반대임 |
| 8 | `multiple-requests` | 같은 active ID에 서로 다른 수명주기 요청이 둘 이상임 |
| 9 | `overlapping-groups` | 한 ID가 서로 다른 전이 group 둘 이상에 속함 |
| 10 | `generalization-cycle` | generalizes 관계에 순환이 있음 |
| 11 | `ambiguous-semantics` | 같은 trigger, action, effect와 겹치는 scope를 갖는 다른 ID의 후보 쌍에 명시적 관계와 request가 없음 |

필수 ID나 schema 필드가 없어 member set 자체를 만들 수 없는 malformed 입력은 conflict envelope를 만들지 않고 schema error로 거부한다. 자유 생성 문장을 reason이나 option impact에 쓰지 않는다.

### Locked decision 6. 안정적 ID는 시간과 실행자를 입력으로 쓰지 않는다

신규 규칙 ID는 다음 생성 정보를 key 순서가 고정된 canonical JSON으로 직렬화한 뒤 SHA-256을 계산해 만든다.

```json
{
  "schema": "nova.team-rule.identity/v1",
  "scope": ["repo"],
  "trigger_key": "completion.before-report",
  "action_key": "verification.run-required-checks",
  "effect": "require",
  "exceptions": []
}
```

결과는 `tr-sha256-<64 lowercase hex>`다. `statement`는 표현을 다듬을 수 있도록 ID 재계산 입력에서 제외한다. ID는 첫 승인 시점에 확정하고 이후 불변으로 유지한다. 같은 ID에 다른 생성 정보가 연결되면 충돌로 처리하고 salt나 timestamp로 임의 회피하지 않는다.

전이 ID는 `schema: "nova.team-rule-transition.identity/v1"`, `operation`, `base_revision`, `base_state_hash`, `inputs`, `outputs`, `before`, `after`, `reason`, `evidence_refs`를 이 순서로 담은 compact JSON의 SHA-256 앞에 `tx-sha256-`를 붙여 만든다. 승인자가 승인할 ID를 승인 전에 계산해야 하므로 `approval`은 해시 입력에서 제외한다. 현재 시간, 작업 디렉터리, branch 이름, 실행자 이름도 해시 입력에 포함하지 않는다.

`before`와 `after`의 content hash를 먼저 계산하고, 그 snapshot으로 전이 ID를 만든 뒤, 영향받은 모든 규칙의 `transition_refs`에 그 ID를 추가한다. content hash가 `transition_refs`를 제외하므로 자기 참조가 생기지 않는다. 전이와 proposal의 `evidence_refs`는 해당 group의 candidate와 request에 있는 근거를 tuple 합집합한 결과다. 실행자가 새 근거를 생성하지 않는다.

### Locked decision 7. 상태는 공유 수명주기와 제안 수명주기를 분리한다

canonical 파일에 저장할 규칙 상태는 `active`와 `retired`뿐이다. `proposed`, `conflict`, `approved`, `rejected`는 제안 상태이며 승인된 전이가 적용되기 전에는 canonical 파일에 쓰지 않는다. 이러한 분리는 미승인 제안이 Git에서 팀 정책처럼 보이는 문제를 막는다.

모든 작업은 먼저 제안만 만든다. `proposed`나 `conflict`인 동안 canonical revision, 기존 `active` 규칙, count, transition ledger는 바뀌지 않는다. 따라서 중복 판정, 결론 충돌, scope 확대나 축소가 있어도 전이 ID를 사람이 승인하기 전에는 기존 정책이 계속 유효하다. 승인 적용 중 검증이 실패해도 부분 상태를 남기지 않고 제안 전 canonical byte를 보존한다.

| 작업 | 전제조건과 입력 | 미승인 출력 | 승인 시 허용 전이와 출력 | 금지 전이 | 왜 |
|---|---|---|---|---|---|
| `promote` | 반복성과 일반성을 통과한 신규 `tc` 후보 1개, 유효한 정제 근거와 scope | 후보를 담은 `proposed` envelope 1개, canonical diff 없음 | 후보 `tc`가 신규 `tr active`가 되고 `promote` 전이 1개 생성 | 후보를 바로 `active`로 쓰기, retired ID 재활성화 | 개인 또는 machine-local 관찰이 사람 판단 없이 팀 정책이 되는 것을 막기 위함 |
| `merge` | 서로 다른 ID, 같은 scope, effect, exceptions, 명시적 `equivalent_to`로 연결된 `active tr` 2개 이상 | 입력별 출처, canonical 선택, 병합 사유를 담은 `proposed` envelope 1개, 기존 규칙 모두 active | 최소 ID 규칙은 `active` 유지, 나머지는 같은 ID의 `retired`로 전이, canonical 규칙에 근거와 `merged_from` 합집, `merge` 전이 1개 생성 | 같은 ID의 exact duplicate나 scope가 다른 규칙을 merge하기, 입력 삭제 | 최소 ID tie-break로 결과를 결정적으로 만들면서 과거 ID와 대체 관계를 보존하기 위함 |
| `generalize` | 공통 원칙을 담고 원본 `active tr` 2개 이상을 `generalizes`로 참조하는 신규 `tc` 1개, 예외, scope 영향, 원본별 `source_dispositions` | 관계, 범위 변화, 예외, 근거, 원본별 처분을 담은 `proposed` envelope 1개, 원본 모두 기존 상태 유지 | 신규 `tr active` 생성, 원본은 명시된 처분대로 `active` 유지 또는 같은 ID의 `retired`로 전이, `generalize` 전이 1개 생성 | 예외, scope 영향, 원본 처분을 추론하거나 누락한 채 적용, 원본 삭제 | 일반 원칙이 특수한 예외를 지우거나 적용 범위를 몰래 넓히는 것을 막기 위함 |
| `retire` | `active tr` 1개, 비어 있지 않은 폐기 사유, 다른 `active tr` 대체 ID 또는 명시적 `null` | 이전과 이후 snapshot, 사유, 대체 ID를 담은 `proposed` envelope 1개, 대상은 active 유지 | 대상은 동일 ID의 `retired`가 되고 `retirement.reason`, `retirement.replaced_by`, `retire` 전이 1개를 보존 | 규칙 삭제, 사유 누락, 자기 자신이나 retired 규칙을 대체 ID로 지정, `retired`를 `active`로 복귀 | 정책 제거도 감사 가능한 결정이어야 하며 참조하던 과거 ID를 깨뜨리지 않기 위함 |
| `replace-scope` | `active tr` 1개, 변경된 scope를 가진 신규 `tc` 1개, 계산된 `expand`, `narrow`, `mixed` 영향 | 이전/이후 scope와 영향을 담은 `proposed` envelope 1개, 기존 규칙은 원래 scope로 active 유지 | 기존 ID는 같은 ID의 `retired`, 신규 ID는 `active`가 되며 하나의 `replace-scope` 전이에 원자적으로 기록 | 기존 ID의 scope 직접 수정, retire와 신규 active 생성 중 하나만 적용 | ID가 의미 범위를 대표하게 하고 범위 변경 중 부분 적용을 막기 위함 |
| `rephrase` | `active tr` 1개, 동일 생성 정보, 새 statement, 의미 불변 사유 | 문장 전후를 담은 `proposed` envelope 1개, 기존 문장 유지 | 동일 ID와 status를 유지하며 statement, content hash, 전이 이력만 변경 | trigger, action, effect, scope, exceptions 변경 | 표현 수정과 정책 의미 변경을 구분해 안정적 ID 계약을 지키기 위함 |
| `conflict` | 겹치는 scope에서 결론이 충돌하거나 필수 판단 정보가 부족한 component | 결정적 conflict ID, 원인 code, 두 고정 option과 영향, canonical diff 없음 | canonical 전이 없음. `keep-existing` 또는 `revise-input` 선택은 immutable conflict envelope를 바꾸지 않고 현재 process만 종료 | conflict를 `approved`나 `rejected`로 바꾸기, 임의 승자 선택, option 선택만으로 규칙 변경 | 불완전하거나 모순된 입력에서 기존 유효 정책을 안전한 기본값으로 보존하기 위함 |

제안 상태 전이는 `proposed -> approved` 또는 `proposed -> rejected`만 허용한다. `approved`는 승인 직후 stale, schema, privacy 검사를 다시 통과해 canonical diff가 원자적으로 적용되는 순간의 process state이며 파일에 독립 상태로 남기지 않는다. 승인 직전 재검사나 원자적 적용에 실패하면 제안은 같은 `tx` ID의 `rejected`로 종료하고 부분 diff 없이 기존 canonical 상태를 보존한다.

conflict envelope는 `state: conflict`와 같은 `cf` ID를 유지하는 immutable terminal output이므로 다른 제안 상태로 전이하지 않는다. `keep-existing`은 현재 process를 끝내고 envelope를 폐기하며, `revise-input`은 이를 수정하지 않고 새 normalized batch에서 새 ID를 만든다. `rejected -> proposed`, `retired -> active`, `conflict -> approved`, `conflict -> rejected` 직접 전이는 v1에서 금지한다.

`merge`의 canonical ID는 입력 active ID 중 UTF-8 byte 순서로 가장 작은 값이다. canonical 규칙의 생성 정보, 문장, scope를 유지한다. `evidence_refs`는 모든 입력 규칙의 근거 합집합이고 `relations`은 각 key의 합집합이며, `merged_from`에 canonical 자신을 제외한 입력 ID를 추가한다. 실행자가 `rule` 근거를 자동 생성하지 않는다. 나머지 규칙은 삭제하지 않고 `replaced_by`로 canonical ID를 기록한다. retirement reason은 `canonical 규칙 <canonical-id>에 병합됨` literal이다.

같은 생성 정보와 같은 `statement`의 후보는 같은 ID이므로 batch 안에서 provenance를 합집하는 exact duplicate이며 merge 전이를 만들지 않는다. 생성 정보는 같지만 `statement`가 다른 신규 후보는 접지 않고 `id-collision` conflict로 보낸다. 이 접기는 후보 정규화일 뿐 기존 canonical 규칙을 바꾸지 않는다. 기존 active와 같은 ID인 후보는 canonical no-op이며, 신규 후보끼리 접힌 하나의 후보는 별도 `promote` 승인 전까지 공유 규칙이 아니다. `replace-scope`로 retired가 되는 기존 규칙의 reason은 `scope 변경으로 규칙 <new-rule-id>에 대체됨` literal이다.

`generalize`의 원본 상태는 candidate의 `source_dispositions`를 그대로 적용한다. retired 처분의 사유는 `일반 규칙 <new-rule-id>가 원본을 완전히 대체함` literal이고, active 처분은 `specializes`로 새 규칙을 참조한다. 같은 원본에 서로 다른 처분이 들어오거나 처분이 빠지면 conflict이므로 gardener가 임의로 고르지 않는다.

직접 scope 수정은 허용하지 않는다. 규칙 하나의 범위를 확대하거나 축소하면 `replace-scope`로 기존 ID의 retire와 새 ID의 promote를 하나의 승인 단위에 직렬화한다. 여러 원본에서 범위가 넓은 원칙을 만들 때만 `generalize`를 쓴다.

retired 규칙을 active로 되돌리는 전이는 v1에서 금지한다. 같은 생성 정보는 같은 ID를 만드므로 그대로 재등록할 수 없다. 다시 필요하면 scope, trigger, action, effect, exceptions 중 실제로 바뀐 의미 요소를 반영한 새 `promote` 제안을 만들고 기존 retired ID를 근거로 참조한다.

### Locked decision 8. 중복과 충돌 판정 순서를 고정한다

먼저 모든 후보와 요청을 정규화하고 ID를 재계산해 불일치를 거부한다. 같은 candidate ID는 앞의 합집합 규칙으로 하나로 접되, 신규 후보 `statement`가 다른 `id-collision` 변형과 `source-disposition-invalid` 변형은 소거하지 않고 conflict 출력에서 보존한다. 같은 request ID는 하나로 중복 제거한다. self edge와 batch에 없는 ID 참조는 schema error로 거부한다.

request operation은 `retire`, `rephrase`, `replace-scope`만 허용한다. 세 operation 모두 `targets`는 canonical active `tr` 1개고 `reason`은 문자열이며 `evidence_refs`는 정렬된 참조 배열이다. `retire`는 `requested_scope` 와 `requested_statement`가 `null`, `source_dispositions`가 `[]`, `replaced_by`가 다른 active ID 또는 `null`이다. `rephrase`는 `requested_statement`가 문자열 또는 `null`이고, `requested_scope`와 `replaced_by`가 `null`, `source_dispositions`가 `[]`여야 한다. `replace-scope`는 `requested_scope`가 scope 배열 또는 `null`이고, `requested_statement`와 `replaced_by`가 `null`, `source_dispositions`가 `[]`여야 한다.

허용되지 않은 operation, 잘못된 target cardinality, 잘못된 필드 type과 조합은 schema error다. 정규화한 `reason`이 비어 있거나 `rephrase` statement와 `replace-scope` scope가 `null`이면 `judgment-required`다. 제공된 `rephrase` statement가 기존과 같거나 `replace-scope` scope가 기존과 같으면 요청한 operation의 전제를 어긴 schema error다.

후보는 ID pair를 `(lower_id, higher_id)`로 만들어 tuple byte 순서로 순회한다. exact duplicate를 접은 뒤 모든 pair에 대해 아래 조건을 전부 평가하며 첫 매칭에서 멈추지 않는다.

1. `equivalent_to`로 연결된 다른 ID의 scope, effect, exceptions가 모두 같으면 semantic duplicate 조건이다.
2. 같은 trigger와 action, 반대 `effect`, 겹치는 scope면 `opposite-effect`를 수집한다.
3. `conflicts_with`가 선언되고 scope가 겹치면 `declared-conflict`를 수집한다.
4. `equivalent_to`와 `conflicts_with`가 함께 있거나 `equivalent_to`와 같은 방향의 `generalizes`가 함께 있으면 `declared-conflict`를 수집한다.
5. `equivalent_to` component의 scope, effect, exceptions 중 하나라도 다르면 `equivalence-constraint-mismatch`를 수집한다.
6. 같은 trigger, action, effect와 겹치는 scope를 갖는 다른 ID의 pair에 명시적 관계와 둘을 같은 operation group으로 연결하는 request가 없으면 `ambiguous-semantics`를 수집한다.

자연어 유사도는 위 조건에 추가하지 않는다. 관계는 normalized batch 경계 전에 사람이 명시한 입력만 쓴다. 한 pair에서 여러 conflict code가 수집되어도 임의로 하나를 고르지 않는다.

이후 conflict 여부와 무관하게 provisional group을 모두 만든다. semantic duplicate는 `equivalent_to` connected component, generalize는 후보와 `generalizes` 원본, retire와 rephrase는 request와 target이 각각 하나의 group이다. scope change는 `replace-scope` request, target, target과 생성 정보 중 scope만 다르고 requested scope와 정확히 일치하는 후보가 하나의 group이다. promote는 이 그룹과 no-op 어느 것에도 속하지 않는 단독 신규 후보만 group이 된다. `replace-scope`에 일치하는 후보가 1개가 아니면 `judgment-required`를 수집한다.

provisional group을 node로 하는 group-overlap graph에서 candidate, request, target ID 중 하나라도 공유하면 두 group을 무방향 edge로 연결한다. node가 2개 이상인 각 connected component는 모든 node의 member 합집합을 하나의 `overlapping-groups` conflict로 만든다. 같은 target의 서로 다른 request group이 둘 이상이면 `multiple-requests`도 같은 member 집합에 수집한다. 일반화 순환은 순환이 속한 relation component에 `generalization-cycle`을 수집한다.

pair가 아닌 conflict code도 영향받는 member 집합에 정확히 붙인다. `id-collision`은 해당 ID의 변형, `retired-id-reuse`는 후보와 retired ID, `source-disposition-invalid`는 후보와 disposition target, `judgment-required`는 해당 candidate나 request와 target이 member다. 이 member를 빈 집합으로 대체하거나 인접한 그룹에 임의로 확대하지 않는다.

최종 conflict graph의 vertex는 candidate, request, target ID다. edge는 conflict를 수집한 pair, pair가 아닌 conflict code의 member 집합 내 모든 서로 다른 member 쌍, semantic duplicate나 generalize group을 만든 relation, request와 target, request와 paired candidate, group-overlap component 내의 모든 member 쌍이다. scope가 겹치지 않는 `conflicts_with` 선언처럼 conflict도 group도 만들지 않는 relation은 edge가 아니다.

conflict code가 하나 이상 있는 각 connected component마다 member 합집합 하나로 conflict envelope 하나를 만든다. reason은 component에 수집된 모든 code 중 Locked decision 5의 가장 작은 rank를 쓴다. 이때만 conflict component의 모든 member를 다른 제안에서 제외한다.

충돌 없이 남은 provisional group만 `merge`, `generalize`, `replace-scope`, `promote`, `retire`, `rephrase` proposal이 된다. group signature는 candidate, request, target ID의 합집합을 정렬해 LF로 연결한 문자열이다. 제안 목록은 `conflict`, `merge`, `generalize`, `replace-scope`, `promote`, `retire`, `rephrase` 순서를 작업 rank로 쓴다. 같은 rank에서는 group signature의 UTF-8 byte 순서로 정렬한다. 각 승인 후 나머지 제안은 새 revision에서 다시 계산한다.

canonical active와 같은 생성 정보로 접힌 후보가 수명주기 request나 다른 규칙과의 명시적 관계에 속하지 않으면 no-op이다. 후보의 새 origin, 근거, statement는 단독으로 기존 canonical을 변경하지 않는다. 이 후보만 남은 group은 proposal, transition, revision 증가, canonical diff를 만들지 않는다. 관계 선언이 있으면 no-op으로 숨기지 않고 앞의 관계 무결성 검사를 적용한다.

### Locked decision 9. 사람 승인은 전이 ID 단위로 받는다

제안은 `base_revision`, 전이 ID, 이전과 이후, scope 영향, 예외, 사유, 정제된 근거를 포함한다. approval은 전이 ID의 해시 입력이 아니므로 정확한 최종 byte 승인은 두 단계로 받는다. 먼저 사용자는 아래 키 순서의 draft 입력으로 전이 ID 하나와 공개 기록 값을 지정한다.

```json
{"transition_id":"tx-sha256-<64 lowercase hex>","actor":"maintainer-a","decision_ref":null}
```

gardener는 draft 값을 넣고 `privacy_reviewed: true`를 둔 최종 after byte를 memory에서 render한다. 그 byte 전체의 SHA-256인 `after_byte_hash`와 정확한 byte를 보여주되 파일에는 쓰지 않는다. 사용자는 byte를 검토한 뒤 아래 키 순서의 confirmation에서 draft 값을 그대로 반복하고 그 hash를 지정한다.

```json
{"transition_id":"tx-sha256-<64 lowercase hex>","after_byte_hash":"sha256-<64 lowercase hex>","actor":"maintainer-a","decision_ref":null,"privacy_reviewed":true}
```

confirmation의 값으로 다시 render한 byte의 SHA-256이 `after_byte_hash`와 같아야 하며, draft의 transition ID, actor, decision ref와도 byte 단위로 같아야 한다. 하나라도 다르면 적용하지 않고 새 preview를 만든다. 한 입력에는 전이 ID 하나만 허용한다. `승인`, `좋아`, `전부 적용`, ID 목록, wildcard처럼 대상을 하나로 고정하지 못한 응답은 승인으로 보지 않는다. `merge`로 처리되는 의미 중복, `generalize`, `retire`, `promote`, `replace-scope`, `rephrase`는 예외 없이 이 두 단계 승인을 요구한다. 같은 ID로 접혀 canonical diff가 없는 exact duplicate와 기존 active no-op은 적용할 전이가 없으므로 승인 대상이 아니다.

draft preview를 만들기 전과 confirmation 직후 canonical의 `revision`과 full state hash를 다시 계산해 제안의 `base_revision`, `base_state_hash`와 모두 비교한다. 하나라도 다르면 제안을 stale로 폐기하고 새 기준 버전에서 다시 생성한다. confirmation 직후 재검사한 after byte가 preview byte 및 hash와 모두 같을 때만 관련 규칙, count, revision, transition ledger를 하나의 원자적 diff로 바꾼다.

충돌 제안은 두 고정 option과 기존 active 규칙에 미치는 영향을 보여준다. 선택할 때는 아래 키 순서의 입력으로 conflict ID와 option ID 하나를 함께 지정한다.

```json
{"conflict_id":"cf-sha256-<64 lowercase hex>","option_id":"to-sha256-<64 lowercase hex>","actor":"maintainer-a","decision_ref":null,"privacy_reviewed":true}
```

이 선택 receipt는 같은 JSON을 세션 응답에 돌려줄 뿐 파일로 저장하지 않는다. `keep-existing`은 immutable conflict envelope를 바꾸지 않고 현재 process를 끝내며, `revise-input`은 현재 process를 끝낸 뒤 보완된 normalized batch를 새로 받는다. 둘 다 canonical 파일을 바꾸지 않으며 명시적 선택이 없어도 기존 active 규칙을 그대로 유지한다. 이후 실제 전이가 필요하면 새 proposal ID에 대해 별도의 전이 승인을 다시 받는다.

### Locked decision 10. 정제된 근거만 팀 경계를 넘는다

`evidence_refs`의 각 항목은 `kind`, `ref`, `summary`를 이 순서로 갖는다. 허용 형식은 다음과 같다.

| `kind` | `ref` 형식 | 용도 |
|---|---|---|
| `git` | `git:<40자 또는 64자 소문자 hex>` | 저장소에 존재하는 commit |
| `rule` | `rule:<tr-id>` | 다른 팀 규칙 |
| `gate-summary` | `gate:<allowed-mode>:count=<positive integer>` | 반복 실패의 비식별 집계 |
| `doc` | `doc:<commit-hex>:<blob-hex>#h=<positive integer>` | Git으로 추적되는 설계나 결정 문서의 heading 순번 |

`gate-summary`의 allowed mode는 gate aggregator가 고정한 `verification-evidence-missing`, `verification-failure-unresolved`, `requested-scope-omitted`, `unrequested-scope-added`, `reference-not-found`, `ambiguity-not-raised`, `completion-overstated`뿐이다. `unclassified`와 임의 mode는 거부한다.

`rule` ref의 ID는 현재 canonical 파일의 active 또는 retired 규칙에 실제로 존재해야 한다. 자기 자신이나 적용 중인 transition에서 처음 생성될 규칙을 근거로 참조하면 순환이므로 거부한다.

`doc`의 commit은 저장소에 존재하는 commit object여야 하고, blob은 그 commit의 tree에서 도달 가능해야 한다. heading 순번은 해당 blob의 ATX heading을 문서 순서로 세어 1부터 시작하며 실제 순번 범위 안에 있어야 한다. 경로와 heading 문구를 ref에 넣지 않으므로 machine-local 절대 경로, 세션 ID, 자유 서술을 payload에 넣을 수 없다.

`summary`는 자유 서술이 아니다. `git`은 `저장소 변경에서 정제한 근거`, `rule`은 `기존 팀 규칙에서 정제한 근거`, `doc`은 `저장소 문서에서 정제한 근거` literal만 쓴다. `gate-summary`는 allowed mode에 대응하는 aggregator의 exact Korean rule proposal을 그대로 쓴다.

validator는 `kind`, 전체 `ref`, `summary` 모두에 allowlist를 적용한다. 사람 이름, 이메일, 절대 경로, 세션 ID, 원문 claim, 명령, 출력, secret을 받는 자유 필드는 없다. allowlist를 통과하지 못한 항목이 하나라도 있으면 전이 전체를 거부한다.

raw ledger를 읽는 adapter는 공유 후보 생성 경계로 `{mode, count}`만 넘길 수 있다. `mode`는 위 allowed mode 중 하나고 `count`는 양의 정수다. command, output, claim, session, timestamp, 파일 경로와 원문 일부는 adapter 출력 schema에 없으며 gardener는 ledger 문자열을 `statement`, `exceptions`, `reason`, `summary`, `approval`로 복사하거나 보간하지 않는다. gate 후보의 `summary`와 전이 `reason`은 각각 고정 mode 문구와 Locked decision 5의 literal로만 만든다. 개인 후보와 Git/doc 후보의 사람이 작성한 규칙 문장, 예외, retire 사유도 raw evidence를 입력으로 받지 않고, 승인자는 after byte 전체를 공개 가능한 정제 정보로 검토한다.

다음 파일은 machine-local이며 Git 추적 대상이 아니다.

- `.nova/evidence.jsonl`
- `.nova/gate-history.jsonl`
- `.nova/gate-verdict.json`

임시 제안과 충돌 보고서는 파일 경로를 갖지 않는다. 세션 응답과 process memory에만 존재하며 제안 생성 전후의 `git status --short`가 같아야 한다. 이 불변조건은 임시 제안의 ignore 패턴을 새로 관리해야 하는 모호한 경로를 없앤다.

`.nova/gate.on`과 `.nova/.gitignore`는 기존 정책대로 추적할 수 있다. `.nova/team-rules.md`는 도입 승인 후에만 allowlist에 추가한다. 나머지 `.nova/` 파일을 포괄적으로 unignore하지 않는다.

도입 시 `.nova/.gitignore`의 Nova 관리 block은 파일의 마지막 block이어야 하며 `*`, `!.gitignore`, `!gate.on`, `!team-rules.md`를 이 순서로 둔다. 마지막에 둬야 사용자 정의 unignore가 raw ledger를 다시 노출할 수 없다. 제안 생성과 승인 적용의 첫 단계는 각 machine-local 파일에 대해 다음 두 조건을 모두 검사하는 privacy preflight다.

1. `git check-ignore --no-index -q -- <path>`가 성공해 파일 존재와 index 상태에 관계없이 ignore pattern이 실제로 적용된다.
2. `git ls-files --error-unmatch -- <path>`가 실패해 index에 추적된 경로가 아니다.

이 검사는 `.nova/evidence.jsonl`, `.nova/gate-history.jsonl`, `.nova/gate-verdict.json` 세 경로에 파일 존재 여부와 관계없이 똑같이 적용한다. 어느 조건이든 어기면 proposal도 canonical diff도 만들지 않고 fail-closed한다. `.gitignore`는 이미 추적 중인 파일을 index에서 제거하지 못하므로 gardener가 `git rm --cached`, history rewrite, 파일 삭제를 자동 실행하지 않는다. 사용자가 유출 범위를 판단하고 index와 필요하면 Git history를 별도로 정리한 뒤 preflight를 다시 통과해야 한다.

### Locked decision 11. `promote`는 반복성과 일반성을 모두 입력으로 받는다

`origins`에 `gate`가 있는 후보는 기존 aggregator가 서로 다른 유효 record 3건 이상을 집계했을 때만 gate 반복성을 통과한다. `personal`이 있는 후보는 서로 다른 세션이나 Git 결정 3건 이상의 비식별 요약 참조가 있을 때만 personal 반복성을 통과한다. 원본 ledger 행 번호와 세션 ID는 공유하지 않는다.

일반성은 제안된 `scope`, `trigger_key`, `action_key`, 예외이 특정 사람이나 machine-local 경로에 의존하지 않는지로 판정한다. 실패 횟수가 기준을 넘어도 팀 범위에 적용할 수 없으면 observation으로 남기고 promote 후보로 만들지 않는다. 반복성과 일반성을 통과해도 사람 승인 전에는 공유 상태가 아니다.

### Locked decision 12. 이식성은 의존성 부재로 검증한다

절차는 Git, Nova 플러그인 자체 파일, 표준 Node.js 런타임만을 사용할 수 있어야 한다. `doc-publish`, `swk-wiki`, `secret-manage`, 회사 인증, 전용 orchestrator, 외부 중앙 병합 서버를 요구하지 않는다. 자동 다수결, 사용자 평판, 중앙 계정도 판정 입력에서 제외한다.

## 제안 생성과 적용 절차

1. 세 machine-local 경로의 privacy preflight를 실행하고 실패하면 파일을 바꾸지 않고 중단한다.
2. canonical 파일을 읽고 `revision`을 `base_revision`으로 고정한다.
3. 후보를 정규화하고 ID와 정렬 순서를 계산한다.
4. 중복, 충돌, scope 영향을 고정된 우선순위로 판정한다.
5. 전이 ID, 이전과 이후, 사유, 근거, 선택지 영향을 보여준다.
6. 단일 전이 ID의 approval draft를 받은 뒤 stale 검사와 privacy preflight를 다시 실행하고 정확한 after byte와 hash를 보여준다.
7. 같은 ID와 after hash의 confirmation을 받기 전에는 공유 파일이나 Git index를 바꾸지 않는다.
8. confirmation 직후 stale, 중복, 충돌, privacy preflight, after byte hash를 다시 검사한다.
9. 통과한 전이만 preview와 byte가 같은 하나의 canonical diff로 적용하고, commit 명령은 실행하지 않은 채 제목만 제안한다.

동일한 정규화 후보 집합과 동일한 `base_revision`이 입력이면 작업 디렉터리, 입력 순서, 실행자와 관계없이 같은 규칙 ID, 전이 ID, 섹션 순서, 제안 바이트를 만들어야 한다. approval draft에 동일한 actor와 decision ref를 더하면 같은 preview byte와 after hash가 나와야 하고, confirmation 뒤 적용 diff도 바이트 단위로 같아야 한다. 승인이 필요한 값은 사용자가 제공하며, 실행자가 임의로 채우지 않는다.

canonical diff의 규범 결과는 line patch가 아니라 `.nova/team-rules.md`의 정확한 before byte와 after byte 한 쌍이다. 승인 적용은 정규화된 base state를 memory에서 복제하고, 전이를 적용하고, transition ID를 참조 규칙에 추가하고, approval을 전이 레코드에 넣고, revision을 1 올리고, count를 다시 계산한 뒤 전체 literal template을 새로 render한다. 기존 파일의 부분 문자열을 in-place로 치환하지 않는다.

기존 파일 byte가 파싱한 state를 위 template로 다시 render한 byte와 다르면 묵시하거나 자동 수정하지 않고 fail-closed 처리한다. 승인된 after byte를 한 번에 교체하기 전에 before byte와 `base_state_hash`를 다시 확인한다. 프로세스가 파일을 교체한 후에는 즉시 다시 읽어 after byte와 같은지 확인하며, 다르면 적용 실패로 보고하고 성공으로 기록하지 않는다.

Git이 표시하는 hunk, index hash, 색상은 Git 버전과 설정에 따라 달라질 수 있으므로 ID나 승인 입력에 넣지 않는다. 결정성 검증은 두 실행의 proposal byte와 after byte를 각각 `cmp`한다. `git diff --no-ext-diff --no-textconv -- .nova/team-rules.md`는 사람이 보는 검토 자료이며 규범 byte 계약은 아니다.

## 예시 diff

다음은 `merge`가 승인된 뒤 추적 필드를 판독하기 위한 비규범 diff다. 지면을 줄이기 위해 ID와 hash를 `...`로 줄였으므로 parser 입력이나 fixture로 쓰지 않는다. 규범 결과는 Locked decision 2의 전체 template과 canonical pretty JSON으로 render한 before byte와 after byte다.

```diff
 schema: nova.team-rules/v1
-revision: 4
+revision: 5
-active_count: 3
-retired_count: 0
+active_count: 2
+retired_count: 1

 ### Active
 #### tr-sha256-1111...
-  "evidence_refs": [
-    {
-      "kind": "git",
-      "ref": "git:aaaa...",
-      "summary": "저장소 변경에서 정제한 근거"
-    }
-  ],
+  "evidence_refs": [
+    {
+      "kind": "git",
+      "ref": "git:aaaa...",
+      "summary": "저장소 변경에서 정제한 근거"
+    },
+    {
+      "kind": "git",
+      "ref": "git:bbbb...",
+      "summary": "저장소 변경에서 정제한 근거"
+    }
+  ],
+  "relations": {
+    "merged_from": [
+      "tr-sha256-2222..."
+    ],
+    "generalizes": [],
+    "specializes": []
+  },

-#### tr-sha256-2222...
+### Retired
+#### tr-sha256-2222...
-  "status": "active",
+  "status": "retired",
+  "retirement": {
+    "reason": "canonical 규칙 tr-sha256-1111...에 병합됨",
+    "replaced_by": "tr-sha256-1111..."
+  },

+### Transition ledger
+#### tx-sha256-3333...
+{
+  "id": "tx-sha256-3333...",
+  "operation": "merge",
+  "base_revision": 4,
+  "base_state_hash": "sha256-4444...",

+  "inputs": [
+    "tr-sha256-1111...",
+    "tr-sha256-2222..."
+  ],
+  "outputs": [
+    "tr-sha256-1111...",
+    "tr-sha256-2222..."
+  ],

+  "before": [
+    {
+      "id": "tr-sha256-1111...",
+      "status": "active",
+      "scope": [
+        "repo"
+      ],
+      "content_hash": "sha256-5555..."
+    },
+    {
+      "id": "tr-sha256-2222...",
+      "status": "active",
+      "scope": [
+        "repo"
+      ],
+      "content_hash": "sha256-6666..."
+    }
+  ],

+  "after": [
+    {
+      "id": "tr-sha256-1111...",
+      "status": "active",
+      "scope": [
+        "repo"
+      ],
+      "content_hash": "sha256-7777..."
+    },
+    {
+      "id": "tr-sha256-2222...",
+      "status": "retired",
+      "scope": [
+        "repo"
+      ],
+      "content_hash": "sha256-8888..."
+    }
+  ],

+  "reason": "동일 의미와 scope의 규칙 [\"tr-sha256-1111...\",\"tr-sha256-2222...\"]를 canonical 규칙 tr-sha256-1111...로 병합함",
+  "evidence_refs": [
+    {
+      "kind": "git",
+      "ref": "git:aaaa...",
+      "summary": "저장소 변경에서 정제한 근거"
+    },
+    {
+      "kind": "git",
+      "ref": "git:bbbb...",
+      "summary": "저장소 변경에서 정제한 근거"
+    }
+  ],

+  "approval": {
+    "actor": "maintainer-a",
+    "decision_ref": null,
+    "privacy_reviewed": true
+  }
+}
```

미승인이거나 conflict 상태라면 위 diff를 적용하지 않는다. 기존 active 규칙과 revision은 그대로 남는다.

## Git 추적 계약

한 commit은 승인된 전이 하나만 담는 것을 기본으로 한다. 범위 축소처럼 `retire` 와 `promote`가 원자적으로 묶여야 하는 경우는 하나의 전이 ID와 commit으로 다룬다. 권장 commit 제목은 `update(team-rules): <operation> <short-id>`다.

파일의 transition ledger는 다음 대응을 따라 승인 이력을 보존한다.

| 추적 항목 | canonical 필드 | 판독 규칙 |
|---|---|---|
| 전이 종류 | `operation` | `merge`, `generalize`, `retire`, `promote`, `replace-scope`, `rephrase` 중 하나다. |
| 이전 상태 | `before` | ID, `status`, `scope`, `content_hash`로 승인 직전 상태를 식별한다. |
| 이후 상태 | `after` | 같은 snapshot 형식으로 승인 직후 상태를 식별한다. |
| 사유 | `reason` | 전이 계약의 literal 또는 정규화된 retire 사유를 보존한다. |
| 승인자 | `approval.actor` | 승인자가 제공한 비식별 공개 alias만 보존한다. |
| 승인 근거 | `approval.decision_ref` | 공개 저장소에서 검증할 수 있는 Git 또는 doc ref를 보존한다. |
| 정제된 근거 | `evidence_refs` | allowlist를 통과한 비식별 참조만 보존한다. |

`git diff --no-ext-diff --no-textconv -- .nova/team-rules.md`는 승인된 내용 변경을 보여준다. `git log --follow --format=fuller -- .nova/team-rules.md`는 누가 언제 그 변경을 기록했는지 보여준다. 승인자와 commit author가 다른 경우 `approval.actor`와 commit metadata를 각각 추적하며, 둘을 같은 사람으로 추론하지 않는다. `.nova/evidence.jsonl`은 ledger의 참조나 Git 이력에 포함하지 않는다.

## 승인 후 구현 fixture 계약

이 절은 스키마 도입 승인 후 생성할 테스트 아티팩트의 규범 계약이다. 현재 단계에서는 `tests/fixtures/team-rules/`나 validator를 생성하지 않는다.

### fixture 디렉터리와 파일

각 case는 `tests/fixtures/team-rules/<category>/<case>/`에 둔다. 파일은 아래 이름을 쓰고, 해당하지 않는 optional 파일은 만들지 않는다.

| 파일 | 역할 | 필수 범위 |
|---|---|---|
| `base.md` | 실행 전 `.nova/team-rules.md`의 정확한 byte다. virtual revision 0 case는 생략한다. | canonical base가 있는 case |
| `ledger.jsonl` | machine-local gate ledger 입력이다. 빈 ledger는 0 byte, raw sentinel case는 sentinel이 든 한 행으로 고정한다. | gate 입력이 필요한 case |
| `input.json` | normalized batch의 canonical pretty JSON이다. 입력 permutation은 `input-order-a.json`, `input-order-b.json`을 쓴다. | 모든 case |
| `expected-proposal.json` | `proposed` 또는 `conflict` envelope의 정확한 byte다. | 제안과 충돌 case |
| `approval-draft.json` | 승인 preview를 요청하는 단일 transition ID다. | 정상 승인 case |
| `approval-confirmation.json` | after byte hash를 포함한 두 번째 승인이다. | 정상 승인 case |
| `expected-after.md` | 승인 적용 후 canonical 전체 byte다. | 정상 승인 case |
| `expected-error.json` | `schema-error`, `privacy-error`, `stale`, `approval-error` 중 하나와 고정 code다. | 금지와 거부 case |
| `expected.json` | ID, 상태, 정렬, 승인, shared diff 기대치를 담는 manifest다. | 모든 case |

`expected.json`의 key 순서는 `schema`, `case`, `category`, `outcome`, `ids`, `states`, `order`, `approval`, `shared_diff`다. `ids`는 `candidates`, `rules`, `requests`, `proposal`, `options`를, `states`는 `proposal`, `canonical_before`, `canonical_after`를, `order`는 `proposals`, `active`, `retired`, `transitions`를 이 순서로 담는다. `approval`은 `transition_required`, `human_decision_required`, `provided`, `accepted`를 이 순서로 담는다. ID가 없는 경우 배열은 `[]`, scalar는 `null`로 쓴다.

`input.json`의 key 순서는 `schema`, `base_revision`, `base_state_hash`, `candidates`, `requests`다. `schema`는 `nova.team-rule-batch/v1`, revision과 state hash는 `base.md` 또는 virtual empty state와 일치해야 한다. `candidates`와 `requests`는 Locked decision 2의 전체 canonical record 배열이며, 없으면 `[]`다. 입력 순서 결정성 case의 `input-order-a.json`, `input-order-b.json`만 배열 순서를 의도적으로 어길 수 있으며, 나머지 case는 canonical 순서를 지킨다. unknown key나 누락 key는 schema error다.

다음 manifest는 virtual revision 0에서 gate 집계 3건을 `promote`로 승인한 기준 case의 규범값이다.

```json
{
  "schema": "nova.team-rules-fixture-expectation/v1",
  "case": "normal/promote-approved",
  "category": "normal",
  "outcome": "applied",
  "ids": {
    "candidates": ["tc-sha256-74f9deffbfc04c847b2ec6aa0b8ead0a961edc3bae1b208d3500a29f9a8b4ab9"],
    "rules": ["tr-sha256-74f9deffbfc04c847b2ec6aa0b8ead0a961edc3bae1b208d3500a29f9a8b4ab9"],
    "requests": [],
    "proposal": "tx-sha256-3dd3172be4ba2173dd9a7d26f76fd78bd60f01c459eece5027fa09cc1d1c6f66",
    "options": []
  },
  "states": {
    "proposal": "approved",
    "canonical_before": [],
    "canonical_after": ["active"]
  },
  "order": {
    "proposals": ["tx-sha256-3dd3172be4ba2173dd9a7d26f76fd78bd60f01c459eece5027fa09cc1d1c6f66"],
    "active": ["tr-sha256-74f9deffbfc04c847b2ec6aa0b8ead0a961edc3bae1b208d3500a29f9a8b4ab9"],
    "retired": [],
    "transitions": ["tx-sha256-3dd3172be4ba2173dd9a7d26f76fd78bd60f01c459eece5027fa09cc1d1c6f66"]
  },
  "approval": {
    "transition_required": true,
    "human_decision_required": true,
    "provided": true,
    "accepted": true
  },
  "shared_diff": true
}
```

이 case의 신규 후보는 `statement` `완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다.`(gate aggregator가 `verification-evidence-missing`에 고정한, Locked decision 10의 "exact Korean rule proposal")와 `evidence_refs` `[{"kind":"gate-summary","ref":"gate:verification-evidence-missing:count=3","summary":"완료를 보고하기 전에 요구된 검증 명령을 실제로 실행하고 통과 출력을 확인한다."}]`를 literal로 고정한다. 이 candidate literal이 Locked decision 3의 `content_hash` 입력 object를 유일하게 결정한다.

이 case의 virtual empty state hash는 `sha256-6e1a1e9c9bcdaac981528609556f91b09cdc9c77ecbf6a8978e97820068a7034`, active rule content hash는 `sha256-616eb537b4f8589e3973f0695009bc31199e1c9c291944cb9ef50587d3262988`, `expected-after.md`의 byte hash는 `sha256-60b817cdf27bda8dc8eadf50a9bdede66b1b465a9946d848d445a3953b69185b`다. approval actor는 `maintainer-a`, `decision_ref`는 `null`로 고정한다. snapshot 갱신 도구로 이 값을 재생성하지 않고 검증 대상 상수로 읽는다.

### 고정 ID catalog

다음 ID는 Locked decision 6의 compact JSON을 독립적으로 SHA-256 계산한 값이다. 실제 fixture는 아래 생성 정보와 ID를 둘 다 직접 보존한다.

| 별칭 | scope | trigger | action | effect | exceptions | 기대 rule ID |
|---|---|---|---|---|---|---|
| `verify` | `["repo"]` | `completion.before-report` | `verification.run-required-checks` | `require` | `[]` | `tr-sha256-74f9deffbfc04c847b2ec6aa0b8ead0a961edc3bae1b208d3500a29f9a8b4ab9` |
| `verify-forbid` | `["repo"]` | `completion.before-report` | `verification.run-required-checks` | `forbid` | `[]` | `tr-sha256-a5fcce04ab40e21df210e5f28ce951fc0791621d3f09020bf5b126b24904aeef` |
| `verify-equivalent` | `["repo"]` | `completion.before-finish` | `verification.execute-required-checks` | `require` | `[]` | `tr-sha256-edff8a53cb5fecbb561212bab2675f2250909fa8b509baeb19fc7053ce5a48b4` |
| `test-before-report` | `["repo"]` | `completion.before-report` | `tests.run-required-checks` | `require` | `[]` | `tr-sha256-541a405c5b769cbc44525f789895b8bb2e3b9e266c5cd9c67da66b1e1e94106c` |
| `general-with-exception` | `["repo"]` | `completion.before-report` | `checks.run-required` | `require` | `["문서만 바꾼 경우"]` | `tr-sha256-2baffd385e2e70125ff012c43575ab020c76509ef95835762c045ce094aae559` |
| `verify-src` | `["tree:src"]` | `completion.before-report` | `verification.run-required-checks` | `require` | `[]` | `tr-sha256-93248d433916b4529a16bc5a69f8b80bfa7d4d6d0de045801bd547b9c4caf698` |
| `verify-docs` | `["tree:docs"]` | `completion.before-report` | `verification.run-required-checks` | `require` | `[]` | `tr-sha256-e7e0994468a56ef5770f8f9b1d8169c4f5155ed0fbf2fcf086c304a26729bff7` |

신규 후보는 같은 digest의 prefix만 `tc-sha256-`로 바꾼다. request fixture의 고정 ID는 `retire/no-replacement` = `rq-sha256-4af45c571c77a32836d0dc771a7be32f5dca46a43976ce924a2ecb30f353482b`, `rephrase/changed-statement` = `rq-sha256-b810fa1a064a7774f240a2d1746c6ef34bb8f085ca8322c33c80610cf7bccab6`, `scope/narrow` = `rq-sha256-1fceb0947cec87d57da506e2f3c9711467192cbdcc606b6cf98c5f010d64189d`이며 이 세 request의 target은 `verify` rule이다. scope 확대와 mixed 회귀용 `scope/expand`와 `scope/mixed` request는 target이 모두 `verify-src` rule이고 `requested_scope`가 각각 `["repo"]`, `["tree:docs"]`다. 두 request의 `rq-sha256-` ID는 같은 파생으로 계산해 각 fixture 파일에 리터럴로 고정한다.

`conflict/opposite-effect`는 `verify` 후보와 `verify-forbid` 후보를 입력으로 쓴다. 기대 conflict ID는 `cf-sha256-81ddc1757dff3e27c6e0125acf1b4621414586f9fb8fcd57a1c9b8a4e173d6d3`다. option은 ID 순으로 `to-sha256-40cfff6d4bb189cc6c1cfdec6ea71f60d71e4503ed5ff6f4ad0903f23f1f53ed` `keep-existing`, `to-sha256-d10fa2e0c6694848633b7a36b36e4ca178884dd3de86f8478f1f7931c6c36d6b` `revise-input`이다. proposal state는 `conflict`, canonical before와 after는 모두 virtual empty, transition approval은 요구하지 않지만 종료 선택에는 사람 결정이 필요하며 `shared_diff` = `false`다.

replace-scope 회귀는 세 방향을 모두 고정한다. `normal/replace-scope-approved`는 `verify`(`["repo"]`)를 `verify-src`(`["tree:src"]`)로 바꿔 `scope_impact: narrow`, `normal/replace-scope-expand-approved`는 `verify-src`를 `verify`로 바꿔 `scope_impact: expand`, `normal/replace-scope-mixed-approved`는 `verify-src`를 `verify-docs`(`["tree:docs"]`)로 바꿔 `scope_impact: mixed`다. 세 case 모두 기존 ID는 같은 ID의 `retired`, 신규 ID는 `active`가 되는 원자적 `replace-scope` 전이 하나를 만들고 `shared_diff` = `true`다. `unapproved/replace-scope-expand`와 `unapproved/replace-scope-mixed`는 같은 proposal ID를 `proposed`로 두고 canonical before와 after가 같으며 `shared_diff` = `false`다.

`forbidden/id-collision`는 같은 생성 정보(같은 `tc-sha256-` digest)를 갖되 정규화된 `statement`만 서로 다른 신규 후보 2개를 입력으로 쓴다. lexical 최소 statement로 하나를 소거하지 않고, 두 변형을 conflict envelope의 `candidates`에 ID 뒤 compact JSON byte 순으로 둘 다 보존한 rank 1 `id-collision` conflict를 기대한다. proposal state는 `conflict`, canonical before와 after는 같고 `shared_diff` = `false`다.

### case matrix

| category / case | 기대 ID와 정렬 | 상태 | 승인 | shared diff |
|---|---|---|---|---|
| `normal/promote-approved` | 위 기준 `tc`, `tr`, `tx` 각 1개 | `proposed -> approved`, `[] -> [active]` | 두 단계 제공됨 | `true` |
| `normal/merge-approved` | `verify` ID가 active canonical, `verify-equivalent` ID가 retired. Active는 ID 순으로 `verify`, retired는 `verify-equivalent` | 두 active가 승인 후 active 1개와 retired 1개 | 두 단계 제공됨 | `true` |
| `normal/generalize-approved` | 새 canonical은 `general-with-exception`, 원본은 `test-before-report`, `verify` ID 순 | 새 규칙과 두 원본 모두 active, 두 원본은 새 규칙을 `specializes`로 참조 | 두 단계 제공됨 | `true` |
| `normal/retire-approved` | target `verify`, request `rq-sha256-4af45c571c77a32836d0dc771a7be32f5dca46a43976ce924a2ecb30f353482b` | `active -> retired`, ID 보존 | 두 단계 제공됨 | `true` |
| `normal/replace-scope-approved` | old `verify` retired, new `verify-src` active, request `rq-sha256-1fceb0947cec87d57da506e2f3c9711467192cbdcc606b6cf98c5f010d64189d` | `scope_impact: narrow`, 두 rule 상태 원자적 변경 | 두 단계 제공됨 | `true` |
| `normal/replace-scope-expand-approved` | request `scope/expand` (target `verify-src`), canonical before `[verify-src active]`, after `[verify-src retired, verify active]` | `scope_impact: expand`, 두 rule 상태 원자적 변경 | 필요, 두 단계 제공됨 | `true` |
| `normal/replace-scope-mixed-approved` | request `scope/mixed` (target `verify-src`), canonical before `[verify-src active]`, after `[verify-src retired, verify-docs active]` | `scope_impact: mixed`, 두 rule 상태 원자적 변경 | 필요, 두 단계 제공됨 | `true` |
| `normal/rephrase-approved` | rule `verify`, request `rq-sha256-b810fa1a064a7774f240a2d1746c6ef34bb8f085ca8322c33c80610cf7bccab6` | ID와 active 유지, content hash만 변경 | 두 단계 제공됨 | `true` |
| `unapproved/promote`, `merge`, `generalize`, `retire`, `replace-scope`, `rephrase` | 동일 normal case와 같은 proposal ID | proposal은 `proposed`, canonical before = after | 필요하지만 미제공 | `false` |
| `unapproved/replace-scope-expand` | 동일 normal expand case와 같은 proposal ID, canonical before와 after 모두 `[verify-src active]` | `scope_impact: expand`, proposal은 `proposed`, canonical no-op | 필요하지만 미제공 | `false` |
| `unapproved/replace-scope-mixed` | 동일 normal mixed case와 같은 proposal ID, canonical before와 after 모두 `[verify-src active]` | `scope_impact: mixed`, proposal은 `proposed`, canonical no-op | 필요하지만 미제공 | `false` |
| `conflict/opposite-effect` | 위 `cf`, `to` ID와 option ID 순 | `conflict`, canonical before = after | transition 승인 없음, 사람 선택 필요 | `false` |
| `conflict/ambiguous-semantics`, `overlapping-groups`, `multiple-requests` | rank로 code를 고른 후 member ID, option ID 순 | `conflict`, canonical before = after | transition 승인 없음, 사람 선택 필요 | `false` |
| `forbidden/malformed`, `self-edge`, `unknown-key`, `direct-scope-edit` | proposal, option, transition ID 없음 | `schema-error`, canonical before = after | 승인 불가 | `false` |
| `forbidden/id-collision`, `retired-reactivation`, `missing-disposition` | rank 1 `id-collision`, rank 2 `retired-id-reuse`, rank 3 `source-disposition-invalid` conflict ID | `conflict`, canonical before = after | transition 승인 없음, 사람 선택 필요 | `false` |
| `forbidden/hash-mismatch`, `ambiguous-approval`, `stale` | 원 proposal ID를 유지하거나 stale로 폐기 | `approval-error` 또는 `stale`, canonical before = after | 제공됐으나 거부 | `false` |
| `privacy/raw-sentinel`, `absolute-path`, `already-tracked` | proposal ID 없음 | `privacy-error`, canonical before = after | 승인 불가 | `false` |
| `boundary/empty-ledger` | candidate, request, proposal ID 없음 | canonical before = after, proposal 목록 `[]` | 승인 대상 없음 | `false` |
| `idempotency/reapply-approved` | 기준 `tr`, `tx` ID 유지, 새 proposal ID 없음 | revision 1과 after byte hash 유지 | 재승인 대상 없음 | `false` |
| `sync/divergent-approved-branches` | 두 branch가 각자 고정한 서로 다른 transition ID를 보존 | Git merge conflict, canonical 재계산 금지 | 명시적 사람 해결 전에 적용 금지 | 자동 diff `false` |

`expected-error.json`의 key 순서는 `schema`, `type`, `code`, `shared_diff`다. 금지 fixture의 `(type, code)`는 `malformed` = (`schema-error`, `malformed-json`), `self-edge` = (`schema-error`, `self-edge`), `unknown-key` = (`schema-error`, `unknown-key`), `direct-scope-edit` = (`schema-error`, `direct-scope-edit`), `hash-mismatch` = (`approval-error`, `after-byte-hash-mismatch`), `ambiguous-approval` = (`approval-error`, `transition-id-required`), `stale` = (`stale`, `base-state-mismatch`)로 고정한다. privacy fixture는 `raw-sentinel` = (`privacy-error`, `raw-adapter-shape`), `absolute-path` = (`privacy-error`, `evidence-ref-not-allowlisted`), `already-tracked` = (`privacy-error`, `machine-local-path-tracked`)를 쓴다. 모든 `shared_diff`는 `false`다.

정상 matrix의 각 transition ID, content hash, after byte hash는 해당 `expected-proposal.json`, `expected-after.md`, `approval-confirmation.json`에 리터럴로 둔다. `normal/promote-approved`의 위 고정값을 첫 seed로 삼고, 다음 normal base는 바로 이전 승인 fixture의 `expected-after.md`를 복사하지 않고 각 case에 독립적으로 고정한다. 이렇게 해야 한 snapshot 갱신이 다른 case의 기대 ID를 연쇄적으로 바꾸지 않는다.

실제 fixture를 추가할 때는 validator를 처음 실행하기 전에 모든 case의 비어 있지 않은 ID, state, order, content hash, after byte hash를 `expected.json`과 예상 파일에 리터럴로 작성해 먼저 commit한다. 예상 값을 생성하거나 갱신하는 snapshot mode는 suite에 두지 않고, validator 출력을 복사해 첫 기대값을 만들지 않는다. 리터럴이 없는 case는 미완성 fixture이며 `tests/team-rules-verify.sh`가 실행하기 전에 실패해야 한다. 현재는 schema rollout 미승인이므로 이 리터럴 파일을 생성하지 않았으며, 위 catalog와 seed는 스펙 수준에서 독립 계산한 상수다.

`idempotency/reapply-approved`는 `normal/promote-approved/expected-after.md`를 base와 expected after로 동시에 쓴다. 같은 normalized candidate를 다시 입력하면 active no-op이며 revision, count, transition ledger, 문서 byte가 하나도 바뀌지 않아야 한다. 실행 전후를 `cmp -s`와 `git diff --exit-code`로 모두 검사하고, 새 proposal이나 승인 요청이 생기면 실패다.

`sync/divergent-approved-branches`는 같은 committed `base.md`에서 `team-a`, `team-b` branch를 만든다. 두 branch는 같은 `verify` rule의 `statement` 한 줄을 서로 다른 문장으로 rephrase하는 서로 다른 승인 transition의 전체 render를 commit한다. 각 branch의 request ID, transition ID, after byte는 fixture에 따로 고정한다. `team-a`에서 `git merge --no-commit --no-ff team-b`는 non-zero여야 하고 `test -n "$(git ls-files -u -- .nova/team-rules.md)"`로 unmerged entry를 확인한다.

gardener는 conflict marker를 파싱하거나 ID, revision, ledger를 재산출하지 않는다. 테스트는 `git merge --abort` 후 `team-a` HEAD의 byte와 `cmp -s`를 통과시켜 기존 active 정책이 손상되지 않았음을 입증한다. 실제 해결은 사람이 두 diff의 영향을 검토하고 새 base revision에서 전이를 다시 제안해 개별 승인한다.

`set -e`에서 예상된 merge conflict만 받고 fatal error를 숨기지 않도록 아래 idiom을 쓴다. merge exit는 정확히 1이어야 하며 unmerged index가 없으면 실패다.

```sh
if git merge --no-commit --no-ff team-b; then
  exit 1
else
  merge_status=$?
  test "$merge_status" -eq 1 || exit "$merge_status"
fi
test -n "$(git ls-files -u -- .nova/team-rules.md)"
```

### 정렬과 결정성 fixture

`determinism/input-order-a.json`과 `input-order-b.json`은 같은 normalized set의 candidate, request, relation 배열만 역순으로 둔다. 한 실행은 `LANG=C`, 다른 실행은 `LANG=ko_KR.UTF-8`로 지정하되 shell `sort`는 사용하지 않는다. locale 설치 여부가 실행 성패를 결정하지 않도록 정렬은 Node `Buffer.compare`로만 한다.

전체 proposal 정렬 rank는 `conflict`, `merge`, `generalize`, `replace-scope`, `promote`, `retire`, `rephrase`다. 고정 ID catalog을 함께 출력하는 fixture의 rule ID 순서는 `general-with-exception`, `test-before-report`, `verify`, `verify-src`, `verify-forbid`, `verify-docs`, `verify-equivalent`다. request ID 순서는 `scope/narrow`, `retire/no-replacement`, `rephrase/changed-statement`다. 모든 비교는 완전한 ID byte를 쓰고 별칭이나 표시 문장을 tie-break에 쓰지 않는다.

### 실행 순서와 성공 조건

도입 후의 상위 실행 순서는 아래 1부터 9까지다. `tests/team-rules-verify.sh`는 3부터 9까지의 신규 case만 오케스트레이션하고 기존 3개 회귀를 다시 호출하지 않는다. 상위 runner와 신규 suite는 예상한 non-zero를 위의 merge처럼 명시적으로 캡아 검사하는 경우를 제외하고 첫 non-zero에서 즉시 종료한다.

1. `bash -n tests/*.sh`와 prose lint로 shell과 스펙 문법을 먼저 검사한다.
2. `inc15-verify.sh`, `gate-verify.sh`, `worklog-verify.sh` 순으로 기존 3개 회귀를 실행한다.
3. schema 거부와 고정 ID catalog를 검사하고 `boundary/empty-ledger`를 실행한 뒤 정상, 미승인, conflict case 순으로 실행한다. 정상 순서에 `normal/replace-scope-approved`, `normal/replace-scope-expand-approved`, `normal/replace-scope-mixed-approved`를, 미승인 순서에 `unapproved/replace-scope`, `unapproved/replace-scope-expand`, `unapproved/replace-scope-mixed`를 두어 narrow, expand, mixed의 승인 적용과 no-op을 모두 검사한다.
4. 서로 다른 임시 Git 저장소에서 input order와 `LANG`이 다른 두 실행을 수행한다. proposal byte와 승인 후 after byte 각각에 `cmp -s`와 `git diff --no-index --exit-code --`를 모두 적용한다.
5. `idempotency/reapply-approved`를 실행해 revision, count, transition ledger, after byte가 그대로고 새 proposal과 승인 요청이 없음을 검사한다.
6. 미승인, conflict, 금지 case는 fixture 입력과 canonical base를 commit한 baseline에서 시작한다. 실행 전후에 `git diff --exit-code -- .nova/team-rules.md`와 `test -z "$(git status --short)"`를 모두 통과시킨다.
7. privacy ignore, index 비추적, sentinel 불유출을 순서대로 검사한다.
8. 승인 case를 임시 commit한 뒤 `git diff` 결과와 `git log --follow`의 필수 추적 필드를 검사한다. 이어서 `sync/divergent-approved-branches`를 실행해 merge conflict, unmerged index, abort 후 byte 보존을 검사한다.
9. `portability/unused-empty-repo`, `portability/opted-in-empty-repo` 순으로 인증과 네트워크 없이 실행한 뒤 전체 suite를 종료한다.

```sh
set -eu
bash -n tests/*.sh
node plugins/nova/scripts/lint-prose.mjs docs/specs/2026-07-13-team-rules-artifact.md
bash tests/inc15-verify.sh
bash tests/gate-verify.sh
bash tests/worklog-verify.sh
bash tests/team-rules-verify.sh
```

결정성 검사는 아래 두 명령이 둘 다 exit 0일 때만 통과다. `git diff --no-index`의 exit 1을 사람이 눈으로 확인했다는 이유로 무시하지 않는다.

```sh
cmp -s "$RUN_A/proposal.json" "$RUN_B/proposal.json"
git diff --no-index --exit-code -- "$RUN_A/proposal.json" "$RUN_B/proposal.json"
cmp -s "$RUN_A/after.md" "$RUN_B/after.md"
git diff --no-index --exit-code -- "$RUN_A/after.md" "$RUN_B/after.md"
```

privacy fixture는 raw sentinel을 `ledger.jsonl`에만 두고 proposal, preview, canonical, test stdout·stderr 경로만 검색한다. raw input 자체를 검색 대상에 넣어 예상된 감지를 유출로 오판하지 않는다. 모든 출력 경로는 검색 전에 존재하는 directory로 만들어 `grep` exit 2가 불유출 통과로 오인되지 않게 한다.

```sh
git check-ignore -v --no-index -- .nova/evidence.jsonl
git check-ignore -v --no-index -- .nova/gate-history.jsonl
git check-ignore -v --no-index -- .nova/gate-verdict.json
! git ls-files --error-unmatch -- .nova/evidence.jsonl
! git ls-files --error-unmatch -- .nova/gate-history.jsonl
! git ls-files --error-unmatch -- .nova/gate-verdict.json
test -d "$RUN_OUT/proposals"
test -d "$RUN_OUT/previews"
test -d "$RUN_OUT/canonical"
test -d "$RUN_OUT/stdout"
test -d "$RUN_OUT/stderr"
if grep -R -F -- "$NOVA_RAW_SENTINEL" "$RUN_OUT/proposals" "$RUN_OUT/previews" "$RUN_OUT/canonical" "$RUN_OUT/stdout" "$RUN_OUT/stderr"; then
  exit 1
else
  grep_status=$?
  test "$grep_status" -eq 1 || exit "$grep_status"
fi
```

portability는 두 case로 나눈다. `portability/unused-empty-repo`는 `mktemp -d`와 `git init`만 실행한 뒤 Nova 세션 시작 경로를 호출해도 파일, stdout, context 주입이 없어야 한다. `portability/opted-in-empty-repo`는 도입 승인 후의 최소 `.nova/.gitignore`만 baseline commit한 뒤 virtual revision 0에서 제안 생성과 미승인 no-op를 실행한다. 두 case 모두 `HOME`, `GIT_CONFIG_SYSTEM`, `GIT_CONFIG_GLOBAL`을 격리하고 로컬 Nova 파일과 system `git`, `node` 외의 인증 token, 외부 URL, 회사 CLI를 주입하지 않는다. 통과 시 각 baseline 대비 `git status --short`가 비어 있어야 한다.

## 별도 사용자 승인 항목

이 문서를 추가하는 것은 소비자 저장소의 `.nova/`를 바꾸지 않는다. 다음 항목은 스펙 확정과 실행 권한을 분리하기 위해 사용자가 별도로 결정한다.

| 승인 항목 | 영향 | 기본값 |
|---|---|---|
| `nova.team-rules/v1` 스키마 도입 | `.nova/team-rules.md` 형식과 `.nova/.gitignore` allowlist를 도입한다. | 미도입 |
| 플러그인 구현 | `/learn review` 연결, canonicalization, ID, privacy preflight, 승인 검증, fixture를 추가한다. | 미구현 |
| 마이그레이션 | 기존 Self-Learning Rules를 backfill할지 선택한다. | no backfill |
| 배포 | 승인된 구현과 fixture를 검증한 뒤 플러그인 배포를 수행한다. | 미배포 |

기본 마이그레이션 제안은 no backfill이다. 기존 Self-Learning Rules는 그대로 두고, 도입 이후 새로 승인된 전이부터 `.nova/team-rules.md`에 기록한다. backfill이 필요하면 기존 규칙 각각을 `promote` 제안으로 만들고 개별 전이 ID 승인을 받는다.

하나의 승인을 스키마, 구현, 마이그레이션, 배포 전체에 대한 포괄 승인으로 해석하지 않는다. 각 단계는 직전 단계의 결과와 마이그레이션 영향을 보여준 뒤 명시적 사용자 승인을 다시 받는다. 특히 배포 승인은 스키마 도입이나 구현 승인에 포함되지 않는다.

## 승인 게이트

현재 상태는 `design-locked-rollout-unapproved`다. 설계 경계는 이 문서로 고정하지만 스키마를 사용자 저장소에 도입하지는 않는다. 도입을 원하면 사용자가 `nova.team-rules/v1 도입 승인`이라고 명시해야 한다. 승인 전에는 hook, script, skill, ignore 로직을 변경하지 않는다.
