//
//  OverlayRenderer.swift
//  macos-korean-outliner — `OverlayRendering` 구현체
//
//  AppCoordinator가 apply(...)로 상태를 주입할 수도 있고, 본 클래스가 직접
//  Input/Window/Preferences publisher를 구독할 수도 있다(편의 생성자 제공).
//

import AppKit
import Combine
import QuartzCore

public final class OverlayRenderer: OverlayRendering {

    private let controller = OverlayWindowController()

    // 마지막 상태 캐시 — apply 순서에 무관하게 일관된 화면을 보장.
    private var currentFrame: WindowFrame?
    private var currentLanguage: InputLanguage = .english
    private var currentConfig: OverlayConfig = .default

    private var cancellables = Set<AnyCancellable>()

    /// 순수 컨테이너 모드 — 외부(AppCoordinator)가 apply(...)로 주입.
    public init() {}

    /// 편의 생성자 — Input/Window/Preferences를 직접 바인딩한다.
    /// AppCoordinator가 이 모듈 내부에 흡수되는 단순 조립에 사용.
    public convenience init(
        inputMonitor: InputSourceMonitoring,
        windowTracker: FocusedWindowTracking,
        preferences: PreferencesStoring
    ) {
        self.init()
        bind(inputMonitor: inputMonitor,
             windowTracker: windowTracker,
             preferences: preferences)
    }

    public func bind(
        inputMonitor: InputSourceMonitoring,
        windowTracker: FocusedWindowTracking,
        preferences: PreferencesStoring
    ) {
        // 기존 구독 모두 해제 후 재바인딩 (idempotent)
        cancellables.removeAll()

        inputMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lang in self?.apply(language: lang) }
            .store(in: &cancellables)

        windowTracker.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in self?.apply(frame: frame) }
            .store(in: &cancellables)

        preferences.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cfg in self?.apply(config: cfg) }
            .store(in: &cancellables)
    }

    // MARK: - OverlayRendering

    public func apply(frame: WindowFrame?) {
        assertMain()
        currentFrame = frame
        if let f = frame {
            DiagLogger.log("renderer.apply(frame) bundle=\(f.appBundleID) frame=\(Int(f.frame.origin.x)),\(Int(f.frame.origin.y)) \(Int(f.frame.width))x\(Int(f.frame.height))")
        } else {
            DiagLogger.log("renderer.apply(frame) <nil>")
        }
        render()
    }

    public func apply(language: InputLanguage) {
        assertMain()
        currentLanguage = language
        // render() 단일 진입점으로 통일 — 캐시(currentFrame/currentConfig/currentLanguage)
        // 모두를 사용해 멱등적·일관된 윈도우/레이어 갱신을 보장.
        render()
    }

    public func apply(config: OverlayConfig) {
        assertMain()
        currentConfig = config
        render()
    }

    // MARK: - Render Decision

    private func render() {
        guard currentConfig.isEnabled else {
            DiagLogger.log("renderer.render -> hide (disabled)")
            controller.hide()
            return
        }
        guard let frame = currentFrame else {
            DiagLogger.log("renderer.render -> hide (no frame)")
            controller.hide()
            return
        }
        controller.show(at: frame, config: currentConfig, language: currentLanguage)
    }

    private func assertMain() {
        // 모든 AppKit/CoreAnimation 접근은 메인 스레드에서. 디버그 빌드에서 위반 잡음.
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(.main))
        #endif
    }
}
