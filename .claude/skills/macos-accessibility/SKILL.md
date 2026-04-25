---
name: macos-accessibility
description: macOS Accessibility(AX) API로 시스템 전역의 포커스 윈도우와 위치/크기 변경을 실시간 추적하는 Swift 모듈을 구현할 때 사용하라. AXUIElement, AXObserver, kAXFocusedWindowAttribute, NSWorkspace 알림, Accessibility 권한 요청 플로우를 다룬다. "포커스 윈도우 추적", "AX API", "윈도우 위치 감지", "Accessibility 권한" 같은 키워드가 등장하면 반드시 이 스킬을 사용할 것.
---

# macOS Accessibility-based Window Tracking

`FocusedWindowTracker` 모듈 구현 가이드. `window-tracker-dev` 에이전트가 사용한다.

## 권한 확인/요청

```swift
import ApplicationServices

enum AXPermissionStatus {
    case granted
    case denied
}

enum AXPermission {
    static func status() -> AXPermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// 사용자에게 시스템 권한 다이얼로그 표시
    static func requestIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

규칙:
- 권한 없으면 추적 시작 자체를 스킵
- 권한 다이얼로그는 사용자가 명시적으로 요청할 때만 띄우기 (앱 시작 시 자동 요청은 방해)

## 포커스 앱 추적

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { [weak self] note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
    self?.attachAXObserver(to: app)
}
```

## 포커스 윈도우 조회

```swift
func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        &value
    )
    guard result == .success, let win = value else { return nil }
    return (win as! AXUIElement)
}

func frame(of window: AXUIElement) -> CGRect? {
    var posValue: AnyObject?
    var sizeValue: AnyObject?
    AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue)
    AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

    var origin = CGPoint.zero
    var size = CGSize.zero
    if let p = posValue {
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
    }
    if let s = sizeValue {
        AXValueGetValue(s as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: origin, size: size)
}
```

주의:
- AX 좌표는 **top-left 원점** (메인 스크린 기준)
- `force cast` (`as!`)는 AXValue 변환에서만 안전 (다른 곳에서는 가드)

## AXObserver로 변경 감지

```swift
private var axObserver: AXObserver?

private func observeFrameChanges(window: AXUIElement, app: NSRunningApplication) {
    var observer: AXObserver?
    let pid = app.processIdentifier
    let result = AXObserverCreate(pid, axCallback, &observer)
    guard result == .success, let obs = observer else { return }

    let context = Unmanaged.passUnretained(self).toOpaque()
    AXObserverAddNotification(obs, window, kAXMovedNotification as CFString, context)
    AXObserverAddNotification(obs, window, kAXResizedNotification as CFString, context)
    AXObserverAddNotification(obs, window, kAXUIElementDestroyedNotification as CFString, context)

    CFRunLoopAddSource(
        CFRunLoopGetMain(),
        AXObserverGetRunLoopSource(obs),
        .defaultMode
    )
    self.axObserver = obs
}

// 콜백은 C 함수 형태
private let axCallback: AXObserverCallback = { observer, element, notification, refcon in
    guard let refcon = refcon else { return }
    let me = Unmanaged<FocusedWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async { me.handleAXNotification(element: element, name: notification as String) }
}
```

핵심:
- 콜백은 **C 함수**여야 함 (Swift 메서드 X) → 전역/static 함수
- `refcon`으로 self 포인터 전달 (`passUnretained`)
- 콜백 내부에서 `DispatchQueue.main.async`로 디스패치 (콜백 스레드는 RunLoop 스레드지만 안전성 위해)

## 멀티 디스플레이 처리

```swift
func screenContaining(point: CGPoint) -> NSScreen? {
    // AX 좌표(top-left)를 NSScreen 좌표로 변환하여 매칭
    NSScreen.screens.first { screen in
        let frame = screen.frame
        return frame.contains(point)
    }
}
```

## 옵저버 해제 (누수 방지!)

```swift
func detachObserver() {
    if let obs = axObserver {
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        axObserver = nil
    }
}
```

규칙:
- **앱 전환 시**: 이전 옵저버를 해제하고 새 앱에 새 옵저버 등록
- **윈도우 destroyed 시**: 해당 옵저버 항목 정리
- `deinit`에서 반드시 `detachObserver()` 호출

## 흔한 실수

| 실수 | 결과 | 수정 |
|------|------|------|
| 권한 없이 AX API 호출 | 에러 반환 + 콘솔 스팸 | `AXIsProcessTrusted()` 가드 |
| AXObserverCallback을 Swift 메서드로 작성 | 컴파일 에러 | C 함수 사용 |
| 옵저버 해제 누락 | 콜백 중복, 좀비 호출 | `detachObserver()` 보장 |
| 폴링으로 프레임 추적 | 배터리·CPU 낭비 | AXObserver 이벤트 사용 |
| AX 좌표를 NSWindow에 그대로 사용 | Y축 뒤집힘 | OverlayRenderer가 변환 (좌표 그대로 전달) |
| `attachAXObserver`를 메인 스레드 외에서 호출 | RunLoop 등록 실패 가능 | 메인 스레드에서 |

## 산출물 위치

- `_workspace/modules/FocusedWindowTracker.swift`
- `_workspace/modules/AXPermission.swift`
- `_workspace/modules/WindowFrame.swift` (`02_interfaces.swift`의 정의 사용)
- `_workspace/modules/WindowTracker_contract.md`
