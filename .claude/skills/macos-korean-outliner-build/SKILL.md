---
name: macos-korean-outliner-build
description: macOS 한/영 입력 상태 외곽선 표시 앱(Korean Outliner)의 설계·구현·검증을 위한 통합 오케스트레이터. 이 프로젝트의 빌드/구현/리팩토링/QA/리뷰 요청이 들어오면 반드시 이 스킬을 사용할 것. "한영 외곽선", "Korean Outliner", "외곽선 앱 만들어", "macOS 입력 상태 표시", "외곽선 모듈 추가/수정", "다시 실행", "재실행", "QA 다시", "리뷰 다시", "이전 결과 기반으로", "워크플로우 업데이트" 같은 표현 모두 트리거 대상이다.
---

# Korean Outliner Build Orchestrator

macOS 한/영 입력 상태 외곽선 앱의 전체 구현 워크플로우. 7명 에이전트 팀을 조율한다.

## 산출물 (워크스페이스)

```
_workspace/
├── 00_changelog.md             # 변경 이력
├── 01_architecture.md          # architect
├── 02_interfaces.swift         # architect (SSoT)
├── 03_tech_decisions.md        # architect (ADR)
├── modules/                    # dev 4명
│   ├── InputSourceMonitor.swift
│   ├── FocusedWindowTracker.swift
│   ├── OverlayWindow*.swift
│   ├── PreferencesView.swift
│   ├── AppDelegate.swift
│   └── ...
├── qa/                         # qa-integrator
│   ├── qa_report.md
│   ├── integration_checklist.md
│   └── manual_test_scenarios.md
└── review/                     # reviewer
    └── review_report.md
```

최종 결과물(Xcode 프로젝트 또는 Swift 소스)은 사용자 지정 경로에 생성하고, `_workspace/`는 검증·재실행 추적용으로 보존한다.

## Phase 0: 컨텍스트 확인

워크플로우 시작 시 가장 먼저 실행 모드를 결정한다.

```
if _workspace/ 미존재:
    → 초기 실행 (Phase 1부터 전체)

if _workspace/ 존재 + 사용자가 "전부 다시"/"새로 만들어":
    → 새 실행: _workspace/ 를 _workspace_prev_{timestamp}/ 로 이동 후 Phase 1부터

if _workspace/ 존재 + 사용자가 특정 모듈/단계만 수정 요청:
    → 부분 재실행: 해당 에이전트만 재호출, 다른 모듈은 그대로

if _workspace/ 존재 + "QA 다시" / "리뷰 다시":
    → qa-integrator 또는 reviewer만 재호출
```

부분 재실행 결정 매핑:
- "아키텍처/인터페이스" 수정 → architect 재호출 → 영향받는 dev 재호출 → qa/review 재호출
- "한영 감지 부분" → input-monitor-dev → qa
- "윈도우 추적/권한" → window-tracker-dev → qa
- "외곽선 렌더링/색상/두께" → overlay-renderer-dev → qa
- "메뉴바/Preferences" → preferences-dev → qa
- "결함 보고/QA" → qa-integrator
- "코드 리뷰" → reviewer

## Phase 1: 설계 (단일 에이전트)

**실행 모드**: 단일 에이전트 (architect)

`architect`만 호출. 산출:
- `_workspace/01_architecture.md`
- `_workspace/02_interfaces.swift` (SSoT)
- `_workspace/03_tech_decisions.md`

이 단계는 **순차적**이다. 다른 에이전트는 02_interfaces.swift 없이는 시작할 수 없다.

```
Agent(
  description="아키텍처 설계",
  subagent_type="general-purpose",
  model="opus",
  prompt="""
  당신은 .claude/agents/architect.md에 정의된 architect 에이전트로 동작한다.
  REQUIREMENTS.md를 읽고 macos-architecture 스킬을 활용하여
  _workspace/01_architecture.md, _workspace/02_interfaces.swift,
  _workspace/03_tech_decisions.md 를 생성하라.

  완료 후 02_interfaces.swift의 핵심 protocol 목록을 요약 보고하라.
  """
)
```

## Phase 2: 구현 (에이전트 팀)

**실행 모드**: 에이전트 팀 — 4명의 dev가 병렬 구현하지만 인터페이스 충돌·재조정이 빈번하므로 팀 통신이 핵심

팀 구성:
- input-monitor-dev
- window-tracker-dev
- overlay-renderer-dev
- preferences-dev

```
TeamCreate(
  team_name="korean-outliner-dev",
  members=["input-monitor-dev", "window-tracker-dev", "overlay-renderer-dev", "preferences-dev"]
)
```

각 팀원에 작업 할당 (`TaskCreate`):
1. 모두에게 공통 입력: `_workspace/02_interfaces.swift` 정독
2. 각자 담당 모듈 파일 생성 (각 에이전트 .md 참조)
3. 의존 관계:
   - overlay-renderer-dev는 input-monitor-dev/window-tracker-dev의 publisher 계약을 받아야 함 → 하지만 02_interfaces.swift만 있으면 시작 가능
   - preferences-dev는 overlay-renderer-dev의 OverlayConfig 필드 요구사항을 받아야 함 → 양방향 협의

**팀원 간 통신 (SendMessage):**
- overlay-renderer-dev → input-monitor-dev: "Publisher 타입이 AnyPublisher<InputLanguage, Never> 맞는가?"
- preferences-dev → overlay-renderer-dev: "OverlayConfig.sides는 OptionSet으로 충분한가?"
- 모두 → architect: 인터페이스 변경 요청 시

**규칙:**
- 인터페이스 변경 시 architect만이 02_interfaces.swift를 수정한다
- 변경 후 architect가 모든 dev에게 SendMessage로 공지

완료 조건: `_workspace/modules/` 하위에 모든 모듈 .swift 파일 존재 + 각 에이전트의 `*_contract.md` 존재

## Phase 3: 검증 (팬아웃 → 통합)

**실행 모드**: 하이브리드 — qa-integrator와 reviewer 병렬 실행 (팀 X, 서브 에이전트로 충분)

이전 팀(`korean-outliner-dev`) 정리 후:

```
TeamDelete(team_name="korean-outliner-dev")

# 병렬 실행
Agent(name="qa", subagent_type="general-purpose", model="opus", run_in_background=true,
      prompt=".claude/agents/qa-integrator.md 정의대로 동작. swift-qa-integration 스킬 사용. _workspace/qa/ 산출물 생성")
Agent(name="rv", subagent_type="general-purpose", model="opus", run_in_background=true,
      prompt=".claude/agents/reviewer.md 정의대로 동작. swift-code-review 스킬 사용. _workspace/review/ 산출물 생성")
```

산출:
- `_workspace/qa/qa_report.md`
- `_workspace/review/review_report.md`

## Phase 4: 결함 해소 (반복)

QA/리뷰에서 critical/major 결함이 발견되면:

```
for each critical/major item:
    해당 dev 에이전트를 재호출 (해당 결함만 수정 지시)
```

수정 후 qa-integrator를 재호출하여 결함 해소 확인. 이 루프는 critical/major이 0이 될 때까지 (최대 2회).

## Phase 5: 최종 조립 및 산출물 출력

architect를 다시 호출하여 모듈 조립 가이드를 `_workspace/01_architecture.md`에 추가하고, 사용자에게:

1. Xcode 프로젝트 생성 여부 확인
2. 사용자 지정 경로에 .swift 파일들과 Info.plist 항목 출력
3. 빌드·실행 가이드 (코드사인 미포함, 직접 빌드 안내)

## 데이터 전달 프로토콜

| 전략 | 사용처 |
|------|--------|
| **파일 기반** | `_workspace/` 모든 산출물 — 감사 추적 + 재실행 가능 |
| **메시지 기반** | 팀원 간 인터페이스 협의, 결함 보고 |
| **태스크 기반** | TaskCreate로 의존 관계 명시 (Phase 2) |

파일명 컨벤션: `{phase}_{agent}_{artifact}.{ext}` (예: `01_architect_architecture.md`) 단, 이미 정해진 표준 경로(`02_interfaces.swift` 등)는 그대로 사용.

## 에러 핸들링

| 에러 유형 | 처리 |
|---------|------|
| 에이전트 산출물 누락 | 1회 재시도 → 그래도 누락이면 사용자에게 보고 후 해당 결과 없이 진행 |
| 인터페이스 충돌 | architect 재호출 → 02_interfaces.swift 갱신 → 영향받는 dev 재호출 |
| QA에서 critical 발견 | Phase 4 루프 진입 (최대 2회) |
| Phase 4 루프 2회 후도 critical 잔존 | 사용자에게 보고하고 결정 위임 |
| Xcode 빌드 실패 | qa-integrator가 컴파일 에러를 결함으로 기록 → 해당 dev 재호출 |

## 팀 크기 정당성

이 프로젝트는 모듈 4개 + 검증 2개 = 약 6명 규모. 권장 5~7명에 부합. 4명의 dev가 동시 구현하지만 인터페이스 단일 SSoT(architect)가 있어 조율 오버헤드는 제한적.

## 테스트 시나리오

### 정상 흐름

1. 사용자 "macOS 한/영 외곽선 앱 만들어줘"
2. Phase 0 → _workspace 없음 → 초기 실행
3. Phase 1: architect → 인터페이스 + ADR 생성
4. Phase 2: 4명 팀 구성 → 모듈 병렬 구현 (인터페이스 변경 1~2회 발생, architect 중재)
5. Phase 3: qa + reviewer 병렬 → 결함 보고
6. Phase 4: critical 2건 → 해당 dev 재호출 → 해소 확인
7. Phase 5: 최종 산출물 출력

### 에러 흐름

1. 사용자 "외곽선 색상 변경 즉시 안 됨, 고쳐줘"
2. Phase 0 → _workspace 존재 + 부분 수정 → overlay-renderer-dev + preferences-dev만 재호출
3. 두 에이전트가 publisher 구독 누락 발견 → 수정
4. qa-integrator 재호출 → 해당 시나리오 통과 확인
5. CLAUDE.md 변경 이력에 "OverlayRenderer publisher 구독 누락 수정" 기록

## 후속 작업 트리거 키워드 (description 외 추가)

- "한영 외곽선 / Korean Outliner / 외곽선 앱"
- "다시 실행 / 재실행 / 업데이트 / 수정 / 보완"
- "QA 다시 / 리뷰 다시"
- "외곽선 색상 / 두께 / 위치 / 권한 / 메뉴바"
- "이전 결과 기반"
