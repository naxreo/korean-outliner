# InputSourceMonitor — 사용 계약

- **타입**: `final class InputSourceMonitor: InputSourceMonitoring` (in `InputSourceMonitor.swift`)
- **생성**: `let monitor = InputSourceMonitor()` 후 반드시 `monitor.start()` 호출. 종료 시 `stop()` 또는 `deinit` 자동 해제.
- **Publisher**: `monitor.publisher` 타입은 `AnyPublisher<InputLanguage, Never>`. `CurrentValueSubject` 기반이라 **구독 시점에 현재값 1회 즉시 emit**.
- **동기 조회**: `monitor.current` 로 마지막 알려진 `InputLanguage` 즉시 획득. `start()` 전에는 기본값 `.english`.
- **스레드**: 콜백·emit 모두 **메인 스레드** (DistributedNotificationCenter queue=.main). UI 모듈에서 추가 dispatch 불필요.
- **분류 규칙**: `kTISPropertyInputSourceID` prefix 매칭 — `com.apple.inputmethod.Korean*` → `.korean`, `com.apple.keylayout.ABC|US|British|...` → `.english`, 그 외 → `.other(id:)`. 사용자 언어 의존 localized name은 사용하지 않음.
- **import**: 사용 측은 `import Combine`만 추가하면 됨 (Carbon은 모듈 내부에 캡슐화).
