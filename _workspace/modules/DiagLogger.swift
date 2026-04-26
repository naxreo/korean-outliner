//
//  DiagLogger.swift
//  macos-korean-outliner — 파일 기반 진단 로거.
//
//  메인 앱은 이미 Accessibility 권한을 가지고 있으므로, AX 동작에 대한 가장
//  신뢰할 수 있는 관찰 지점이다. 외부에서 AX를 관찰하려면 별도의 권한 부여가
//  필요한 반면, 이 로거는 앱이 기록하는 모든 사실을 그대로 캡처한다.
//
//  활성화: 환경변수 `KO_DIAG=1`이 설정된 경우에만 동작한다. 평상시에는
//  log()/mark() 호출이 즉시 반환되며 파일도 만들지 않는다. 디버깅이 필요할 때
//  앱을 다음과 같이 실행하면 된다:
//
//      KO_DIAG=1 open "/Applications/Korean Outliner.app"
//      또는
//      bash scripts/diag-run.sh
//
//  로그 경로 (활성화 시 자동 생성):
//      ~/Library/Logs/KoreanOutliner/focus-tracker.log
//
//  파일이 5MB를 넘으면 시작 시 잘라낸다 (rotation).
//

import AppKit
import ApplicationServices
import Foundation

public enum DiagLogger {

    private static let queue = DispatchQueue(
        label: "com.naxreo.koreanoutliner.diag",
        qos: .utility
    )

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public static let logURL: URL? = {
        // KO_DIAG=1 환경변수가 없으면 진단 비활성. 일반 사용자에게 부하/디스크
        // 흔적을 남기지 않는다.
        guard ProcessInfo.processInfo.environment["KO_DIAG"] == "1" else {
            return nil
        }
        let fm = FileManager.default
        guard let libDir = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = libDir.appendingPathComponent("Logs/KoreanOutliner", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("focus-tracker.log")
        // 시작 시점에 5MB 초과면 truncate. 진단 세션 단위로 새로 쌓는다.
        if let attr = try? fm.attributesOfItem(atPath: url.path),
           let size = attr[.size] as? NSNumber,
           size.intValue > 5 * 1024 * 1024 {
            try? Data().write(to: url)
        }
        return url
    }()

    /// 진단 로깅이 활성화되어 있는지 여부. 무거운 사전 계산(예: AX 속성 질의)을
    /// 호출 측에서 가드할 때 사용한다.
    public static var isEnabled: Bool { logURL != nil }

    /// 한 줄 기록.
    public static func log(_ message: @autoclosure @escaping () -> String) {
        guard let url = logURL else { return }
        let ts = formatter.string(from: Date())
        queue.async {
            let line = "[\(ts)] \(message())\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// 세션 시작/종료 등 굵직한 마커 라인.
    public static func mark(_ message: String) {
        log("===== \(message) =====")
    }

    /// AXUIElement를 사람이 읽을 수 있는 문자열로 변환. 디버그용.
    public static func describe(_ element: AXUIElement) -> String {
        var roleVal: AnyObject?
        var subroleVal: AnyObject?
        var titleVal: AnyObject?
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleVal)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal)

        let role = (roleVal as? String) ?? "?"
        let subrole = (subroleVal as? String) ?? "-"
        let title = (titleVal as? String) ?? ""

        var origin = CGPoint.zero
        var size = CGSize.zero
        if let raw = posVal, CFGetTypeID(raw as CFTypeRef) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgPoint, &origin)
        }
        if let raw = sizeVal, CFGetTypeID(raw as CFTypeRef) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgSize, &size)
        }
        return "<\(role)/\(subrole) '\(title)' \(Int(origin.x)),\(Int(origin.y)) \(Int(size.width))x\(Int(size.height))>"
    }

    public static func describeOptional(_ element: AXUIElement?) -> String {
        guard let element = element else { return "<nil>" }
        return describe(element)
    }
}
