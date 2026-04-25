# FocusedWindowTracker — External Contract

- `let tracker = FocusedWindowTracker(); tracker.start()` 후 `tracker.publisher`를 구독하면 포커스 윈도우의 `WindowFrame?`이 흘러 들어온다. `frame.frame`은 **AX 좌표(top-left 원점) 그대로**이며, NSWindow 변환은 OverlayRenderer 책임이다.
- 권한이 없으면 `start()`는 내부적으로 stopped 상태를 유지하고 publisher는 `nil`을 emit, `permissionStatus == .denied`로 노출한다. 권한 요청은 `AXPermission.requestIfNeeded()` 또는 사용자 안내 후 `tracker.openSystemAccessibilityPane()`을 호출한다.
- 윈도우가 사라지거나 숨김/최소화되거나, AX 프레임 조회가 실패(시스템 UI 앱, 윈도우 없는 활성 앱 등)하면 publisher는 `nil`을 emit한다 — `nil` = "그릴 윈도우 없음"의 단일 시맨틱. 멀티 스크린에선 `WindowFrame.screen`이 가장 많이 겹치는 NSScreen으로 채워진다.
- `stop()`은 NSWorkspace 알림과 AXObserver를 모두 해제한다. `deinit`에서도 자동 정리되지만, 라이프사이클이 명확한 곳에서는 명시적으로 호출하라.
- 메인 스레드에서 `start()`/`stop()`을 호출한다 (AXObserver RunLoop 등록 요구사항).
