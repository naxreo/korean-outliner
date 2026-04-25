---
name: macos-architecture
description: macOS 메뉴바 유틸리티 앱(Swift/AppKit/SwiftUI)의 시스템 아키텍처 설계, 모듈 분해, Swift protocol 기반 경계면 계약 정의에 사용하라. 한/영 외곽선 앱처럼 InputSource 감시 + 윈도우 추적 + 오버레이 렌더링 + 설정 UI가 결합된 멀티 모듈 앱을 설계할 때 반드시 이 스킬을 사용할 것. ADR(Architecture Decision Record) 형식으로 기술 결정을 기록하는 작업도 포함.
---

# macOS Architecture Design

macOS 네이티브 유틸리티 앱의 아키텍처를 설계하는 가이드. `architect` 에이전트가 사용한다.

## 산출물

설계가 끝나면 다음 3개 파일을 `_workspace/`에 생성한다:

1. `01_architecture.md` — 모듈 분해, 데이터 흐름, 라이프사이클 다이어그램(텍스트)
2. `02_interfaces.swift` — 모든 모듈 간 경계면을 Swift `protocol`/`struct`/`enum`으로 정의
3. `03_tech_decisions.md` — ADR 형식의 기술 결정 근거 모음

## 모듈 분해 원칙

| 모듈 | 책임 | 외부 의존 |
|------|------|----------|
| **InputSourceMonitor** | 한/영 입력 상태 감지 | TISInputSource (Carbon) |
| **FocusedWindowTracker** | 포커스 앱·윈도우 추적 + 프레임 변경 감지 | NSWorkspace, AXUIElement |
| **OverlayRenderer** | 투명 오버레이 윈도우 + CALayer 외곽선 | AppKit |
| **PreferencesStore** | 설정 영속화 (UserDefaults) | Foundation |
| **PreferencesUI** | SwiftUI 설정 화면 | SwiftUI |
| **MenuBarController** | NSStatusItem | AppKit |
| **AppCoordinator** | 모듈 조립, 라이프사이클 | AppDelegate |

규칙:
- 각 모듈은 외부에 **protocol만 노출**한다 (구현 클래스는 internal)
- 모듈 간 데이터는 **불변 struct/enum**으로 전달한다 (참조 공유 금지)
- 이벤트는 **Combine Publisher** 또는 **클로저 콜백**으로 노출한다 (델리게이트 패턴은 메서드 시그니처 변경 시 마이그레이션 비용 큼)

## 02_interfaces.swift 작성 규칙

`02_interfaces.swift`에는 다음을 모두 포함한다:

```swift
// 1. 도메인 enum
enum InputLanguage: Equatable {
    case korean
    case english
    case other(id: String)
}

// 2. 데이터 구조 (불변)
struct WindowFrame: Equatable {
    let frame: CGRect          // AX 좌표계 (top-left)
    let screen: NSScreen?
    let appBundleID: String
    let windowID: CGWindowID?
}

struct OverlayConfig: Codable, Equatable {
    var koreanColor: ColorData
    var englishColor: ColorData
    var thickness: CGFloat     // 1...10
    var sides: OverlaySides    // OptionSet: [.top, .leading, .trailing, .bottom]
}

// 3. 모듈 protocol
protocol InputSourceMonitoring: AnyObject {
    var current: InputLanguage { get }
    var publisher: AnyPublisher<InputLanguage, Never> { get }
    func start()
    func stop()
}

protocol FocusedWindowTracking: AnyObject {
    var publisher: AnyPublisher<WindowFrame?, Never> { get }
    var permissionStatus: AXPermissionStatus { get }
    func start()
    func stop()
}

protocol OverlayRendering: AnyObject {
    func apply(frame: WindowFrame?)
    func apply(language: InputLanguage)
    func apply(config: OverlayConfig)
}
```

이 파일은 **단일 진실의 원천(SSoT)**이다. 모든 dev 에이전트가 이 파일을 import 하여 구현한다.

## 좌표계 규약 (반드시 명시)

- **AX API 좌표**: top-left 원점 (메인 스크린 기준), Y는 아래로 증가
- **NSWindow 좌표**: bottom-left 원점, Y는 위로 증가
- WindowFrame.frame은 **AX 좌표 그대로 전달**한다
- OverlayRenderer가 NSScreen 정보를 사용해 NSWindow 좌표로 변환한다

이 규약은 `01_architecture.md`와 `02_interfaces.swift` 주석에 명시한다.

## 기술 결정 (ADR) 작성 형식

`03_tech_decisions.md`에 각 결정을 다음 형식으로 기록:

```markdown
## ADR-001: 입력 소스 감지에 TISInputSource 사용

### 결정
TISCopyCurrentKeyboardInputSource() + DistributedNotificationCenter 알림 구독

### 대안
- NSTextInputContext: 앱 내 텍스트 입력만 감지 가능, 시스템 전역 X
- NSEvent flagsChanged 모니터링: 한/영 키 자체는 감지하나 IME 상태 X

### 근거
시스템 전역 입력 소스 변경을 IME-agnostic하게 감지하는 표준 API

### 영향
- Carbon 프레임워크 의존 발생 (Apple은 향후 deprecation 가능성 시사)
- 마이그레이션 시 abstraction layer로 격리 필요
```

## 권한·보안 전략

- **Accessibility 권한**: WindowTracker가 필수로 요구. AppCoordinator에서 시작 시 상태 확인 → 없으면 PreferencesUI의 권한 화면으로 유도
- **Sandboxing**: AX API는 sandbox에서 동작하지 않음 → **Sandboxing 비활성화** (App Store 배포 불가, 직접 배포 전용)
- **Hardened Runtime**: 필요. notarization 위해 enable
- **최소 권한**: AX는 윈도우 프레임 조회만, 입력 가로채기·키 입력 시뮬레이션은 사용하지 않음

## 빌드·배포 결정

- **Xcode 프로젝트**: SPM은 GUI 앱 entitlements 관리가 까다로움 → Xcode 프로젝트 권장
- **타겟 OS**: macOS 13 Ventura 이상 (`@AppStorage`, 모던 SwiftUI)
- **배포**: notarized DMG (App Store 제외, sandbox 미적용)

## 협업 절차

1. REQUIREMENTS.md를 읽고 모듈 분해 초안 작성
2. `02_interfaces.swift` 작성 → 팀에 경로 공유
3. 구현 중 인터페이스 변경 요청 발생 시:
   - 변경 사유를 `_workspace/00_changelog.md`에 기록
   - `02_interfaces.swift` 갱신 후 영향받는 dev 에이전트에 SendMessage
4. 모든 모듈 구현 완료 후 architect는 모듈 조립 가이드를 `01_architecture.md`에 추가
