# Korean Outliner

포커스된 윈도우의 외곽선 색상으로 macOS의 한/영 입력 상태를 시각적으로 표시하는 메뉴바 앱.

> 한글로 입력해야 할 곳에 영문이 입력되거나, 그 반대 상황 때문에 매일 수십 번 backspace를 누르고 있다면 — 이 앱은 현재 포커스된 윈도우 외곽에 한글일 땐 파란선, 영문일 땐 빨간선을 표시해 시선이 가는 곳에서 입력 모드를 즉시 알 수 있게 합니다.

---

## 주요 기능

- **한/영 자동 색상 전환** — TISInputSource API로 시스템 전역 입력 모드 실시간 감지. 색상은 사용자 지정 가능
- **포커스 표시 전용 모드** — 한/영 상태를 무시하고 포커스된 윈도우만 단일 색상으로 표시하는 옵션
- **포커스 윈도우 자동 추적** — Accessibility API 기반. 앱 전환·윈도우 활성 변경 즉시 반응
- **외곽선 표시 위치 4방향 독립 토글** — 위/아래/왼쪽/오른쪽 중 원하는 변만 켜기
- **두께·길이·투명도 조절** — 1~10pt 두께, 5~100% 길이(가운데 정렬), 5~100% 투명도
- **Mission Control / 전체화면 / 멀티 스페이스 / 멀티 모니터 지원** — `.transient` + `.canJoinAllSpaces` + `.fullScreenAuxiliary` 조합으로 모든 환경 대응
- **윈도우 이동·리사이즈 중 자동 숨김** — 드래그 도중 외곽선이 따라다니는 잔상 제거. 정착 후 다시 표시
- **로그인 시 자동 실행** — macOS 13+ `SMAppService.mainApp` 기반 토글
- **메뉴바 전용** — Dock 아이콘·Cmd+Tab 미표시 (`LSUIElement`)
- **권한 자가 복구 도구** — TCC 캐시 꼬임 시 한 번 클릭으로 `tccutil reset` + 자동 재시작

## 시스템 요구사항

- **macOS 13 (Ventura) 이상**
- **Accessibility 권한** (시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용)
- **App Sandbox 비활성** — Accessibility API 사용을 위해 필수. App Store 배포는 불가하며 직접 배포 전용

## 설치

배포된 DMG/PKG가 있다면 평소처럼 `/Applications`로 끌어다 놓으세요. 빌드부터 직접 한다면 [BUILD.md](BUILD.md) 참조.

```bash
brew install xcodegen      # 1회

./scripts/release.sh project   # KoreanOutliner.xcodeproj 생성
./scripts/release.sh app       # .app 빌드
./scripts/release.sh dmg       # DMG 패키징
./scripts/release.sh pkg       # PKG 패키징
./scripts/release.sh all       # 모두

cp -R "build/DerivedData/Build/Products/Release/Korean Outliner.app" /Applications/
open "/Applications/Korean Outliner.app"
```

> `/Applications` 외부에서 실행하면 코드 사인 hash 변경 등으로 권한이 불안정합니다. 항상 `/Applications`에서 실행 권장.

## Release (GitHub Actions 자동화)

GitHub에 새 release를 게시하면 Actions가 macos-14 runner에서 빌드 → DMG/PKG 패키징 → release에 업로드까지 자동 수행합니다.

```bash
./scripts/github-release.sh                  # project.yml의 MARKETING_VERSION 사용
./scripts/github-release.sh 1.2.0            # 버전 명시
./scripts/github-release.sh --bump patch     # patch 자동 증가 + 커밋 + 태그
gh run watch                                 # 빌드 진행 모니터링
```

태그가 push되면 [`.github/workflows/release.yml`](.github/workflows/release.yml)이 트리거되어:
1. XcodeGen으로 .xcodeproj 생성
2. (옵션) 코드사인 인증서 import
3. `./scripts/release.sh all` → DMG + PKG
4. (옵션) notarize
5. Release에 산출물 업로드 + auto-generated release notes

### 코드사인 / Notarization (선택, 권장)

다음 secrets를 GitHub repo Settings → Secrets and variables → Actions에 등록하면 자동으로 사인·notarize됩니다 (없으면 unsigned ad-hoc 빌드).

| Secret | 값 |
|--------|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID 인증서를 P12로 export 후 `base64 < cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | P12 export 시 설정한 비밀번호 |
| `DEVELOPER_ID_APPLICATION` | `Developer ID Application: 이름 (TEAMID)` |
| `DEVELOPER_ID_INSTALLER` | `Developer ID Installer: 이름 (TEAMID)` |
| `NOTARY_APPLE_ID` | Apple ID 이메일 |
| `NOTARY_TEAM_ID` | 10자리 Team ID |
| `NOTARY_APP_PASSWORD` | [appleid.apple.com](https://appleid.apple.com)에서 생성한 app-specific password |

설정하지 않으면 unsigned 빌드가 release에 올라가며, 다운로드한 사용자는 macOS Gatekeeper에서 차단됩니다 (우회 가능하나 일반 배포에는 부적합).

### 수동 재빌드

빌드 실패 또는 산출물 재생성이 필요하면:

```bash
gh workflow run release.yml -f tag=v1.2.0
```

## 사용법

1. 앱 실행 → 메뉴바에 점선 사각형 아이콘 표시
2. 아이콘 클릭 → **Preferences…**
3. 권한 안내 화면에서 "권한 허용" 또는 "시스템 설정 열기" → 손쉬운 사용에서 Korean Outliner 토글 ON
4. 1.5초 내에 외곽선 자동 표시 시작
5. 한/영 키 또는 Caps Lock으로 입력 전환 → 외곽선 색상 즉시 변경

### Preferences 항목

| 섹션 | 설명 |
|------|------|
| 외곽선 표시 활성화 | 마스터 토글 |
| 로그인 시 자동 실행 | macOS 로그인 시 자동 시작 |
| 한/영 상태 무시 | 켜면 포커스 윈도우만 단일 색상(외곽선 색상)으로 표시 |
| 한글/영문 입력 색상 | ColorPicker로 자유 지정 (한/영 상태 무시 시 단일 외곽선 색상) |
| 두께 | 1~10pt |
| 길이 | 5~100%, 가운데 정렬 |
| 투명도 | 5~100% |
| 표시 위치 | 위/아래/왼쪽/오른쪽 4방향 독립 토글 |

## 트러블슈팅

### 권한을 허용했는데 외곽선이 표시되지 않음

가장 흔한 원인은 **TCC 데이터베이스와 binary hash mismatch** 입니다. 다음 절차로 해결:

```bash
killall "Korean Outliner" 2>/dev/null
tccutil reset Accessibility com.naxreo.koreanoutliner
```

그리고 시스템 설정 → 손쉬운 사용에서 **Korean Outliner 항목을 '−' 버튼으로 제거**한 뒤, `/Applications/Korean Outliner.app`을 다시 실행.

또는 Preferences의 권한 안내 섹션에서 **"권한을 허용했는데 동작하지 않나요?"** 펼치고 **"권한 캐시 초기화 후 재시작"** 버튼을 누르면 위 절차가 자동으로 실행됩니다.

### 빌드별로 권한이 매번 무효화됨

ad-hoc 빌드는 binary hash가 매번 달라져 시스템이 다른 앱으로 인식합니다. 안정 동작을 원하면 코드 사인 identity로 일관된 사인을 적용하세요:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: 이름 (TEAMID)"
./scripts/release.sh app
```

## 아키텍처

7개 모듈로 구성된 Swift/AppKit/SwiftUI 앱.

```
InputSourceMonitor    — TISInputSource로 한/영 감지 (BCP-47 활용)
FocusedWindowTracker  — AXObserver로 포커스 윈도우 frame 추적
OverlayWindow + ContentView + Controller — 투명 borderless NSWindow + 4방향 CALayer
OverlayRenderer       — 3개 publisher 구독, 단일 render() 진입점
PreferencesStore      — UserDefaults JSON Codable + 디바운스 영속화
PreferencesView       — SwiftUI 설정 화면
MenuBarController     — NSStatusItem
AppDelegate           — 모듈 조립 + PreferencesPresenting + applicationWillTerminate
```

설계 SSoT: [`_workspace/02_interfaces.swift`](_workspace/02_interfaces.swift)
모듈 분해 + 데이터 흐름: [`_workspace/01_architecture.md`](_workspace/01_architecture.md)
ADR: [`_workspace/03_tech_decisions.md`](_workspace/03_tech_decisions.md)

## 개발 프로세스

이 프로젝트는 Claude Code의 **멀티에이전트 하네스**로 구현되었습니다.

- 7명 에이전트(`architect` + 4 dev + `qa-integrator` + `reviewer`)가 5단계 파이프라인으로 협업
- Phase 1 단일 → Phase 2 팀 → Phase 3 병렬 검증 → Phase 4 핀포인트 결함 해소 → Phase 5 산출물
- 1차 라운드에서 critical 2 + major 8 발견 → 모두 resolved, regression 0
- 하네스 정의: [`.claude/agents/`](.claude/agents/), [`.claude/skills/`](.claude/skills/)
- 변경 이력: [`CLAUDE.md`](CLAUDE.md), [`_workspace/00_changelog.md`](_workspace/00_changelog.md)

## 알려진 제약

- **App Sandbox 미사용** — App Store 배포 불가
- **macOS 13+ 필요** — Carbon TIS + 모던 SwiftUI + SMAppService.mainApp
- **Accessibility 권한 필수** — 권한 미부여 시 외곽선 비활성

## 디렉토리 구조

```
.
├── REQUIREMENTS.md       — 초기 요구사항
├── README.md             — 본 문서
├── BUILD.md              — 빌드/패키징/배포 상세 가이드
├── CLAUDE.md             — 하네스 포인터 + 변경 이력
├── project.yml           — XcodeGen 설정 (SSoT)
├── scripts/
│   └── release.sh        — 빌드/DMG/PKG/notarize 통합 스크립트
├── _workspace/           — 멀티에이전트 산출물 (실제 Swift 소스 + 설계 문서)
│   ├── 01_architecture.md
│   ├── 02_interfaces.swift
│   ├── 03_tech_decisions.md
│   ├── 00_changelog.md
│   ├── modules/          — 14개 .swift, ~1,800줄
│   ├── qa/               — QA 보고서 (1차/2차) + 통합 체크리스트 + 시나리오 10개
│   └── review/           — 코드 리뷰 보고서
└── .claude/
    ├── agents/           — 7명 에이전트 정의
    └── skills/           — 8개 스킬 (오케스트레이터 + 모듈별)
```

## 라이선스

미정.
