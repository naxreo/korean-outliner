//
//  FocusedWindowTracker.swift
//  macos-korean-outliner — FocusedWindowTracking implementation.
//
//  Tracks the system-wide focused window via the macOS Accessibility API and
//  emits WindowFrame events whenever the focused window or its frame changes.
//
//  Coordinate convention (see `02_interfaces.swift`):
//    `WindowFrame.frame` is emitted in **AX coordinates (top-left origin)**.
//    NS coordinate conversion is the OverlayRenderer's responsibility.
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

// MARK: - C callback (must be a free function, not a Swift method)

private func axEventCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon = refcon else { return }
    let tracker = Unmanaged<FocusedWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    DispatchQueue.main.async {
        tracker.handleAXNotification(element: element, name: name)
    }
}

// MARK: - FocusedWindowTracker

public final class FocusedWindowTracker: FocusedWindowTracking {

    // MARK: Public surface (matches FocusedWindowTracking)

    public private(set) var current: WindowFrame?

    public var publisher: AnyPublisher<WindowFrame?, Never> {
        subject.eraseToAnyPublisher()
    }

    public var permissionStatus: AXPermissionStatus {
        AXPermission.status()
    }

    // MARK: Private state

    private let subject = CurrentValueSubject<WindowFrame?, Never>(nil)
    private var isStarted = false

    private var activeApp: NSRunningApplication?
    private var activeAppElement: AXUIElement?
    private var activeWindow: AXUIElement?
    private var axObserver: AXObserver?

    private var workspaceObserver: NSObjectProtocol?

    /// 윈도우 이동/리사이즈 중에는 외곽선을 숨기고, 마지막 알림 후 일정 시간 동안
    /// 추가 변화가 없으면 ("settle") 최종 프레임을 emit하기 위한 디바운스 워크 아이템.
    private var settleWorkItem: DispatchWorkItem?

    /// 이동/리사이즈 settle 디바운스 지연. 너무 짧으면 깜빡임, 너무 길면 정착 후
    /// 외곽선이 늦게 다시 나타나는 체감.
    private static let settleDelay: TimeInterval = 0.18

    public init() {}

    deinit {
        teardown()
    }

    // MARK: Lifecycle

    public func start() {
        guard !isStarted else { return }

        // Permission gate. Without trust, AX calls would only spam the console.
        guard AXPermission.status() == .granted else {
            current = nil
            subject.send(nil)
            return
        }

        isStarted = true

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self.attach(to: app)
        }

        // Bootstrap with whichever app is already frontmost. This is intentional
        // belt-and-suspenders against environments where
        // NSWorkspace.didActivateApplicationNotification may not fire for the
        // already-active app at start time (observed on some macOS builds and
        // when the user starts the outliner via Spotlight/launcher). We rely on
        // a single notification channel (NSWorkspace.shared.notificationCenter)
        // — if it ever stops delivering for the *currently* frontmost app, this
        // immediate attach still gives us a working initial state.
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            attach(to: frontApp)
        }
    }

    public func stop() {
        guard isStarted else { return }
        cancelSettle()
        teardown()
        isStarted = false
        current = nil
        subject.send(nil)
    }

    public func openSystemAccessibilityPane() {
        AXPermission.openSystemSettings()
    }

    // MARK: Attach / detach AX observer

    private func attach(to app: NSRunningApplication) {
        // Drop the previous app's observer first to avoid stacking callbacks.
        detachObserver()

        // Skip self and apps that opt out of AX (e.g. system UI helpers with no pid).
        guard app.processIdentifier > 0 else {
            current = nil
            subject.send(nil)
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        activeApp = app
        activeAppElement = appElement

        var observer: AXObserver?
        let createResult = AXObserverCreate(app.processIdentifier, axEventCallback, &observer)
        guard createResult == .success, let obs = observer else {
            // Log the failure (debug aid only — no window titles or other
            // user-visible content). Recovery: leave activeApp/activeAppElement
            // cleared so the next didActivateApplicationNotification triggers
            // a fresh attach via detachObserver() at the top of attach(to:).
            NSLog(
                "[FocusedWindowTracker] AXObserverCreate failed for pid=%d (result=%d). Will retry on next app activation.",
                app.processIdentifier,
                createResult.rawValue
            )
            activeApp = nil
            activeAppElement = nil
            current = nil
            subject.send(nil)
            return
        }
        axObserver = obs

        let context = Unmanaged.passUnretained(self).toOpaque()

        // App-level: focused window may change while the app stays frontmost.
        AXObserverAddNotification(obs, appElement,
            kAXFocusedWindowChangedNotification as CFString, context)
        AXObserverAddNotification(obs, appElement,
            kAXApplicationHiddenNotification as CFString, context)
        AXObserverAddNotification(obs, appElement,
            kAXApplicationShownNotification as CFString, context)

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        // Resolve the currently focused window (if any) and start observing it.
        if let window = focusedWindow(of: appElement) {
            attachWindow(window, observer: obs, context: context)
            emit(window: window, app: app)
        } else {
            activeWindow = nil
            current = nil
            subject.send(nil)
        }
    }

    private func attachWindow(
        _ window: AXUIElement,
        observer: AXObserver,
        context: UnsafeMutableRawPointer
    ) {
        // Detach previous window-level notifications (if any) before re-binding.
        detachActiveWindow(observer: observer)

        AXObserverAddNotification(observer, window,
            kAXMovedNotification as CFString, context)
        AXObserverAddNotification(observer, window,
            kAXResizedNotification as CFString, context)
        AXObserverAddNotification(observer, window,
            kAXUIElementDestroyedNotification as CFString, context)
        AXObserverAddNotification(observer, window,
            kAXWindowMiniaturizedNotification as CFString, context)
        AXObserverAddNotification(observer, window,
            kAXWindowDeminiaturizedNotification as CFString, context)

        activeWindow = window
    }

    private func detachActiveWindow(observer: AXObserver) {
        guard let window = activeWindow else { return }
        AXObserverRemoveNotification(observer, window,
            kAXMovedNotification as CFString)
        AXObserverRemoveNotification(observer, window,
            kAXResizedNotification as CFString)
        AXObserverRemoveNotification(observer, window,
            kAXUIElementDestroyedNotification as CFString)
        AXObserverRemoveNotification(observer, window,
            kAXWindowMiniaturizedNotification as CFString)
        AXObserverRemoveNotification(observer, window,
            kAXWindowDeminiaturizedNotification as CFString)
        activeWindow = nil
    }

    private func detachObserver() {
        // 앱 전환 시점에 살아있는 settle 워크 아이템이 fire되면 이전 앱 컨텍스트로
        // emit이 일어나 외곽선이 잘못된 위치에 잠시 표시될 수 있음. 먼저 정리한다.
        cancelSettle()
        if let obs = axObserver {
            detachActiveWindow(observer: obs)
            if let appElement = activeAppElement {
                AXObserverRemoveNotification(obs, appElement,
                    kAXFocusedWindowChangedNotification as CFString)
                AXObserverRemoveNotification(obs, appElement,
                    kAXApplicationHiddenNotification as CFString)
                AXObserverRemoveNotification(obs, appElement,
                    kAXApplicationShownNotification as CFString)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(obs),
                .defaultMode
            )
        }
        axObserver = nil
        activeAppElement = nil
        activeApp = nil
        activeWindow = nil
    }

    private func teardown() {
        if let token = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceObserver = nil
        }
        detachObserver()
    }

    // MARK: AX callback handler (main thread)

    fileprivate func handleAXNotification(element: AXUIElement, name: String) {
        guard isStarted else { return }
        guard let app = activeApp, let obs = axObserver else { return }

        switch name {
        case kAXFocusedWindowChangedNotification as String:
            cancelSettle()
            if let window = focusedWindow(of: activeAppElement ?? element) {
                let context = Unmanaged.passUnretained(self).toOpaque()
                attachWindow(window, observer: obs, context: context)
                emit(window: window, app: app)
            } else {
                detachActiveWindow(observer: obs)
                current = nil
                subject.send(nil)
            }

        case kAXMovedNotification as String,
             kAXResizedNotification as String:
            // 이동/리사이즈 진행 중에는 외곽선을 숨기고, 마지막 알림 후 settleDelay
            // 동안 추가 변화가 없을 때만 최종 frame을 emit한다 ("settle on stop").
            // `element` 는 윈도우 자체.
            scheduleSettle(window: element, app: app)

        case kAXUIElementDestroyedNotification as String,
             kAXWindowMiniaturizedNotification as String,
             kAXApplicationHiddenNotification as String:
            cancelSettle()
            detachActiveWindow(observer: obs)
            current = nil
            subject.send(nil)

        case kAXWindowDeminiaturizedNotification as String,
             kAXApplicationShownNotification as String:
            cancelSettle()
            if let window = focusedWindow(of: activeAppElement ?? element) {
                let context = Unmanaged.passUnretained(self).toOpaque()
                attachWindow(window, observer: obs, context: context)
                emit(window: window, app: app)
            }

        default:
            break
        }
    }

    // MARK: Move/resize settle debounce

    /// 이동/리사이즈 알림 도착 시 호출. 즉시 외곽선을 숨기고 마지막 알림 후
    /// `settleDelay` 동안 추가 알림이 없으면 최종 frame을 emit한다.
    private func scheduleSettle(window: AXUIElement, app: NSRunningApplication) {
        // 즉시 hide. 멱등하므로 연속 호출되어도 OverlayRenderer 측 비용 없음.
        if current != nil {
            current = nil
        }
        subject.send(nil)

        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isStarted else { return }
            // 이동 도중 윈도우가 미니마이즈/소멸되었으면 activeWindow가 정리되어
            // 있으므로 별도 처리 불필요(emit이 frame 조회 실패 시 nil emit).
            self.emit(window: window, app: app)
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.settleDelay,
            execute: work
        )
    }

    private func cancelSettle() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
    }

    // MARK: AX queries

    private func focusedWindow(of appElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success, let raw = value else { return nil }
        // Type-check the CFTypeID before casting. Some apps (e.g. Electron-based
        // or transient teardown states) have been reported to return .success
        // with a non-AXUIElement value; an unconditional `as!` would crash the
        // entire app on the main thread after the AX callback dispatch.
        guard CFGetTypeID(raw as CFTypeRef) == AXUIElementGetTypeID() else {
            return nil
        }
        return (raw as! AXUIElement)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        let posResult = AXUIElementCopyAttributeValue(
            window, kAXPositionAttribute as CFString, &posValue
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            window, kAXSizeAttribute as CFString, &sizeValue
        )
        guard posResult == .success, sizeResult == .success,
              let posRaw = posValue, let sizeRaw = sizeValue else {
            return nil
        }

        // Type-check both raw values are AXValue before unwrapping. Same crash
        // risk as `focusedWindow(of:)` — a malformed AX response would otherwise
        // trap the main thread.
        guard CFGetTypeID(posRaw as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRaw as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        let posOK = AXValueGetValue(posRaw as! AXValue, .cgPoint, &origin)
        let sizeOK = AXValueGetValue(sizeRaw as! AXValue, .cgSize, &size)
        guard posOK, sizeOK else { return nil }

        return CGRect(origin: origin, size: size)
    }

    /// Finder 데스크톱 래퍼 식별. 실제 Finder 윈도우(브라우저, Get Info 다이얼로그
    /// 등)는 항상 AXSubrole을 가진다(`AXStandardWindow`, `AXDialog` 등). 데스크톱
    /// 래퍼는 subrole이 누락되거나 빈 문자열이다. 이 차이를 감지에 사용한다.
    private func isDesktopWrapper(window: AXUIElement, app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier == "com.apple.finder" else { return false }
        var subroleValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            window, kAXSubroleAttribute as CFString, &subroleValue
        )
        guard result == .success,
              let subrole = subroleValue as? String,
              !subrole.isEmpty else {
            return true
        }
        return false
    }

    private func windowID(of window: AXUIElement) -> CGWindowID? {
        // _AXUIElementGetWindow is private SPI. We avoid it and let consumers
        // rely on appBundleID + frame for matching. Returning nil is allowed
        // by the WindowFrame contract.
        _ = window
        return nil
    }

    private func emit(window: AXUIElement, app: NSRunningApplication) {
        // Finder가 활성 앱이지만 열린 Finder 창이 하나도 없으면(부팅 직후, 모든
        // 창을 닫은 상태) kAXFocusedWindow는 데스크톱 래퍼 요소를 반환한다. 이
        // 요소의 frame은 화면 전체와 거의 같아 외곽선이 바탕화면 가장자리에
        // 그려지는 시각적 버그가 된다. 사용자가 입력하는 대상이 아니므로 거른다.
        if isDesktopWrapper(window: window, app: app) {
            current = nil
            subject.send(nil)
            return
        }

        guard let rect = frame(of: window) else {
            // Frame query failed (e.g. system UI app, windowless active app,
            // transient AX failure). Treat as "no window to outline" so the
            // OverlayRenderer hides immediately instead of leaving a stale
            // frame on screen.
            current = nil
            subject.send(nil)
            return
        }

        let bundleID = app.bundleIdentifier ?? ""
        let screen = screenContaining(axRect: rect)
        let wf = WindowFrame(
            frame: rect,
            screen: screen,
            appBundleID: bundleID,
            windowID: windowID(of: window)
        )

        current = wf
        subject.send(wf)
    }

    // MARK: Multi-display matching (AX → NSScreen)

    /// Find the NSScreen that best contains the given AX rect.
    /// AX coordinates are top-left origin with the primary screen's top-left at (0,0).
    /// NSScreen coordinates are bottom-left origin with the primary screen's
    /// bottom-left at (0,0). We convert the AX rect into NS space using the
    /// primary screen height before matching.
    ///
    /// Primary screen resolution must match `OverlayWindowController.primaryScreen()`
    /// (the renderer side) — otherwise the converted AX→NS y-coordinate would
    /// reference a different screen height and the outline would be drawn at
    /// an offset. Use the same 3-step fallback: zero-origin screen → first
    /// listed screen → NSScreen.main.
    private func screenContaining(axRect: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.screens.first
                ?? NSScreen.main else { return nil }
        let primaryMaxY = primary.frame.maxY

        let nsRect = CGRect(
            x: axRect.origin.x,
            y: primaryMaxY - (axRect.origin.y + axRect.size.height),
            width: axRect.size.width,
            height: axRect.size.height
        )

        // Pick the screen whose frame intersects the most with the converted rect.
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(nsRect)
            if intersection.isNull { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }
        return bestScreen ?? NSScreen.main ?? primary
    }
}
