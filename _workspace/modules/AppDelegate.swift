//
//  AppDelegate.swift
//  macos-korean-outliner — 앱 진입점 + 전 모듈 조립
//
//  - SwiftUI App 프로토콜 + NSApplicationDelegateAdaptor 패턴
//  - applicationDidFinishLaunching에서:
//      PreferencesStore → InputSourceMonitor → FocusedWindowTracker → OverlayRenderer
//      → MenuBarController → PermissionViewModel 순으로 인스턴스화 후 입력/윈도우 모니터 시작
//  - LSUIElement = YES (Info.plist) 가정. Settings { EmptyView() }는 SwiftUI 기본 메뉴 억제용
//    플레이스홀더이며 실제 Preferences 윈도우는 NSWindow + NSHostingController로 직접 띄움.
//
//  Phase 4 결함 수정 반영:
//   - review-critical-1: monitor.publisher / store.publisher → menuBar setLanguage/setEnabled 구독
//   - review-major-1 / qa-major-2: PermissionViewModel을 앱 라이프타임으로 격상 + 권한 미부여 시
//     자동 Preferences 표시 + PreferencesPresenting 채택
//   - qa-major-3: applicationWillTerminate에서 명시적 stop + cancellables 해제
//

import AppKit
import Combine
import SwiftUI

@main
struct KoreanOutlinerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, PreferencesPresenting {

    // 모든 모듈은 강한 참조로 보유 — 특히 NSStatusItem을 가진 MenuBarController는 필수.
    private var preferencesStore: PreferencesStore!
    private var inputMonitor: InputSourceMonitor!
    private var windowTracker: FocusedWindowTracker!
    private var renderer: OverlayRenderer!
    private var menuBar: MenuBarController!
    private var permissionViewModel: PermissionViewModel!
    private var preferencesWindow: NSWindow?

    /// MenuBarController publisher 구독 + 기타 Combine 구독 보관.
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = PreferencesStore()
        let monitor = InputSourceMonitor()
        let tracker = FocusedWindowTracker()
        let renderer = OverlayRenderer(
            inputMonitor: monitor,
            windowTracker: tracker,
            preferences: store
        )

        self.preferencesStore = store
        self.inputMonitor = monitor
        self.windowTracker = tracker
        self.renderer = renderer

        // 입력 소스 모니터링은 권한 무관 — 즉시 시작.
        monitor.start()

        // 윈도우 추적은 Accessibility 권한이 부여된 경우에만 시작.
        // 미부여 시 PermissionViewModel이 폴링하다가 부여 시점에 start() 호출.
        if tracker.permissionStatus == .granted {
            tracker.start()
        }

        // 메뉴바 진입점.
        let menuBar = MenuBarController(
            onShowPreferences: { [weak self] in self?.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        self.menuBar = menuBar

        // review-critical-1: MenuBarController는 publisher 구독 없이는 setLanguage/setEnabled가
        // 호출되지 않아 메뉴바 아이콘/툴팁이 한/영·마스터 토글에 반응하지 않는다.
        // AppDelegate가 두 publisher를 sink하여 메인 스레드에서 setter를 트리거.
        monitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak menuBar] lang in menuBar?.setLanguage(lang) }
            .store(in: &cancellables)

        store.publisher
            .map(\.isEnabled)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak menuBar] enabled in menuBar?.setEnabled(enabled) }
            .store(in: &cancellables)

        // review-major-1: PermissionViewModel을 앱 라이프타임으로 격상.
        // Preferences를 한 번도 열지 않은 채 시스템 설정에서 권한을 허용하는 first-run
        // 시나리오에서도 폴링이 가동되어 tracker.start()가 자동 호출된다.
        let pvm = PermissionViewModel(tracker: tracker)
        // 권한 부여 시점에 자동으로 Preferences 창을 닫지는 않는다(사용자가 다른 설정도
        // 함께 보고 있을 수 있음). 다만 향후 정책 변경 여지를 위해 콜백 hook은 유지.
        pvm.onGranted = { /* no-op: tracker.start()는 PermissionViewModel이 직접 처리 */ }
        pvm.onRevoked = { [weak self] in
            // revoke 시 사용자가 즉시 인지할 수 있도록 Preferences 자동 노출.
            self?.showAccessibilityPrompt()
        }
        self.permissionViewModel = pvm

        // qa-major-2: 첫 실행 시 권한이 .denied/.notDetermined이면 Preferences를 자동 표시하여
        // 권한 안내 섹션을 강조. swift-qa-integration 시나리오 #1 충족.
        if tracker.permissionStatus != .granted {
            showAccessibilityPrompt()
        }
    }

    // qa-major-3: 종료 시 잔여 AX/NSWorkspace 옵저버 콜백이 dangling self에 접근하지 않도록
    // 명시적으로 stop() 호출 + cancellables 해제 + 미저장 설정 flush.
    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
        inputMonitor?.stop()
        windowTracker?.stop()
        preferencesStore?.flush()
    }

    // MARK: - PreferencesPresenting

    /// Preferences 윈도우는 1회 생성 후 캐시 (멀티 인스턴스/메모리 누수 방지).
    func show() {
        if preferencesWindow == nil {
            let view = PreferencesView()
                .environmentObject(preferencesStore)
                .environmentObject(permissionViewModel)

            let host = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: host)
            win.title = "Korean Outliner — Preferences"
            win.styleMask = [.titled, .closable, .resizable]
            win.setContentSize(NSSize(width: 420, height: 420))
            win.center()
            win.isReleasedWhenClosed = false
            preferencesWindow = win
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// AX 권한 안내 강조 표시 — 현재는 일반 show()와 동일하게 Preferences를 띄운다.
    /// PreferencesView 최상단 권한 섹션이 자동으로 미부여 상태를 노출하므로 별도 강조 UI는 불필요.
    func showAccessibilityPrompt() {
        show()
    }

    /// MenuBarController에서 호출하던 기존 진입점 호환용 별칭.
    /// (메뉴바 "Preferences..." 메뉴 클릭 시 호출됨)
    func showPreferences() {
        show()
    }
}
