//
//  AXPermission.swift
//  macos-korean-outliner — Accessibility permission helpers.
//
//  See `_workspace/02_interfaces.swift` for the canonical AXPermissionStatus
//  type. This module only provides querying / requesting helpers around it.
//

import AppKit
import ApplicationServices
import Foundation

public enum AXPermission {

    /// Snapshot the current Accessibility trust state.
    /// Does NOT prompt the user.
    ///
    /// `AXIsProcessTrustedWithOptions(prompt: false)` 를 사용하면 일부 macOS
    /// 환경에서 `AXIsProcessTrusted()` 의 캐시된 결과를 회피하고 더 즉각적인
    /// 갱신 결과를 받는다. 권한 토글 직후의 polling 응답성을 높이기 위함.
    public static func status() -> AXPermissionStatus {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: [String: Any] = [key: false]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary) ? .granted : .denied
    }

    /// Trigger the system Accessibility permission dialog if the process is
    /// not yet trusted. Returns the trust state at call time.
    ///
    /// Should be invoked only from an explicit user action (e.g. a
    /// "Grant access" button), never on app launch.
    @discardableResult
    public static func requestIfNeeded() -> AXPermissionStatus {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: [String: Any] = [key: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary) ? .granted : .denied
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    public static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 진단 정보. PreferencesView의 트러블슈팅 섹션이 표시한다.
    /// `tccutil reset` 후에도 권한이 잡히지 않을 때 binary 위치/번들 ID/trust 결과를
    /// 사용자가 한눈에 확인할 수 있게 한다.
    public struct Diagnostics {
        public let bundlePath: String
        public let bundleID: String
        public let trustedRaw: Bool         // AXIsProcessTrusted()
        public let trustedWithOptions: Bool // AXIsProcessTrustedWithOptions([:])
    }

    public static func diagnostics() -> Diagnostics {
        let path = Bundle.main.bundlePath
        let id = Bundle.main.bundleIdentifier ?? "(no bundle id)"
        let raw = AXIsProcessTrusted()
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: [String: Any] = [key: false]
        let withOpts = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        return Diagnostics(
            bundlePath: path,
            bundleID: id,
            trustedRaw: raw,
            trustedWithOptions: withOpts
        )
    }

    /// `tccutil reset Accessibility <bundle-id>` 를 실행한다. admin 권한 없이도
    /// 자기 앱에 대해서는 동작. 호출 직후 앱을 재시작해야 효과 발휘.
    @discardableResult
    public static func resetTCC() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            NSLog("[AXPermission] tccutil reset failed: \(error.localizedDescription)")
            return false
        }
    }
}
