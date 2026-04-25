# QA Report — macos-korean-outliner

- **검증 시점**: 2026-04-25
- **검증 대상**: `_workspace/02_interfaces.swift` SSoT + `_workspace/modules/*.swift` 13개 파일
- **검증 방식**: 파일 단위 read + grep 교차 비교(시그니처/이벤트 흐름/라이프사이클/좌표/설정 전파)
- **결과 요약**

| 심각도 | 건수 |
|--------|------|
| critical | 0 |
| major | 4 |
| minor | 5 |

> 빌드/실행은 SDK 환경 부재로 수행 불가. 정적 검증 결과만 보고한다. 실기기 시나리오는 `manual_test_scenarios.md` 참조.

---

## QA-001: AppDelegate가 MenuBarController에 입력 언어/활성 상태를 전파하지 않음 [major]

**위치**: `_workspace/modules/AppDelegate.swift:36-65` (applicationDidFinishLaunching)

**증상**: `MenuBarPresenting` 프로토콜에 정의된 `setEnabled(_:)` / `setLanguage(_:)`는 `MenuBarController`에 구현되어 있으나, AppDelegate가 어떤 publisher 구독으로도 이 메서드들을 호출하지 않는다. 결과적으로 메뉴바 아이콘/툴팁이 한/영 전환·마스터 토글 변경에 반응하지 않는다.

**재현**:
1. 앱 실행
2. 한/영 전환 (Caps Lock 또는 한/영 키)
3. 메뉴바 아이콘에 마우스 오버 → 툴팁 항상 "Korean Outliner" 또는 초기 영문 상태 그대로 (기대: "Korean Outliner — 한글" / "— English"로 갱신)
4. Preferences에서 마스터 토글 OFF → 메뉴바 아이콘이 dim 처리되지 않음 (`appearsDisabled` 미적용)

**추정 원인**: `OverlayRenderer.bind(...)` 안에서 input/window/preferences 3개 publisher만 sink하고 menuBar 갱신은 누락. AppDelegate에도 전달 코드 없음. `MenuBarPresenting`의 두 setter는 dead code 상태.

**권장 수정**: AppDelegate에 cancellables 추가 후 다음 구독:
```swift
private var menuBarCancellables = Set<AnyCancellable>()
// applicationDidFinishLaunching 마지막에:
inputMonitor.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.menuBar.setLanguage($0) }
    .store(in: &menuBarCancellables)

preferencesStore.publisher
    .map(\.isEnabled)
    .removeDuplicates()
    .receive(on: DispatchQueue.main)
    .sink { [weak self] in self?.menuBar.setEnabled($0) }
    .store(in: &menuBarCancellables)
```

**담당**: integration(AppDelegate 작성자) / 협의 대상: menubar-dev

---

## QA-002: 첫 실행 시 Preferences 자동 표시 + 권한 안내 화면 강조 누락 [major]

**위치**: `_workspace/modules/AppDelegate.swift:36-65`, `_workspace/02_interfaces.swift:266-272` (PreferencesPresenting.showAccessibilityPrompt)

**증상**: SSoT의 `PreferencesPresenting.showAccessibilityPrompt()` 계약이 존재하지만 어떤 모듈도 이 프로토콜을 채택하지 않고, 첫 실행 시 권한이 없을 때 Preferences 윈도우를 자동으로 띄우는 로직이 AppDelegate에 없다. swift-qa-integration 시나리오 #1("첫 실행 시 Preferences 자동 표시 → 권한 안내")이 충족되지 않는다.

**재현**:
1. `defaults delete com.naxreo.koreanoutliner` 또는 신규 사용자로 실행
2. AX 권한 미부여 상태에서 앱 실행
3. 메뉴바 아이콘만 표시되고 Preferences 윈도우는 뜨지 않음
4. 사용자는 외곽선이 안 그려지는 이유를 알 수 없음

**추정 원인**: `applicationDidFinishLaunching`에서 권한 미부여 시 자동으로 `showPreferences()`를 호출하지 않음. `PreferencesPresenting` 프로토콜은 정의만 되어 있고 미구현.

**권장 수정**:
```swift
// applicationDidFinishLaunching 마지막
if tracker.permissionStatus != .granted {
    showPreferences() // 권한 안내 섹션이 자동으로 노출됨
}
```
선택적으로 "처음 실행" 플래그(UserDefaults)로 권한 부여 후에도 한 번은 띄우는 UX 보강 가능.

**담당**: integration(AppDelegate) / 협의 대상: preferences-dev

---

## QA-003: AppDelegate에 applicationWillTerminate 핸들러 부재 — 옵저버 명시적 해제 누락 [major]

**위치**: `_workspace/modules/AppDelegate.swift` (전체)

**증상**: 앱 종료 시 `inputMonitor.stop()` / `windowTracker.stop()`이 명시적으로 호출되지 않는다. deinit 경유 정리에 의존하지만, AppDelegate가 NSApp의 강한 참조를 받기 때문에 종료 시점에 deinit이 동기적으로 실행된다는 보장이 없다(특히 종료 직전 NSWorkspace 알림 큐의 잔여 콜백). swift-qa-integration 시나리오 #10("Quit → 외곽선 즉시 사라짐")이 보장되지 않는다.

**재현**:
1. 앱 실행 → 외곽선 표시 중
2. Cmd+Q
3. 종료 직전 잔여 AX 콜백이 `tracker.handleAXNotification`에서 dangling self 접근 가능 (low-probability 크래시 또는 Console 경고)

**추정 원인**: `applicationWillTerminate(_:)` 미구현. AXObserver/NSWorkspace 옵저버는 deinit으로만 해제됨.

**권장 수정**:
```swift
func applicationWillTerminate(_ notification: Notification) {
    inputMonitor?.stop()
    windowTracker?.stop()
}
```

**담당**: integration(AppDelegate)

---

## QA-004: PermissionViewModel.poll → tracker.start() 메인 스레드 보장 부재 [major]

**위치**: `_workspace/modules/PermissionViewModel.swift:28-34, 51-58`

**증상**: `Timer.scheduledTimer`는 호출자 RunLoop(보통 main)에서 도는 게 일반적이지만, `PermissionViewModel`이 백그라운드에서 인스턴스화되면 timer가 메인이 아닐 수 있다. `WindowTracker_contract.md`는 "메인 스레드에서 start()/stop()"을 요구한다. AXObserver의 `CFRunLoopGetMain()` 등록은 메인 RunLoop에서 호출되어야 안정적.

**재현**: 현재 호출 경로(AppDelegate.showPreferences → PermissionViewModel(tracker:))는 메인이지만, 코드는 호출자 컨텍스트에 의존하는 잠복 결함.

**추정 원인**: `Timer.scheduledTimer` 명시적 RunLoop 미지정 + `poll()` 내부 `tracker?.start()`도 메인 dispatch 미사용.

**권장 수정**:
```swift
private func poll() {
    let granted = AXPermission.status() == .granted
    DispatchQueue.main.async { [weak self] in
        guard let self, granted != self.isGranted else { return }
        self.isGranted = granted
        if granted { self.tracker?.start() }
    }
}
```
또는 init에서 `RunLoop.main.add(timer!, forMode: .common)`을 명시.

**담당**: window-tracker-dev (또는 permission-vm 작성자)

---

## QA-005: ColorData 변환 extension은 단일 정의 — 중복 없음 (PASS) [정보]

**위치**: `_workspace/modules/ColorData+Convert.swift:12`, `_workspace/modules/PreferencesView.swift:158`

**증상**: 의심 사항이었던 ColorData NSColor extension 중복은 **없음**.
- `ColorData+Convert.swift`: `public extension ColorData { var nsColor / init(_ NSColor) / init(_ CGColor) }`
- `PreferencesView.swift`: `private extension ColorData { init(swiftUI: Color) / var swiftUIColor }` — file-private, SwiftUI.Color 전용 + 라벨이 `swiftUI:`로 차별화되어 시그니처 충돌 없음.

**결과**: 통과. 별도 수정 불필요.

---

## QA-006: OverlayRenderer 편의 생성자 라벨 일치 (PASS) [정보]

**위치**: `_workspace/modules/OverlayRenderer.swift:29-38`, `_workspace/modules/AppDelegate.swift:40-44`

**증상**: AppDelegate가 호출하는
```swift
OverlayRenderer(inputMonitor: monitor, windowTracker: tracker, preferences: store)
```
와 정의
```swift
public convenience init(inputMonitor: InputSourceMonitoring, windowTracker: FocusedWindowTracking, preferences: PreferencesStoring)
```
가 **정확히 일치**. 라벨 3개 모두 동일.

**결과**: 통과.

---

## QA-007: AXObserver 누수 방지 — 앱 전환 시 이전 옵저버 해제 (PASS) [정보]

**위치**: `_workspace/modules/FocusedWindowTracker.swift:114-116, 202-223`

**증상**: `attach(to:)`가 첫 줄에서 `detachObserver()`를 호출하여 이전 앱의 AX 옵저버를 해제. `detachObserver()`는 window-level + app-level 알림을 모두 RemoveNotification + RunLoopSource까지 정리. teardown(deinit/stop)은 workspace observer까지 정리.

**결과**: 통과. 단, AXObserver 자체는 `axObserver = nil`로 ARC에 의해 해제 — 명시적 무효화 API는 macOS AX에 없으므로 적절.

---

## QA-008: Publisher 초기값 즉시 emit (PASS) [정보]

**위치**:
- `InputSourceMonitor.swift:12` — `CurrentValueSubject<InputLanguage, Never>(.english)`
- `FocusedWindowTracker.swift:53` — `CurrentValueSubject<WindowFrame?, Never>(nil)`
- `PreferencesStore.swift:19, 41-46` — `CurrentValueSubject<OverlayConfig, Never>(loaded)`

**증상**: 3개 publisher 모두 CurrentValueSubject로 구독 즉시 현재값 1회 emit 보장. OverlayRenderer.bind에서 sink 시 `currentLanguage`/`currentFrame`/`currentConfig` 캐시가 즉시 채워진다.

**결과**: 통과.

---

## QA-009: AXObserverCallback에서 메인 스레드 dispatch (PASS) [정보]

**위치**: `_workspace/modules/FocusedWindowTracker.swift:21-33`

**증상**: 자유 함수 `axEventCallback` 내부에서 `DispatchQueue.main.async { tracker.handleAXNotification(...) }`로 dispatch. `handleAXNotification` 본체는 메인에서만 실행됨.

**결과**: 통과. 단, AX 콜백 자체는 옵저버를 등록한 RunLoop 모드(`.defaultMode`)에서 호출되므로 보통 메인이지만, 본 코드는 명시적으로 main async를 한 번 더 거쳐 안전.

---

## QA-010: OverlayRenderer가 3개 publisher 모두 구독 + cancellables.store (PASS) [정보]

**위치**: `_workspace/modules/OverlayRenderer.swift:40-62`

**증상**:
```swift
inputMonitor.publisher.receive(on: .main).sink { ... }.store(in: &cancellables)
windowTracker.publisher.receive(on: .main).sink { ... }.store(in: &cancellables)
preferences.publisher.receive(on: .main).sink { ... }.store(in: &cancellables)
```
모든 publisher 구독 + cancellables 저장 + 메인 스레드 hop 보장.

**결과**: 통과.

---

## QA-011: InputSourceMonitor 한국어 분류 — `Korean` substring 매칭의 위양성 가능 [minor]

**위치**: `_workspace/modules/InputSourceMonitor.swift:69-82`

**증상**: `sourceID.contains("Korean")`가 `com.apple.inputmethod.Korean*` 외의 사용자 정의 입력기 ID(예: 누군가가 만든 "MyKoreanFlavor" 같은 비표준 ID)도 Korean으로 분류한다. 또한 일부 macOS 환경에서 Hangul 입력기는 `com.apple.inputmethod.Korean.2SetKorean` 같이 prefix는 일치하지만, 고유의 다른 ID 변형(`com.apple.keylayout.Korean`)도 존재할 수 있다 — 후자는 prefix 매칭으로 잡지 못하고 substring으로 cover됨.

**평가**: 현 분류 규칙은 contract 가이드("`com.apple.inputmethod.Korean*` prefix")보다 한 단계 관대하다. 위양성 위험은 낮으나, 분류 의도와 코드 동작이 살짝 어긋남.

**권장 수정**:
```swift
if sourceID.hasPrefix("com.apple.inputmethod.Korean") ||
   sourceID.hasPrefix("com.apple.keylayout.Korean") {
    return .korean
}
```
substring 매칭 제거 + keylayout.Korean prefix 추가.

**담당**: input-monitor-dev

---

## QA-012: primaryScreen 도출 로직이 Tracker와 Renderer 사이에서 비대칭 [minor]

**위치**:
- `FocusedWindowTracker.swift:351-353` — `let primary = NSScreen.screens.first` (origin 무관)
- `OverlayWindowController.swift:88-92` — `NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first ?? NSScreen.main`

**증상**: 일반적으로 둘은 같지만, 멀티 모니터에서 사용자가 시스템 설정 → 디스플레이 → 정렬에서 NSScreen.screens 순서를 바꾸면 `screens.first`가 더 이상 `origin == .zero`가 아닐 수 있다. 이 경우 Tracker가 변환 기준으로 사용한 primaryMaxY와 Renderer가 사용한 primaryMaxY가 다른 스크린 높이를 사용 → screen 매칭과 NS 변환 결과가 어긋남(외곽선 위치 오프셋).

**재현**: 멀티 모니터 + 보조 디스플레이 위쪽 배치 + screens.first가 보조라면 발생 가능. 단일 모니터에서는 둘 다 같은 스크린이라 무해.

**권장 수정**: `screenContaining`도 OverlayWindowController와 동일한 우선순위(`origin == .zero` 우선)로 변경.

**담당**: window-tracker-dev (또는 architect 동기화 결정)

---

## QA-013: InputSourceMonitor가 NotificationCenter가 아닌 DistributedNotificationCenter 사용 — 알림 미수신 잠재성 [minor]

**위치**: `_workspace/modules/InputSourceMonitor.swift:30-37`

**증상**: `kTISNotifySelectedKeyboardInputSourceChanged`는 `DistributedNotificationCenter`가 아니라 일반 `NotificationCenter.default`로 발송되는 케이스가 있다(macOS 12 이후 변동 보고). 일부 macOS에서 한/영 전환이 외부 도구(예: 한영 단축키 매핑 앱)에 의해 트리거될 때 알림 누락 가능.

**평가**: contract 가이드는 `DistributedNotificationCenter`로 명시되어 있고, 본 케이스는 macOS 13+에서 일반적으로 동작한다. 다만 신뢰도 보강을 위해 양쪽 구독 + 디바운스가 안전.

**권장 수정(선택)**:
```swift
let dist = DistributedNotificationCenter.default()
let local = NotificationCenter.default
let name = NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
dist.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshCurrentSource() }
local.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshCurrentSource() }
```
+ `refreshCurrentSource` 내부의 `if next != subject.value` 가드로 중복 emit 방지.

**담당**: input-monitor-dev

---

## QA-014: PermissionViewModel이 권한 revoke 시 tracker.stop()을 호출하지 않음 [minor]

**위치**: `_workspace/modules/PermissionViewModel.swift:51-58`

**증상**: 폴링이 `granted != isGranted` 변화를 감지했을 때 부여 방향(false→true)에서만 `tracker.start()`를 호출한다. revoke(true→false) 방향에서는 아무 동작 없음. swift-qa-integration 시나리오 #9("권한 revoke → 외곽선 사라짐")가 직접 보장되지 않는다(Tracker 내부의 AX 호출 실패에 의존).

**재현**:
1. 외곽선 표시 중
2. 시스템 설정에서 AX 권한 해제
3. 1.5초 폴링이 isGranted=false 갱신
4. tracker는 여전히 isStarted=true 상태로 동작 시도(콘솔 에러 가능). publisher는 nil emit이 보장되지 않음.

**권장 수정**:
```swift
private func poll() {
    let granted = AXPermission.status() == .granted
    guard granted != isGranted else { return }
    isGranted = granted
    if granted { tracker?.start() } else { tracker?.stop() }
}
```

**담당**: window-tracker-dev / permission-vm 작성자

---

## QA-015: PreferencesView가 store를 ObservedObject 의존성으로만 사용 — store.config setter는 objectWillChange 수동 호출이지만 SwiftUI 갱신 트리거가 비표준 [minor]

**위치**: `_workspace/modules/PreferencesStore.swift:25-33`, `_workspace/modules/PreferencesView.swift:17`

**증상**: `PreferencesStore.config`는 computed property + 수동 `objectWillChange.send()`. 일반적인 `@Published` 패턴 대비 위험한 점: setter 진입 직후 send를 호출하면 SwiftUI는 **변경 전** 상태에서 view 무효화를 큐잉하지만, save→subject.send 사이에 SwiftUI가 view body 재계산을 시도할 수 있다. 결과는 동일한 값 1회 깜빡임 또는 첫 렌더에서 옛 값. 실용상 거의 보이지 않음.

**평가**: 동작 자체는 수렴하므로 minor. SwiftUI 권장 패턴은 `@Published var config: OverlayConfig { didSet { save(); subject.send(config) } }`이지만 ObservableObject + Combine subject 두 채널을 동시에 노출하는 의도라면 현 구조도 합리적.

**권장 수정(선택)**: 그대로 유지하되 단위 테스트 추가하여 SwiftUI 갱신·publisher emit이 한 사이클 안에 끝남을 회귀 방지.

**담당**: preferences-dev

---

## 검증 결과 종합

- **critical 결함**: 0건 — 빌드 차단 또는 핵심 기능 불가 결함 없음
- **major 결함**: 4건 — 메뉴바 미반응(QA-001), 첫 실행 권한 안내 자동화 부재(QA-002), 종료 정리 누락(QA-003), 권한 폴링 메인스레드 보장(QA-004)
- **minor 결함**: 5건 — 분류 규칙 정밀화(QA-011), primary 스크린 비대칭(QA-012), 알림 채널 보강(QA-013), revoke 시 stop()(QA-014), Preferences 갱신 패턴(QA-015)
- **PASS 항목**: 6건 — ColorData 단일 정의, 편의 생성자 라벨, AXObserver 해제, 초기값 emit, 메인 스레드 dispatch, 3개 publisher 구독+store

**다음 단계 권고**:
1. QA-001~004 (major) 우선 수정 후 재검증
2. 실기기에서 `manual_test_scenarios.md`의 시나리오 #1, #9, #10을 직접 실행 — major 결함이 시각적으로 확인되어야 정상
3. minor 결함은 기능 안정성을 우선 확보한 후 1.0.1 후속 릴리스에서 처리 가능
