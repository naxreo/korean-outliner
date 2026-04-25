//
//  02_interfaces.swift
//  macos-korean-outliner — Single Source of Truth (SSoT)
//
//  본 파일은 architect 에이전트가 관리하는 모든 모듈 간 경계면 계약이다.
//  모든 dev 에이전트는 이 파일에 정의된 protocol/struct/enum **만** 사용하여
//  구현하고, 인터페이스 변경 요청은 반드시 architect를 경유한다.
//
//  ──────────────────────────────────────────────────────────────────────────
//  좌표계 규약 (필독)
//  ──────────────────────────────────────────────────────────────────────────
//  본 시스템은 두 좌표계를 혼용한다.
//
//  - AX 좌표계 (Accessibility API): top-left 원점.
//      kAXPositionAttribute / kAXSizeAttribute가 반환하는 값.
//      메인 스크린 top-left가 (0,0), Y는 아래로 증가.
//
//  - NSWindow 좌표계 (AppKit): bottom-left 원점.
//      NSWindow.setFrame(_:display:)이 받는 값.
//      메인 스크린 bottom-left가 (0,0), Y는 위로 증가.
//
//  계약:
//   1. `WindowFrame.frame`은 **AX 좌표 그대로** 전달한다 (변환 금지).
//   2. NSWindow 좌표 변환은 **OverlayRenderer 단독 책임**이다.
//   3. 다른 모듈이 frame 값을 NSScreen 좌표로 가정하면 안 된다.
//
//  변환 참고식 (OverlayRenderer 내부에서만 사용):
//      ns.x = ax.x
//      ns.y = primaryScreen.frame.maxY - (ax.y + ax.height)
//  ──────────────────────────────────────────────────────────────────────────
//

import AppKit
import Combine
import CoreGraphics
import Foundation

// MARK: - Domain Enums

/// 시스템 전역 입력 언어 상태.
/// `other(id:)`의 id는 TISInputSource의 kTISPropertyInputSourceID 문자열을
/// 그대로 보존한다 (예: "com.apple.keylayout.Dvorak").
public enum InputLanguage: Equatable {
    case korean
    case english
    case other(id: String)
}

/// AX 권한(Accessibility) 부여 상태.
/// FocusedWindowTracker가 동작하려면 `.granted` 이어야 한다.
public enum AXPermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

// MARK: - Value Types (immutable)

/// 포커스된 윈도우의 프레임 정보.
///
/// - Important: `frame`은 **AX 좌표계 (top-left 원점)** 값이다.
///   NSWindow 좌표로 변환하지 말고 그대로 전달한다.
///   변환은 OverlayRenderer 내부에서만 수행한다.
public struct WindowFrame: Equatable {
    /// AX 좌표계 기준 윈도우 프레임 (top-left 원점, Y 아래로 증가).
    public let frame: CGRect

    /// 윈도우가 주로 위치한 NSScreen. 멀티 모니터 환경에서 OverlayRenderer가
    /// 어느 스크린의 좌표로 변환할지 결정하는 힌트로 사용한다. nil 가능.
    public let screen: NSScreen?

    /// 포커스 윈도우를 소유한 앱의 번들 ID (예: "com.apple.Safari").
    public let appBundleID: String

    /// CGWindowList에서 얻을 수 있는 윈도우 ID. AX는 직접 노출하지 않으므로
    /// 보조 식별자(스크린샷 매칭 등)로만 사용. nil 허용.
    public let windowID: CGWindowID?

    public init(
        frame: CGRect,
        screen: NSScreen?,
        appBundleID: String,
        windowID: CGWindowID?
    ) {
        self.frame = frame
        self.screen = screen
        self.appBundleID = appBundleID
        self.windowID = windowID
    }
}

/// 외곽선 표시면을 나타내는 OptionSet.
/// 사용자는 어느 변(상/하/좌/우)에 외곽선을 표시할지 자유롭게 조합할 수 있다.
public struct OverlaySides: OptionSet, Codable, Equatable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top      = OverlaySides(rawValue: 1 << 0)
    public static let leading  = OverlaySides(rawValue: 1 << 1)
    public static let trailing = OverlaySides(rawValue: 1 << 2)
    public static let bottom   = OverlaySides(rawValue: 1 << 3)

    public static let horizontal: OverlaySides = [.top, .bottom]
    public static let vertical:   OverlaySides = [.leading, .trailing]
    public static let all:        OverlaySides = [.top, .leading, .trailing, .bottom]
}

/// NSColor의 직렬화 표현. UserDefaults에 Codable로 저장하기 위해 사용한다.
///
/// 구현 메모(architect → preferences-dev):
/// - `extension ColorData { init(_ nsColor: NSColor) ... ; var nsColor: NSColor ... }`
///   를 별도 구현 파일에 둔다 (NSColor.usingColorSpace(.sRGB) 변환 권장).
/// - 이 SSoT 파일에는 **데이터 모양**만 정의한다. 구현은 모듈 내부.
public struct ColorData: Codable, Equatable, Hashable {
    /// sRGB red component, 0.0...1.0
    public var red: Double
    /// sRGB green component, 0.0...1.0
    public var green: Double
    /// sRGB blue component, 0.0...1.0
    public var blue: Double
    /// alpha, 0.0...1.0
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// 사용자 설정 가능한 외곽선 구성. PreferencesStore가 영속화한다.
public struct OverlayConfig: Codable, Equatable {
    /// 한글 입력 시 외곽선 색상.
    public var koreanColor: ColorData
    /// 영문 입력 시 외곽선 색상.
    public var englishColor: ColorData
    /// 외곽선 두께 (포인트 단위). 권장 범위 1...10.
    public var thickness: CGFloat
    /// 외곽선 길이 비율 (0.0...1.0). 1.0이면 변 전체, 0.5이면 변 가운데 50%만 표시.
    /// 가운데 정렬되며 양쪽 끝에서 (1-ratio)/2 만큼 잘려나간다.
    public var lengthRatio: CGFloat
    /// 외곽선 전체 투명도 (0.0...1.0). 색상 자체의 alpha와 곱해져 적용된다.
    public var opacity: CGFloat
    /// 표시할 변. 비어있으면 외곽선을 그리지 않는다.
    public var sides: OverlaySides
    /// 마스터 토글. false이면 OverlayRenderer는 어떤 입력에도 그리지 않는다.
    public var isEnabled: Bool

    public init(
        koreanColor: ColorData,
        englishColor: ColorData,
        thickness: CGFloat,
        lengthRatio: CGFloat = 1.0,
        opacity: CGFloat = 1.0,
        sides: OverlaySides,
        isEnabled: Bool
    ) {
        self.koreanColor = koreanColor
        self.englishColor = englishColor
        self.thickness = thickness
        self.lengthRatio = max(0, min(1, lengthRatio))
        self.opacity = max(0, min(1, opacity))
        self.sides = sides
        self.isEnabled = isEnabled
    }

    /// 합리적 기본값. PreferencesStore가 첫 실행 시 사용.
    public static let `default` = OverlayConfig(
        koreanColor:  ColorData(red: 0.20, green: 0.50, blue: 1.00, alpha: 1.0), // blue
        englishColor: ColorData(red: 1.00, green: 0.30, blue: 0.30, alpha: 1.0), // red
        thickness: 3,
        lengthRatio: 1.0,
        opacity: 1.0,
        sides: [.top, .bottom],
        isEnabled: true
    )

    // 기존 OverlayConfig.v1로 저장된 데이터(lengthRatio/opacity 누락)와 호환.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let korean   = try c.decode(ColorData.self, forKey: .koreanColor)
        let english  = try c.decode(ColorData.self, forKey: .englishColor)
        let thick    = try c.decode(CGFloat.self,    forKey: .thickness)
        let length   = try c.decodeIfPresent(CGFloat.self, forKey: .lengthRatio) ?? 1.0
        let opa      = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1.0
        let sides    = try c.decode(OverlaySides.self, forKey: .sides)
        let enabled  = try c.decode(Bool.self,         forKey: .isEnabled)
        self.init(
            koreanColor: korean,
            englishColor: english,
            thickness: thick,
            lengthRatio: length,
            opacity: opa,
            sides: sides,
            isEnabled: enabled
        )
    }
}

// MARK: - Module Protocols

/// 시스템 전역 한/영(IME) 입력 상태를 감지한다.
///
/// 구현 가이드 (architect → input-monitor-dev):
/// - TISCopyCurrentKeyboardInputSource()로 현재값 조회
/// - DistributedNotificationCenter의 "AppleSelectedInputSourcesChangedNotification"
///   (또는 동등 알림) 구독으로 변경 감지
/// - kTISPropertyInputSourceID에서 "Korean" 또는 "com.apple.inputmethod.Korean..."
///   prefix 매칭으로 .korean 판정. 그 외 ABC/US 등은 .english, 나머지는 .other(id:)
public protocol InputSourceMonitoring: AnyObject {
    /// 마지막으로 감지된 입력 언어. start() 호출 전에는 마지막 알려진 값(또는 .english)을 반환.
    var current: InputLanguage { get }

    /// 입력 언어 변경 이벤트 스트림. start() 이후 emit 시작.
    var publisher: AnyPublisher<InputLanguage, Never> { get }

    /// 모니터링 시작. 이미 시작된 상태에서 호출 시 no-op.
    func start()

    /// 모니터링 중지 및 알림 구독 해제.
    func stop()
}

/// 포커스된 앱·윈도우 추적 + 프레임 변경 감지.
///
/// 구현 가이드 (architect → window-tracker-dev):
/// - NSWorkspace.shared.notificationCenter의
///   .didActivateApplicationNotification 으로 포커스 앱 변경 감지
/// - 새 앱마다 AXUIElementCreateApplication 후 AXObserver 신규 생성, 이전 observer 해제
/// - 관찰 알림: kAXFocusedWindowChangedNotification, kAXMovedNotification,
///   kAXResizedNotification, kAXWindowMiniaturizedNotification,
///   kAXWindowDeminiaturizedNotification, kAXApplicationHiddenNotification
/// - 권한 없으면 publisher는 nil emit, permissionStatus = .denied
public protocol FocusedWindowTracking: AnyObject {
    /// 마지막으로 알려진 포커스 윈도우 프레임. 없으면 nil.
    /// 좌표계는 **AX (top-left)**.
    var current: WindowFrame? { get }

    /// 포커스 윈도우 프레임 변경 스트림. 윈도우 없음/숨김 시 nil emit.
    var publisher: AnyPublisher<WindowFrame?, Never> { get }

    /// AX 권한 부여 상태. start() 호출 전에 확인 권장.
    var permissionStatus: AXPermissionStatus { get }

    /// 추적 시작. 권한 미부여 상태에서 호출하면 내부적으로 stopped 유지하고
    /// publisher는 nil emit, permissionStatus를 .denied로 노출.
    func start()

    /// 추적 중지. AXObserver 및 NSWorkspace 알림 구독 해제.
    func stop()

    /// 시스템 환경설정 > 보안 및 개인정보 보호 > 손쉬운 사용 패널을 연다.
    /// 사용자 안내 UX에서 호출.
    func openSystemAccessibilityPane()
}

/// 외곽선 렌더링. NSWindow + CALayer를 사용하여 투명 오버레이를 그린다.
///
/// 구현 가이드 (architect → overlay-renderer-dev):
/// - NSWindow level은 .statusBar (NSStatusWindowLevel) 권장. ADR-003 참조
/// - styleMask: .borderless, isOpaque: false, backgroundColor: .clear,
///   ignoresMouseEvents: true, collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
/// - frame 적용 시 AX → NS 좌표 변환은 **이 모듈 내부에서만** 수행
/// - apply(language:) / apply(frame:) / apply(config:)는 멱등(idempotent)해야 함
/// - 마지막 상태(language, frame, config)를 모듈 내부에 캐시하여 어떤 순서로
///   apply가 호출되어도 일관된 화면을 그린다
public protocol OverlayRendering: AnyObject {
    /// 외곽선을 그릴 윈도우 프레임 적용. nil이면 오버레이 숨김.
    /// 입력 좌표는 AX 좌표계 (top-left).
    func apply(frame: WindowFrame?)

    /// 입력 언어 적용. 색상 결정에 사용.
    func apply(language: InputLanguage)

    /// 사용자 설정 적용 (색상/두께/표시면/마스터 토글).
    func apply(config: OverlayConfig)
}

/// 사용자 설정의 영속화·복원·변경 알림.
///
/// 구현 가이드 (architect → preferences-dev):
/// - UserDefaults에 OverlayConfig를 JSON Codable로 저장
/// - update(_:)는 즉시 영속화 + publisher emit
/// - 첫 실행 시 OverlayConfig.default 사용
public protocol PreferencesStoring: AnyObject {
    /// 현재 설정 스냅샷. 동기 접근.
    var current: OverlayConfig { get }

    /// 설정 변경 스트림. 구독 시 즉시 현재값 1회 emit (CurrentValueSubject 권장).
    var publisher: AnyPublisher<OverlayConfig, Never> { get }

    /// 설정 갱신. 영속화 후 publisher emit.
    func update(_ config: OverlayConfig)
}

/// SwiftUI 설정 화면 표시 책임.
public protocol PreferencesPresenting: AnyObject {
    /// 설정 윈도우를 띄우고 활성화한다. 이미 떠 있으면 front로 가져온다.
    func show()

    /// AX 권한 안내 화면을 강조하여 표시한다 (앱 시작 시 권한 미부여 상태).
    func showAccessibilityPrompt()
}

/// NSStatusItem 메뉴바 컨트롤러.
public protocol MenuBarPresenting: AnyObject {
    /// 메뉴바 아이콘 설치.
    func install()

    /// 마스터 토글 상태(색상 외곽선 활성/비활성)를 아이콘에 반영.
    func setEnabled(_ enabled: Bool)

    /// 현재 입력 언어를 아이콘 상태에 반영(선택적 시각 표시).
    func setLanguage(_ language: InputLanguage)
}
