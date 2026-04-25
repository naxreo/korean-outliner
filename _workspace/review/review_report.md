# Review Report — macos-korean-outliner

- 리뷰 대상: `_workspace/modules/*.swift` (13개)
- 기준 SSoT: `_workspace/02_interfaces.swift`
- 적용 체크리스트: `swift-code-review` 스킬 A~H

## 핵심 지표

| 심각도 | 개수 |
|--------|------|
| critical | 2 |
| major | 6 |
| minor | 8 |
| good | 3 |
| 추가 확인 필요 | 1 |

담당 dev 에이전트별 즉시 회신 권장:
- input-monitor-dev: minor 1건
- window-tracker-dev: critical 1건, major 2건, minor 2건
- overlay-renderer-dev: minor 2건
- preferences-dev: critical 1건(앱 조립), major 4건, minor 3건

---

## [critical]

### [critical] AppDelegate.swift:60-65 — MenuBarController가 입력 언어/마스터 토글 publisher에 구독되지 않아 `setLanguage`/`setEnabled`가 영원히 호출되지 않음
**담당**: preferences-dev (조립 책임), 또는 architect 결정 필요

```swift
// 현재
self.menuBar = MenuBarController(
    onShowPreferences: { [weak self] in self?.showPreferences() },
    onQuit: { NSApp.terminate(nil) }
)
// 끝. monitor.publisher / store.publisher → menuBar로의 연결이 없음.

// 권장 — 조립부에서 명시적으로 바인딩
self.menuBar = MenuBarController(
    onShowPreferences: { [weak self] in self?.showPreferences() },
    onQuit: { NSApp.terminate(nil) }
)

monitor.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak menuBar] lang in menuBar?.setLanguage(lang) }
    .store(in: &cancellables)

store.publisher
    .receive(on: DispatchQueue.main)
    .map(\.isEnabled)
    .removeDuplicates()
    .sink { [weak menuBar] enabled in menuBar?.setEnabled(enabled) }
    .store(in: &cancellables)
```

**근거**: `MenuBarPresenting` 프로토콜이 `setEnabled(_:)`/`setLanguage(_:)`를 요구하고 `MenuBarController`도 이를 구현하지만, AppDelegate 어디에서도 호출하지 않는다. 결과적으로 메뉴바 툴팁/`appearsDisabled` 상태가 SSoT 인터페이스가 약속한 "마스터 토글/입력 언어 반영"과 영구 불일치한다. 또한 `AppDelegate`에 `cancellables` 자체가 없어 추가 구독을 보관할 곳도 없다.

---

### [critical] FocusedWindowTracker.swift:286 — `as!` 강제 캐스팅이 AX malformed 응답에서 크래시
**담당**: window-tracker-dev

```swift
// 현재
guard result == .success, let raw = value else { return nil }
return (raw as! AXUIElement)

// 권장
guard result == .success, let raw = value else { return nil }
guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
return (raw as! AXUIElement)   // 또는 unsafeBitCast
```

**근거**: `kAXFocusedWindowAttribute`가 정상이라면 AXUIElement를 반환하지만, 타사 앱(특히 Electron 기반/오래된 Carbon 앱)이 AX 트리에 잘못된 값을 노출할 때 result는 `.success` 인데도 `value`가 AXUIElement 가 아닌 케이스가 보고된 적이 있다. 앱이 막 종료되는 시점의 transient 상태에서도 발생 가능. 강제 캐스팅이 실패하면 AX 콜백 스레드 디스패치 직후 메인 스레드에서 트랩이 발생해 앱 전체가 죽는다. 305~306라인의 `posRaw as! AXValue` / `sizeRaw as! AXValue`도 같은 패턴 — `AXValueGetTypeID()` 체크로 가드해야 안전하다.

---

## [major]

### [major] AppDelegate.swift:36-65 — 권한 미부여 상태에서 사용자가 Preferences를 열지 않고 권한을 허용하면 `tracker`가 영원히 시작되지 않음
**담당**: preferences-dev / architect

```swift
// 현재 — PermissionViewModel은 showPreferences() 호출 시점에만 생성됨
func showPreferences() {
    if preferencesWindow == nil {
        let view = PreferencesView()
            .environmentObject(preferencesStore)
            .environmentObject(PermissionViewModel(tracker: windowTracker))
        ...
    }
}

// 권장 — 앱 라이프타임 PermissionViewModel을 AppDelegate가 보유
private var permissionViewModel: PermissionViewModel!

func applicationDidFinishLaunching(_ notification: Notification) {
    ...
    self.permissionViewModel = PermissionViewModel(tracker: tracker)  // 즉시 폴링 시작
    monitor.start()
    if tracker.permissionStatus == .granted { tracker.start() }
    ...
}

func showPreferences() {
    if preferencesWindow == nil {
        let view = PreferencesView()
            .environmentObject(preferencesStore)
            .environmentObject(permissionViewModel)   // 공유
        ...
    }
}
```

**근거**: 현 구조에서는 `PermissionViewModel`의 폴링 Timer가 Preferences 창이 열린 이후에만 가동된다. 사용자가 메뉴바에서 앱을 켜고 Preferences를 한 번도 열지 않은 채 시스템 설정에서 직접 AX 권한을 허용하는 시나리오(가장 흔한 first-run 흐름)에서, 윈도우 추적이 시작되지 않아 외곽선이 절대 그려지지 않는다. 앱이 "동작하지 않는다"로 보이는 critical UX 결함이다. 타이머는 `AXIsProcessTrusted`만 호출하므로 비용이 무시 가능하므로 라이프타임 보유가 적절.

---

### [major] PermissionViewModel.swift:28-58 — 권한 부여 후에도 1.5초 폴링 Timer가 영원히 도는 배터리/CPU 낭비
**담당**: window-tracker-dev / preferences-dev

```swift
// 현재
private func poll() {
    let granted = AXPermission.status() == .granted
    guard granted != isGranted else { return }
    isGranted = granted
    if granted {
        tracker?.start()
    }
}

// 권장 — 부여 후 invalidate
private func poll() {
    let granted = AXPermission.status() == .granted
    guard granted != isGranted else { return }
    isGranted = granted
    if granted {
        tracker?.start()
        timer?.invalidate()
        timer = nil
    }
}
```

**근거**: AX 권한은 한 번 부여되면 사용자가 명시적으로 회수할 때까지 유지된다. 부여 후에도 1.5초마다 `AXIsProcessTrusted` 호출은 불필요하고, 더 중요한 것은 `Timer.scheduledTimer`가 **Timer가 self를 strong-capture하는 것이 아니라** `[weak self]` 클로저를 통해 self를 약하게 잡지만, **Timer는 RunLoop가 강하게 보유**한다. self가 deinit되면 콜백은 weak이라 안전하지만 Timer 자체는 invalidate되기 전까지 RunLoop에 남아 폴링한다 — `deinit { timer?.invalidate() }`가 있으나 self가 살아있는 한 영원히 발사된다. 권한 회수 감지가 필요한 디자인이라면 의도이지만, ADR/계약상 회수 모니터링 요구가 명시되어 있지 않으므로 부여 후 stop이 합리적.

---

### [major] PreferencesStore.swift:25-33 — ColorPicker 드래그 중 매 emit마다 동기 JSON 인코딩 + UserDefaults write가 발생
**담당**: preferences-dev

```swift
// 현재
public var config: OverlayConfig {
    get { subject.value }
    set {
        guard newValue != subject.value else { return }
        objectWillChange.send()
        save(newValue)             // 1) 영속화 — 매번 JSONEncoder + UserDefaults
        subject.send(newValue)
    }
}

// 권장 — 영속화는 디바운스, in-memory + publisher는 즉시
private var saveDebouncer: DispatchWorkItem?

public var config: OverlayConfig {
    get { subject.value }
    set {
        guard newValue != subject.value else { return }
        objectWillChange.send()
        subject.send(newValue)              // 즉시 전파 — 외곽선 색 즉시 변경
        scheduleSave(newValue)              // 200ms 디바운스 후 디스크 쓰기
    }
}

private func scheduleSave(_ config: OverlayConfig) {
    saveDebouncer?.cancel()
    let item = DispatchWorkItem { [weak self] in self?.save(config) }
    saveDebouncer = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
}
```

**근거**: SwiftUI `ColorPicker`는 사용자가 슬라이더를 드래그하는 동안 60fps 수준으로 selection을 emit한다. 현재 코드는 emit마다 `JSONEncoder().encode` + `UserDefaults.set(_:forKey:)`를 호출 — synchronous 디스크 동기화는 아니지만 plist 직렬화/메모리 복사 비용이 있고 불필요한 변경 알림을 유발한다. 또한 SSoT 계약("update(_:)는 영속화 후 emit") 자체가 ColorPicker 같은 고빈도 입력에 부적합 — emit을 먼저 하고 영속화를 디바운스하는 편이 외곽선 색 응답성도 좋다. 계약 변경이 필요하면 architect 의사결정 필요.

---

### [major] OverlayRenderer.swift:72-79 — `apply(language:)` 분기가 색상 변경에서 `apply(frame:)` 호출 후 첫 frame 이전 입력 변경을 무시
**담당**: overlay-renderer-dev

```swift
// 현재
public func apply(language: InputLanguage) {
    assertMain()
    currentLanguage = language
    if currentFrame != nil, currentConfig.isEnabled {
        controller.refresh(config: currentConfig, language: currentLanguage)
    }
}

// 권장 — render() 단일 진입점으로 통일
public func apply(language: InputLanguage) {
    assertMain()
    currentLanguage = language
    render()
}
```

**근거**: 현재 `apply(language:)`는 `currentFrame != nil`을 조건으로 `controller.refresh`만 호출한다. 그러나 `render()`는 frame이 있으면 `controller.show(at:)`을 호출 — `show(at:)`은 윈도우가 처음 가시화될 때 `orderFrontRegardless`까지 수행한다. 즉 refresh 경로는 윈도우가 이미 visible이라는 가정을 깔고 있는데, frame이 set되었지만 아직 한 번도 show되지 않은 transient 상태에서 입력 언어가 먼저 변경되면 윈도우는 보이지 않은 채 layer 색만 바뀐다. `render()` 단일 경로로 묶으면 멱등성·일관성 모두 향상되고 `OverlayRendering`의 SSoT 가이드("어떤 순서로 apply가 호출되어도 일관된 화면")에 정확히 부합한다.

---

### [major] InputSourceMonitor.swift:69-82 — `classify(sourceID:)`가 Korean 한글 분류 정확성에 취약, .english 화이트리스트 누락된 영문 키보드는 .other로 분류됨
**담당**: input-monitor-dev

```swift
// 현재
static func classify(sourceID: String) -> InputLanguage {
    if sourceID.hasPrefix("com.apple.inputmethod.Korean") || sourceID.contains("Korean") {
        return .korean
    }
    if sourceID.hasPrefix("com.apple.keylayout.ABC")
        || sourceID.hasPrefix("com.apple.keylayout.US")
        || sourceID.hasPrefix("com.apple.keylayout.British")
        ...
}

// 권장 — kTISPropertyInputSourceLanguages를 1순위로
private static func classify(source: TISInputSource, fallbackID: String) -> InputLanguage {
    if let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
       let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String],
       let primary = langs.first {
        if primary.hasPrefix("ko") { return .korean }
        if primary.hasPrefix("en") { return .english }
    }
    return .other(id: fallbackID)
}
```

**근거**: 문자열 prefix 화이트리스트는 (1) Korean이 아닌 한국어 IME(예: 3rd-party 한글 입력기)를 놓치고 (2) Dvorak/Colemak 등 영문 키보드를 .other로 잘못 분류한다. `kTISPropertyInputSourceLanguages`는 Carbon이 직접 노출하는 BCP-47 언어 코드 배열이므로 의도와 정확히 부합한다. 또한 `.contains("Korean")`은 너무 광범위(다른 언어 IME 이름에 "Korean"이 부분 매칭될 가능성)하다.

---

### [major] FocusedWindowTracker.swift:65-67, 225-231 — `axObserver`의 `AXObserverRemoveNotification` 호출만 수행하고 `CFRunLoopRemoveSource`는 `detachObserver`에 있으나, `deinit`에서 `teardown` → `detachObserver` 경로의 `CFRunLoopRemoveSource`가 실행되기 전 옵저버가 nil인 케이스 발생 가능
**담당**: window-tracker-dev

```swift
// 현재 (detachObserver)
private func detachObserver() {
    if let obs = axObserver {
        ...
        CFRunLoopRemoveSource(...)
    }
    axObserver = nil
    ...
}

// 검토: stop() → teardown() → detachObserver() — OK
// deinit → teardown() → detachObserver() — OK
// attach() 도중 createResult != .success로 early-return 시 axObserver는 nil 그대로
```

**근거**: 현재 코드는 `attach`에서 AXObserverCreate 실패 시 `axObserver`에 새 값 할당 없이 early return하므로 이전 observer가 잔존할 수 있다. attach 시작에서 `detachObserver()`를 먼저 호출하므로 직전 observer는 정리되지만, `activeAppElement` / `activeApp`이 새 앱으로 덮어쓰여지는 데 비해 observer 자리는 빈 채로 남아 있을 수 있다 — 이후 callback이 없으니 누수는 아니지만, `handleAXNotification`이 `axObserver = nil`을 보고 silently 종료될 뿐이라 동작상 무해. **단** attach 실패 후 다음 앱 활성화 시 새 observer로 정상 복구되는지에 대한 회복 시나리오 테스트 필요. — **추가 확인 필요** 항목으로 분류.

---

## [minor]

### [minor] AppDelegate.swift:29-33 — IUO(`!`)로 모듈 보관 → `try-let` 또는 lazy 생성 권장
```swift
// 현재
private var preferencesStore: PreferencesStore!
private var inputMonitor: InputSourceMonitor!
private var windowTracker: FocusedWindowTracker!
private var renderer: OverlayRenderer!
private var menuBar: MenuBarController!

// 권장 — 명시적 옵셔널 또는 didFinishLaunching 직전에 한 번만 만드는 컴포지션 객체
```
**근거**: IUO는 launch 이전 접근 시 silent crash를 만든다. 이 앱은 사실상 launch 이후만 접근이지만, 향후 `applicationWillTerminate`나 테스트 컨텍스트에서 nil 가능성이 생기면 깨진다. 옵셔널 + `guard let`이 안전.

### [minor] FocusedWindowTracker.swift:115-123 — `pid <= 0` 가드는 Sequoia에서도 일부 system UI 앱(예: Window Server)에서 양수 pid를 반환하지만 AXUIElementCreateApplication가 의미 없는 결과를 줄 수 있음
```swift
// 현재
guard app.processIdentifier > 0 else { ... }

// 권장 (보강)
guard app.processIdentifier > 0,
      app.bundleIdentifier != "com.apple.WindowManager",
      app.bundleIdentifier != "com.apple.dock" else {
    current = nil; subject.send(nil); return
}
```
**근거**: 외곽선이 Dock/WindowManager 같은 시스템 앱에 잘못 그려지는 경우를 방지. 다만 정책적 결정이므로 minor.

### [minor] PreferencesStore.swift:60, 70 — `NSLog`는 콘솔에 노출, 프라이버시 측면에서 OSLog로 교체
```swift
// 현재
NSLog("[PreferencesStore] decode failed, falling back to default: \(error)")

// 권장
import os
private let log = Logger(subsystem: "com.example.korean-outliner", category: "PreferencesStore")
log.error("decode failed: \(error.localizedDescription, privacy: .public)")
```
**근거**: `os.Logger`는 프라이버시 자동 마스킹·구조화 로깅·성능 모두 우수. 디코드 에러 자체는 민감 정보가 아니지만 일관성을 위해 권장.

### [minor] MenuBarController.swift:91-93 — 툴팁에 `id` (입력 소스 식별자) 노출 — 사용자에게 의미 없는 문자열
```swift
// 현재
case .other(let id):
    button.toolTip = enabled ? "Korean Outliner — \(id)" : "Korean Outliner (off)"

// 권장
case .other:
    button.toolTip = enabled ? "Korean Outliner — Other" : "Korean Outliner (off)"
```
**근거**: `com.apple.keylayout.Dvorak` 같은 식별자가 툴팁에 그대로 노출되는 것은 DX는 좋지만 UX는 나쁘다. 사용자에게 보이는 표면이므로 사람이 읽을 수 있는 표현 권장.

### [minor] OverlayContentView.swift:103-119 — `.leading`/`.trailing`을 좌/우로 hard-code, RTL 미지원이 SSoT 주석에 없음
```swift
// 현재
// leading (좌측 — LTR 가정. RTL 로컬라이제이션 미지원)
if config.sides.contains(.leading) { ... x: 0 ... }
if config.sides.contains(.trailing) { ... x: b.width - t ... }

// 권장 — userInterfaceLayoutDirection 반영하거나 옵션셋 이름을 .left/.right로
```
**근거**: SSoT의 `OverlaySides`는 `leading`/`trailing` 이름을 쓰지만 코드는 항상 좌/우. 한국어 사용자 대상이라 LTR 고정이 합리적이나, 이름이 RTL 대응을 함의하므로 SSoT 주석에 "이 앱은 LTR만 지원"을 명시하거나 OptionSet 이름을 `.left/.right`로 변경하는 것이 더 정직. architect 결정 필요.

### [minor] OverlayWindowController.swift:70-80 — 좌표 변환 단위 테스트 부재 (멀티 디스플레이/스크린 음수 origin 케이스)
```swift
static func nsRect(from axRect: CGRect, on screen: NSScreen) -> CGRect {
    let primary = primaryScreen() ?? screen
    let primaryHeight = primary.frame.maxY
    ...
}
```
**근거**: `screen` 인자를 받지만 변환 자체는 `primaryScreen()`만 사용 — 인자 `screen`은 거의 사용되지 않는다(폴백 목적). 멀티 모니터에서 보조 스크린이 메인 위쪽에 있을 때 `primary.frame.maxY`만으로 계산이 정확한지 단위 테스트 부재. SSoT 좌표계 주석은 정확하지만 케이스별 회귀 테스트 권장.

### [minor] PreferencesView.swift:84-99 — `Binding(get: { store.config.koreanColor.swiftUIColor }, set: ...)` 클로저가 ColorData → SwiftUI.Color 변환을 매 redraw에 수행
**근거**: 작은 컴포넌트지만 redraw마다 sRGB 분해/조립 — `@Published` config 변경 시 SwiftUI가 재평가하므로 비용이 누적될 가능성. 다만 ColorData는 4개 Double뿐이라 마이크로한 비용. minor.

### [minor] AXPermission.swift:34-39 — `URL(string:)` 폴백 동작 없음(silent return)
```swift
// 현재
public static func openSystemSettings() {
    guard let url = URL(string: ...) else { return }
    NSWorkspace.shared.open(url)
}
```
**근거**: 하드코딩된 URL이 실패할 일은 사실상 없지만, 실패 시 사용자에게 아무 피드백이 없다. NSLog/Logger로 한 줄 남기는 정도는 디버깅 편의성 향상.

---

## [good]

### [good] OverlayContentView.swift:48-58 — 묵시적 애니메이션 차단 패턴이 모범적
4면 layer 각각에 `actions = NSNull()` + `CATransaction.setDisableActions(true)` 이중 가드. 외곽선 흔들림 critical 이슈를 사전에 회피.

### [good] InputSourceMonitor.swift:51-66 — Carbon retain 규칙(`takeRetainedValue` for Copy, `takeUnretainedValue` for Get)이 정확
`TISCopyCurrentKeyboardInputSource()` → `takeRetainedValue`, `TISGetInputSourceProperty` → `Unmanaged.fromOpaque().takeUnretainedValue()` — 메모리 의미가 명시되어 있고 둘 다 옳다.

### [good] FocusedWindowTracker.swift:21-33 — AX C 콜백을 free function으로 두고 main queue 디스패치 패턴이 정확
`Unmanaged<...>.fromOpaque(refcon).takeUnretainedValue()` + `DispatchQueue.main.async`. AX 콜백 스레드 위반 위험을 깨끗하게 해소.

---

## [추가 확인 필요]

### FocusedWindowTracker.swift:114-163 — AXObserverCreate 실패 시 회복 경로
`AXObserverCreate`가 `.success`가 아닌 경우 `attach`는 early return하지만 `activeApp`/`activeAppElement`는 새 값으로 갱신된 채 남아 있다. 다음 `didActivateApplicationNotification`에서 `attach`가 다시 호출되면 `detachObserver()`로 정상 클린업되는지, 그리고 그 사이에 도착하는 AX 콜백이 안전한지 통합 테스트 필요. dev 측 의도(실패 시 무시 후 다음 활성화 이벤트 대기)를 architect와 합의 후 주석 명시 권장.

---

## 종합 평가

전반적으로 SSoT(`02_interfaces.swift`) 계약 준수도가 높고 Swift/macOS 메모리·스레드 규약(특히 AX 콜백 디스패치, Carbon retain 규칙, CALayer 묵시 애니메이션 차단)이 잘 지켜진 양호한 구현이다. 다만 **앱 조립부(AppDelegate)에서 (1) MenuBarController가 publisher에 연결되지 않은 점과 (2) PermissionViewModel이 Preferences 윈도우 의존인 점**, 그리고 **PreferencesStore의 동기 영속화**가 사용자 가시 동작/배터리에 직접 영향을 미치는 critical/major 이슈로, 우선 처리 권장.

권장 처리 순서:
1. `[critical] AppDelegate menuBar 연결` — preferences-dev 또는 architect
2. `[critical] FocusedWindowTracker as! 가드` — window-tracker-dev
3. `[major] PermissionViewModel 라이프타임 격상` — preferences-dev / architect 합의
4. `[major] PreferencesStore 디바운스` — preferences-dev (계약 변경 필요 시 architect 합의)
5. `[major] OverlayRenderer apply(language:) → render()` — overlay-renderer-dev
6. `[major] InputSourceMonitor classify` — input-monitor-dev
