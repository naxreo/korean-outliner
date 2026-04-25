//
//  PermissionViewModel.swift
//  macos-korean-outliner — Accessibility 권한 폴링 ObservableObject
//
//  시스템 설정에서 권한 변경은 NotificationCenter 알림이 없어 폴링이 유일한 방법.
//  - 미부여 상태: 1.5초 폴링 (사용자 체감상 즉각적)
//  - 부여 상태:   30초 폴링 (revoke 감지용 저속 모드 — 배터리/CPU 절약)
//
//  권한 안내 플로우 (window-tracker-dev 가이드):
//   1) 화면 진입 시 status()로 상태 표시
//   2) "권한 허용" 버튼 → requestPermission() (최초 1회 다이얼로그)
//   3) 이미 거부된 상태 → openSystemSettings()로 시스템 설정 직링크
//
//  라이프타임: AppDelegate가 앱 시작 시 즉시 생성하여 보유한다(Preferences 윈도우 의존 X).
//  granted 변화 시 tracker.start()/stop()을 자동 트리거하고, 외부 통지 콜백(onGranted/onRevoked)도
//  지원하여 AppDelegate가 권한 미부여 시 Preferences 자동 노출을 구현할 수 있게 한다.
//

import Combine
import Foundation

public final class PermissionViewModel: ObservableObject {

    @Published public private(set) var isGranted: Bool

    private weak var tracker: FocusedWindowTracking?
    private var timer: Timer?

    /// 권한 미부여 상태 폴링 간격 (사용자 체감 즉각성)
    private let fastInterval: TimeInterval = 1.5
    /// 권한 부여 후 revoke 감지용 저속 폴링 간격 (배터리/CPU 절약)
    private let slowInterval: TimeInterval = 30.0

    /// 권한 상태 변화 콜백 (AppDelegate가 Preferences 자동 표시/숨김에 사용).
    /// 클로저는 메인 스레드에서 호출된다.
    public var onGranted: (() -> Void)?
    public var onRevoked: (() -> Void)?

    public init(tracker: FocusedWindowTracking) {
        self.tracker = tracker
        self.isGranted = AXPermission.status() == .granted
        scheduleTimer(interval: isGranted ? slowInterval : fastInterval)
    }

    deinit { timer?.invalidate() }

    /// 사용자가 "권한 허용" 버튼을 눌렀을 때 호출.
    /// 시스템 권한 다이얼로그를 띄운다 (앱 시작 시 자동 호출 금지 — 명시적 사용자 액션 전용).
    public func requestPermission() {
        AXPermission.requestIfNeeded()
        // 다이얼로그 응답 후 폴링이 isGranted를 갱신하고 tracker.start()도 호출한다.
    }

    /// 사용자가 "시스템 설정 열기" 버튼을 눌렀을 때 호출.
    /// 다이얼로그가 더 이상 뜨지 않는 경우(이미 거부됨) 직접 설정 패널로 안내.
    public func openSystemSettings() {
        AXPermission.openSystemSettings()
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.poll()
        }
        // AXObserver 등록 안정성을 위해 명시적으로 메인 RunLoop common 모드 등록.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let granted = AXPermission.status() == .granted
        // 메인 스레드 보장 — tracker.start()/stop()은 메인에서만 호출되어야 함.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard granted != self.isGranted else { return }
            self.isGranted = granted
            if granted {
                self.tracker?.start()
                self.onGranted?()
                // 부여 후 폴링 간격을 늘려 배터리/CPU 절약 (revoke 감지 지연 허용).
                self.scheduleTimer(interval: self.slowInterval)
            } else {
                // QA-014: revoke 시 tracker.stop() 명시적 호출.
                self.tracker?.stop()
                self.onRevoked?()
                // revoke 시 빠른 재부여 감지를 위해 fast 모드로 복귀.
                self.scheduleTimer(interval: self.fastInterval)
            }
        }
    }
}
