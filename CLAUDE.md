# macOS Korean Outliner

포커스된 윈도우의 외곽선 색상으로 한글/영문 입력 상태를 시각적으로 표시하는 macOS 메뉴바 앱.

## 하네스: macOS Korean Outliner Build

**목표:** Swift/AppKit/SwiftUI 기반 한/영 외곽선 표시 앱의 설계·구현·검증·재실행을 7명 에이전트 팀으로 자동화.

**트리거:** 이 프로젝트의 빌드/구현/리팩토링/QA/리뷰 요청 시 `macos-korean-outliner-build` 스킬을 사용하라. 단순 질문(예: "TISInputSource가 뭐야?")은 직접 응답해도 된다.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-04-25 | 초기 하네스 구성 (에이전트 7, 스킬 8) | 전체 | REQUIREMENTS.md 기반 신규 구축 |
| 2026-04-25 | 1차 멀티에이전트 구현 완료 (5 phase, 1,604줄 Swift) | _workspace/, BUILD.md | 사용자 요청 "구현 시작". critical 2 + major 8건 모두 resolved |
| 2026-04-25 | DMG/PKG 빌드 스크립트 추가 | project.yml, scripts/release.sh | 사용자 요청 "DMG/PKG 빌드 스크립트". XcodeGen + xcodebuild + hdiutil + pkgbuild/productbuild |
| 2026-04-25 | 외곽선 길이(lengthRatio)·투명도(opacity) 조절 기능 추가 | OverlayConfig, OverlayContentView, PreferencesView | 사용자 요청. v1 영속화 후방 호환은 커스텀 init(from:)으로 보장 |
| 2026-04-25 | 버그 수정: Mission Control 시 외곽선 잔존 | OverlayWindow.swift | `.stationary` → `.transient` 교체. 시스템이 Exposé/Mission Control 진입 시 자동 숨김 |
| 2026-04-25 | 기능 개선: 윈도우 이동/리사이즈 중 외곽선 일시 숨김 | FocusedWindowTracker.swift | settleDelay 180ms 디바운스. 움직임 도중 hide → 정착 후 emit |
| 2026-04-25 | .gitignore 추가 | .gitignore | macOS+Xcode+XcodeGen+빌드산출물+Claude 런타임 모두 커버 |
| 2026-04-25 | 권한 인식 개선 + 트러블슈팅 UI | AXPermission.swift, PreferencesView.swift | AXIsProcessTrustedWithOptions로 캐시 회피 + 시스템 설정 항목 제거 안내 |
| 2026-04-25 | 로그인 시 자동 실행 옵션 | LaunchAtLogin.swift, PreferencesView.swift | macOS 13+ SMAppService.mainApp 기반. requiresApproval/notFound는 UI로 안내 |
| 2026-04-25 | 권한 자가 진단/복구 도구 | AXPermission.swift, AppRestart.swift, PreferencesView.swift | tccutil reset + 자동 재시작 버튼. /Applications 외부 경로 경고 포함 |
| 2026-04-25 | README.md 작성 | README.md | 사용자/개발자용 진입 문서. 기능·설치·트러블슈팅·아키텍처 요약 |
| 2026-04-25 | GitHub Release 자동화 | scripts/github-release.sh, .github/workflows/release.yml | tag push → Actions가 DMG/PKG 빌드+notarize+release 업로드 자동화 |
