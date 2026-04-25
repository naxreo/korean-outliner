---
name: macos-overlay-window
description: 투명 NSWindow + CALayer로 다른 앱 위에 외곽선/하이라이트를 렌더링하는 macOS Swift 모듈을 구현할 때 사용하라. 클릭 투과(ignoresMouseEvents), 윈도우 레벨, NSScreen 좌표 변환, 4방향 외곽선 독립 토글, 입력 언어별 색상 자동 전환을 다룬다. "오버레이", "외곽선 그리기", "투명 윈도우", "borderless window" 같은 키워드가 등장하면 반드시 이 스킬을 사용할 것.
---

# Overlay Window Rendering

`OverlayRenderer` / `OverlayWindowController` 모듈 구현 가이드. `overlay-renderer-dev` 에이전트가 사용한다.

## 투명 오버레이 윈도우 구성

```swift
final class OverlayWindow: NSWindow {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true               // 클릭 투과
        self.level = .statusBar                      // 대부분의 앱 위에 표시
        self.collectionBehavior = [
            .canJoinAllSpaces,                       // 모든 스페이스에 표시
            .stationary,                             // Mission Control에서 정지
            .fullScreenAuxiliary                     // 전체화면 앱 위에도 표시
        ]
        self.isReleasedWhenClosed = false
        self.contentView = makeContentView()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

핵심:
- `.borderless` + 투명 배경 → 보이지 않는 윈도우
- `ignoresMouseEvents = true` → 사용자가 아래 앱을 정상 클릭 가능
- `canJoinAllSpaces`, `fullScreenAuxiliary` → 스페이스 전환·전체화면에도 동행
- `canBecomeKey = false` → 키보드 포커스 강탈 방지

## 4방향 외곽선 CALayer 구성

각 방향(top/right/bottom/left)을 독립 `CALayer`로 만들어 사용자가 일부만 켤 수 있게 한다.

```swift
final class OverlayContentView: NSView {
    private let topLayer = CALayer()
    private let rightLayer = CALayer()
    private let bottomLayer = CALayer()
    private let leftLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        for l in [topLayer, rightLayer, bottomLayer, leftLayer] {
            l.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(l)
        }
    }

    func update(config: OverlayConfig, language: InputLanguage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)        // 묵시적 애니메이션 차단

        let color = (language == .korean ? config.koreanColor : config.englishColor).cgColor
        let t = config.thickness
        let bounds = self.bounds

        topLayer.frame = config.sides.contains(.top)
            ? CGRect(x: 0, y: bounds.height - t, width: bounds.width, height: t)
            : .zero
        bottomLayer.frame = config.sides.contains(.bottom)
            ? CGRect(x: 0, y: 0, width: bounds.width, height: t)
            : .zero
        leftLayer.frame = config.sides.contains(.leading)
            ? CGRect(x: 0, y: 0, width: t, height: bounds.height)
            : .zero
        rightLayer.frame = config.sides.contains(.trailing)
            ? CGRect(x: bounds.width - t, y: 0, width: t, height: bounds.height)
            : .zero

        for l in [topLayer, rightLayer, bottomLayer, leftLayer] {
            l.backgroundColor = color
        }

        CATransaction.commit()
    }
}
```

핵심:
- `CATransaction.setDisableActions(true)` 없으면 프레임 변경 시 부드럽게 따라가는 듯하지만 실은 어긋남
- `actions = ["...": NSNull()]`도 함께 사용하여 모든 묵시적 애니메이션 비활성

## 좌표 변환 (AX → NS)

WindowTracker가 AX 좌표(top-left)로 프레임을 보내준다. 오버레이는 NSWindow 좌표(bottom-left)로 변환해야 한다.

```swift
func nsRect(from axRect: CGRect, on screen: NSScreen) -> CGRect {
    let screenFrame = screen.frame
    let flippedY = screenFrame.maxY - axRect.maxY + screenFrame.minY
    return CGRect(x: axRect.origin.x, y: flippedY, width: axRect.width, height: axRect.height)
}
```

주의:
- 메인 스크린(주 디스플레이) 기준: AX는 메인 스크린 top을 0으로 잡지만 NSScreen들은 자체 좌표계 보유
- 멀티 모니터 환경에서는 어느 스크린에 속하는지 먼저 결정 후 변환

## 입력 언어 변경 시 색상 즉시 반영

```swift
inputMonitor.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] lang in self?.currentLanguage = lang; self?.refresh() }
    .store(in: &cancellables)
```

- `CurrentValueSubject`이면 구독 즉시 초기값 받음 → 앱 시작 직후 색상 반영
- 색상만 바뀔 때 윈도우 프레임은 그대로 두고 layer 색만 갱신 → 깜빡임 없음

## 윈도우 프레임 변경 시 오버레이 추적

```swift
windowTracker.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] frame in
        guard let self else { return }
        if let f = frame {
            self.show(at: f)
        } else {
            self.hide()
        }
    }
    .store(in: &cancellables)
```

show 구현:
```swift
func show(at windowFrame: WindowFrame) {
    guard let screen = windowFrame.screen ?? NSScreen.main else { return }
    let nsFrame = nsRect(from: windowFrame.frame, on: screen)
    overlayWindow.setFrame(nsFrame, display: false)
    overlayWindow.orderFrontRegardless()             // key가 되지 않으면서 표시
    contentView.update(config: currentConfig, language: currentLanguage)
}
```

`orderFrontRegardless()` 사용 이유: `makeKeyAndOrderFront`는 키 윈도우가 되어 입력 강탈 → 사용자 작업 방해

## 설정 변경 즉시 반영

```swift
preferencesStore.publisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] config in
        self?.currentConfig = config
        self?.contentView.update(config: config, language: self?.currentLanguage ?? .other(id: ""))
    }
    .store(in: &cancellables)
```

## 흔한 실수

| 실수 | 결과 | 수정 |
|------|------|------|
| `makeKeyAndOrderFront` 사용 | 입력 강탈 → 사용자 타이핑 끊김 | `orderFrontRegardless` |
| `ignoresMouseEvents = false` | 클릭 차단 | `true` 명시 |
| `setFrame(_:display:)` 시 묵시 애니메이션 | 외곽선이 따라가는 잔상 | `CATransaction.setDisableActions(true)` |
| 좌표 변환 누락 | Y축 뒤집힘 | `nsRect(from:on:)` 사용 |
| 윈도우 레벨 너무 높음(`.screenSaver`) | 시스템 다이얼로그 가림 | `.statusBar` 정도로 충분 |
| `collectionBehavior` 미설정 | 다른 스페이스에서 안 보임 | `canJoinAllSpaces` + `stationary` |

## 산출물 위치

- `_workspace/modules/OverlayWindow.swift`
- `_workspace/modules/OverlayContentView.swift`
- `_workspace/modules/OverlayWindowController.swift` — 라이프사이클 관리
- `_workspace/modules/OverlayRenderer.swift` — Combine 구독 조립
- `_workspace/modules/OverlayConfig.swift`
- `_workspace/modules/OverlayRenderer_contract.md`
