//
//  ColorData+Convert.swift
//  macos-korean-outliner — ColorData ↔ NSColor / CGColor 변환
//
//  SSoT(02_interfaces.swift)는 ColorData의 데이터 모양만 정의한다.
//  실제 변환은 본 모듈 내부에서 수행하여 SSoT의 import 부담을 최소화한다.
//

import AppKit
import CoreGraphics

public extension ColorData {

    /// sRGB NSColor로 변환. 컴포넌트는 0...1로 클램프.
    var nsColor: NSColor {
        NSColor(
            srgbRed: Self.clamp(red),
            green:   Self.clamp(green),
            blue:    Self.clamp(blue),
            alpha:   Self.clamp(alpha)
        )
    }

    /// CALayer.backgroundColor용 CGColor. NSColor 경유로 colorSpace를 명시.
    var cgColor: CGColor {
        nsColor.cgColor
    }

    /// NSColor → ColorData. 입력이 sRGB가 아니면 sRGB로 변환 후 추출.
    init(_ nsColor: NSColor) {
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red:   Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue:  Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }

    /// CGColor → ColorData. sRGB로 변환 후 컴포넌트 추출.
    /// - Returns: 변환 실패 시(컴포넌트 없음) 불투명 흰색 폴백.
    init(_ cgColor: CGColor) {
        let ns = NSColor(cgColor: cgColor) ?? .white
        self.init(ns)
    }

    private static func clamp(_ v: Double) -> CGFloat {
        CGFloat(min(max(v, 0.0), 1.0))
    }
}
