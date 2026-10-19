## 2026-04-25 - 초기 아키텍처 SSoT 확정

- `01_architecture.md`: 모듈 분해(InputSourceMonitor, FocusedWindowTracker, OverlayRenderer, PreferencesStore, PreferencesUI, MenuBarController, AppCoordinator) 및 데이터 흐름·라이프사이클·조립 가이드 초안 작성
- `02_interfaces.swift`: SSoT 파일 신설. InputLanguage / WindowFrame / OverlayConfig / OverlaySides / ColorData / AXPermissionStatus 및 InputSourceMonitoring / FocusedWindowTracking / OverlayRendering / PreferencesStoring / MenuBarPresenting protocol 정의. 좌표계 규약(AX top-left vs NS bottom-left) 파일 헤더 주석에 명시
- `03_tech_decisions.md`: ADR-001(TISInputSource) / ADR-002(AXObserver) / ADR-003(NSWindow level) / ADR-004(Sandbox 비활성화) / ADR-005(NSColor → ColorData 직렬화) 등 5건 기록

## 2026-04-25 - Phase 4: overlay-renderer-dev major 수정

- `OverlayRenderer.swift`: review-major-4 결함(`apply(language:)` 멱등성 깨짐) 수정. `apply(language:)`가 `controller.refresh(...)`로 분기하던 우회 경로를 제거하고 `render()` 단일 진입점으로 통일. 이로써 `apply(frame:)`/`apply(config:)`와 동일하게 캐시(currentFrame/currentLanguage/currentConfig) 갱신 → render() 흐름을 따르며, frame이 set되었지만 윈도우가 아직 visible이 아닌 transient 상태에서 입력 언어 변경 시 윈도우가 정상적으로 표시되지 않던 일관성 문제 해소.

## 2026-04-25 - Phase 4: input-monitor-dev major 수정

- `InputSourceMonitor.swift`: review-major-5 / qa-011 결함(`classify(sourceID:)` 분류 부정확) 수정. hybrid 분류 전략으로 재구성:
  - 1순위: ID prefix 매칭을 `com.apple.inputmethod.Korean` + `com.apple.keylayout.Korean` 두 형태로 명시화하고 위양성을 유발하던 `contains("Korean")` 제거.
  - 2순위: `TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)`로 BCP-47 언어 코드 배열을 추출 후 primary 언어가 `ko`/`ko-*`이면 `.korean`, `en`/`en-*`이면 `.english`로 분류. 이로써 `com.apple.keylayout.Dvorak`/`Colemak` 등 화이트리스트에 없던 영문 키보드도 정확히 `.english`로 잡힘.
  - Carbon 메모리 규칙 준수: `TISGetInputSourceProperty`는 Get-규칙이므로 반환 CFArray를 `Unmanaged.fromOpaque(...).takeUnretainedValue()`로 처리.
  - 분류 헬퍼 시그니처를 `classify(sourceID:languages:)`로 변경(내부 static 메서드, 외부 호출자 없음).

## 2026-04-25 - Phase 4: window-tracker-dev critical/major 수정

- `FocusedWindowTracker.swift` (review-critical-2): `focusedWindow(of:)`의 `raw as! AXUIElement` 강제 캐스팅 앞에 `CFGetTypeID(raw as CFTypeRef) == AXUIElementGetTypeID()` 가드 추가. `frame(of:)`의 `posRaw as! AXValue` / `sizeRaw as! AXValue`에도 동일하게 `AXValueGetTypeID()` 비교 가드 추가. AX가 `.success`로 반환했지만 transient하게 다른 CFType을 돌려주는 케이스(Electron/Carbon/teardown 시점)에서 메인 스레드 트랩으로 앱 전체가 크래시되던 위험 제거. 가드 실패 시 nil을 반환하여 OverlayRenderer가 외곽선을 즉시 숨기도록 한다.
- `FocusedWindowTracker.swift` (review-major-6): `AXObserverCreate` 실패 시 회복 경로 보강. (1) 실패 사유를 `NSLog`로 기록(pid + AXError rawValue만 로깅, 윈도우 타이틀/사용자 콘텐츠는 일절 로그하지 않음). (2) 실패 직후 `activeApp` / `activeAppElement`를 명시적으로 nil로 클리어하여 다음 `didActivateApplicationNotification` 도착 시 attach가 깨끗한 상태에서 재시도되도록 변경(이전에는 검증 실패한 activeAppElement가 잔존했음). publisher는 nil emit으로 외곽선을 즉시 숨김.
- `FocusedWindowTracker.swift` (qa-012): `screenContaining(axRect:)`의 primary 스크린 도출을 OverlayWindowController와 동일한 3단 fallback(`screens.first { $0.frame.origin == .zero } ?? screens.first ?? NSScreen.main`)으로 변경. 멀티 모니터 + 사용자 정렬 시 Tracker와 Renderer가 서로 다른 primaryMaxY를 사용해 외곽선이 오프셋되던 비대칭 결함 해소.
- `FocusedWindowTracker.swift` (qa-013): `start()` 시점의 `NSWorkspace.shared.frontmostApplication` 즉시 attach 경로(기존 코드)를 의도 주석으로 보강. 일부 macOS 환경에서 `didActivateApplicationNotification`이 이미 활성 중인 앱에 대해 발사되지 않을 수 있는 상황에 대한 belt-and-suspenders임을 명시. `DistributedNotificationCenter` 이중 채널 구독은 과도한 비용/중복 emit 위험으로 채택하지 않음.
- `AXPermission.swift`: 본 결함 셋과 무관 — 변경 없음.

## 2026-04-25 - Phase 4: preferences-dev critical/major 수정

- `AppDelegate.swift` (review-critical-1 / qa-major-1): MenuBarController publisher 미연결 결함 수정. `cancellables: Set<AnyCancellable>`을 추가하고 `applicationDidFinishLaunching`에서 두 구독을 등록 — `inputMonitor.publisher`를 메인 스레드에서 sink하여 `menuBar.setLanguage(_:)`로 전달, `preferencesStore.publisher`를 `map(\.isEnabled)` + `removeDuplicates()` 후 sink하여 `menuBar.setEnabled(_:)`로 전달. 이로써 한/영 전환 시 메뉴바 툴팁이 갱신되고 마스터 토글 OFF 시 아이콘이 dim 처리된다(MenuBarController의 두 setter가 dead code 상태에서 활성화).
- `AppDelegate.swift` (review-major-1 / qa-major-2): `PermissionViewModel`을 `showPreferences()` 첫 호출에만 lazy 생성하던 구조에서 `applicationDidFinishLaunching` 시점 즉시 생성·보유로 격상. Preferences 윈도우를 한 번도 열지 않은 채 시스템 설정에서 권한을 허용하는 first-run 시나리오에서도 폴링이 가동되어 `tracker.start()`가 자동 호출된다. 동시에 AppDelegate가 `PreferencesPresenting` 프로토콜(`show()` / `showAccessibilityPrompt()`) 채택 — 권한이 `.granted`가 아니면 `applicationDidFinishLaunching` 마지막에 `showAccessibilityPrompt()`를 호출해 Preferences 자동 노출. revoke 시점에는 PermissionViewModel의 `onRevoked` 콜백을 통해 다시 Preferences를 띄워 사용자에게 즉시 알림. MenuBarController에서 호출하던 기존 `showPreferences()`는 `show()` 별칭으로 유지하여 호환성 보존.
- `AppDelegate.swift` (qa-major-3): `applicationWillTerminate(_:)` 핸들러 신설. `cancellables.removeAll()` → `inputMonitor.stop()` → `windowTracker.stop()` → `preferencesStore.flush()` 순서로 종료 정리. 종료 직전 NSWorkspace/AX 알림 큐의 잔여 콜백이 dangling self에 접근하는 low-probability 크래시 위험 차단. swift-qa-integration 시나리오 #10("Quit → 외곽선 즉시 사라짐") 보장.
- `PermissionViewModel.swift` (review-major-2): 권한 부여 후에도 1.5초 폴링 Timer가 영구 가동되던 배터리/CPU 낭비 결함 수정. 폴링 간격을 이중화: 미부여 상태는 1.5초(즉각성), 부여 상태는 30초(저속 모드 — revoke 감지 지연은 허용). `scheduleTimer(interval:)` 헬퍼로 상태 전환 시 timer를 invalidate 후 새 간격으로 재예약. `RunLoop.main.add(_:forMode: .common)` 명시 등록으로 모달/스크롤 중에도 폴링 보장(QA-004 부수적 개선).
- `PermissionViewModel.swift` (qa-014): granted=true→false revoke 전환 시 `tracker?.stop()`을 명시적으로 호출하도록 보강. 또한 granted/revoked 양쪽 모두에 `onGranted` / `onRevoked` 콜백 hook을 추가하여 AppDelegate가 권한 변화에 따른 UX 액션(Preferences 자동 표시 등)을 위임받을 수 있게 분리. `poll()` 내부 isGranted 갱신 + tracker start/stop은 `DispatchQueue.main.async`로 메인 스레드 보장(QA-004 정식 수정).
- `PreferencesStore.swift` (review-major-3): `config.didSet` 시 매번 동기 `JSONEncoder().encode` + `UserDefaults.set` 호출이 ColorPicker 드래그 중 60fps로 발생하던 결함 수정. 영속화 경로만 `DispatchWorkItem` 기반 150ms 디바운스 적용(`scheduleSave`), publisher emit은 즉시 수행하여 OverlayRenderer 색상 반영의 응답성은 그대로 유지. 기존 계약("update(_:)는 영속화 후 emit")을 사실상 "emit 즉시 + 영속화 디바운스"로 완화 — 사용자 가시 동작에는 차이 없으며 디스크 write 빈도는 드래그 1회당 1회로 수렴. AppDelegate `applicationWillTerminate`에서 호출 가능한 `flush()` 공개 메서드를 추가하여 종료 시 미저장 변경분 즉시 반영.

## 2026-04-25 - 기능 추가: 외곽선 길이/투명도 조절

- `02_interfaces.swift`: `OverlayConfig`에 `lengthRatio: CGFloat` (0.0...1.0) 와 `opacity: CGFloat` (0.0...1.0) 두 필드 추가. 기본값 둘 다 1.0으로 설정하여 기존 동작 유지.
  - init에서 `max(0, min(1, ...))`로 범위 클램프.
  - `init(from decoder:)` 커스텀 구현으로 v1 영속화 데이터(두 필드 누락)와 후방 호환 보장 — `decodeIfPresent`로 빠진 키는 1.0 default 적용. UserDefaults 키 `OverlayConfig.v1` 그대로 유지하여 기존 사용자 설정 보존.
- `OverlayContentView.swift`: `update(config:language:)`에 길이/투명도 적용. lengthRatio로 가로변(top/bottom)은 width를 비율 축소 후 가운데 정렬(`hOff = (b.width - hLen)/2`), 세로변(leading/trailing)은 height를 비율 축소 후 가운데 정렬. opacity는 4개 layer 모두에 `layer.opacity = Float(alpha)`로 적용. CATransaction 묵시 애니메이션 차단의 이미 등록된 `"opacity": NSNull()` 액션이 그대로 유효.
- `PreferencesView.swift`: `lengthSection`, `opacitySection` 두 섹션을 `thicknessSection` 다음에 추가. 둘 다 `0.05...1.0` 범위 Slider(완전 invisible 방지를 위한 5% 하한). 표시는 `Int((value*100).rounded())%` 백분율. 기존 thicknessSection의 라벨 폭을 36→48pt로 확장하여 길이/투명도 라벨과 시각적 정렬.

## 2026-04-25 - 버그 수정: Mission Control 진입 시 외곽선 잔존

- 증상: Mission Control 활성화 시 외곽선이 화면 전체 위에 남아있어 시각적 결함 발생 (사용자 스크린샷 보고).
- 근본 원인: `OverlayWindow.collectionBehavior`에 포함된 `.stationary`가 정확히 "Mission Control 진입 시 윈도우를 화면에 정지된 상태로 유지"하는 동작을 명시한다. 즉 의도와 정확히 반대로 동작하던 옵션.
- 수정: `OverlayWindow.swift`의 `collectionBehavior`에서 `.stationary`를 제거하고 `.transient`로 교체. `.transient`는 시스템에 "이 윈도우는 일시적이므로 Exposé / Mission Control 진입 시 무시하라"고 알림. 부수적으로 `.ignoresCycle` 추가하여 Cmd+`(또는 ⌘~) 윈도우 순환에서도 외곽선 윈도우가 제외되게 함.
- 보존된 동작: `.canJoinAllSpaces`(모든 스페이스에서 표시)와 `.fullScreenAuxiliary`(전체화면 앱 위에서도 표시)는 그대로 유지.

## 2026-04-25 - 기능 개선: 윈도우 이동/리사이즈 중 외곽선 일시 숨김 (settle on stop)

- 사용자 요청: 앱 윈도우의 크기/위치가 변경되는 중에는 외곽선을 표시하지 않고, 움직임이 끝난 후에만 다시 표시.
- 수정 위치: `FocusedWindowTracker.swift`
- 추가된 인프라:
  - `settleWorkItem: DispatchWorkItem?` 인스턴스 변수 — 디바운스 워크 아이템 핸들.
  - `static let settleDelay: TimeInterval = 0.18` — 마지막 이동/리사이즈 알림 이후 정착 판정 지연. 너무 짧으면 깜빡임, 너무 길면 정착 후 외곽선이 늦게 다시 나타나는 체감 → 180ms 균형값.
  - `scheduleSettle(window:app:)` / `cancelSettle()` 헬퍼.
- 동작 변경:
  - `kAXMovedNotification` / `kAXResizedNotification` 도착 시 기존에는 즉시 `emit(window:app:)` 으로 새 frame을 publish했으나, 이제는:
    1. 즉시 `subject.send(nil)` → OverlayRenderer가 외곽선을 즉시 hide.
    2. `settleWorkItem`을 cancel 후 새 work를 `DispatchQueue.main.asyncAfter(180ms)`로 예약.
    3. 180ms 동안 추가 Move/Resize 알림이 도착하지 않으면 work가 실행되어 최종 frame을 emit → 외곽선 재표시.
    4. 추가 알림이 도착하면 work를 cancel하고 새로 예약(드래그 중에는 hidden 유지).
  - `kAXFocusedWindowChangedNotification` / `kAXUIElementDestroyedNotification` 등 영구적 상태 변화 알림 시 `cancelSettle()`을 먼저 호출하여 잔류 work가 잘못된 frame을 publish하지 않도록 함.
  - `detachObserver()` / `stop()` 진입 시점에도 `cancelSettle()` 호출. 앱 전환 직후 이전 앱 컨텍스트로 fire되어 외곽선이 잘못된 위치에 잠시 보이는 경계 조건 차단.
- 멱등성: `settleWorkItem` 클로저는 `[weak self]` + `isStarted` 가드로 안전하게 종료된다.

## 2026-04-25 - 권한 인식 개선: AX trust polling 강화 + 트러블슈팅 안내

- 사용자 보고: 시스템 설정에서 권한을 허용했는데도 외곽선이 표시되지 않음.
- 근본 원인 분석 (가능성 순):
  1. **코드 사인 mismatch** — ad-hoc/매번 다른 사인 빌드는 시스템 설정의 기존 권한 항목과 새 binary가 매치되지 않아 토글 ON이어도 TCC가 거부. 이게 가장 흔한 원인.
  2. **`AXIsProcessTrusted()` 캐시** — 일부 macOS 환경에서 권한 토글 직후 캐시된 false를 반환하다 다음 query에서 갱신.
  3. polling 응답성 자체는 이미 1.5초로 충분 (3번이 아님을 확인).
- 코드 수정:
  - `AXPermission.swift`: `status()`를 `AXIsProcessTrusted()` 단순 호출에서 `AXIsProcessTrustedWithOptions(empty options)` 호출로 교체. options dict는 비어있으나(prompt: false), 일부 환경에서 캐시 회피·즉각 갱신 효과가 보고됨. 권한 토글 직후 polling 응답성 향상.
  - `PreferencesView.swift`: 권한 미부여 섹션 하단에 `DisclosureGroup` "권한을 허용했는데 동작하지 않나요?" 추가. 펼치면 3단계 절차 안내 — (1) 시스템 설정 손쉬운 사용에서 항목 '−'로 제거, (2) 앱 재시작, (3) 다시 허용. 코드 사인 mismatch 케이스의 자체 해결 경로 제공.
- 동작 변화: 권한 부여 즉시 외곽선이 동작 시작하지 않는 경우라도 사용자가 UI 안내만으로 자체 복구 가능.

## 2026-04-25 - 기능 추가: 로그인 시 자동 실행 옵션

- 사용자 요청: 로그인 시 자동 실행 토글 추가.
- 구현 방식: macOS 13+의 `ServiceManagement.SMAppService.mainApp` API 사용. legacy `SMLoginItemSetEnabled`(deprecated) 미사용.
- 신규 파일 `LaunchAtLogin.swift`:
  - `LaunchAtLoginController: ObservableObject` 도입. `@MainActor`로 격리.
  - `@Published var isEnabled: Bool` — SMAppService.mainApp.status를 읽어 갱신. set은 private이고 외부는 setEnabled(_:)로만 변경.
  - `@Published var disabledReason: String?` — `.requiresApproval`(시스템 설정 별도 승인 필요), `.notFound`(번들 위치 변경 후 재등록 필요) 같은 상태에 대한 사용자 안내 메시지.
  - `setEnabled(_:)`은 `SMAppService.mainApp.register()`/`unregister()` 호출 후 `refresh()`로 실제 시스템 상태를 다시 읽어 UI 일관성 보장.
  - `refresh()`는 외부에서도 호출 가능 — PreferencesView가 onAppear에서 호출하여 사용자가 시스템 설정에서 직접 변경한 경우와도 동기화.
- `PreferencesView.swift`:
  - `@StateObject private var launchAtLogin = LaunchAtLoginController()` 도입.
  - 외곽선 표시 활성화 토글 바로 아래에 `launchAtLoginSection` 신설. SwiftUI Toggle + `disabledReason`이 있으면 주황색 작은 안내 텍스트.
  - `body.onAppear { launchAtLogin.refresh() }` — Preferences 윈도우가 활성화될 때마다 시스템 상태와 재동기화.
- Info.plist / project.yml 변경 불필요. `SMAppService.mainApp`은 메인 번들 자체를 로그인 항목으로 등록하므로 별도 LaunchAgent plist를 번들링하지 않아도 된다. `ServiceManagement` 프레임워크는 표준이라 자동 링크.
- 알려진 제약:
  - ad-hoc/자주 옮긴 빌드는 `.notFound` 또는 `.requiresApproval` 상태가 될 수 있음 → UI의 disabledReason 메시지가 사용자에게 절차 안내.
  - 안정 동작을 위해 앱을 `/Applications`로 이동한 뒤 토글 권장(BUILD.md 안내 사항과 일치).

## 2026-04-25 - 권한 자가 진단 + 자가 복구 도구

- 사용자 보고: AXPermission 캐시 회피 패치(AXIsProcessTrustedWithOptions) 이후에도 권한 인식 실패 지속. 재설치/재허용/비허용 반복해도 외곽선 미작동, Preferences는 계속 "권한 허용 필요" 표시.
- 추정 근본 원인: ad-hoc 빌드의 binary hash가 매번 달라져 TCC 데이터베이스 항목과 실제 binary가 mismatch. 반복된 ON/OFF로 TCC가 inconsistent 상태가 된 것으로 보임.
- 추가 도구:
  - `AXPermission.swift`:
    - `Diagnostics` struct + `diagnostics()` 메서드 추가 — bundle path, bundle ID, `AXIsProcessTrusted()` raw 결과, `AXIsProcessTrustedWithOptions(prompt:false)` 결과를 한 번에 조회.
    - `resetTCC()` 메서드 — `/usr/bin/tccutil reset Accessibility <bundle-id>`를 Process로 실행. 자기 앱 항목에 대해서는 admin 권한 없이 동작.
  - 신규 `AppRestart.swift`:
    - `AppRestart.relaunch(delay:)` — `NSWorkspace.openApplication(at:configuration:)` (createsNewApplicationInstance=true)로 새 인스턴스 launch 후 0.4초 뒤 `NSApp.terminate(nil)`. tccutil reset 직후 호출하면 TCC가 새 프로세스에 대해 trust를 다시 평가.
  - `PreferencesView.swift` 트러블슈팅 섹션 강화:
    - "권한 캐시 초기화 후 재시작" 버튼 추가 → 한 번 클릭으로 `resetTCC()` + `AppRestart.relaunch()` 자동 실행.
    - 수동 절차 4단계 안내 + tccutil 명령어를 selectable 모노스페이스 텍스트로 표시.
    - 진단 정보 블록 — Bundle ID / 경로 / 두 가지 trust 호출 결과를 selectable 모노스페이스로 표시. 경로가 `/Applications/` 외부면 주황색 경고 ("⚠️ /Applications 외부에서 실행 중입니다. TCC 권한이 불안정할 수 있습니다.").
- 빌드 영향:
  - `AppRestart.swift` 신규 파일은 `./scripts/release.sh project` 재실행 시 XcodeGen이 자동으로 타깃에 포함.
  - 추가 framework 의존 없음 (AppKit + Foundation 표준).

## 2026-04-25 - GitHub Release 자동화

- 사용자 요청: GitHub에 release를 만드는 스크립트 + Actions로 DMG/PKG 빌드 후 release에 자동 등록.
- 신규 파일:
  - `scripts/github-release.sh` — 로컬 트리거. project.yml의 MARKETING_VERSION 또는 인자로 버전 결정, `--bump major|minor|patch` 옵션으로 자동 증가 + project.yml 갱신 + 커밋. git working tree clean / origin 동기화 / 태그 충돌 사전 검증. `git tag -a v$VERSION` + `git push origin $TAG`.
  - `.github/workflows/release.yml` — `on: push: tags: ['v*']` + `workflow_dispatch` 트리거. macos-14 runner. XcodeGen 설치 → (옵션) 코드사인 인증서 임시 keychain import → `./scripts/release.sh all` → (옵션) notarize → `gh release create --generate-notes` 또는 `gh release upload --clobber`. 종료 시 keychain 삭제(if: always()).
- 보안:
  - 코드사인 시크릿(`MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `DEVELOPER_ID_APPLICATION`, `DEVELOPER_ID_INSTALLER`)이 모두 설정된 경우에만 import. 미설정 시 unsigned ad-hoc 빌드로 release 게시(개인/테스트 용도).
  - Notarization 시크릿(`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_APP_PASSWORD`) 별도. 코드사인 + 모두 설정 시에만 동작.
  - 임시 keychain은 OpenSSL random 24바이트 패스워드, lock timeout 21600s (6시간), `set-key-partition-list`로 `apple-tool:,apple:,codesign:` 파티션 권한 부여.
- README에 "Release (GitHub Actions 자동화)" 섹션 추가. secrets 설정 표 + 수동 재빌드(`gh workflow run`) 안내 포함.

## 2026-10-19 - 포커스 표시 전용 모드 (한/영 상태 무시)

- `OverlayConfig`에 `ignoresInputSource: Bool`(기본 false), `focusColor: ColorData`(기본 green) 추가. 구버전 저장 데이터는 `decodeIfPresent`로 기본값 폴백.
- `OverlayContentView.color(for:config:)` — `ignoresInputSource`면 입력 언어와 무관하게 `focusColor` 반환.
- `PreferencesView` 색상 섹션 — "한/영 상태 무시" 토글 추가. 켜면 단일 "외곽선 색상" 피커, 끄면 기존 한글/영문 피커 표시.
