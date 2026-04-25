# Info.plist Additions

이 앱은 메뉴바 전용(LSUIElement) macOS 앱이며 Accessibility 권한을 사용한다.
Xcode 프로젝트의 `Info.plist` (또는 타깃의 Info 탭)에 다음 키들을 추가한다.

## 필수 키

| Key | Type | Value | 사유 |
|-----|------|-------|------|
| `LSUIElement` | Boolean | `YES` | Dock 미표시, Cmd+Tab 제외 — 메뉴바 전용 동작 |
| `NSAccessibilityUsageDescription` | String | "포커스된 윈도우의 위치/크기를 읽어 외곽선을 그리기 위해 Accessibility 권한이 필요합니다." | 권한 요청 다이얼로그에 표시되는 사유 문구 |

## 권장 키

| Key | Type | Value | 사유 |
|-----|------|-------|------|
| `LSMinimumSystemVersion` | String | `13.0` | macOS Ventura 이상 (Carbon TIS + AX API 안정성) |
| `NSHumanReadableCopyright` | String | `Copyright © 2026` | About 화면 표기 |
| `CFBundleShortVersionString` | String | `1.0.0` | 사용자 노출 버전 |
| `CFBundleVersion` | String | `1` | 빌드 번호 |
| `CFBundleIdentifier` | String | `com.naxreo.koreanoutliner` (예) | 권한 dialog 식별자 |
| `CFBundleName` | String | `Korean Outliner` | 메뉴 이름 |

## 사용하지 않음 (경고용 메모)

| Key | 비사용 사유 |
|-----|-----------|
| `NSAppleEventsUsageDescription` | 본 앱은 AppleScript / Apple Events를 호출하지 않음 |
| `NSCameraUsageDescription` 등 | 사용 안 함 |
| App Sandbox | **반드시 비활성화**. Sandbox에서는 Accessibility API 동작 불가 |
| Hardened Runtime | 활성화 가능. Accessibility는 시스템 권한이므로 별도 entitlement 불필요 |

## XML 스니펫 (참조용)

```xml
<key>LSUIElement</key>
<true/>

<key>NSAccessibilityUsageDescription</key>
<string>포커스된 윈도우의 위치/크기를 읽어 외곽선을 그리기 위해 Accessibility 권한이 필요합니다.</string>

<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<key>CFBundleShortVersionString</key>
<string>1.0.0</string>

<key>CFBundleVersion</key>
<string>1</string>
```

## Xcode 설정 체크리스트

- [ ] Target → Signing & Capabilities → **App Sandbox 제거** (있다면)
- [ ] Target → General → Deployment Info → macOS 13.0+
- [ ] Target → Info → Custom macOS Application Target Properties에 위 키 추가
- [ ] 모든 모듈을 단일 타깃으로 묶기 (별도 프레임워크 분리 없음 — public 접근자는 그대로 유지)
- [ ] Build Settings → Swift Language Version 5 이상
- [ ] `Carbon.HIToolbox`, `ApplicationServices`, `AppKit`, `SwiftUI`, `Combine` 자동 링크 (별도 라이브러리 추가 불필요)

## 권한 부여 안내 문구 (사용자용)

> Korean Outliner가 정상 동작하려면 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 본 앱을 허용해야 합니다.
> 권한 부여 후 앱을 다시 시작할 필요는 없습니다 (1.5초 폴링 후 자동 활성화).
