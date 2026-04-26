//
//  OverlayWindowController.swift
//  macos-korean-outliner — 오버레이 윈도우 라이프사이클·좌표 변환 관리
//

import AppKit

final class OverlayWindowController {

    private let contentView: OverlayContentView
    private let window: OverlayWindow

    init() {
        let view = OverlayContentView(frame: .zero)
        self.contentView = view
        self.window = OverlayWindow(contentView: view)
    }

    /// AX 좌표계의 WindowFrame을 받아 NS 좌표로 변환 후 표시한다.
    /// - 0 크기 프레임이면 숨김 처리.
    /// - 적합한 NSScreen을 찾지 못하면 메인 스크린 폴백, 그래도 없으면 스킵.
    func show(at windowFrame: WindowFrame, config: OverlayConfig, language: InputLanguage) {
        guard windowFrame.frame.width > 0, windowFrame.frame.height > 0 else {
            DiagLogger.log("overlay.show -> hide (zero size)")
            hide()
            return
        }
        guard let screen = windowFrame.screen ?? NSScreen.main else {
            // 변환 기준 스크린 없음 — 안전하게 숨김
            DiagLogger.log("overlay.show -> hide (no screen)")
            hide()
            return
        }

        let nsFrame = Self.nsRect(from: windowFrame.frame, on: screen)
        let wasVisible = window.isVisible

        // setFrame은 contentView bounds 갱신을 동반함 → 묵시 애니메이션 차단을
        // 위해 CATransaction begin/commit으로 감싼다.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(nsFrame, display: true)
        CATransaction.commit()

        contentView.update(config: config, language: language)

        // 윈도우 파괴/포커스 전환 등 외부 이벤트에 의해 macOS가 묵시적으로
        // 오버레이 윈도우를 숨기는 경우가 있다(특히 .transient collectionBehavior
        // 와 결합 시). isVisible 캐시를 신뢰하지 말고 매 렌더마다 명시적으로
        // 전면 정렬한다 — 이미 visible이면 멱등.
        window.orderFrontRegardless()

        let nowVisible = window.isVisible
        DiagLogger.log("overlay.show ns=\(Int(nsFrame.origin.x)),\(Int(nsFrame.origin.y)) \(Int(nsFrame.width))x\(Int(nsFrame.height)) wasVisible=\(wasVisible) nowVisible=\(nowVisible)")
    }

    /// 입력 언어 또는 설정만 변경되었을 때 — 윈도우 프레임은 유지하고 색만 갱신.
    func refresh(config: OverlayConfig, language: InputLanguage) {
        contentView.update(config: config, language: language)
    }

    func hide() {
        if window.isVisible {
            DiagLogger.log("overlay.hide (was visible)")
            window.orderOut(nil)
        }
    }

    // MARK: - Coordinate Conversion

    /// AX 좌표(top-left, 글로벌) → NS 좌표(bottom-left, 글로벌) 변환.
    ///
    /// AX는 메인 스크린 top-left가 (0,0). NSWindow도 글로벌 bottom-left가 (0,0)
    /// (스크린 0의 bottom-left 기준)이지만, Y축이 반대.
    ///
    /// 변환식 (메인 스크린 = 메뉴바 보유, frame.origin == .zero인 스크린):
    ///   ns.x = ax.x
    ///   ns.y = primaryScreen.frame.maxY - (ax.y + ax.height)
    static func nsRect(from axRect: CGRect, on screen: NSScreen) -> CGRect {
        let primary = primaryScreen() ?? screen
        let primaryHeight = primary.frame.maxY
        let flippedY = primaryHeight - (axRect.origin.y + axRect.height)
        return CGRect(
            x: axRect.origin.x,
            y: flippedY,
            width: axRect.width,
            height: axRect.height
        )
    }

    /// 글로벌 좌표 변환 기준 스크린(AX (0,0)과 동일 원점) 도출.
    /// 우선순위:
    ///   1) origin == .zero 스크린 (정의상 글로벌 좌표 원점)
    ///   2) NSScreen.screens.first (Apple 문서상 "primary display")
    ///   3) NSScreen.main (key window 위치 기반 — 좌표 기준은 흔들리지만 최후 폴백)
    /// window-tracker-dev의 WindowFrame.screen 도출 fallback 체인과 동기화됨.
    private static func primaryScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
            ?? NSScreen.main
    }
}
