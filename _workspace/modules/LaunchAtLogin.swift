//
//  LaunchAtLogin.swift
//  macos-korean-outliner — 로그인 시 자동 실행 등록/해제
//
//  macOS 13(Ventura)+의 SMAppService.mainApp API를 사용한다.
//  legacy SMLoginItemSetEnabled는 macOS 13에서 deprecated되어 사용하지 않는다.
//
//  SMAppService.mainApp.status는 시스템 설정 → 일반 → 로그인 항목과 양방향
//  동기화되므로 사용자가 시스템 설정에서 직접 변경한 경우에도 PreferencesView가
//  앱 활성화 시점에 refresh()를 호출하면 UI가 일치한다.
//

import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginController: ObservableObject {

    /// SwiftUI 토글이 바인딩하는 등록 상태. set은 무시되며 setEnabled(_:)를 사용해야 한다.
    @Published public private(set) var isEnabled: Bool = false

    /// 시스템에 등록할 수 없는 사유 (sandbox 제약, 권한 등). nil이면 등록 가능.
    @Published public private(set) var disabledReason: String?

    public init() {
        refresh()
    }

    /// SMAppService.mainApp.status를 읽어 isEnabled / disabledReason을 갱신한다.
    /// PreferencesView가 onAppear / 윈도우 활성화 시 호출하면 시스템 설정에서의
    /// 외부 변경과도 동기화된다.
    public func refresh() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            isEnabled = true
            disabledReason = nil
        case .notRegistered:
            isEnabled = false
            disabledReason = nil
        case .requiresApproval:
            // 사용자가 시스템 설정에서 별도 승인해야 등록 완료되는 상태.
            isEnabled = false
            disabledReason = "시스템 설정 → 일반 → 로그인 항목에서 승인이 필요합니다."
        case .notFound:
            // 번들이 등록되지 않았거나 재배치된 상태. 흔히 ad-hoc 빌드를 자주 옮기면 발생.
            isEnabled = false
            disabledReason = "앱 번들을 찾을 수 없습니다. /Applications로 이동 후 재시도하세요."
        @unknown default:
            isEnabled = false
            disabledReason = "알 수 없는 상태(\(status.rawValue))"
        }
    }

    /// 사용자 토글 액션. enabled=true면 register, false면 unregister.
    /// 호출 후 곧바로 refresh()로 실제 시스템 상태를 다시 읽어 UI에 반영한다.
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[LaunchAtLogin] toggle failed: \(error.localizedDescription)")
            disabledReason = error.localizedDescription
        }
        refresh()
    }
}
