# OverlayRenderer — 사용 계약

- **타입**: `final class OverlayRenderer: OverlayRendering` (in `OverlayRenderer.swift`). 보조 타입: `OverlayWindow`(internal), `OverlayContentView`(internal), `OverlayWindowController`(internal). 모두 `import AppKit` + `import Combine` + `import QuartzCore` 필요.
- **생성/주입**: 두 가지 방식 ① 순수 — `let r = OverlayRenderer()` 후 `apply(frame:)`/`apply(language:)`/`apply(config:)`를 외부 코디네이터가 호출. ② 편의 — `OverlayRenderer(inputMonitor:windowTracker:preferences:)`로 즉시 3개 publisher를 자동 구독(`.receive(on: .main)` 후 sink). 두 모드 모두 멱등(idempotent)하며 어떤 순서로 apply가 호출되어도 마지막 상태로 일관 렌더.
- **좌표계**: `WindowFrame.frame`은 **AX(top-left)** 그대로 받고, 내부에서 origin==.zero NSScreen(메인=메뉴바 보유) 기준으로 NSWindow(bottom-left) 좌표로 변환한다. 호출 측은 변환 금지.
- **렌더 규칙**: `config.isEnabled == false` 또는 `frame == nil` 또는 0 크기 프레임이면 즉시 숨김(`orderOut`). 활성 시 `orderFrontRegardless`로 키 포커스 강탈 없이 표시. 모든 묵시 애니메이션은 `CATransaction.setDisableActions(true)` + per-layer NSNull actions로 차단.
- **스레드**: 모든 public API는 **메인 스레드**에서만 호출. 편의 생성자는 모든 구독에 `.receive(on: .main)`을 강제하므로 호출 측 추가 dispatch 불필요. DEBUG 빌드는 `dispatchPrecondition`으로 위반 검출.
- **OverlayConfig 색상 변환**: `ColorData+Convert.swift`가 `ColorData.nsColor` / `ColorData.cgColor` / `init(NSColor)` / `init(CGColor)` extension 제공. sRGB 강제 + 0...1 클램프. preferences-dev에서 NSColor↔ColorData 직렬화 시 동일 extension 재사용.
- **한/영 외 입력 폴백**: `InputLanguage.other(id:)` 입력 시 영문 색상으로 폴백(외곽선 사라지면 사용자가 앱 종료로 오해할 수 있어 항상 표시).
