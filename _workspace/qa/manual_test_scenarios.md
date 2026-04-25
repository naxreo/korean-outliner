# Manual Test Scenarios — macos-korean-outliner

실기기에서 직접 수행할 10개 시나리오. 각 케이스는 **사전 조건 → 단계 → 기대 결과 → 실패 시 점검 포인트** 형식. swift-qa-integration 스킬에 정의된 표준 시나리오를 그대로 채택한다.

> 사전 공통 준비
> - macOS 13.0 이상에서 빌드한 앱 실행
> - `defaults delete com.naxreo.koreanoutliner` 으로 기존 설정 초기화 (선택)
> - 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 본 앱 권한 토글 가능 상태

---

## 시나리오 1: 첫 실행 시나리오 (Onboarding)

**사전 조건**: 앱 첫 실행, AX 권한 미부여

**단계**:
1. 앱 빌드 후 실행
2. (기대) Preferences 윈도우 자동 표시 + 권한 안내 섹션 강조
3. "권한 허용" 버튼 클릭 → 시스템 다이얼로그 노출
4. (또는) "시스템 설정 열기" 클릭 → 손쉬운 사용 패널 직링크
5. 시스템 설정에서 본 앱 토글 ON
6. 1.5초 이내 외곽선이 현재 포커스된 윈도우에 표시

**기대 결과**:
- 메뉴바에 `rectangle.dashed` 아이콘 표시
- Preferences 권한 섹션이 녹색 체크마크 + "Accessibility 권한 허용됨"으로 전환
- 외곽선이 영문 입력 색상(빨강)으로 표시

**실패 시 점검**:
- Preferences 자동 표시 안 됨 → **QA-002** (AppDelegate에 자동 트리거 없음)
- 권한 부여 후 외곽선 미표시 → PermissionViewModel.poll의 tracker?.start() 동작 확인
- 콘솔 "AccessibilityCheck failed" 반복 → 권한 다이얼로그가 다른 번들 ID로 등록되었을 가능성

---

## 시나리오 2: 한/영 전환

**사전 조건**: AX 권한 부여됨, 외곽선 표시 중

**단계**:
1. 텍스트 에디터(예: TextEdit) 열기
2. 한글 입력 상태로 전환 (Caps Lock 또는 한/영 키)
3. 외곽선 색상 즉시 변경 관찰 (영문 빨강 → 한글 파랑)
4. 다시 영문으로 전환
5. 외곽선 색상이 즉시 빨강으로 복귀

**기대 결과**:
- 색상 전환 지연 100ms 이내
- 메뉴바 아이콘 툴팁이 "Korean Outliner — 한글" / "— English"로 갱신

**실패 시 점검**:
- 색상이 안 바뀜 → InputSourceMonitor가 알림을 받지 못함. `kTISNotifySelectedKeyboardInputSourceChanged` 외에 `NotificationCenter.default`로도 emit되는지 확인 → **QA-013**
- 툴팁이 갱신 안 됨 → **QA-001** (AppDelegate가 menuBar.setLanguage를 호출하지 않음)
- 사용자 정의 입력기에서 한글로 잘못 분류 → **QA-011** (substring 매칭 위양성)

---

## 시나리오 3: 앱 전환 (Cmd+Tab)

**사전 조건**: 외곽선 표시 중

**단계**:
1. Safari 열기 → 외곽선이 Safari 윈도우에 표시
2. Cmd+Tab → Mail로 전환 → 외곽선이 Mail 윈도우로 이동
3. Cmd+Tab → Finder로 전환 → 외곽선이 Finder 윈도우로 이동
4. 빠르게 5회 이상 Cmd+Tab 반복

**기대 결과**:
- 외곽선이 매번 새 윈도우 frame으로 즉시 이동
- 잔상 없음, 콘솔에 AX 에러 폭증 없음

**실패 시 점검**:
- 외곽선이 이전 위치에 잔상 → AXObserver 누수 가능. `attach(to:)`의 `detachObserver()` 호출 확인 (현재 PASS)
- 콘솔에 "AXObserverAddNotification: AXError -25204" 반복 → 권한 또는 sandbox 문제
- 메뉴바 아이콘 색상이 자주 깜빡임 → 정상(앱마다 사파리/메일 등에서 한/영 상태 다를 수 있음)

---

## 시나리오 4: 윈도우 리사이즈 / 이동

**사전 조건**: 외곽선 표시 중

**단계**:
1. Safari 윈도우의 모서리 핸들로 크기 변경 (드래그 200ms 단위)
2. 타이틀바 드래그로 윈도우 이동
3. 다른 모서리, 다른 변 핸들도 시도

**기대 결과**:
- 외곽선이 60Hz 수준으로 자연스럽게 따라감
- 묵시 애니메이션 잔상 없음 (`CATransaction.setDisableActions`)
- CPU 사용률 안정적

**실패 시 점검**:
- 외곽선이 한 박자 늦음 → 정상 (kAXMovedNotification 콜백 주기 한계)
- 잔상이 0.25초 보임 → CALayer actions 비활성 누락. OverlayContentView.commonInit의 `disabledActions` 적용 확인
- 외곽선이 윈도우 외부에 그려짐 → 좌표 변환 버그. **QA-012** 의심

---

## 시나리오 5: 전체화면 전환

**사전 조건**: 외곽선 표시 중

**단계**:
1. Safari 또는 비디오 플레이어를 풀스크린으로 전환 (초록 버튼)
2. 풀스크린 상태에서 외곽선 확인
3. ESC로 풀스크린 해제
4. Mission Control 제스처로 다른 앱과 동시 풀스크린 분할

**기대 결과**:
- 풀스크린 전환 후에도 외곽선 표시 유지 (`.fullScreenAuxiliary` collectionBehavior)
- 메뉴바가 자동 숨김되어도 외곽선은 사라지지 않음

**실패 시 점검**:
- 풀스크린에서 외곽선 사라짐 → `OverlayWindow.collectionBehavior` 확인. 현재는 `.canJoinAllSpaces, .stationary, .fullScreenAuxiliary` PASS
- 외곽선이 메뉴바 위에 그려져 메뉴 클릭 차단 → `ignoresMouseEvents = true` 확인 (현재 PASS)

---

## 시나리오 6: 멀티 스페이스 (Mission Control)

**사전 조건**: 외곽선 표시 중

**단계**:
1. 새 스페이스 생성 (Mission Control → 우상단 +)
2. Cmd+Ctrl+→ 또는 ←로 스페이스 이동
3. 각 스페이스마다 다른 앱을 포커스
4. 한/영 전환과 함께 스페이스 이동 반복

**기대 결과**:
- 외곽선이 새 스페이스로 따라감 (`.canJoinAllSpaces`)
- 한/영 색상도 즉시 반영

**실패 시 점검**:
- 외곽선이 이전 스페이스에 남음 → `.canJoinAllSpaces` 누락. 현재 PASS
- 새 스페이스에서 외곽선 안 그려짐 → workspace observer가 `didActivateApplicationNotification`을 받지 못할 수 있음. 콘솔 로그 확인

---

## 시나리오 7: 멀티 모니터

**사전 조건**: 외부 모니터 연결, 외곽선 표시 중

**단계**:
1. 메인 모니터 위쪽에 보조 모니터 배치 (시스템 설정 → 디스플레이 → 정렬)
2. 보조 모니터의 윈도우 클릭 → 외곽선이 보조 모니터에 표시
3. 좌측 배치, 우측 배치, 아래 배치도 각각 시도
4. 두 모니터에 걸친 윈도우(절반씩 걸침) 클릭

**기대 결과**:
- 외곽선이 항상 윈도우가 더 많이 걸친 모니터에 그려짐 (`screenContaining`이 가장 큰 intersection 선택)
- 좌표 오프셋 없음 (위/아래/좌/우 모서리 정확)

**실패 시 점검**:
- 외곽선이 메인 모니터에 잘못 그려짐 → **QA-012** (Tracker와 Renderer의 primary 스크린 도출 비대칭)
- 외곽선이 살짝 위/아래로 이동 → primaryScreen.frame.maxY 계산 차이. Renderer는 `origin == .zero` 우선, Tracker는 `screens.first` 우선
- 보조 모니터에서 외곽선 크기 잘못됨 → AX 좌표는 글로벌이지만 NSScreen.frame은 각 스크린별 — 변환 식 재확인

---

## 시나리오 8: 설정 변경 즉시 반영

**사전 조건**: 외곽선 표시 중, Preferences 윈도우 열림

**단계**:
1. 두께 슬라이더를 1pt → 10pt로 천천히 드래그
2. 한글 색상을 보라색으로 변경 (한글 입력 상태에서)
3. "오른쪽" 토글 OFF → 우측 외곽선만 사라짐
4. 마스터 토글 OFF → 외곽선 전체 즉시 사라짐
5. 마스터 토글 ON → 외곽선 즉시 복귀
6. 앱 종료 후 재실행 → 모든 설정 복원 확인

**기대 결과**:
- 슬라이더 드래그와 동시에 외곽선 두께 변화 (지연 ≤16ms)
- 색상 변경 즉시 반영
- 마스터 토글 OFF 시 OverlayWindow 자체가 hide → CPU 사용률 ~0%
- 재실행 시 UserDefaults에서 OverlayConfig 복원

**실패 시 점검**:
- 슬라이더 끝에서야 반영 → Binding의 set이 dragging 중 호출되지 않음. PreferencesView의 Slider 구현 확인
- 색상이 계속 영문 색상으로 표시 → 현재 입력 언어 분류 확인 (한글 입력 상태에서만 한글 색이 적용됨)
- 마스터 토글 OFF 직후 외곽선 잔상 → render()의 isEnabled 가드와 OverlayContentView의 isHidden 이중 처리 확인 (현재 PASS)
- 재실행 시 기본값으로 리셋 → JSONDecoder 실패. 콘솔에 `[PreferencesStore] decode failed` 로그 확인

---

## 시나리오 9: 권한 Revoke 후 즉시 반영

**사전 조건**: 외곽선 표시 중, AX 권한 부여됨

**단계**:
1. 외곽선 표시 확인
2. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 본 앱 토글 OFF
3. (1.5초 이내) Preferences 윈도우 확인 → 권한 안내 상태로 전환
4. 외곽선 즉시 사라짐 확인
5. 다시 ON → 외곽선 복귀

**기대 결과**:
- Revoke 1.5초 이내 외곽선 사라짐, Preferences 안내 갱신
- 콘솔 에러 폭증 없음
- ON 복귀 시 자동으로 tracker.start() 재호출

**실패 시 점검**:
- 외곽선이 그대로 남음 → Tracker.stop() 미호출. **QA-014** (PermissionViewModel.poll이 revoke 방향에서 stop 안 부름)
- 콘솔에 AXError 폭증 → tracker가 isStarted=true 상태로 AX 호출 시도 중. **QA-014** 수정 후 재검
- ON 후 외곽선 안 돌아옴 → tracker.start()가 메인 스레드 외부에서 호출되었을 수 있음. **QA-004**

---

## 시나리오 10: 앱 종료 / 재시작

**사전 조건**: 외곽선 표시 중, 설정 일부 변경 후

**단계**:
1. Preferences에서 두께 7pt, 한글 색상 보라, sides=[top, leading, trailing, bottom] 설정
2. 메뉴바 → Quit (또는 Cmd+Q)
3. 외곽선 즉시 사라지는지 확인
4. 즉시 앱 재실행
5. 메뉴바 아이콘 다시 표시 + 외곽선이 직전 설정 그대로 그려짐 확인

**기대 결과**:
- Quit 직후 외곽선 사라짐 (← stop() 또는 deinit으로 OverlayWindow.orderOut)
- 재실행 시 UserDefaults에서 OverlayConfig.v1 복원
- 모든 설정값 동일

**실패 시 점검**:
- Quit 후 외곽선 0.5초 정도 잔상 → applicationWillTerminate 미구현. **QA-003**
- 재실행 시 기본값 → save() 호출 누락. PreferencesStore.save 호출 경로 확인 (현재 setter에서 호출 PASS)
- 종료 시점 콘솔에 "AXObserver: callback fired on dealloced object" → AX 콜백이 deinit 도중 발화. **QA-003** 수정 시 해결

---

## 회귀 테스트 메트릭

각 시나리오마다 다음을 기록:

| 시나리오 | 통과/실패 | 소요 시간 | 콘솔 에러 수 | 비고 |
|---------|----------|---------|------------|------|
| 1. Onboarding | | | | |
| 2. 한/영 전환 | | | | |
| 3. 앱 전환 | | | | |
| 4. 리사이즈/이동 | | | | |
| 5. 전체화면 | | | | |
| 6. 멀티 스페이스 | | | | |
| 7. 멀티 모니터 | | | | |
| 8. 설정 변경 | | | | |
| 9. 권한 revoke | | | | |
| 10. 종료/재시작 | | | | |

릴리스 게이트: **시나리오 1~4, 8, 10이 100% PASS, 나머지는 80% 이상**일 때 정식 릴리스 가능.
