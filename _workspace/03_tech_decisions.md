# 기술 결정 기록 (ADR)

본 문서는 macos-korean-outliner의 기술 선택 근거를 기록한다.
ADR(Architecture Decision Record) 형식.

작성: architect 에이전트, 2026-04-25
상태: 초기 SSoT 확정 (v0.1)

---

## ADR-001: 입력 소스 감지에 TISInputSource 사용

### 결정
`TISCopyCurrentKeyboardInputSource()` + `DistributedNotificationCenter`의
`AppleSelectedInputSourcesChangedNotification` (또는 동등 키) 구독으로
시스템 전역 한/영 상태를 감지한다.

### 대안
- **NSTextInputContext**: 자기 앱의 텍스트 입력 컨텍스트만 알 수 있고,
  포커스된 *외부* 앱의 IME 상태를 얻을 수 없다.
- **NSEvent.addGlobalMonitorForEvents(.flagsChanged)**: 한/영 키 자체의 키다운은
  관찰할 수 있으나 IME 토글 결과(현재 입력 소스)는 알 수 없다. 또한 한/영 키가
  없는 키보드(외장 영문 키보드 + Caps Lock 토글, 단축키 매핑)를 못 잡는다.
- **CGEventTap**: 시스템 전역 키 이벤트를 가로챌 수 있으나 입력 가로채기 권한이
  추가로 필요하고 IME 결과를 직접 알려주지 않는다.

### 근거
TISInputSource는 macOS의 표준 텍스트 입력 시스템 API로, IME 종류에 무관하게
"현재 활성 입력 소스 ID"를 정규화된 문자열로 제공한다. 알림 기반이라
폴링이 필요 없고, 알림 지연은 일반적으로 < 30 ms.

### 영향
- Carbon (HIToolbox) 프레임워크 의존이 발생한다. Apple은 Carbon의 점진적
  deprecation을 시사해 왔으나 TIS는 현재까지 대체재 없이 유효하며, macOS 14
  Sonoma까지 정상 동작 확인.
- 향후 deprecation에 대비해 `InputSourceMonitoring` protocol로 격리. 구현
  교체만으로 마이그레이션 가능.
- "Korean" 판정은 input source ID prefix 매칭(`com.apple.inputmethod.Korean`,
  `com.apple.keylayout.Korean` 등)으로 한다. 미지의 ID는 `.other(id:)`로 보존.

---

## ADR-002: 포커스 윈도우 추적에 AXObserver 사용 (NSWorkspace 폴링 X)

### 결정
- 포커스 *앱* 변경: `NSWorkspace.shared.notificationCenter`의
  `.didActivateApplicationNotification` 구독.
- 포커스 *윈도우* 변경 / 윈도우 이동·리사이즈: 활성 앱마다 `AXUIElementCreateApplication`
  후 `AXObserverCreate`로 다음 알림 구독:
  - `kAXFocusedWindowChangedNotification`
  - `kAXMovedNotification`
  - `kAXResizedNotification`
  - `kAXWindowMiniaturizedNotification` / `kAXWindowDeminiaturizedNotification`
  - `kAXApplicationHiddenNotification` / `kAXApplicationShownNotification`

### 대안
- **CGWindowList 폴링**: `CGWindowListCopyWindowInfo`를 16ms 간격(60fps) 폴링하면
  CPU 점유 ~5–10% 발생. 저전력 노트북에서 부담.
- **NSWorkspace 알림만 사용**: 앱 활성화는 잡지만 윈도우 이동/리사이즈는 못 잡는다.
- **CGEventTap**: 마우스 드래그 이벤트로 윈도우 이동 추론 가능하나 키보드 단축키
  이동(예: Rectangle, Magnet)은 못 잡고 권한도 추가 필요.

### 근거
AXObserver는 윈도우 위치/크기 변경 시 OS가 직접 알림을 푸시한다. 폴링이 없어
유휴 시 CPU 0%에 가깝고, 이동/리사이즈 중에도 콜백당 비용이 작다.

### 영향
- **Accessibility 권한 필수**. 권한 미부여 시 AXObserverCreate가 실패하거나
  알림이 오지 않는다. `AXIsProcessTrustedWithOptions(prompt: false)`로 사전 확인,
  PreferencesUI에서 시스템 설정으로 안내.
- 포커스 앱이 바뀔 때마다 이전 AXObserver를 해제하고 새 앱에 재바인딩해야 함
  (메모리 누수 위험 → 구현 시 명시적 해제 필수).
- AX는 일부 앱(특히 Electron, 비표준 윈도우 시스템)에서 frame 보고가 늦거나
  부정확할 수 있다. 알려진 케이스는 QA에서 별도 트래킹.

---

## ADR-003: 오버레이 NSWindow level은 `.statusBar` (NSStatusWindowLevel)

### 결정
오버레이 NSWindow의 level을 `NSWindow.Level.statusBar` 로 설정한다.
`styleMask = .borderless`, `isOpaque = false`, `backgroundColor = .clear`,
`ignoresMouseEvents = true`,
`collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.

### 대안
- **`.floating` (NSFloatingWindowLevel)**: 일반 floating 패널 위에는 잘 뜨지만,
  타 앱의 `.modalPanel` 모달, 시스템 알림 패널 위로는 못 올라감. 외곽선이
  사용자가 입력 중인 창 뒤에 깔리는 사고 발생.
- **`.popUpMenu`**: 메뉴 표시 중 메뉴 위로 올라가는 부작용. 메뉴 외곽선은 의미 없음.
- **`.screenSaver`**: 너무 높음. 시스템 알림/스크린세이버 위로 올라가 거슬림.
- **`.normal`**: 일반 윈도우와 동급이라 포커스 변경 시 가려진다.

### 근거
`.statusBar`는 사용자 콘텐츠 위에 안정적으로 떠 있되 시스템 메뉴바/알림 센터보다
낮아 시스템 UI를 가리지 않는 균형점이다. macOS의 외곽선/주석 도구(예:
ScreenFloat, Annotate)들이 동일한 level을 사용한다.

`ignoresMouseEvents = true`로 클릭 통과(click-through)를 보장. 사용자가 외곽선
때문에 아래 윈도우와 상호작용을 잃는 일이 없다.

`collectionBehavior`에 `.canJoinAllSpaces`/`.fullScreenAuxiliary`를 넣어 Spaces
전환·Full Screen 모드에서도 외곽선이 따라가도록 한다.

### 영향
- 시스템 모달 알림(예: 권한 프롬프트, 'Are you sure?') 위로는 올라가지 않음 — 의도된 동작.
- Mission Control 진입 시 macOS가 모든 윈도우를 축소하는데, 오버레이도 함께
  축소되어 어색해 보일 수 있음. 향후 `.windowDidEnterFullScreen` 등에서 hide
  처리 검토(Phase 2).

---

## ADR-004: App Sandboxing 비활성화, Hardened Runtime 활성화, notarized DMG 직접 배포

### 결정
- App Sandbox: **OFF**
- Hardened Runtime: **ON**
- 배포: notarized DMG (Developer ID 서명) — App Store 미배포

### 대안
- **Sandbox ON + 일부 entitlement**: AX API는 sandbox 내에서 동작하지 않는다.
  `com.apple.security.temporary-exception.apple-events`로 일부 우회 가능하지만
  AXUIElement는 우회 불가능 → 핵심 기능을 잃는다.
- **App Store 배포**: Sandbox가 강제되므로 위와 같이 불가능.
- **Hardened Runtime OFF**: notarization 불가 → Gatekeeper에서 실행 차단되어
  사용자가 우클릭→열기 우회를 매번 해야 함. 사용성 매우 나쁨.

### 근거
이 앱은 **시스템 전역 윈도우 정보 조회**를 핵심 가치로 한다. AX API는
sandbox와 양립 불가하므로 sandbox는 포기할 수밖에 없다. 대신 다른 보안 면을
강화한다:
- Hardened Runtime으로 코드 인젝션·동적 라이브러리 로드 제한
- 최소 권한 원칙: AX는 *조회만* 사용, 입력 가로채기/시뮬레이션은 사용하지 않음
- 자동 업데이트 시 Sparkle 사용 시 EdDSA 서명 강제

### 영향
- App Store 배포 영구 불가 (사업적/유통 결정 반영 필요).
- 사용자에게 "AX 권한 필요" 사전 안내 UX가 필수 (PreferencesUI의 권한 화면).
- 향후 macOS가 비-sandbox 앱 제한을 강화하면 재평가.
- CI에서 `codesign --sign "Developer ID Application: ..." --options runtime` +
  `xcrun notarytool submit` 자동화 필요 (devops 영역).

---

## ADR-005: NSColor의 영속화는 sRGB 4-component `ColorData` 사용 (NSKeyedArchiver 미사용)

### 결정
사용자 색상 설정은 `ColorData { red, green, blue, alpha: Double }` 구조체로
JSON Codable 직렬화하여 UserDefaults에 저장한다.
직렬화/역직렬화 시 **sRGB color space로 정규화**한다
(`NSColor.usingColorSpace(.sRGB)`).

### 대안
- **NSKeyedArchiver(NSColor)**: NSColor가 NSSecureCoding을 지원하지만 결과는
  불투명 binary blob. JSON 설정 파일 export/diff/디버깅이 어렵다. 향후 macOS
  업데이트로 NSColor 내부 구조가 바뀌면 호환 깨질 위험.
- **CGColor 직접 직렬화**: CGColor는 Codable 기본 지원 없음. 컴포넌트 + color
  space 식별자를 별도 인코딩해야 해서 결국 ColorData와 비슷해진다.
- **Hex 문자열 ("#RRGGBBAA")**: 사람이 읽기 좋지만 부동소수 정밀도 손실
  (특히 alpha) 발생. 향후 P3/wide color 확장 시 표현 한계.

### 근거
ColorData는:
1. **투명한 JSON**: `{"red":0.2,"green":0.5,"blue":1.0,"alpha":1.0}` — 사용자가
   설정 파일을 직접 편집/공유 가능.
2. **명시적 color space**: sRGB로 정규화하므로 displayP3/genericRGB 등 입력
   color space에 따라 달라지지 않음.
3. **OS 버전 독립**: NSColor 내부 직렬화 포맷에 의존하지 않음.
4. **Codable 자동 합성**: 별도 인코딩 코드 없음.

### 영향
- NSColor → ColorData 변환 시 `usingColorSpace(.sRGB)` 실패 가능성 처리 필요
  (예: catalog color). 실패 시 기본값으로 fallback 또는 호출 측 검증.
- P3 wide color는 표현 못 함 (sRGB 클램핑). 본 앱은 외곽선 색상 용도이므로
  실용상 문제 없다고 판단.
- 변환 구현은 `02_interfaces.swift`(SSoT)에 두지 않고 preferences-dev 모듈
  내부 extension에 둔다. SSoT는 데이터 모양만 정의.

---

## (참고) 추가 고려중인 결정

다음은 현 단계에서 결정 보류, dev 진행 중 확정 예정:

- **ADR-006 후보**: 멀티 모니터에서 윈도우가 두 스크린에 걸칠 때 외곽선을 어느
  스크린의 NSWindow에 그릴지 (스크린별 별도 NSWindow vs 단일 거대 NSWindow).
  → overlay-renderer-dev가 spike 후 architect와 협의.
- **ADR-007 후보**: PreferencesUI에서 색상 변경을 실시간 미리보기할지,
  apply 버튼을 둘지. → preferences-dev UX 결정.
