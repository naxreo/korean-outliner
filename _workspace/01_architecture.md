# macos-korean-outliner — 시스템 아키텍처 (초안 v0.1)

작성일: 2026-04-25
작성자: architect 에이전트
상태: 초기 SSoT 확정 — dev 에이전트 병렬 구현 착수 가능

---

## 1. 목표 요약

포커스된 macOS 윈도우의 외곽선(상/하/좌/우 선택 가능)에 현재 시스템 입력 언어(한/영)에 따라 다른 색상의 테두리를 실시간으로 표시하여, 사용자가 IME 상태를 시각적으로 즉시 인지하도록 돕는 메뉴바 유틸리티.

핵심 비기능 요건:

- **실시간성**: 입력 전환 < 50 ms, 윈도우 이동/리사이즈 추적 60 fps 수준 반응성
- **저전력**: 폴링 금지. 모두 이벤트 기반(AXObserver, DistributedNotificationCenter)
- **권한 회복 가능**: AX 권한 미부여 상태에서도 앱이 죽지 않고 안내 화면으로 유도
- **사용자 커스텀**: 색상(한/영 각각), 두께, 표시면(상/하/좌/우 OptionSet)

---

## 2. 모듈 분해

| 모듈 | 책임 | 주 의존 | 노출 인터페이스 |
|------|------|---------|----------------|
| **InputSourceMonitor** | 시스템 한/영 입력 소스 변경 감지 | TISInputSource (Carbon), DistributedNotificationCenter | `InputSourceMonitoring` |
| **FocusedWindowTracker** | 포커스 앱·윈도우 추적, 프레임 변경 이벤트 | NSWorkspace, AXUIElement, AXObserver | `FocusedWindowTracking` |
| **OverlayRenderer** | 투명 NSWindow + CALayer 외곽선 렌더링, 좌표계 변환 | AppKit, QuartzCore | `OverlayRendering` |
| **PreferencesStore** | 사용자 설정 영속화/복원 | Foundation (UserDefaults, Codable) | `PreferencesStoring` |
| **PreferencesUI** | SwiftUI 설정 화면 (색상, 두께, 표시면, 권한 안내) | SwiftUI | `PreferencesPresenting` |
| **MenuBarController** | NSStatusItem 아이콘/메뉴, 토글, Preferences 호출 | AppKit | `MenuBarPresenting` |
| **AppCoordinator** | 모듈 조립, 라이프사이클, 권한 게이트 | AppDelegate | (없음 — 최상위) |

규칙:
- 모듈 간 통신은 `02_interfaces.swift`에 정의된 protocol/struct/enum **만** 사용
- 모듈 구현체(class)는 internal. 외부에는 protocol만 노출
- 데이터 전달은 불변 struct/enum. 참조 공유 금지
- 이벤트는 Combine `AnyPublisher`로 통일 (델리게이트 X)

---

## 3. 데이터 흐름

```
                ┌────────────────────────┐
                │   System (macOS)       │
                │  TIS / AX events       │
                └──────────┬─────────────┘
                           │ DistributedNotification, AXObserver callback
            ┌──────────────┴───────────────┐
            ▼                              ▼
  ┌──────────────────┐            ┌────────────────────┐
  │ InputSource-     │            │ FocusedWindow-     │
  │ Monitor          │            │ Tracker            │
  │  → InputLanguage │            │  → WindowFrame?    │
  └────────┬─────────┘            └─────────┬──────────┘
           │ Publisher<InputLanguage>       │ Publisher<WindowFrame?>
           │                                │
           └────────────┬───────────────────┘
                        ▼
              ┌─────────────────────┐         ┌────────────────────┐
              │  AppCoordinator     │◀────────│ PreferencesStore   │
              │  (Combine merge)    │         │  Publisher<Config> │
              └─────────┬───────────┘         └────────────────────┘
                        │ apply(language/frame/config)
                        ▼
              ┌─────────────────────┐
              │  OverlayRenderer    │
              │  (NSWindow + CALayer)│
              └─────────────────────┘
```

핵심:
- AppCoordinator가 3 publisher를 `combineLatest`/`merge`로 결합
- OverlayRenderer는 **상태를 직접 보유하지 않는다**. AppCoordinator가 `apply(...)` 호출로 마지막 상태 주입
- PreferencesUI 변경 → PreferencesStore 갱신 → Publisher emit → AppCoordinator → OverlayRenderer 재적용

---

## 4. 라이프사이클

### 4.1 앱 시작 시퀀스

1. `AppDelegate.applicationDidFinishLaunching` → `AppCoordinator.bootstrap()`
2. `AppCoordinator`가 다음 순서로 모듈 인스턴스화:
   1. `PreferencesStore` (영속 상태 우선 로드)
   2. `MenuBarController` (메뉴바 즉시 표시 — 권한 없어도 OK)
   3. `InputSourceMonitor.start()` (Carbon TIS는 권한 불필요)
   4. AX 권한 확인 → `AXIsProcessTrustedWithOptions(prompt: false)`
      - 부여됨: `FocusedWindowTracker.start()`, `OverlayRenderer` 활성화
      - 미부여: PreferencesUI의 권한 안내 화면을 자동 표시, Tracker는 stopped 상태 유지
3. PreferencesUI는 lazy 생성. 메뉴바 아이콘 클릭 시 NSWindowController가 첫 생성
4. AppCoordinator는 입력/윈도우/설정 publisher를 구독하여 OverlayRenderer에 적용

### 4.2 권한 회복 플로우

1. PreferencesUI에서 "시스템 설정 열기" 버튼 → `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"))`
2. 사용자가 권한 부여 후 앱으로 복귀 → `NSApplication.didBecomeActiveNotification` 핸들러가 `AXIsProcessTrusted()` 재확인
3. 부여 확인 시 `FocusedWindowTracker.start()` 호출, OverlayRenderer 활성화
4. 부여 실패 시 안내 유지

### 4.3 종료 시퀀스

1. `AppDelegate.applicationWillTerminate` → `AppCoordinator.shutdown()`
2. 각 모니터·트래커의 `stop()` 호출 → AXObserver 해제, DistributedNotification 구독 해제
3. OverlayRenderer는 윈도우 close
4. PreferencesStore는 `synchronize()` (UserDefaults는 자동이지만 안전 차원)

### 4.4 런타임 이벤트 시나리오

| 이벤트 | 트리거 | 처리 |
|--------|--------|------|
| 한/영 전환 | TIS 알림 | InputSourceMonitor → publisher emit → AppCoordinator → OverlayRenderer.apply(language:) |
| 포커스 앱 변경 | NSWorkspace.didActivateApplicationNotification | FocusedWindowTracker가 새 AX 앱에 AXObserver 재바인딩 → publisher emit |
| 윈도우 이동/리사이즈 | AXObserver(kAXMovedNotification, kAXResizedNotification) | publisher emit → OverlayRenderer.apply(frame:) |
| 윈도우 최소화/숨김 | AXObserver(kAXWindowMiniaturizedNotification 등) | publisher emit nil → OverlayRenderer hide |
| 설정 변경 | PreferencesUI 바인딩 | PreferencesStore → publisher emit → OverlayRenderer.apply(config:) |

---

## 5. 좌표계 규약 (필독)

본 시스템은 **두 좌표계가 혼재**한다. 변환 책임을 OverlayRenderer로 단일화한다.

- **AX 좌표 (top-left)**: `kAXPositionAttribute`, `kAXSizeAttribute`로 얻은 값. 메인 스크린 top-left가 (0,0), Y 아래로 증가
- **NSWindow 좌표 (bottom-left)**: `NSWindow.setFrame(_:display:)`가 받는 좌표. 메인 스크린 bottom-left가 (0,0), Y 위로 증가

규약:
1. `WindowFrame.frame`은 **AX 좌표 그대로** 전달한다 (변환하지 않음)
2. OverlayRenderer가 `NSScreen.screens`와 메인 스크린 높이를 사용해 NS 좌표로 변환한다
3. 멀티 모니터 환경: `NSScreen.main!.frame.height` 가 아니라 **모든 스크린을 포함하는 글로벌 좌표**의 메인 스크린 기준 변환을 사용 (스킬 규약 준수)

변환 공식 참고:
```
ns.x = ax.x
ns.y = NSScreen.screens[0].frame.maxY - (ax.y + ax.height)
```
(스크린 0이 메뉴바 있는 메인 스크린이라는 가정. OverlayRenderer 구현 시 `NSScreen.screens.first { $0.frame.origin == .zero }` 등으로 안전 도출)

---

## 6. 모듈 조립 가이드

`AppCoordinator`의 의존성 주입 예시(개념 — 실제 구현은 dev 에이전트 책임):

```swift
final class AppCoordinator {
    private let prefs: PreferencesStoring
    private let inputMonitor: InputSourceMonitoring
    private let windowTracker: FocusedWindowTracking
    private let overlay: OverlayRendering
    private let menuBar: MenuBarPresenting
    private var cancellables = Set<AnyCancellable>()

    init(
        prefs: PreferencesStoring,
        inputMonitor: InputSourceMonitoring,
        windowTracker: FocusedWindowTracking,
        overlay: OverlayRendering,
        menuBar: MenuBarPresenting
    ) { ... }

    func bootstrap() {
        menuBar.install()
        inputMonitor.start()
        if windowTracker.permissionStatus == .granted {
            windowTracker.start()
        }
        wireBindings()
    }

    private func wireBindings() {
        inputMonitor.publisher
            .sink { [weak self] in self?.overlay.apply(language: $0) }
            .store(in: &cancellables)
        windowTracker.publisher
            .sink { [weak self] in self?.overlay.apply(frame: $0) }
            .store(in: &cancellables)
        prefs.publisher
            .sink { [weak self] in self?.overlay.apply(config: $0) }
            .store(in: &cancellables)
    }
}
```

각 dev 에이전트의 책임 범위:

- `input-monitor-dev`: `InputSourceMonitoring` 구현 (TIS + DistributedNotificationCenter)
- `window-tracker-dev`: `FocusedWindowTracking` + `AXPermissionStatus` 판별 로직
- `overlay-renderer-dev`: `OverlayRendering` 구현 (좌표 변환 포함, NSWindow level/collectionBehavior 결정)
- `preferences-dev`: `PreferencesStoring` (UserDefaults Codable) + `PreferencesPresenting` (SwiftUI)
- (architect): `AppCoordinator`, `MenuBarController` 골격

---

## 7. 빌드·배포 결정 (요약)

- Xcode 프로젝트 (SPM 아님), 타겟 macOS 13 Ventura 이상
- Swift 5.9+, SwiftUI + AppKit 혼용 (AppKit이 NSWindow level/AX 호환 우위)
- Sandboxing **OFF** (AX API 미동작) — App Store 배포 불가, notarized DMG 직접 배포
- Hardened Runtime ON (notarization 요구)

세부 근거는 `03_tech_decisions.md` 참조.

---

## 8. 변경 이력

- 2026-04-25: 초기 SSoT 확정 (architect)
