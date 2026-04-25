---
name: macos-input-source
description: macOS TISInputSource (Carbon) API로 한글/영문 입력 상태를 실시간 감지하는 Swift 모듈을 구현할 때 사용하라. 키보드 입력 소스 변경 알림 구독, IME 식별, Combine Publisher 노출 패턴을 다룬다. "한영 감지", "input source", "TIS", "현재 입력 소스" 같은 표현이 등장하면 반드시 이 스킬을 사용할 것.
---

# macOS Input Source Monitoring

`InputSourceMonitor` 모듈 구현 가이드. `input-monitor-dev` 에이전트가 사용한다.

## 핵심 API

```swift
import Carbon.HIToolbox

// 현재 입력 소스 조회
let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()

// 입력 소스 ID 얻기 (분류용)
let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
let id = Unmanaged<CFString>.fromOpaque(idPtr!).takeUnretainedValue() as String
```

핵심 주의:
- `TISCopyCurrentKeyboardInputSource()`는 **retained** → `takeRetainedValue()`
- `TISGetInputSourceProperty()`는 **not retained** → `takeUnretainedValue()`
- 잘못 사용하면 메모리 누수 또는 크래시

## 변경 알림 구독

```swift
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.refreshCurrentSource()
}
```

규칙:
- `NSDistributedNotificationCenter` (X) — `DistributedNotificationCenter.default()` (O)
- 큐는 `.main`으로 (구독자가 메인 스레드에서 UI 업데이트 가능하게)
- `[weak self]` 캡처 필수 (관측자 누수 방지)
- `deinit`에서 `removeObserver(self)` 호출

## 한/영 분류 로직

입력 소스 ID 패턴으로 분류:

```swift
func classify(sourceID: String) -> InputLanguage {
    if sourceID.contains("Korean") || sourceID.hasPrefix("com.apple.inputmethod.Korean") {
        return .korean
    }
    if sourceID.hasPrefix("com.apple.keylayout.ABC") ||
       sourceID.hasPrefix("com.apple.keylayout.US") ||
       sourceID.hasPrefix("com.apple.keylayout.British") {
        return .english
    }
    return .other(id: sourceID)
}
```

규칙:
- **localized name 사용 금지**: 사용자 언어에 따라 "한국어"/"Korean"/"韓國語" 다양 → 절대 이걸로 판별하지 말 것
- **ID 접두사로 판별**: `kTISPropertyInputSourceID` 값만 사용
- **타사 IME(예: 구름입력기)**는 일단 `.other`로 분류 → 추후 확장

## 구현 골격

```swift
final class InputSourceMonitor: InputSourceMonitoring {
    private let subject = CurrentValueSubject<InputLanguage, Never>(.other(id: "init"))
    private var observer: NSObjectProtocol?

    var current: InputLanguage { subject.value }
    var publisher: AnyPublisher<InputLanguage, Never> { subject.eraseToAnyPublisher() }

    func start() {
        refreshCurrentSource()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCurrentSource()
        }
    }

    func stop() {
        if let obs = observer {
            DistributedNotificationCenter.default().removeObserver(obs)
            observer = nil
        }
    }

    deinit { stop() }

    private func refreshCurrentSource() {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            subject.send(.other(id: "unknown"))
            return
        }
        guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else {
            subject.send(.other(id: "unknown"))
            return
        }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        subject.send(classify(sourceID: id))
    }
}
```

핵심:
- `CurrentValueSubject` 사용 → 구독 시점에 최신값 즉시 방출 (UI 시작 시 색상 즉시 반영)
- `start()`에서 `refreshCurrentSource()` 먼저 호출 → 알림 도착 전에도 초기값 확보

## 흔한 실수

| 실수 | 결과 | 수정 |
|------|------|------|
| `takeRetainedValue` ↔ `takeUnretainedValue` 혼동 | 누수 또는 크래시 | TIS 함수별 retain 규칙 확인 |
| `NotificationCenter.default` 사용 | 알림 미수신 | `DistributedNotificationCenter` 사용 |
| 큐를 `nil`로 설정 | 임의 스레드 콜백 → UI 업데이트 시 크래시 | `.main` 명시 |
| `PassthroughSubject` 사용 | 신규 구독자가 초기값 못 받음 | `CurrentValueSubject` 사용 |
| ID 비교를 `==` 정확 매칭 | 입력 소스 변형(예: 2-Set, 3-Set 한글) 누락 | `hasPrefix`/`contains` 사용 |

## 산출물 위치

- `_workspace/modules/InputSourceMonitor.swift`
- `_workspace/modules/InputLanguage.swift`
- `_workspace/modules/InputMonitor_contract.md` — 외부에서 사용하는 방법 요약 (3~5줄)
