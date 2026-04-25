//
//  AppRestart.swift
//  macos-korean-outliner — 앱 자체 재시작 헬퍼
//
//  TCC 권한 캐시가 꼬인 경우(시스템 설정 토글 ON인데 AXIsProcessTrusted() 가 계속
//  false 반환)에는 "tccutil reset" 후 프로세스를 새로 시작해야 trust가 재인식된다.
//  사용자가 수동으로 quit → relaunch 하지 않아도 되도록 자동화한다.
//

import AppKit
import Foundation

public enum AppRestart {

    /// 새 인스턴스를 launch한 뒤 현재 프로세스를 종료한다.
    /// `delay`는 새 인스턴스가 완전히 떠서 메뉴바 아이콘을 등록할 시간을 준다.
    public static func relaunch(delay: TimeInterval = 0.4) {
        let bundleURL = Bundle.main.bundleURL

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true

        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: config
        ) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.terminate(nil)
            }
        }
    }
}
