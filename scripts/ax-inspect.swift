#!/usr/bin/env xcrun swift
//
// ax-inspect.swift — 특정 앱의 AX 알림과 focused window 상태를 실시간으로
// 표준출력에 덤프하는 진단 도구.
//
// Usage:
//   swift scripts/ax-inspect.swift <bundleID-or-localized-name>
//   swift scripts/ax-inspect.swift com.googlecode.iterm2
//   swift scripts/ax-inspect.swift Finder
//
// 출력은 stderr에 찍는 시작 메시지를 제외하고 stdout 한 줄당 1 이벤트:
//   [HH:mm:ss.SSS] <event> elem=<role/subrole/title/frame> focused=<...>
//
// 종료: Ctrl+C
//
// 주의: AX 권한이 필요. AXObserver/AXUIElementCopy 호출 자체는 성공해도
// 권한이 없으면 알림이 오지 않거나 .cannotComplete가 반환된다. 시작 직후
// AXIsProcessTrusted() 결과를 출력한다.
//

import Cocoa
import ApplicationServices

// MARK: - Args

let args = CommandLine.arguments.dropFirst()
guard let key = args.first else {
    fputs("usage: swift scripts/ax-inspect.swift <bundleID-or-name>\n", stderr)
    exit(2)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == key
        || $0.localizedName?.compare(key, options: .caseInsensitive) == .orderedSame
}) else {
    fputs("no running app matched: \(key)\n", stderr)
    fputs("running apps with bundle id:\n", stderr)
    for a in NSWorkspace.shared.runningApplications {
        if let bid = a.bundleIdentifier, !bid.hasPrefix("com.apple.") {
            fputs("  \(bid)  (\(a.localizedName ?? "?"))\n", stderr)
        }
    }
    exit(1)
}

let pid = app.processIdentifier
let appElement = AXUIElementCreateApplication(pid)
let context = UnsafeMutableRawPointer(bitPattern: 0xC0DE)

fputs("target: \(app.localizedName ?? "?") pid=\(pid) bundle=\(app.bundleIdentifier ?? "?")\n", stderr)
fputs("AXIsProcessTrusted = \(AXIsProcessTrusted())\n", stderr)

// MARK: - Formatting

let tsFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func ts() -> String { tsFormatter.string(from: Date()) }

func describe(_ element: AXUIElement) -> String {
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
    if let posRaw = posVal,
       CFGetTypeID(posRaw as CFTypeRef) == AXValueGetTypeID() {
        AXValueGetValue(posRaw as! AXValue, .cgPoint, &origin)
    }
    if let sizeRaw = sizeVal,
       CFGetTypeID(sizeRaw as CFTypeRef) == AXValueGetTypeID() {
        AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
    }
    return "<\(role)/\(subrole) '\(title)' frame=\(Int(origin.x)),\(Int(origin.y)) \(Int(size.width))x\(Int(size.height))>"
}

func focusedWindow() -> AXUIElement? {
    var v: AnyObject?
    let r = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &v)
    guard r == .success, let raw = v,
          CFGetTypeID(raw as CFTypeRef) == AXUIElementGetTypeID() else {
        return nil
    }
    return (raw as! AXUIElement)
}

func describeFocused() -> String {
    if let w = focusedWindow() { return describe(w) }
    return "<nil>"
}

func emit(_ message: String) {
    print("[\(ts())] \(message)")
    FileHandle.standardOutput.synchronizeFile()
}

// MARK: - AX observer

func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    let name = notification as String
    let elemDesc = describe(element)
    DispatchQueue.main.async {
        let f = describeFocused()
        emit("\(name) elem=\(elemDesc) focused=\(f)")
    }
}

var observer: AXObserver?
let createResult = AXObserverCreate(pid, axCallback, &observer)
guard createResult == .success, let obs = observer else {
    fputs("AXObserverCreate failed: \(createResult.rawValue)\n", stderr)
    exit(1)
}

let notifications: [String] = [
    kAXFocusedWindowChangedNotification,
    kAXMainWindowChangedNotification,
    kAXFocusedUIElementChangedNotification,
    kAXApplicationHiddenNotification,
    kAXApplicationShownNotification,
    kAXApplicationActivatedNotification,
    kAXApplicationDeactivatedNotification,
    kAXWindowCreatedNotification,
    kAXWindowMovedNotification,
    kAXWindowResizedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
    kAXUIElementDestroyedNotification,
    kAXTitleChangedNotification,
]

for n in notifications {
    let r = AXObserverAddNotification(obs, appElement, n as CFString, context)
    if r != .success {
        fputs("WARN add \(n): \(r.rawValue)\n", stderr)
    }
}

CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)

emit("inspector started. initial focused=\(describeFocused())")

// 종료 시 마지막으로 한 번 더 상태를 찍는다.
signal(SIGINT) { _ in
    print("[\(tsFormatter.string(from: Date()))] SIGINT received, exiting")
    exit(0)
}

CFRunLoopRun()
