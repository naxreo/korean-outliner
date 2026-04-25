# QA Report — Phase 4 재검증

- **검증 시점**: 2026-04-25 (round 2)
- **검증 범위**: 이전 보고서(`qa_report.md` / `review_report.md`)의 critical 2 + major 8 + 추가 minor 2 = 총 10건
- **검증 방식**: 변경 파일 직접 read + grep 교차 검증. SDK 부재로 빌드/실행은 미수행 (정적 검증).
- **변경 이력 출처**: `_workspace/00_changelog.md` (2026-04-25 Phase 4 4건의 dev 수정 블록)

---

## 결함 해소 확인

| ID | 상태 | 위치 | 메모 |
|----|------|------|------|
| review-critical-1 / qa-major-1 | resolved | AppDelegate.swift:80-90 | `cancellables: Set<AnyCancellable>` 신설(L44). `inputMonitor.publisher` → `receive(on: .main).sink { menuBar.setLanguage($0) }.store(in:)` 및 `preferencesStore.publisher.map(\.isEnabled).removeDuplicates().receive(on: .main).sink { menuBar.setEnabled($0) }.store(in:)` 두 구독 모두 등록. `[weak menuBar]` 캡처로 retain cycle 회피. |
| review-critical-2 | resolved | FocusedWindowTracker.swift:308-311, 331-334 | `focusedWindow(of:)`는 `CFGetTypeID(raw as CFTypeRef) == AXUIElementGetTypeID()` 가드 추가. `frame(of:)`는 posRaw/sizeRaw 모두 `AXValueGetTypeID()` 비교 가드 추가. 가드 실패 시 nil 반환 → emit이 nil로 이어져 외곽선 즉시 숨김(L353-361). 강제 캐스팅 패턴은 가드 직후라 안전. |
| review-major-1 / qa-major-2 | resolved | AppDelegate.swift:46-110, 32 | `applicationDidFinishLaunching`에서 `PermissionViewModel(tracker:)`을 즉시 인스턴스화하여 `permissionViewModel` 프로퍼티에 보유(L95-103). AppDelegate가 `PreferencesPresenting` 채택(L32), `show()` / `showAccessibilityPrompt()` 메서드 구현(L121-147). 권한이 `.granted`가 아니면 `applicationDidFinishLaunching` 마지막에서 자동으로 `showAccessibilityPrompt()` 호출(L107-109). 기존 `showPreferences()`는 별칭으로 호환 유지(L151-153). |
| review-major-2 | resolved | PermissionViewModel.swift:60-71, 84-90 | 폴링 간격 이중화: `fastInterval = 1.5s` (L30), `slowInterval = 30.0s` (L32). granted 전환 시 `scheduleTimer(interval: slowInterval)` 호출하여 invalidate + 재예약(L84). revoke 시 `fastInterval`로 복귀(L90). `RunLoop.main.add(t, forMode: .common)` 명시 등록(L69)으로 모달 중에도 폴링 보장. |
| review-major-3 | resolved | PreferencesStore.swift:33-41, 81-88, 63-67 | setter는 `subject.send(newValue)`를 즉시 수행(L38) 후 `scheduleSave(newValue)`로 영속화 디바운스(L39). `scheduleSave`는 150ms `DispatchWorkItem`을 cancel & 재예약(L81-88). 종료 직전 미저장 변경은 `flush()` 공개 메서드로 즉시 저장(L63-67). AppDelegate.applicationWillTerminate에서 호출(L118). |
| review-major-4 | resolved | OverlayRenderer.swift:72-78 | `apply(language:)`가 더 이상 `controller.refresh(...)` 분기를 호출하지 않음. 캐시 갱신 후 `render()` 단일 진입점만 호출. `apply(frame:)` / `apply(config:)`도 동일 패턴(L66-84) → 호출 순서 무관 멱등성 만족. |
| review-major-5 / qa-011 | resolved | InputSourceMonitor.swift:74-108 | `classify(sourceID:languages:)`로 시그니처 변경(L88). 1순위는 `com.apple.inputmethod.Korean` + `com.apple.keylayout.Korean` prefix(L90-92, `contains("Korean")` 제거). 2순위는 `kTISPropertyInputSourceLanguages` BCP-47 primary 언어 — `ko`/`ko-`/`ko_` → `.korean`, `en`/`en-`/`en_` → `.english`(L97-103). Dvorak/Colemak 등 영문 키보드도 `.english`로 정확히 분류. `languages(of:)`는 Get-규칙(`takeUnretainedValue`) 준수(L74-80). |
| review-major-6 | resolved | FocusedWindowTracker.swift:138-153 | `AXObserverCreate` 실패 시 `NSLog`로 pid + AXError rawValue만 로깅(L143-147, 윈도우 타이틀 등 사용자 콘텐츠 일절 미로깅). 실패 직후 `activeApp = nil`, `activeAppElement = nil`로 클리어(L148-149) → 다음 `didActivateApplicationNotification` 도착 시 `attach(to:)` 진입부의 `detachObserver()`가 깨끗한 상태에서 새 옵저버 생성을 재시도. publisher는 nil emit으로 외곽선 즉시 숨김(L150-151). |
| qa-major-3 | resolved | AppDelegate.swift:114-119 | `applicationWillTerminate(_:)` 신설. 순서: `cancellables.removeAll()` → `inputMonitor?.stop()` → `windowTracker?.stop()` → `preferencesStore?.flush()`. NSWorkspace/AX 잔여 콜백이 dangling self 접근하기 전 명시 정리. |
| qa-014 | resolved | PermissionViewModel.swift:73-93 | `poll()` 내부 `granted != self.isGranted` 가드 후 분기에서, granted=true→false revoke 케이스에 `self.tracker?.stop()` + `self.onRevoked?()` 명시 호출(L85-90). 메인 스레드 `DispatchQueue.main.async` 래핑(L76)으로 tracker.stop() 호출 스레드 보장도 동시 충족(QA-004 부수 해소). |

---

## 새 결함 점검

### 1. cancellables 저장 누락 여부

- AppDelegate.swift: 신규 sink 2개 모두 `.store(in: &cancellables)` 적용(L83, L90). Set<AnyCancellable>이 인스턴스 멤버(L44)로 보관되어 AppDelegate 라이프타임과 일치. 누락 없음.
- OverlayRenderer.swift: 기존 3개 sink 모두 `.store(in: &cancellables)` 유지(L51, L56, L61). 누락 없음.
- PreferencesStore.swift: Combine sink 사용 안함(자체 publisher만 노출), 검사 대상 외.

### 2. weak self 캡처 누락 여부

- AppDelegate.swift L82, L89: `[weak menuBar]` 캡처 사용 — AppDelegate가 menuBar를 강한 참조로 보유(L39)하므로 sink 클로저가 menuBar를 직접 strong-capture하면 menuBar→cancellables→cancellable→closure→menuBar 순환은 발생하지 않으나(closure는 cancellables가 보관, menuBar와 직접 루프 없음), AppDelegate가 closure를 통해 menuBar를 잡는 형태 → AppDelegate→cancellables→closure→menuBar는 단방향이고 menuBar가 AppDelegate를 다시 잡지 않으므로 retain cycle은 없음. 그래도 `[weak menuBar]`로 명시 — 안전 보강. 메뉴바 nil이 되는 시나리오는 `applicationWillTerminate`에서 `cancellables.removeAll()` 직후이므로 race도 차단됨.
- AppDelegate.swift L72: `onShowPreferences` 클로저 `[weak self]` 적용. MenuBarController가 클로저를 강한 참조로 보유하고 AppDelegate가 menuBar를 보유하므로 self를 strong-capture하면 retain cycle. weak으로 차단됨.
- AppDelegate.swift L99-101: `pvm.onRevoked` 클로저에 `[weak self]` 적용. AppDelegate가 pvm을 보유 + pvm이 onRevoked 보유 → self를 strong-capture하면 cycle. weak으로 차단됨. `pvm.onGranted = { /* no-op */ }`는 캡처 없음(L98).
- PermissionViewModel.swift L65-67, L76-77: Timer 콜백·DispatchQueue.main.async 클로저 모두 `[weak self]` 적용. `private weak var tracker` 보유(L26)도 정확.
- PreferencesStore.swift L83-85: `DispatchWorkItem { [weak self] in self?.save(config) }` weak 적용. 디바운스가 self를 강하게 잡지 않음.
- OverlayRenderer.swift L50, L55, L60: 모든 sink가 `[weak self]` 적용.

retain cycle / 메모리 누수 누락 없음.

### 3. PreferencesStore 디바운스 — 마지막 변경 누락 가능성

- ColorPicker 드래그 종료 후 150ms 안에 앱이 종료되면 디바운스 work item이 취소·실행 누락될 수 있음. 그러나 AppDelegate.applicationWillTerminate가 `preferencesStore?.flush()`를 호출(L118)하므로 — `flush()`는 `saveDebouncer?.cancel()` + `save(subject.value)` 즉시 실행(L63-67). 종료 시 미저장 위험 차단됨.
- 단, 비정상 종료(SIGKILL/크래시)에는 flush 미호출 가능 — 일반적인 제약, minor 외 항목 아님.

### 4. AppDelegate가 PreferencesPresenting 채택 — retain cycle

- AppDelegate가 PreferencesPresenting을 self로 노출하지만, 외부 모듈(MenuBarController 등)에서 PreferencesPresenting 타입으로 AppDelegate를 보관하지 않음. MenuBarController는 `() -> Void` 클로저만 보유 + 클로저는 `[weak self]` 캡처. self → menuBar → closure → self의 잠재적 사이클을 weak로 끊었으므로 안전.
- `permissionViewModel.onRevoked = { [weak self] ... self?.showAccessibilityPrompt() }`도 weak self로 차단.

### 5. AXObserverCreate 실패 회복 후 다음 이벤트에서 attach 정상 동작

- 실패 시 `activeApp` / `activeAppElement` nil 클리어(L148-149). 다음 didActivateApplicationNotification → `attach(to:)` 진입 첫 줄 `detachObserver()`(L123)는 `axObserver`가 nil이라 if 블록을 스킵하고 부수 nil 클리어만 수행(L237-240). 그 후 새 `AXObserverCreate` 호출. 회복 경로 정상.

### 6. PermissionViewModel `scheduleTimer` 재예약 시 중복 발사 가능성

- `scheduleTimer(interval:)` 첫 줄 `timer?.invalidate()` 후 새 Timer 생성(L61-70). RunLoop.main에 추가. 이전 Timer가 invalidate되면 RunLoop가 다음 fire 사이클에 제거하므로 중복 발사 위험 없음.

### 7. PermissionViewModel.poll() — DispatchQueue.main.async 안의 중첩 시점

- Timer 콜백은 main RunLoop common 모드에서 호출됨. `poll()` 진입은 이미 메인 — 그 안에서 다시 `DispatchQueue.main.async`로 hop하는 것은 비용은 미미하지만 동기 호출이 아니라 한 번 더 next-runloop-tick으로 미룸. AXPermission.status() 호출이 메인 외에서 일어날 가능성은 없으므로 굳이 async일 필요는 없으나, 의도(scheduleTimer 재호출이 현재 timer fire 도중에 발생하지 않도록 분리)가 합리적이며 동작상 문제는 없음. 결함 없음.

### 8. classify 정합성 — 폴백 분기

- `kTISPropertyInputSourceLanguages` 반환이 빈 배열이고 prefix 매칭도 실패하면 `.other(id: sourceID)` 폴백(L107). 기존 화이트리스트(ABC/US/British/...) 의존성 제거됨 — 예전엔 `com.apple.keylayout.British` 등을 hard-code 확인했는데 새 분류는 BCP-47 `en` prefix로 일반화되어 모두 자동 흡수. 누락 없음.

### 9. AXObserverCreate 실패 로깅의 프라이버시

- pid는 sandbox 외부에서도 보이는 프로세스 식별자, AXError rawValue는 정수. 둘 다 사용자 콘텐츠 아님. NSLog가 시스템 콘솔에 기록됨 — minor한 프라이버시 보강은 OSLog 전환이지만 review_report의 minor 항목과 동일 범주, 본 round 검증 대상 아님.

신규 회귀(regression) 결함 없음.

---

## 핵심 지표

| 카테고리 | 개수 |
|---------|------|
| resolved | 10 |
| partial | 0 |
| unresolved | 0 |
| regression | 0 |

---

## 비고

- 정적 검증 한계: SDK 환경 부재로 실기기 빌드/실행/시각 확인 미수행. `manual_test_scenarios.md`의 시나리오 #1(첫 실행 권한 안내), #9(권한 revoke 시 외곽선 사라짐), #10(Quit 시 외곽선 즉시 사라짐), 추가로 #N(ColorPicker 드래그 응답성)을 실기기에서 직접 확인 권장.
- 이전 round의 minor 5건(QA-012/013/015 등)은 본 재검증 범위 외이며, qa-013은 changelog에서 "이중 채널 구독 미채택"으로 의식적 의사결정을 명시함. qa-012는 이번에 부수적으로 함께 해소됨(FocusedWindowTracker.screenContaining의 primary 도출이 OverlayWindowController와 동일한 3단 fallback으로 통일).
- review_report의 추가 확인 필요 항목(AXObserverCreate 실패 회복)도 review-major-6 수정에 포함되어 함께 해소.
