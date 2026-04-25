---
name: swift-code-review
description: macOS Swift 코드의 안전성, 메모리, AppKit/SwiftUI 관용구, Carbon/AX API 사용 적절성을 리뷰할 때 사용하라. 강제 언래핑, 강한 참조 순환, AXObserver/NotificationCenter 누수, Unmanaged retain 규칙, 메인 스레드 위반을 점검한다. "코드 리뷰", "리팩토링 제안", "Swift 점검", "리뷰" 같은 키워드가 등장하면 반드시 이 스킬을 사용할 것.
---

# Swift / macOS Code Review

`reviewer` 에이전트가 사용하는 코드 리뷰 가이드.

## 리뷰 출력 형식

`_workspace/review/review_report.md`에 심각도별 분류:

```markdown
## [critical] OverlayContentView.swift:48 — 묵시적 애니메이션으로 외곽선 흔들림

```swift
// 현재
topLayer.frame = CGRect(...)

// 권장
CATransaction.begin()
CATransaction.setDisableActions(true)
topLayer.frame = CGRect(...)
CATransaction.commit()
```

**근거**: CALayer의 frame 변경은 기본적으로 0.25초 묵시 애니메이션. 윈도우 추적 중 매번 애니메이션이 발생하면 외곽선이 늘 어긋난 위치에 표시됨.
```

심각도:
- `critical` — 크래시, 누수, 데이터 손실
- `major` — 자주 마주치는 결함, 성능 저하
- `minor` — 스타일, 가독성, 미세 개선

## 리뷰 체크리스트

### A. Swift 안전성

- [ ] 강제 언래핑(`!`) 사용처 → `guard let` 또는 `if let`로 대체 가능한가?
- [ ] `as!` 강제 캐스팅 → 안전한 타입인가? (AXValue 변환은 OK, 그 외는 의심)
- [ ] `try!` 사용 → 실패 시 영향 범위는?
- [ ] 옵셔널 체이닝(`?.`)이 묵시적으로 silent failure를 만들지 않는가?

### B. 메모리 안전성

- [ ] 클로저 캡처에 `[weak self]` 또는 `[unowned self]` 사용?
- [ ] `Combine` `cancellables`에 `.store(in:)` 누락 없는가?
- [ ] `AXObserver`, `NSWorkspace.notificationCenter`, `DistributedNotificationCenter` 옵저버 → `deinit`/`stop`에서 해제?
- [ ] `Unmanaged.passUnretained` vs `passRetained` 적절한가?
- [ ] Carbon API의 `takeRetainedValue` vs `takeUnretainedValue` 정확한가?
  - `TISCopyCurrentKeyboardInputSource` → `Copy`니까 retained → `takeRetainedValue`
  - `TISGetInputSourceProperty` → `Get`이니까 not retained → `takeUnretainedValue`

### C. 스레드 안전성

- [ ] AXObserver 콜백에서 UI 업데이트 시 메인 스레드로 디스패치?
- [ ] Combine `.receive(on: DispatchQueue.main)` 누락 없는가?
- [ ] `@Published`/`@State` 업데이트가 메인 스레드에서?

### D. macOS API 적절성

- [ ] 폴링 대신 옵저버 사용? (Timer로 윈도우 프레임 감시는 X)
- [ ] `makeKeyAndOrderFront` vs `orderFrontRegardless` 적절한 선택?
  - 오버레이는 `orderFrontRegardless` (포커스 강탈 X)
  - Preferences는 `makeKeyAndOrderFront` (편집 가능)
- [ ] `NSWindow.level` 적절성? (오버레이는 `.statusBar` 정도)
- [ ] `collectionBehavior` 멀티 스페이스 대응?
- [ ] `ignoresMouseEvents = true` 설정?

### E. 라이프사이클

- [ ] `NSStatusItem` 강한 참조 보유?
- [ ] Preferences 윈도우 캐싱 (다중 인스턴스 방지)?
- [ ] `applicationWillTerminate`에서 정리?
- [ ] 권한 revoke 시 추적 중단 경로?

### F. SwiftUI 관용구

- [ ] `@StateObject` vs `@ObservedObject` vs `@EnvironmentObject` 적절히?
  - 소유자: `@StateObject`
  - 외부 주입: `@ObservedObject` 또는 `@EnvironmentObject`
- [ ] `@AppStorage`로 NSColor 등 비-Codable 직접 저장 시도 없는가?
- [ ] `Binding` 작성 시 `Binding(get:set:)` 클로저가 무거운 작업 하지 않는가?

### G. 가독성

- [ ] 함수가 한 가지 일만 하는가?
- [ ] 매직 넘버 → `let` 상수로?
- [ ] 의미 없는 주석(코드와 동어반복) → 삭제 권고
- [ ] 네이밍이 의도를 드러내는가?

### H. 보안·프라이버시

- [ ] AX 권한 사용 범위가 최소? (윈도우 프레임 조회만, 키 입력 가로채기 X)
- [ ] 로그에 민감 정보(앱 이름, 윈도우 타이틀 등) 출력?
  - 윈도우 타이틀은 잠재 민감 (이메일 제목, 채팅 내용) → 로그 금지

## 자주 발견되는 패턴 (이 도메인)

| 패턴 | 권장 |
|------|------|
| `weak var observer: NSObjectProtocol?` 후 addObserver의 반환값 저장 안 함 | 반환값을 강한 참조로 보관 (해제용) |
| `[unowned self]` 남용 | 가능하면 `[weak self]` 우선 (안전) |
| `Task { ... }`로 비동기 호출 후 `await MainActor.run { ... }` 누락 | `@MainActor` 메서드로 만들거나 명시적 디스패치 |
| `ColorPicker`의 NSColor 변환에서 colorSpace 미지정 | `usingColorSpace(.sRGB)` 명시 |
| `print()` 디버그 잔재 | 제거 또는 `os_log` 사용 |
| 강제 캐스트 `as! AXUIElement` 가드 없이 | `guard let win = value as? AXUIElement` |

## 재호출 시 동작

- 기존 `review_report.md`에 있는 항목 중 해결된 것은 `[resolved]` 표시
- 새로 추가된 코드만 차분 검토 (이미 OK 받은 부분 재지적 금지)
- dev가 동의하지 않는 항목은 architect에 결정 위임

## 산출물 위치

- `_workspace/review/review_report.md`
