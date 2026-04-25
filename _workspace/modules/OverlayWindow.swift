//
//  OverlayWindow.swift
//  macos-korean-outliner — 투명 borderless NSWindow 서브클래스
//
//  외곽선 렌더링 전용 윈도우. 클릭 투과·키 포커스 비획득·전 스페이스 표시.
//

import AppKit

final class OverlayWindow: NSWindow {

    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.level = .statusBar
        // .transient: Mission Control / App Exposé 진입 시 시스템이 자동으로 숨김.
        // .stationary는 반대로 화면에 정지된 상태로 남기 때문에 외곽선이 Mission Control
        // 위에 떠있는 시각적 결함이 발생함.
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        self.isReleasedWhenClosed = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}
