# Integration Checklist — macos-korean-outliner

검증 시점: 2026-04-25 · 표기: PASS / FAIL / WARN(minor) / N/A

---

## 1. 인터페이스 SSoT 일치 (`02_interfaces.swift` ↔ 구현체)

### 1.1 InputSourceMonitoring → InputSourceMonitor
- [x] **PASS** — `final class InputSourceMonitor: InputSourceMonitoring` (`InputSourceMonitor.swift:10`)
- [x] **PASS** — `var current: InputLanguage` (line 18)
- [x] **PASS** — `var publisher: AnyPublisher<InputLanguage, Never>` (line 20-22)
- [x] **PASS** — `func start()` (line 24)
- [x] **PASS** — `func stop()` (line 39)
- [x] **PASS** — CurrentValueSubject로 구독 즉시 초기값 emit

### 1.2 FocusedWindowTracking → FocusedWindowTracker
- [x] **PASS** — `final class FocusedWindowTracker: FocusedWindowTracking` (line 37)
- [x] **PASS** — `var current: WindowFrame?` (line 41)
- [x] **PASS** — `var publisher: AnyPublisher<WindowFrame?, Never>` (line 43-45)
- [x] **PASS** — `var permissionStatus: AXPermissionStatus` (line 47-49)
- [x] **PASS** — `func start()` (line 71)
- [x] **PASS** — `func stop()` (line 100)
- [x] **PASS** — `func openSystemAccessibilityPane()` (line 108)

### 1.3 OverlayRendering → OverlayRenderer
- [x] **PASS** — `final class OverlayRenderer: OverlayRendering` (line 13)
- [x] **PASS** — `func apply(frame: WindowFrame?)` (line 66)
- [x] **PASS** — `func apply(language: InputLanguage)` (line 72)
- [x] **PASS** — `func apply(config: OverlayConfig)` (line 81)
- [x] **PASS** — 편의 생성자 `init(inputMonitor:windowTracker:preferences:)` 라벨이 AppDelegate 호출과 정확히 일치

### 1.4 PreferencesStoring → PreferencesStore
- [x] **PASS** — `final class PreferencesStore: ObservableObject, PreferencesStoring` (line 17)
- [x] **PASS** — `var current: OverlayConfig` (line 35)
- [x] **PASS** — `var publisher: AnyPublisher<OverlayConfig, Never>` (line 37-39)
- [x] **PASS** — `func update(_ config: OverlayConfig)` (line 49)

### 1.5 PreferencesPresenting → 미구현
- [ ] **FAIL** — 어떤 모듈도 `PreferencesPresenting`을 채택하지 않음. AppDelegate.showPreferences()가 사실상 그 역할을 하지만 프로토콜 외부 노출 없음. → **QA-002**
- [ ] **FAIL** — `showAccessibilityPrompt()` 미호출 → 첫 실행 자동 안내 부재

### 1.6 MenuBarPresenting → MenuBarController
- [x] **PASS** — `final class MenuBarController: NSObject, MenuBarPresenting` (line 10)
- [x] **PASS** — `func install()` (line 29)
- [x] **PASS** — `func setEnabled(_:)` (line 37) — **호출처 없음**
- [x] **PASS** — `func setLanguage(_:)` (line 42) — **호출처 없음**
- [ ] **FAIL** — setter 2개가 dead code. AppDelegate가 publisher 구독으로 호출하지 않음 → **QA-001**

---

## 2. 이벤트 흐름 끝-끝 추적

### 2.1 InputSourceMonitor.publisher → OverlayRenderer
- [x] **PASS** — `OverlayRenderer.bind:48-51` — `.receive(on: .main).sink { apply(language:) }.store(in: &cancellables)`
- [x] **PASS** — `apply(language:)`가 `currentFrame != nil && currentConfig.isEnabled`일 때 `controller.refresh(config:language:)` 호출
- [x] **PASS** — `OverlayContentView.update`가 `.korean` / `.english` / `.other`(영문 폴백)에 따라 색상 적용

### 2.2 FocusedWindowTracker.publisher → OverlayRenderer
- [x] **PASS** — `OverlayRenderer.bind:53-56` — sink하여 `apply(frame:)`
- [x] **PASS** — `apply(frame:)`가 `render()`로 위임 → `controller.show(at:config:language:)` 또는 `hide()`
- [x] **PASS** — `WindowFrame == nil`이면 `hide()`

### 2.3 PreferencesStore.publisher → OverlayRenderer
- [x] **PASS** — `OverlayRenderer.bind:58-61` — sink하여 `apply(config:)`
- [x] **PASS** — `apply(config:)`가 `render()`로 즉시 재렌더 → 두께/색상/sides/isEnabled 즉시 반영

### 2.4 publishers → MenuBarController
- [ ] **FAIL** — 어떤 publisher도 MenuBar에 연결되지 않음 → **QA-001**
  - `inputMonitor.publisher` → `menuBar.setLanguage` 누락
  - `preferencesStore.publisher.map(\.isEnabled)` → `menuBar.setEnabled` 누락

### 2.5 구독 위치 / 라이프사이클
- [x] **PASS** — bind는 OverlayRenderer 편의 init 안에서 호출되어 publisher 첫 emit 시점부터 수신
- [x] **PASS** — store(in: &cancellables) 누락 없음 — 즉시 해제 위험 없음

---

## 3. 라이프사이클 정합성

| 시나리오 | 기대 동작 | 실제 | 상태 |
|---------|---------|------|------|
| 앱 시작 (권한 있음) | InputMonitor.start, Tracker.start, Renderer 구독 활성 | 모두 수행 | PASS |
| 앱 시작 (권한 없음) | InputMonitor.start, Tracker.start 보류, Preferences 자동 표시 | InputMonitor.start만 수행, Preferences 자동 표시 누락 | FAIL (QA-002) |
| 권한 허용 (revoked → granted) | PermissionViewModel 폴링 → tracker.start | 동작 (line 56) | PASS |
| 권한 revoke (granted → denied) | tracker.stop, AXObserver 해제, 외곽선 사라짐 | tracker.stop 호출 없음 | FAIL (QA-014) |
| 앱 종료 | 모든 옵저버 해제, 외곽선 즉시 사라짐 | applicationWillTerminate 미구현, deinit 의존 | FAIL (QA-003) |
| 앱 전환 (Cmd+Tab) | 이전 앱 AXObserver 해제, 새 앱 attach | `attach(to:)` 첫 줄 detachObserver 호출 | PASS |

---

## 4. 좌표계 변환 (AX top-left → NS bottom-left)

- [x] **PASS** — `WindowFrame.frame`은 AX 좌표 그대로 emit (FocusedWindowTracker.swift:309) — 변환 없음
- [x] **PASS** — NS 변환은 OverlayWindowController 단독 책임 (`nsRect(from:on:)` line 70)
- [x] **PASS** — 변환식: `ns.y = primary.frame.maxY - (ax.y + ax.height)` SSoT 가이드와 일치
- [WARN] **WARN** — Tracker의 `screenContaining`은 `NSScreen.screens.first`를, Renderer의 `primaryScreen()`은 `origin == .zero` 우선 — 멀티 모니터 비표준 배치에서 비대칭 가능 → **QA-012**
- [x] **PASS** — `WindowFrame.screen`을 Tracker가 채우고 Renderer가 우선 사용 (line 27 `windowFrame.screen ?? NSScreen.main`)
- [x] **PASS** — 0 크기 프레임 / 기준 스크린 부재 시 hide 안전 처리

---

## 5. 설정 변경 전파

- [x] **PASS** — `PreferencesStore.config setter` → `objectWillChange.send` → `save(newValue)` → `subject.send(newValue)` 순서 (라인 25-33)
- [x] **PASS** — 영속화(JSONEncoder → UserDefaults) 후 publisher emit 보장
- [x] **PASS** — OverlayRenderer.apply(config:)가 즉시 render() 호출 → 두께/색상/sides/isEnabled 적용
- [x] **PASS** — PreferencesView의 모든 컨트롤이 `bind(\.field)` 또는 직접 binding으로 store.config 갱신 (즉시 반영 보장)
- [x] **PASS** — `isEnabled == false`이면 OverlayContentView가 모든 layer 숨김 + Renderer.render에서도 `controller.hide()` 이중 가드
- [WARN] **WARN** — SwiftUI 갱신 패턴이 표준 `@Published`가 아닌 수동 `objectWillChange + computed property` — 동작은 함 → **QA-015**

---

## 6. 권한 플로우

- [x] **PASS** — `AXPermission.status()` (`AXPermission.swift:17`) — 비파괴 조회
- [x] **PASS** — `AXPermission.requestIfNeeded()` (line 27) — 명시적 사용자 액션에서만 호출 (PreferencesView "권한 허용" 버튼)
- [x] **PASS** — `AXPermission.openSystemSettings()` (line 34) — 직링크 URL 사용
- [x] **PASS** — Tracker.start가 권한 미부여 시 nil emit + .denied 노출 (line 75-79) — contract 일치
- [WARN] **WARN** — Timer.scheduledTimer가 메인 RunLoop에서 도는 게 보장되지 않을 수 있음 → **QA-004**
- [ ] **FAIL** — revoke 방향에서 tracker.stop() 미호출 → **QA-014**

---

## 7. 누수·성능 점검

- [x] **PASS** — NSStatusItem 강한 참조 (MenuBarController에 statusItem property로 보유, AppDelegate가 menuBar 강한 참조)
- [x] **PASS** — AXObserver: attach 시 detachObserver 호출 → 누수 방지 (FocusedWindowTracker.swift:116)
- [x] **PASS** — DistributedNotificationCenter observer: stop()/deinit에서 removeObserver (InputSourceMonitor.swift:42)
- [x] **PASS** — NSWorkspace observer: teardown에서 removeObserver (FocusedWindowTracker.swift:227)
- [x] **PASS** — Preferences 윈도우 캐시 (`AppDelegate.preferencesWindow == nil` 가드, `isReleasedWhenClosed = false`)
- [x] **PASS** — OverlayWindow는 `hidesOnDeactivate = false`, `animationBehavior = .none`, `ignoresMouseEvents = true` — 메뉴바 클릭 차단/애니메이션 깜빡임 없음
- [x] **PASS** — Combine cancellables는 OverlayRenderer가 보유, deinit에서 자동 해제

---

## 8. 빌드/링크 사전 점검 (정적)

- [x] **PASS** — 모든 import 적합 (`AppKit`, `Combine`, `Carbon.HIToolbox`, `ApplicationServices`, `CoreGraphics`, `Foundation`, `QuartzCore`, `SwiftUI`)
- [x] **PASS** — Info.plist 추가사항 문서화 (`Info.plist.additions.md`) — LSUIElement, NSAccessibilityUsageDescription, App Sandbox 비활성 명시
- [x] **PASS** — public/internal 가시성: 외부 호출 surface는 모두 public, 내부 헬퍼는 internal/private
- [N/A] **N/A** — 실제 Xcode 빌드는 본 정적 검증 범위 밖

---

## 종합 통과율

| 카테고리 | 항목 수 | PASS | FAIL | WARN | N/A |
|---------|--------|------|------|------|-----|
| 인터페이스 SSoT | 25 | 22 | 3 | 0 | 0 |
| 이벤트 흐름 | 7 | 6 | 1 | 0 | 0 |
| 라이프사이클 | 6 | 3 | 3 | 0 | 0 |
| 좌표계 변환 | 6 | 5 | 0 | 1 | 0 |
| 설정 전파 | 6 | 5 | 0 | 1 | 0 |
| 권한 플로우 | 6 | 4 | 1 | 1 | 0 |
| 누수/성능 | 7 | 7 | 0 | 0 | 0 |
| 빌드/링크 | 4 | 3 | 0 | 0 | 1 |
| **합계** | **67** | **55** | **8** | **3** | **1** |

**총평**: critical 결함 없음. 다만 라이프사이클(종료/revoke)과 메뉴바 반영, 첫 실행 권한 안내 자동화에서 4건의 major FAIL이 누적되어 있어 사용자 경험에 직접 영향. 좌표계·이벤트 코어 흐름은 견고.
