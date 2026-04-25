---
name: swift-qa-integration
description: macOS Swift 앱의 모듈 경계면 정합성, 이벤트 흐름 연결성, 권한·라이프사이클 시나리오를 점검할 때 사용하라. 단위 테스트가 아니라 "A 모듈의 출력 shape이 B 모듈의 입력에 맞는가"를 교차 비교하는 통합 QA 방법론을 제공한다. "QA", "통합 검증", "경계면 점검", "회귀 테스트" 키워드가 등장하면 반드시 이 스킬을 사용할 것.
---

# Swift Integration QA

`qa-integrator` 에이전트가 사용하는 통합 QA 방법론.

## 핵심 원칙: 경계면 교차 비교

단위 테스트는 dev 에이전트가 책임진다. QA의 역할은 다르다:

- "메서드가 존재하는가?" (X)
- "**A의 출력 타입과 B의 입력 타입이 같은가?**" (O)
- "**A의 이벤트 시점에 B가 구독 중인가?**" (O)

## 검증 절차

### 1. 인터페이스 SSoT 일치 확인

`_workspace/02_interfaces.swift`에 정의된 모든 protocol에 대해:

```
[ ] InputSourceMonitoring 프로토콜 → InputSourceMonitor가 구현?
    [ ] var current 타입 일치
    [ ] var publisher 타입 일치 (AnyPublisher<InputLanguage, Never>)
    [ ] start/stop 시그니처 일치
[ ] FocusedWindowTracking 프로토콜 → FocusedWindowTracker
[ ] OverlayRendering 프로토콜 → OverlayRenderer
```

**Bash 검증 예시:**
```bash
grep -n "protocol InputSourceMonitoring" _workspace/02_interfaces.swift
grep -n "InputSourceMonitoring" _workspace/modules/InputSourceMonitor.swift
```

### 2. 이벤트 흐름 끝-끝 추적

도식:
```
InputSourceMonitor.publisher
    └─→ OverlayRenderer (구독)
        └─→ OverlayContentView.update(language:)

FocusedWindowTracker.publisher
    └─→ OverlayRenderer (구독)
        └─→ OverlayWindowController.show(at:)

PreferencesStore.publisher
    └─→ OverlayRenderer (구독)
        └─→ OverlayContentView.update(config:)
```

체크:
- [ ] OverlayRenderer가 3개 publisher 모두 구독하는가?
- [ ] 구독 위치가 `init` 또는 `start()`인가? (지연 구독 시 초기 이벤트 누락)
- [ ] `cancellables`에 store 되는가? (안 하면 즉시 해제)

### 3. 라이프사이클 정합성

| 시나리오 | 기대 동작 | 점검 포인트 |
|---------|---------|-----------|
| 앱 시작 | InputMonitor 즉시 시작, WindowTracker는 권한 있을 때만 | AppDelegate.applicationDidFinishLaunching |
| 권한 허용 | WindowTracker 자동 시작 | PermissionViewModel의 `tracker?.start()` |
| 권한 revoke | WindowTracker 정지, AXObserver 해제 | tracker.stop() 호출 경로 존재 여부 |
| 앱 종료 | 모든 옵저버 해제 | applicationWillTerminate 또는 deinit |

### 4. 좌표계 변환 검증

WindowTracker → OverlayRenderer 흐름에서:
- WindowFrame.frame은 AX 좌표(top-left)인가?
- OverlayRenderer가 NSScreen 정보로 변환하는가?
- 멀티 모니터 시 올바른 스크린 선택?

**증거 수집 방식:**
- `nsRect(from:on:)` 함수 존재 확인
- WindowTracker가 `screen` 필드를 채워서 보내는지 확인
- 멀티 모니터에서 시각 검증 (수동)

### 5. 설정 변경 전파 검증

PreferencesView 토글 → PreferencesStore.config → publisher → OverlayRenderer

체크:
- `config.didSet { save() }`가 publisher emit을 트리거하는가?
- `@Published`이므로 자동으로 emit 됨
- OverlayRenderer가 즉시 layer 갱신하는가?

수동 검증: Preferences에서 두께 슬라이더 움직였을 때 외곽선이 즉시 바뀌는지.

## 결함 보고 형식

`_workspace/qa/qa_report.md`에 다음 형식:

```markdown
## QA-001: OverlayRenderer가 PreferencesStore publisher를 구독하지 않음 [critical]

**위치**: `_workspace/modules/OverlayRenderer.swift:32`

**증상**: Preferences에서 색상 변경 시 외곽선 색이 바뀌지 않음

**재현**:
1. 앱 실행 → 한글 입력 상태 → 외곽선 파란색 확인
2. Preferences 열기 → 한글 색상을 보라색으로 변경
3. 텍스트 입력 → 여전히 파란색 (기대: 보라색)

**추정 원인**: OverlayRenderer.start()에 preferencesStore.publisher 구독 누락

**권장 수정**:
```swift
preferencesStore.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] cfg in self?.applyConfig(cfg) }
    .store(in: &cancellables)
```

**담당**: overlay-renderer-dev
```

심각도:
- `critical` — 크래시, 핵심 기능 동작 불가
- `major` — 자주 마주치는 동작 결함
- `minor` — 엣지 케이스, 시각적 사소한 차이

## 자주 발생하는 경계면 버그 (사례)

| 버그 | 증상 | 수정 |
|------|------|------|
| 좌표계 미변환 | 외곽선이 윈도우 위/아래로 뒤집혀 표시 | nsRect(from:on:) 사용 |
| Publisher 초기값 누락 | 앱 시작 시 색상이 회색 | CurrentValueSubject 사용 |
| AXObserver 누수 | 앱 전환 자주 하면 CPU 폭증 | 전환 시 detachObserver |
| 윈도우 레벨 충돌 | 메뉴바 아이콘 클릭 시 메뉴 안 열림 | 오버레이 windowLevel을 statusBar 이하로 |
| `NotificationCenter` 오용 | 한/영 변경 알림 안 옴 | `DistributedNotificationCenter` 사용 |
| Preferences 다중 인스턴스 | 매번 새 윈도우 → 메모리 누적 | window 캐시 |
| Sandbox 활성화 | AX API 동작 X | sandbox 비활성 (App Store 배포 X) |

## 실기기 수동 테스트 시나리오

`_workspace/qa/manual_test_scenarios.md`에 다음 케이스를 모두 포함:

1. **첫 실행 시나리오** — 앱 처음 실행 → Preferences 자동 표시 → 권한 안내 → 시스템 설정 → 권한 허용 → 외곽선 표시
2. **한/영 전환** — 텍스트 에디터에서 Caps Lock 또는 한/영 키 → 외곽선 색상 즉시 변경
3. **앱 전환** — Cmd+Tab으로 여러 앱 순회 → 외곽선이 따라감
4. **윈도우 리사이즈/이동** — 커서로 윈도우 크기 변경 → 외곽선 즉시 추적
5. **전체화면 전환** — 비디오 플레이어 전체화면 → 외곽선 사라지지 않고 표시
6. **멀티 스페이스** — Mission Control 스페이스 간 이동 → 외곽선 따라감
7. **멀티 모니터** — 외부 모니터의 윈도우 클릭 → 해당 모니터에 외곽선 표시
8. **설정 변경** — Preferences에서 위치/색상/두께 변경 → 즉시 반영
9. **권한 revoke** — 시스템 설정에서 AX 권한 해제 → 외곽선 사라짐 + Preferences가 권한 안내 상태로 전환
10. **앱 종료** — Quit → 외곽선 즉시 사라짐, 다음 실행 시 설정 복원

## 점진적 QA

QA를 모든 모듈 완성 후 1회만 하지 말 것:
- input-monitor-dev 완료 → 즉시 QA-1 (한/영 분류 정확성)
- window-tracker-dev 완료 → 즉시 QA-2 (권한 + AX 추적)
- overlay-renderer-dev 완료 → 즉시 QA-3 (이벤트 흐름 + 좌표 변환)
- preferences-dev 완료 → 즉시 QA-4 (설정 영속화 + UI)
- 전체 통합 → 최종 시나리오 검증

## 산출물 위치

- `_workspace/qa/qa_report.md` — 결함 목록
- `_workspace/qa/integration_checklist.md` — 통과/실패 체크리스트
- `_workspace/qa/manual_test_scenarios.md` — 위 10개 시나리오
