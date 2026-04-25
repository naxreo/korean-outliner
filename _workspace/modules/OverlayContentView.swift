//
//  OverlayContentView.swift
//  macos-korean-outliner — 4방향 CALayer 외곽선 렌더링 NSView
//
//  4개 독립 CALayer로 OverlaySides 토글에 대응한다.
//  CATransaction.setDisableActions(true) + per-layer .actions = NSNull로
//  묵시적 애니메이션을 차단하여 즉시 반영을 보장.
//

import AppKit
import QuartzCore

final class OverlayContentView: NSView {

    private let topLayer    = CALayer()
    private let leadingLayer = CALayer()
    private let trailingLayer = CALayer()
    private let bottomLayer  = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer = CALayer()
        layer?.actions = Self.disabledActions

        for sub in allLayers {
            sub.actions = Self.disabledActions
            sub.frame = .zero
            layer?.addSublayer(sub)
        }
    }

    override var isFlipped: Bool { false }

    private var allLayers: [CALayer] {
        [topLayer, leadingLayer, trailingLayer, bottomLayer]
    }

    private static let disabledActions: [String: CAAction] = [
        "position":        NSNull(),
        "bounds":          NSNull(),
        "frame":           NSNull(),
        "backgroundColor": NSNull(),
        "hidden":          NSNull(),
        "opacity":         NSNull(),
        "contents":        NSNull(),
        "sublayers":       NSNull(),
        "transform":       NSNull()
    ]

    /// 설정과 현재 입력 언어를 즉시 반영한다.
    /// - Note: contentView의 bounds 기준으로 4면을 그린다. 호출 측에서 윈도우 frame
    ///   변경을 먼저 적용한 뒤 호출해야 한다.
    func update(config: OverlayConfig, language: InputLanguage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        defer { CATransaction.commit() }

        // 마스터 토글 OFF → 모두 숨김
        guard config.isEnabled else {
            for l in allLayers { l.isHidden = true }
            return
        }

        let cgColor = Self.color(for: language, config: config).cgColor
        let t = max(0, config.thickness)
        let b = self.bounds
        let r = max(0, min(1, config.lengthRatio))
        let alpha = Float(max(0, min(1, config.opacity)))

        // 두께 0 / 길이 0이면 그릴 게 없음
        guard t > 0, r > 0, b.width > 0, b.height > 0 else {
            for l in allLayers { l.isHidden = true }
            return
        }

        // 가운데 정렬된 길이 — 양쪽 끝에서 (1-r)/2 만큼씩 잘림
        let hLen = b.width * r
        let hOff = (b.width - hLen) / 2
        let vLen = b.height * r
        let vOff = (b.height - vLen) / 2

        // top (y는 bottom-left 좌표 — 위쪽 변)
        if config.sides.contains(.top) {
            topLayer.isHidden = false
            topLayer.frame = CGRect(x: hOff, y: b.height - t, width: hLen, height: t)
            topLayer.backgroundColor = cgColor
            topLayer.opacity = alpha
        } else {
            topLayer.isHidden = true
        }

        // bottom
        if config.sides.contains(.bottom) {
            bottomLayer.isHidden = false
            bottomLayer.frame = CGRect(x: hOff, y: 0, width: hLen, height: t)
            bottomLayer.backgroundColor = cgColor
            bottomLayer.opacity = alpha
        } else {
            bottomLayer.isHidden = true
        }

        // leading (좌측 — LTR 가정. RTL 로컬라이제이션 미지원)
        if config.sides.contains(.leading) {
            leadingLayer.isHidden = false
            leadingLayer.frame = CGRect(x: 0, y: vOff, width: t, height: vLen)
            leadingLayer.backgroundColor = cgColor
            leadingLayer.opacity = alpha
        } else {
            leadingLayer.isHidden = true
        }

        // trailing (우측)
        if config.sides.contains(.trailing) {
            trailingLayer.isHidden = false
            trailingLayer.frame = CGRect(x: b.width - t, y: vOff, width: t, height: vLen)
            trailingLayer.backgroundColor = cgColor
            trailingLayer.opacity = alpha
        } else {
            trailingLayer.isHidden = true
        }
    }

    private static func color(for language: InputLanguage, config: OverlayConfig) -> NSColor {
        switch language {
        case .korean:
            return config.koreanColor.nsColor
        case .english:
            return config.englishColor.nsColor
        case .other:
            // 한/영 외 입력 소스는 영문 색상으로 폴백 (외곽선이 사라지면 사용자가
            // 앱이 죽었다고 오해할 수 있으므로 색상은 항상 표시)
            return config.englishColor.nsColor
        }
    }
}
