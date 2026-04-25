# Korean Outliner — 빌드 가이드

7명 멀티에이전트 하네스로 생성된 macOS 한/영 외곽선 표시 앱의 Xcode 빌드 절차.

## 산출물 인벤토리 (`_workspace/`)

### 1. 설계 문서
- `_workspace/01_architecture.md` — 모듈 분해, 데이터 흐름, 라이프사이클
- `_workspace/02_interfaces.swift` — **SSoT**: 전체 protocol, struct, enum (284줄)
- `_workspace/03_tech_decisions.md` — ADR 5건

### 2. 구현 모듈 (`_workspace/modules/`, 총 1,604줄 Swift)

| 파일 | 역할 |
|------|------|
| `InputSourceMonitor.swift` | TIS API 한/영 감지 (BCP-47 활용 분류) |
| `FocusedWindowTracker.swift` | AX API 윈도우 추적 (안전 가드 + 회복 경로) |
| `AXPermission.swift` | Accessibility 권한 헬퍼 |
| `OverlayWindow.swift` | 투명 borderless NSWindow |
| `OverlayContentView.swift` | 4방향 CALayer 외곽선 |
| `OverlayWindowController.swift` | 라이프사이클 + AX→NS 좌표 변환 |
| `OverlayRenderer.swift` | 3개 publisher 구독 + 단일 render() |
| `ColorData+Convert.swift` | NSColor ↔ ColorData 변환 |
| `AppDelegate.swift` | 앱 진입점, PreferencesPresenting 채택 |
| `MenuBarController.swift` | NSStatusItem |
| `PreferencesStore.swift` | UserDefaults + 150ms 디바운스 |
| `PreferencesView.swift` | SwiftUI 설정 화면 |
| `PermissionViewModel.swift` | 권한 폴링 (1.5s/30s 이중) |

### 3. 검증 산출물
- `_workspace/qa/qa_report.md` + `qa_report_round2.md`
- `_workspace/qa/integration_checklist.md`
- `_workspace/qa/manual_test_scenarios.md` (10개 시나리오)
- `_workspace/review/review_report.md`

## 자동화 빌드 (권장)

`scripts/release.sh` + `project.yml`로 .xcodeproj 생성부터 DMG/PKG 패키징까지 자동화 가능.

### 사전 준비 (1회)
```bash
brew install xcodegen          # project.yml → .xcodeproj 자동 생성
```

### 자주 쓰는 커맨드
```bash
./scripts/release.sh project   # KoreanOutliner.xcodeproj 생성
./scripts/release.sh app       # .app 빌드만
./scripts/release.sh dmg       # .app + .dmg 패키징
./scripts/release.sh pkg       # .app + .pkg 패키징
./scripts/release.sh all       # project + app + dmg + pkg 모두
./scripts/release.sh clean     # build/, dist/ 정리
```

산출물 위치:
- `build/DerivedData/Build/Products/Release/Korean Outliner.app`
- `dist/KoreanOutliner-1.0.0.dmg`
- `dist/KoreanOutliner-1.0.0.pkg`

### 코드사인 + Notarization

직접 배포 시:
```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: 이름 (TEAMID)"
export DEVELOPER_ID_INSTALLER="Developer ID Installer: 이름 (TEAMID)"
export NOTARY_PROFILE="my-notary-profile"   # xcrun notarytool store-credentials 로 사전 등록

./scripts/release.sh dmg
./scripts/release.sh notarize dist/KoreanOutliner-1.0.0.dmg

./scripts/release.sh pkg
./scripts/release.sh notarize dist/KoreanOutliner-1.0.0.pkg
```

환경변수가 없으면 미사인 ad-hoc 빌드로 진행 (개인 테스트용).

## Xcode 프로젝트 수동 생성 (대안)

XcodeGen을 쓰지 않을 경우.

### 1. 새 프로젝트
```
Xcode → File → New → Project → macOS → App
- Product Name: Korean Outliner
- Interface: SwiftUI
- Language: Swift
- Bundle Identifier: com.yourorg.koreanoutliner
- Deployment Target: macOS 13.0
```

기본 생성된 `App.swift`와 `ContentView.swift`는 **삭제**한다.

### 2. 소스 추가

`_workspace/02_interfaces.swift` + `_workspace/modules/*.swift` (13개 .swift)를 모두 Xcode 타깃에 드래그 앤 드롭하여 추가. **단일 타깃에 모두 포함**해야 cross-file 타입 참조가 풀린다 (현재 SourceKit 진단 에러는 모두 이 때문).

추가할 파일 13개:
```
02_interfaces.swift
modules/InputSourceMonitor.swift
modules/FocusedWindowTracker.swift
modules/AXPermission.swift
modules/OverlayWindow.swift
modules/OverlayContentView.swift
modules/OverlayWindowController.swift
modules/OverlayRenderer.swift
modules/ColorData+Convert.swift
modules/AppDelegate.swift
modules/MenuBarController.swift
modules/PreferencesStore.swift
modules/PreferencesView.swift
modules/PermissionViewModel.swift
```

### 3. Info.plist 설정

`_workspace/modules/Info.plist.additions.md` 참조하여 다음 키 추가:

**필수**
- `LSUIElement` = `YES`
- `NSAccessibilityUsageDescription` = "포커스된 윈도우의 위치/크기를 읽어 외곽선을 그리기 위해 Accessibility 권한이 필요합니다."

**필수 설정 변경**
- Target → Signing & Capabilities → **App Sandbox 제거** (Sandbox에서 AX API 동작 불가)
- Target → General → Deployment Info → macOS 13.0
- Hardened Runtime는 활성화 가능 (별도 entitlement 불필요)

### 4. 빌드 & 첫 실행

1. Cmd+R로 빌드 → 첫 실행 시 Dock 아이콘 없이 메뉴바에 점선 사각형 아이콘 표시
2. 메뉴바 아이콘 클릭 → "Preferences…" → 권한 안내 화면
3. "권한 허용" 또는 "시스템 설정 열기" 클릭
4. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 본 앱 허용
5. 1.5초 내에 외곽선이 자동 표시되기 시작

### 5. 배포

Sandbox 비활성으로 App Store 배포는 불가. 직접 배포:
- Hardened Runtime 활성화
- Developer ID Application으로 코드사인
- `notarytool`로 notarization
- DMG 또는 ZIP 패키징

## 검증 시나리오

`_workspace/qa/manual_test_scenarios.md`의 10개 시나리오를 실기기에서 모두 통과해야 한다:

1. 첫 실행 (권한 안내)
2. 한/영 전환
3. 앱 전환
4. 윈도우 리사이즈/이동
5. 전체화면 전환
6. 멀티 스페이스
7. 멀티 모니터
8. 설정 변경
9. 권한 revoke
10. 앱 종료

## 알려진 제약

- **App Sandbox 미사용** — App Store 배포 불가, 직접 배포 전용
- **macOS 13+ 필요** — Carbon TIS + 모던 SwiftUI
- **AX 권한 필수** — 권한 없으면 외곽선 표시 불가 (앱은 동작하나 추적 비활성)

## 통계

- 코드 행: 1,604줄 Swift + 12개 Markdown 문서
- 결함 처리: critical 2 + major 8 (모두 resolved, regression 0)
- 멀티에이전트 협업: 7명 (architect, 4 dev, qa, reviewer)
